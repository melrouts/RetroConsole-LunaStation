#!/usr/bin/env python3
"""Generate original indexed Earth artwork and a fully rotated lander sprite atlas."""
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def inside(x, y, vertices):
    hit = False
    for (ax, ay), (bx, by) in zip(vertices, vertices[1:] + vertices[:1]):
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            hit = not hit
    return hit


def segment(x, y, ax, ay, bx, by, width=0.65):
    ratio = max(0, min(1, ((x-ax)*(bx-ax) + (y-ay)*(by-ay)) /
                       ((bx-ax)**2 + (by-ay)**2)))
    return (x-ax-ratio*(bx-ax))**2 + (y-ay-ratio*(by-ay))**2 <= width**2


def lander(x, y):
    if inside(x, y, [(-3, 5), (3, 5), (0, 14)]):
        return 3
    legs = [(-4, 3, -8, 8), (4, 3, 8, 8), (-10, 8, -6, 8), (6, 8, 10, 8),
            (-4, -1, -8, 2), (4, -1, 8, 2)]
    if any(segment(x, y, *line) for line in legs):
        return 1
    if inside(x, y, [(-5, -4), (-3, -8), (3, -8), (5, -4), (5, 1),
                     (3, 4), (-3, 4), (-5, 1)]):
        return 2 if -3 <= x <= 3 and -6 <= y <= -3 else 1
    return 0


def sprite_atlas():
    pixels = []
    for angle in range(32):
        sine, cosine = math.sin(angle * math.tau / 32), math.cos(angle * math.tau / 32)
        for y in range(-16, 16):
            for x in range(-16, 16):
                pixels.append(lander(x*cosine + y*sine, -x*sine + y*cosine))
    return pixels


def earth_art():
    # Original coarse continent silhouettes projected onto a shaded globe.
    continents = [
        [(-.83, -.55), (-.50, -.77), (-.18, -.61), (-.23, -.33), (-.42, -.14),
         (-.26, .03), (-.36, .12), (-.58, -.02), (-.74, -.25)],
        [(-.34, .04), (-.13, .12), (-.06, .36), (-.26, .74), (-.40, .52), (-.48, .18)],
        [(.06, -.46), (.30, -.64), (.76, -.47), (.84, -.13), (.55, -.04),
         (.34, -.22), (.16, -.13)],
        [(.12, -.16), (.42, -.10), (.48, .23), (.26, .52), (.08, .27), (-.02, .02)],
        [(.60, .46), (.82, .40), (.87, .59), (.66, .66)],
    ]
    pixels = []
    for row in range(128):
        for column in range(128):
            x, y = (column - 63.5)/60, (row - 63.5)/60
            radius = x*x + y*y
            if radius > 1.10:
                pixels.append(0)
                continue
            if radius > 1:
                pixels.append(1 if radius < 1.055 else 2)
                continue
            z = math.sqrt(1-radius)
            light = max(0, -.55*x - .35*y + .76*z)
            land = any(inside(x, y, polygon) for polygon in continents)
            clouds = (math.sin(x*21 + math.sin(y*13)*2) +
                      math.sin(y*31 - x*7) > 1.22) or y < -.83
            if light < .13:
                color = 3
            elif clouds:
                color = 12 if light > .65 else 11 if light > .35 else 10
            elif land:
                color = 9 if light > .65 else 8 if light > .35 else 7
            else:
                color = 6 if light > .65 else 5 if light > .35 else 4
            pixels.append(color)
    return pixels


def main():
    for filename, pixels in (("lander.hex", sprite_atlas()), ("earth.hex", earth_art())):
        (ROOT / "build" / filename).write_text("".join(f"{pixel:x}\n" for pixel in pixels))


if __name__ == "__main__":
    main()
