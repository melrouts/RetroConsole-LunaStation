#!/usr/bin/env python3
"""Validate and copy an image into GAMES on a mounted SD card, without formatting."""

import argparse
import hashlib
import os
import re
import tempfile
from pathlib import Path

from game_image import configuration, validate


def verified_write(destination, content):
    if destination.is_symlink():
        raise ValueError(f"Refusing symlink: {destination}")
    fd, temporary = tempfile.mkstemp(prefix="COPY", suffix=".TMP", dir=destination.parent)
    temporary = Path(temporary)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        if temporary.read_bytes() != content:
            raise OSError("SD readback mismatch before rename")
        os.replace(temporary, destination)
        if destination.read_bytes() != content:
            raise OSError("SD readback mismatch after rename")
    finally:
        temporary.unlink(missing_ok=True)


def deploy(source, directory):
    config = configuration()
    content = source.read_bytes()
    validate(content, ram_bytes=config["MAIN_RAM_BYTES"],
             stack_bytes=config["STACK_BYTES"], abi=config["ABI_VERSION"])
    name = source.name.upper()
    if not re.fullmatch(r"[A-Z0-9_]{1,8}\.BIN", name):
        raise ValueError("Image needs a short 8.3 filename, e.g. LUNAR.BIN")
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("GAMES must be a real directory")
    destination = directory / name
    if destination.is_symlink():
        raise ValueError("Refusing symlink destination")
    if destination.exists():
        previous = destination.read_bytes()
        if previous == content:
            return destination
        backup_dir = directory / "BACKUP"
        if backup_dir.is_symlink():
            raise ValueError("Refusing symlink backup directory")
        backup_dir.mkdir(exist_ok=True)
        backup = backup_dir / (hashlib.sha256(previous).hexdigest()[:8].upper() + ".BAK")
        if backup.exists():
            if backup.is_symlink() or backup.read_bytes() != previous:
                raise ValueError("Backup filename collision; previous image was not replaced")
        else:
            verified_write(backup, previous)
    verified_write(destination, content)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--volume", type=Path, default=Path("/Volumes/Luna9"))
    args = parser.parse_args()
    try:
        if args.volume.is_symlink() or not args.volume.is_mount():
            raise ValueError(f"SD volume is not mounted: {args.volume}")
        directory = args.volume / "GAMES"
        if directory.is_symlink():
            raise ValueError("Refusing symlink GAMES directory")
        directory.mkdir(exist_ok=True)
        destination = deploy(args.image, directory)
    except (ValueError, OSError) as error:
        parser.exit(1, f"SD deployment error: {error}\n")
    print(f"Verified SD image: {destination}")


if __name__ == "__main__":
    main()
