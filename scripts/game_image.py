#!/usr/bin/env python3
"""Pack or validate the bounded LUNA v1 RV32I image format."""

import argparse
import re
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HEADER = struct.Struct("<4sHH6I")


def configuration():
    text = (ROOT / "hardware/platform_config.vh").read_text()
    values = {}
    for name in ("MAIN_RAM_BYTES", "STACK_BYTES", "ABI_VERSION"):
        match = re.search(rf"^`define {name}\s+([0-9]+(?:'[hHdD][0-9a-fA-F]+)?)\s*$",
                          text, re.MULTILINE)
        if not match:
            raise ValueError(f"Missing integer hardware constant: {name}")
        literal = match[1]
        if "'" in literal:
            _, value = literal.split("'")
            values[name] = int(value[1:], 16 if value[0].lower() == "h" else 10)
        else:
            values[name] = int(literal)
    return values


def validate(image, *, ram_bytes, stack_bytes, abi):
    if len(image) < HEADER.size:
        raise ValueError("Truncated LUNA header")
    magic, version, image_abi, size, load, entry, flags, payload_crc, header_crc = (
        HEADER.unpack_from(image)
    )
    if magic != b"LUNA" or version != 1:
        raise ValueError("Unsupported image magic/format")
    if image_abi != abi:
        raise ValueError("Incompatible hardware ABI")
    if flags:
        raise ValueError("Reserved image flags must be zero")
    if zlib.crc32(image[:28]) != header_crc:
        raise ValueError("Header CRC mismatch")
    if not 0 < stack_bytes < ram_bytes:
        raise ValueError("Invalid RAM/stack configuration")
    if not size or len(image) != HEADER.size + size:
        raise ValueError("Payload size mismatch or trailing bytes")
    if load % 4 or entry % 4:
        raise ValueError("RV32I load/entry must be 4-byte aligned")
    if load >= ram_bytes - stack_bytes or size > ram_bytes - stack_bytes - load:
        raise ValueError("Image overlaps reserved stack or exceeds RAM")
    if entry < load or entry + 4 > load + size:
        raise ValueError("Entry must contain a complete RV32I instruction in payload")
    if zlib.crc32(image[HEADER.size:]) != payload_crc:
        raise ValueError("Payload CRC mismatch")
    return {"size": size, "load": load, "entry": entry, "abi": image_abi}


def pack(payload, *, load=0, entry=0, ram_bytes, stack_bytes, abi):
    header = HEADER.pack(b"LUNA", 1, abi, len(payload), load, entry, 0,
                         zlib.crc32(payload), 0)
    image = header[:28] + struct.pack("<I", zlib.crc32(header[:28])) + payload
    validate(image, ram_bytes=ram_bytes, stack_bytes=stack_bytes, abi=abi)
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    packing = subparsers.add_parser("pack")
    packing.add_argument("payload", type=Path)
    packing.add_argument("output", type=Path)
    packing.add_argument("--load", type=lambda v: int(v, 0), default=0)
    packing.add_argument("--entry", type=lambda v: int(v, 0), default=0)
    checking = subparsers.add_parser("check")
    checking.add_argument("image", type=Path)
    args = parser.parse_args()
    config = configuration()
    bounds = {"ram_bytes": config["MAIN_RAM_BYTES"],
              "stack_bytes": config["STACK_BYTES"], "abi": config["ABI_VERSION"]}
    try:
        if args.command == "pack":
            if args.output.exists() and args.output.samefile(args.payload):
                raise ValueError("Output must not overwrite the raw input payload")
            image = pack(args.payload.read_bytes(), load=args.load, entry=args.entry, **bounds)
            args.output.write_bytes(image)
        else:
            image = args.image.read_bytes()
        info = validate(image, **bounds)
    except (OSError, ValueError, struct.error) as error:
        parser.exit(1, f"Image error: {error}\n")
    print(f"PASS: LUNA v1 ABI {info['abi']}, {info['size']} payload bytes, "
          f"load=0x{info['load']:08x}, entry=0x{info['entry']:08x}")


if __name__ == "__main__":
    main()
