#!/usr/bin/env python3
"""Fit supplied Luna 9 and NASA Apollo 11 photographs into a four-tone ROM."""
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ("luna9-capsule.jpg", "apollo11-nasa-6900956.jpg")
TEXT = (
    "LUNA 9 - 1966", "APOLLO 11 - 1969",
    "FIRST SOFT LANDING", "ON THE MOON",
    "FIRST FAX FROM THE MOON :)", "",
    "FIRST HUMANS ON THE MOON", "",
    "THE EAGLE HAS LANDED", "",
    "ONE SMALL STEP FOR A MAN,", "ONE GIANT LEAP FOR MANKIND.",
    "LUNA 9 / 3 FEBRUARY 1966", "PHOTO: NASA / NEIL ARMSTRONG",
    "", "",
)
SCREEN_TEXT = (
    "LUNAR", "LANDER", "PRECISION LUNAR FLIGHT", "BEST SCORE", "",
    "PRESS W TO LAUNCH", "A/D ROTATE   W THRUST   B MENU", "Eduard Garanskij  retro@lea.lt",
    "Retro Computer Festival 2026", "Centre for Computer History", "Cambridge",
    "DEMO - PRESS W TO PLAY", "LANDED! NEXT RELEASE WINDOW",
    "CRASHED - CAPSULE LOST", "GAME OVER - W TO RESTART", "EXIT? W YES / B RESUME",
)
# Lines 32-35 follow the failure bits of the landing result (pad, descent speed,
# side speed, tilt); line 36 is the points label.
CAUSE_TEXT = (
    "MISSED THE LANDING PAD", "DESCENT SPEED TOO HIGH",
    "SIDE SPEED TOO HIGH", "TILT ANGLE TOO LARGE",
)
POINTS_TEXT = "POINTS"
CONSOLE_TEXT = (
    "LUNA 9K", "BIN GAMES", "SETTINGS", "MENU BACK",
    "NO SD CARD", "NO GAMES FOUND", "SAVE FAILED", "IMAGE ERROR",
    "UP/DOWN SELECT A LAUNCH", "UP/DN ADJUST A SELECT MENU BACK",
    "MUSIC EFFECTS", "MENU SETTINGS",
)
ROM_ENTRIES = 2048


def photograph(path):
    with Image.open(path) as source:
        image = ImageOps.contain(ImageOps.exif_transpose(source).convert("L"),
                                 (128, 64), Image.Resampling.LANCZOS)
    canvas = Image.new("L", (128, 64))
    canvas.paste(image, ((128-image.width)//2, (64-image.height)//2))
    # Ordered four-tone quantization preserves detail without random build output.
    bayer = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
    return [max(0, min(3, (value*3 + bayer[y % 4][x % 4]*16)//256))
            for y in range(64) for x in range(128)
            for value in (canvas.getpixel((x, y)),)]


def caption_rom():
    """The 2048 ASCII entries of the renderer caption ROM, 32 columns per line."""
    lines = ([line.center(32) for line in TEXT] +
             [line.ljust(32) for line in SCREEN_TEXT] +
             [line.center(32) for line in CAUSE_TEXT] +
             [POINTS_TEXT.ljust(32)] +
             [line.ljust(32) for line in CONSOLE_TEXT])
    return "".join(lines).ljust(ROM_ENTRIES)


def main(build=ROOT / "build"):
    pixels = [pixel for name in SOURCES for pixel in photograph(ROOT / "photos" / name)]
    (build / "memorial.hex").write_text("".join(f"{pixel:x}\n" for pixel in pixels))
    (build / "memorial-text.hex").write_text(
        "".join(f"{ord(char):02x}\n" for char in caption_rom()))


if __name__ == "__main__":
    main()
