#!/usr/bin/env python3
"""Convert a Lunar Lander .song file (format LLSONG 1) to a standard MIDI file.

The MIDI output contains the same voices the ESP32 synthesizer plays:
lead, bass, a three-note pad and a 16th-note arpeggio.
"""
import argparse
import re
import struct
import sys

NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
PPQ = 480


def parse_note(text):
    match = re.fullmatch(r"([A-G])([#b]?)(-?\d)", text)
    if not match:
        raise ValueError(f"bad note name: {text}")
    name, accidental, octave = match.groups()
    value = (int(octave) + 1) * 12 + NOTE_NAMES[name]
    value += {"#": 1, "b": -1, "": 0}[accidental]
    if not 0 <= value <= 127:
        raise ValueError(f"note out of range: {text}")
    return value


def parse_song(text):
    song = {"lead": [], "chords": [], "bpm": 120, "title": ""}
    for number, raw in enumerate(text.splitlines(), 1):
        # Only whole lines are comments: '#' inside a line is a sharp sign.
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, _, rest = line.partition(" ")
        values = rest.split()
        try:
            if key == "format":
                if values != ["LLSONG", "1"]:
                    raise ValueError("unsupported format")
            elif key == "title":
                song["title"] = rest.strip()
            elif key == "bpm":
                song["bpm"] = int(values[0])
            elif key == "step":
                if values != ["1/8"]:
                    raise ValueError("only step 1/8 is supported")
            elif key == "chords":
                for chord in values:
                    minor = chord.endswith("m")
                    song["chords"].append((parse_note(chord[:-1] if minor else chord),
                                           3 if minor else 4))
            elif key == "lead":
                if len(values) != 16:
                    raise ValueError("a lead line must have 16 steps")
                song["lead"].extend(0 if v == "." else parse_note(v) for v in values)
            else:
                raise ValueError(f"unknown keyword: {key}")
        except (ValueError, IndexError) as error:
            raise SystemExit(f"line {number}: {error}")
    if len(song["lead"]) != len(song["chords"]) * 16:
        raise SystemExit("lead must have 16 steps (2 bars) per chord")
    return song


def variable_length(value):
    data = [value & 0x7F]
    value >>= 7
    while value:
        data.insert(0, 0x80 | (value & 0x7F))
        value >>= 7
    return bytes(data)


def track(events, name, channel=None, program=None):
    """events: list of (tick, note, velocity_or_0)."""
    data = bytearray(b"\x00\xff\x03" + variable_length(len(name)) + name.encode())
    if program is not None:
        data += bytes([0, 0xC0 | channel, program])
    last = 0
    for tick, kind, payload in sorted(events, key=lambda e: (e[0], e[1] != "off")):
        data += variable_length(tick - last)
        last = tick
        if kind == "tempo":
            data += b"\xff\x51\x03" + payload.to_bytes(3, "big")
        else:
            note, velocity = payload
            status = (0x90 if kind == "on" else 0x80) | channel
            data += bytes([status, note, velocity])
    data += b"\x00\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + bytes(data)


def note(events, start, length, pitch, velocity):
    events.append((start, "on", (pitch, velocity)))
    events.append((start + length, "off", (pitch, 0)))


def to_midi(song):
    beat, eighth, sixteenth = PPQ, PPQ // 2, PPQ // 4
    lead, bass, pad, arp = [], [], [], []
    for step, pitch in enumerate(song["lead"]):
        if pitch:
            note(lead, step * eighth, eighth * 9 // 10, pitch, 100)
    for index, (root, third) in enumerate(song["chords"]):
        start = index * 8 * beat
        for voice in (root + 12, root + 12 + third, root + 19):
            note(pad, start, 8 * beat, voice, 60)
        for b in range(8):
            note(bass, start + b * beat, beat, root - 12 + (7 if b % 4 == 2 else 0), 90)
        for s in range(32):
            offset = (0, 7, third, 7)[s % 4]
            note(arp, start + s * sixteenth, sixteenth * 9 // 10, root + 24 + offset, 70)
    tempo = [(0, "tempo", 60_000_000 // song["bpm"])]
    tracks = [
        track(tempo, song["title"] or "Lunar Lander"),
        track(lead, "Lead", 0, 80),
        track(bass, "Bass", 1, 38),
        track(pad, "Pad", 2, 89),
        track(arp, "Arpeggio", 3, 81),
    ]
    return b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), PPQ) + b"".join(tracks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("song")
    parser.add_argument("midi")
    args = parser.parse_args()
    with open(args.song, encoding="utf-8") as source:
        song = parse_song(source.read())
    with open(args.midi, "wb") as output:
        output.write(to_midi(song))
    print(f"{args.midi}: {len(song['chords']) * 2} bars, {song['bpm']} BPM")


if __name__ == "__main__":
    sys.exit(main())
