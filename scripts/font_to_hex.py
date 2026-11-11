#!/usr/bin/env python3
"""Convert pinned public-domain font8x8 ASCII 32..127 to MSB-left ROM bytes."""

import argparse
import re
from pathlib import Path

DASHBOARD_GLYPHS = {
    "0": "01110_11011_11011_11011_11011_11011_01110",
    "1": "00110_01110_00110_00110_00110_00110_01111",
    "2": "11110_00011_00011_01110_11000_11000_11111",
    "3": "11110_00011_00011_01110_00011_00011_11110",
    "4": "11011_11011_11011_11111_00011_00011_00011",
    "5": "11111_11000_11000_11110_00011_00011_11110",
    "6": "01110_11000_11000_11110_11011_11011_01110",
    "7": "11111_00011_00110_00110_01100_01100_01100",
    "8": "01110_11011_11011_01110_11011_11011_01110",
    "9": "01110_11011_11011_01111_00011_00011_01110",
    "L": "11000_11000_11000_11000_11000_11000_11111",
    "E": "11111_11000_11000_11110_11000_11000_11111",
    "V": "11011_11011_11011_11011_11011_01110_00100",
    "F": "11111_11000_11000_11110_11000_11000_11000",
    "U": "11011_11011_11011_11011_11011_11011_01110",
    "I": "01110_00100_00100_00100_00100_00100_01110",
    "S": "01111_11000_11000_01110_00011_00011_11110",
    "C": "01111_11000_11000_11000_11000_11000_01111",
    "O": "01110_11011_11011_11011_11011_11011_01110",
    "R": "11110_11011_11011_11110_11100_11010_11011",
    "P": "11110_11011_11011_11110_11000_11000_11000",
    "D": "11110_11011_11011_11011_11011_11011_11110",
    "A": "01110_11011_11011_11111_11011_11011_11011",
    "T": "11111_00100_00100_00100_00100_00100_00100",
    "M": "10001_11011_11111_10101_10001_10001_10001",
    "/": "00001_00011_00110_00100_01100_11000_10000",
}


def convert(text):
    rows = re.findall(r"\{\s*((?:0x[0-9a-fA-F]{2}\s*,?\s*){8})\}", text)
    if len(rows) != 128:
        raise ValueError("Expected 128 font8x8 glyphs")
    values = []
    for row in rows[32:128]:
        for value in re.findall(r"0x[0-9a-fA-F]{2}", row):
            values.append(int(f"{int(value, 16):08b}"[::-1], 2))
    return "".join(f"{value:02x}\n" for value in values)


def convert_hud(text):
    values = convert(text).splitlines()
    values.extend(["00"] * (2048 - len(values)))
    for character, glyph in DASHBOARD_GLYPHS.items():
        rows = glyph.split("_")
        if len(rows) != 7 or any(len(row) != 5 for row in rows):
            raise ValueError(f"Invalid dashboard glyph: {character}")
        for row, bits in enumerate(rows):
            values[1024 + (ord(character) - 32) * 8 + row] = f"{int(bits, 2) << 2:02x}"
    return "\n".join(values) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--hud", action="store_true",
                        help="combine normal and dashboard glyphs into one registered ROM")
    args = parser.parse_args()
    try:
        text = args.source.read_text()
        args.output.write_text(convert_hud(text) if args.hud else convert(text))
    except (OSError, ValueError) as error:
        parser.exit(1, f"Font error: {error}\n")


if __name__ == "__main__":
    main()
