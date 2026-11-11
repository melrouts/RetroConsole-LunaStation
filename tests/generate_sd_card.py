#!/usr/bin/env python3
"""Generate sparse SDHC simulation sectors containing the real diagnostic image."""

from pathlib import Path
import struct
import sys
import zlib

from test_native_boot import directory_entry, disk_fixture


def main():
    image = Path(sys.argv[1]).read_bytes()
    game = "--game" in sys.argv[2:]
    prefix = "build/game-card" if game else "build/test-card"
    for bad_crc, filename in ((False, prefix + ".hex"), (True, prefix + "-bad.hex")):
        payload = bytearray(image)
        if bad_crc:
            payload[40] ^= 1
        sectors, _ = disk_fixture(image=payload, fragmented=False)
        if game:
            smoke = Path("build/images/SMOKE.BIN").read_bytes()
            games = sectors[58]
            games[64:96] = directory_entry(b"SMOKE   BIN", 0x20, 6, len(smoke))
            games[96:128] = directory_entry(b"LUNAR   BIN", 0x20, 8, len(payload))
            sectors[59] = smoke.ljust(512, b"\0")
            sectors[33][12:14] = b"\xff\xff"
            for slot, first in enumerate((32, 64)):
                for offset in range(16):
                    cluster = first + offset
                    struct.pack_into("<H", sectors[33], cluster*2,
                                     cluster+1 if offset < 15 else 0xffff)
                    sectors[55 + cluster - 2] = bytes(512)
                name = b"UPDATEA BIN" if slot == 0 else b"UPDATEB BIN"
                games[128+slot*32:160+slot*32] = directory_entry(name, 0x20, first, 8192)
            upload = bytearray(struct.pack("<4sII", b"LUP1", len(smoke), zlib.crc32(smoke)))
            for index, offset in enumerate(range(0, len(smoke), 64)):
                block = struct.pack("<H", index) + smoke[offset:offset+64]
                upload.extend(block + struct.pack("<I", zlib.crc32(block)))
            Path("build/test-upload.hex").write_text(
                "".join(f"{value:02x}\n" for value in upload.ljust(1024, b"\0")))
        card = bytearray(256 * 512)
        for sector, content in sectors.items():
            if sector >= 256:
                raise ValueError("Simulation fixture sector exceeds sparse storage")
            card[sector*512:(sector+1)*512] = content
        Path(filename).write_text("".join(f"{value:02x}\n" for value in card))


if __name__ == "__main__":
    main()
