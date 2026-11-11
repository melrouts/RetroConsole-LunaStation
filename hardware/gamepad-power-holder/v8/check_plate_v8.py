"""Checks the V8 LED-matrix plate (matrix_plate_v8.stl) against the V6 lid and the case.

Everything is compared as Z sections (shapely), in lid coordinates:
* the plate is watertight and printable flat (bottom at Z 126.5, standoffs up);
* its bolt holes sit on the lid insert holes, the boss and stop ends touch only the plate top (Z 130);
* standoffs, matrix and screw heads do not touch the lid mount and frame;
* plate, standoffs and matrix keep CLEARANCE to the case walls and the magnet post
  (V7 case: lid Z 135 is case Z 31; V5 case: lid Z 135 is case Z 30).

Needs trimesh and shapely; reads ../v5, ../v6 and ../v7 meshes.
"""
import sys
from pathlib import Path

import numpy as np
import trimesh
from shapely.geometry import Point, Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent / "v6"))
from prepare_lid_v6 import section  # noqa: E402

# Must match matrix_plate_v8.scad.
WINDOW = (0.0, 28.75)
BOSS_PITCH = (40.0, 24.0)
PCB_PITCH = 16.0
PCB = 30.0
PCB_T = 1.5
LED = 5.0
LED_H = 1.6
LED_PITCH = 8.0
MOUNT_Z = 130.0
PLATE_T = 3.5
TOP_Z = 138.8
LED_RECESS = 1.5
STANDOFF_D = 6.0
INSERT_D = 3.2
INSERT_DEPTH = 4.5
BOLT_D = 2.4
HEAD_D = 4.4
SCREW_HEAD_D = 3.9              # M2 pan head, 3.8-4.0
CLEARANCE = 0.6
CASES = (("V7", ROOT.parent / "v7" / "gamepad_case_v7.stl", -104.0),
         ("V5", ROOT.parent / "v5" / "gamepad_case_v5.stl", -105.0))

STANDOFF_H = TOP_Z - LED_RECESS - LED_H - PCB_T - MOUNT_Z
BOARD_Z = MOUNT_Z + STANDOFF_H
cx, cy = WINDOW
failures = []


def check(ok, text):
    print(("ok   " if ok else "FAIL ") + text)
    if not ok:
        failures.append(text)


def sec(mesh, z):
    s = section(mesh, z)
    return Polygon() if s is None else s


def holes_of(poly):
    return [Polygon(h) for g in getattr(poly, "geoms", [poly]) for h in g.interiors]


def hole_at(poly, x, y):
    for h in holes_of(poly):
        if h.contains(Point(x, y)):
            return h
    return None


def diameter(p):
    return 0.0 if p is None else 2 * np.sqrt(p.area / np.pi)


plate = trimesh.load(ROOT / "matrix_plate_v8.stl")
lid = trimesh.load(ROOT.parent / "v6" / "gamepad_lid_v6.stl")

lo, hi = plate.bounds
check(plate.is_watertight and plate.is_winding_consistent, "plate is watertight")
check(abs(lo[2] - (MOUNT_Z - PLATE_T)) < 1e-3 and abs(hi[2] - BOARD_Z) < 1e-3,
      f"plate Z {lo[2]:.2f}..{hi[2]:.2f} (flat bottom, standoffs up)")
print(f"     size {hi[0] - lo[0]:.1f} x {hi[1] - lo[1]:.1f} mm, volume {plate.volume / 1000:.1f} cm3, "
      f"standoffs {STANDOFF_H:.2f} mm above the plate")

bolts = [(cx + sx * BOSS_PITCH[0] / 2, cy + sy * BOSS_PITCH[1] / 2) for sx in (-1, 1) for sy in (-1, 1)]
pcb_holes = [(cx + sx * PCB_PITCH / 2, cy + sy * PCB_PITCH / 2) for sx in (-1, 1) for sy in (-1, 1)]

# Bolt holes, counterbores and the insert holes of the lid bosses above them.
s_hole = sec(plate, MOUNT_Z - 1.0)
s_head = sec(plate, MOUNT_Z - PLATE_T + 1.0)
s_lid = sec(lid, MOUNT_Z + 0.5)
for x, y in bolts:
    h, c, i = hole_at(s_hole, x, y), hole_at(s_head, x, y), hole_at(s_lid, x, y)
    ok = (h is not None and c is not None and i is not None and h.within(i)
          and abs(diameter(h) - BOLT_D) < 0.05 and abs(diameter(c) - HEAD_D) < 0.05
          and abs(diameter(i) - INSERT_D) < 0.05)
    check(ok, f"bolt ({x:.0f}, {y:.2f}): hole {diameter(h):.2f}, counterbore {diameter(c):.2f}, "
              f"lid insert hole {diameter(i):.2f} above it")

# Insert pockets.
s_pocket = sec(plate, BOARD_Z - 1.0)
s_floor = sec(plate, BOARD_Z - INSERT_DEPTH - 0.1)
for x, y in pcb_holes:
    h = hole_at(s_pocket, x, y)
    check(h is not None and abs(diameter(h) - INSERT_D) < 0.05 and hole_at(s_floor, x, y) is None,
          f"insert pocket ({x:.0f}, {y:.2f}): {diameter(h):.2f} mm, floor "
          f"{BOARD_Z - INSERT_DEPTH - lo[2]:.1f} mm, wall {(STANDOFF_D - INSERT_D) / 2:.1f} mm")

# Lid mount: the boss ends rest on the plate top and nothing else overlaps.
plate_top = sec(plate, MOUNT_Z - 0.05)
lid_ends = sec(lid, MOUNT_Z + 0.05)
contact = plate_top.intersection(lid_ends).area
boss_ends = lid_ends.intersection(unary_union([Point(x, y).buffer(3.4) for x, y in bolts]))
check(boss_ends.area > 80 and boss_ends.difference(plate_top).area < 0.05, "all four boss ends rest on the plate")
print(f"     contact with the lid mount: {contact:.1f} mm2 (bosses and the two stops over the plate)")

keepout = []
worst = 99.0
for z in np.arange(MOUNT_Z + 0.05, BOARD_Z + PCB_T + LED_H, 0.25):
    parts = [sec(plate, min(z, BOARD_Z - 0.01))]
    if z > BOARD_Z:
        parts.append(box(cx - PCB / 2, cy - PCB / 2, cx + PCB / 2, cy + PCB / 2))
    mine = unary_union(parts)
    theirs = sec(lid, z)
    if mine.intersection(theirs).area > 1e-6:
        keepout.append(round(float(z), 2))
    if not theirs.is_empty:
        worst = min(worst, mine.distance(theirs))
check(not keepout, f"standoffs and matrix do not touch the lid (closest {worst:.2f} mm)")

# Screw heads between the LEDs.
corner = np.sqrt(2) * (PCB_PITCH / 2 - (LED_PITCH / 2 + LED / 2))
print(f"     matrix hole to LED corner {corner:.2f} mm; screw head radius {SCREW_HEAD_D / 2:.2f} mm "
      f"-> margin {corner - SCREW_HEAD_D / 2:.2f} mm")
print(f"     LED tops at Z {BOARD_Z + PCB_T + LED_H:.2f}: {TOP_Z - BOARD_Z - PCB_T - LED_H:.1f} mm below the lid top, "
      f"{BOARD_Z + PCB_T + LED_H - 135:+.1f} mm to the lid underside (Z 135)")

# Case walls and the magnet post.
footprint = unary_union([sec(plate, MOUNT_Z - 1.0), box(cx - PCB / 2, cy - PCB / 2, cx + PCB / 2, cy + PCB / 2)])
for name, path, drop in CASES:
    case = trimesh.load(path)
    gap = 99.0
    for z in np.arange(MOUNT_Z - PLATE_T, 135.0, 0.5):
        s = sec(case, z + drop)
        if not s.is_empty:
            gap = min(gap, footprint.distance(s))
    check(gap >= CLEARANCE, f"{name} case: closest wall/post {gap:.2f} mm (needs >= {CLEARANCE})")

if failures:
    raise SystemExit(f"{len(failures)} check(s) failed")
print("all checks passed")
