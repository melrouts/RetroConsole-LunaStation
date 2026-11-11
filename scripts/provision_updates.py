#!/usr/bin/env python3
"""Provision fixed-size update slots once on a mounted FAT card; never truncate existing slots."""
import argparse
import os
from pathlib import Path


def provision(volume):
    volume = Path(volume)
    if not volume.is_dir() or volume.is_symlink() or not os.path.ismount(volume):
        raise ValueError("An existing mounted card volume is required")
    games = volume / "GAMES"
    if games.is_symlink() or not games.is_dir():
        raise ValueError("Existing GAMES directory is required")
    for name in ("UPDATEA.BIN", "UPDATEB.BIN"):
        target = games / name
        if target.is_symlink():
            raise ValueError(f"Refusing symlink: {target}")
        if target.exists():
            if not target.is_file() or target.stat().st_size != 8192:
                raise ValueError(f"Existing slot must be exactly 8192 bytes: {target}")
            print(f"Preserved existing slot: {target}")
            continue
        with target.open("xb") as file:
            file.write(bytes(8192))
            file.flush()
            os.fsync(file.fileno())
        if target.read_bytes() != bytes(8192):
            raise OSError(f"Slot readback failed: {target}")
        print(f"Provisioned empty slot: {target}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--volume", default="/Volumes/Luna9")
    args = parser.parse_args()
    provision(args.volume)


if __name__ == "__main__":
    main()
