#!/usr/bin/env python3
"""Pad a little-endian RV32I firmware image to the hardware RAM capacity."""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--ram-bytes", type=int, required=True)
    args = parser.parse_args()
    data = args.source.read_bytes()
    if args.ram_bytes <= 0 or args.ram_bytes % 4:
        parser.error("RAM capacity must be positive and word-aligned")
    if len(data) > args.ram_bytes:
        parser.error(f"Image exceeds RAM: {len(data)} > {args.ram_bytes}")
    data += bytes(args.ram_bytes - len(data))
    args.output.write_text(
        "".join(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n"
                for i in range(0, len(data), 4)),
        encoding="ascii",
    )


if __name__ == "__main__":
    main()
