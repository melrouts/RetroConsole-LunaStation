#!/usr/bin/env python3
"""Rebuild the LUNA-9K badge: STL files, flat SVG and PNG preview.

Everything is derived from luna9k_badge.scad. Needs the OpenSCAD CLI and Pillow.
Usage: python3 build_badge.py [--no-stl]
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
SCAD = HERE / "luna9k_badge.scad"
OPENSCAD = shutil.which("openscad") or "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD"

RADIUS = 30
LAYERS = (("base", "#081a31"), ("relief", "#7ef7c0"), ("lander", "#d7f3ff"))
PNG_SIZE = 1000
SUPERSAMPLE = 3


def openscad(out, part):
    subprocess.run(
        [OPENSCAD, "-o", str(out), "-D", f'part="{part}"', str(SCAD)],
        check=True,
        capture_output=True,
    )


def read_rings(svg):
    path = " ".join(re.findall(r'<path d="([^"]*)"', svg.read_text()))
    rings = []
    for chunk in path.split("M")[1:]:
        pts = [(float(x), float(y)) for x, y in re.findall(r"(-?[\d.e+-]+),(-?[\d.e+-]+)", chunk)]
        if len(pts) >= 3:
            rings.append(pts)
    return rings


def svg_path(rings):
    parts = []
    for ring in rings:
        pts = " L".join(f"{x:.3f},{y:.3f}" for x, y in ring)
        parts.append(f"M{pts}Z")
    return "".join(parts)


def write_svg(path, layers):
    body = []
    for (name, color), rings in zip(LAYERS, layers):
        if name == "base":
            body.append(f'<circle r="{RADIUS}" fill="{color}"/>')
        else:
            body.append(f'<path fill="{color}" fill-rule="evenodd" d="{svg_path(rings)}"/>')
    path.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="{-RADIUS} {-RADIUS} {2 * RADIUS} {2 * RADIUS}" width="600" height="600">\n'
        "<title>LUNA-9K</title>\n" + "\n".join(body) + "\n</svg>\n"
    )


def write_png(path, layers):
    size = PNG_SIZE * SUPERSAMPLE
    scale = size / (2 * RADIUS)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for (name, color), rings in zip(LAYERS, layers):
        mask = Image.new("1", (size, size), 0)
        for ring in rings:
            one = Image.new("1", (size, size), 0)
            ImageDraw.Draw(one).polygon([((x + RADIUS) * scale, (y + RADIUS) * scale) for x, y in ring], fill=1)
            mask = ImageChops.logical_xor(mask, one)
        img.paste(Image.new("RGBA", (size, size), color), mask=mask)
    img = img.convert("RGBa").resize((PNG_SIZE, PNG_SIZE), Image.LANCZOS).convert("RGBA")
    img.save(path)


def main(with_stl=True):
    if not Path(OPENSCAD).exists():
        raise SystemExit("OpenSCAD not found: install it or put `openscad` on PATH")
    with tempfile.TemporaryDirectory() as tmp:
        layers = []
        for name, _ in LAYERS:
            svg = Path(tmp) / f"{name}.svg"
            openscad(svg, f"flat_{name}")
            layers.append(read_rings(svg))
    write_svg(HERE / "luna9k_badge.svg", layers)
    write_png(HERE / "luna9k_badge.png", layers)
    if not with_stl:
        return

    openscad(HERE / "luna9k_badge.stl", "badge")
    (HERE / "parts").mkdir(exist_ok=True)
    for name, _ in LAYERS:
        openscad(HERE / "parts" / f"luna9k_badge_{name}.stl", name)
    two_color = HERE / "two-color"
    two_color.mkdir(exist_ok=True)
    openscad(two_color / "luna9k_badge_2color.stl", "badge")
    for name, part in (("base", "base"), ("top", "two_color_top")):
        openscad(two_color / f"luna9k_badge_2color_{name}.stl", part)


if __name__ == "__main__":
    main(with_stl="--no-stl" not in sys.argv)
