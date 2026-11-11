#!/usr/bin/env python3
"""Stop-and-wait LUP1 update transport. Returns only after commit AND fresh reboot PASS."""
import argparse
from pathlib import Path
import struct
import time
import zlib

from game_image import configuration, validate


def validate_image(image):
    config = configuration()
    validate(image, ram_bytes=config["MAIN_RAM_BYTES"], stack_bytes=config["STACK_BYTES"],
             abi=config["ABI_VERSION"])


def line_until(port, expected, timeout):
    deadline = time.monotonic() + timeout
    pending = bytearray()
    while time.monotonic() < deadline:
        byte = port.read(1)
        if not byte:
            continue
        pending.extend(byte)
        if len(pending) > 1024:
            raise RuntimeError("Overlong UART response")
        if byte == b"\n":
            line = bytes(pending).strip()
            pending.clear()
            if line.startswith(b"ERR "):
                raise RuntimeError(f"Board refused update: {line.decode('ascii', errors='replace')}")
            if line == expected:
                return
    raise TimeoutError(f"Board did not respond with {expected.decode()}")


def upload(port, image, progress=lambda message: None):
    validate_image(image)
    if len(image) > 7200:
        raise ValueError("Image exceeds update slot limit")
    port.write(b"\x80")
    port.flush()
    port.reset_input_buffer()
    progress("Остановка игры, проверка карты…")
    port.write(b"LUNAUPD!")
    port.flush()
    line_until(port, b"READY LUP1", 60)
    port.write(struct.pack("<4sII", b"LUP1", len(image), zlib.crc32(image)))
    line_until(port, b"SEND", 10)
    for index, offset in enumerate(range(0, len(image), 64)):
        packet = struct.pack("<H", index) + image[offset:offset+64]
        port.write(packet + struct.pack("<I", zlib.crc32(packet)))
        line_until(port, b"ACK", 10)
        progress(f"Передача: {min(offset+64, len(image))}/{len(image)} байт")
    line_until(port, b"WRITE", 10)
    progress("Запись неактивного слота и проверка чтением…")
    line_until(port, b"DONE", 90)
    progress("Запись завершена. Проверка перезапуска игры…")
    line_until(port, b"PASS", 60)
    line_until(port, b"PASS", 5)
    progress("Обновление записано, игра перезапущена: PASS")


def main():
    import serial
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--port", required=True)
    args = parser.parse_args()
    image = args.image.read_bytes()
    validate_image(image)
    with serial.Serial(args.port, 115200, timeout=0.1, write_timeout=2, exclusive=True) as port:
        upload(port, image, print)


if __name__ == "__main__":
    main()
