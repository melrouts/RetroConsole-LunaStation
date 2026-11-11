"""V5 sources: the V4 case and lid with fit fixes.

* Magnet pockets in the case posts and in the lid: diameter 10.2 -> 10.1 mm.
* Bottom button seat lifted 2 mm: the finger recess is 2 mm deeper while the
  panel that holds the button keeps its thickness.
* Lid LED-matrix window 32x32 (V4: 31x31, original: 30x30).

Only selected vertices are moved. Writes gamepad_case_v5_raw.stl and
gamepad_lid_v5_base.stl (the lid without decoration, in the supplied lid's coordinates).
"""

from pathlib import Path
import math
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent / "v2"))
sys.path.insert(0, str(ROOT.parent / "v4"))
import prepare_case_v4 as v4

MAGNETS = [(2.144, 53.331), (71.575, -26.897), (-30.239, -50.408), (-70.965, -18.365)]
MAGNET_R = 5.1
MAGNET_SHRINK = 0.05            # radius: 10.2 -> 10.1 mm
CASE_MAGNET_MIN_Z = 23.5        # pocket wall Z 23.53-25.23 before the V4 stretch
LID_MAGNET_MAX_Z = 136.71       # pocket wall Z 135-136.7
RECESS_EXTRA = 2.0
BOSS_R = 12.05                  # boss outer wall r=12, top chamfer to r=11
SEAT_MIN_Z = 5.0                # recess ceiling Z=5.5, panel top Z=9.5/10.5
SEAT_MAX_Z = 10.6
WINDOW_HALF = v4.LID_SQUARE_HALF
WINDOW_STEP = 1.0               # per side: 30x30 -> 32x32


def shrink_magnet(p, in_pocket_band):
    for centre in MAGNETS:
        dx, dy = p[0] - centre[0], p[1] - centre[1]
        r = math.hypot(dx, dy)
        if r >= MAGNET_R + 0.5 or not in_pocket_band:
            continue
        if abs(r - MAGNET_R) > 0.02:
            raise ValueError(f"Unexpected vertex at r={r:.3f} in magnet pocket {centre}.")
        k = (r - MAGNET_SHRINK) / r
        p[0], p[1] = centre[0] + dx * k, centre[1] + dy * k
        return True
    return False


def deepen_recess(p):
    r = math.hypot(p[0] - v4.CASE_BUTTON[0], p[1] - v4.CASE_BUTTON[1])
    if r > BOSS_R:
        return
    if SEAT_MIN_Z <= p[2] <= SEAT_MAX_Z:
        p[2] += RECESS_EXTRA
    elif 1.6 < p[2] < SEAT_MIN_Z or SEAT_MAX_Z < p[2] < 23.5:
        raise ValueError(f"Unexpected vertex near the bottom button: {p}.")


def move_case(p):
    in_band = p[2] >= CASE_MAGNET_MIN_Z
    v4.move_case(p)
    shrink_magnet(p, in_band)
    deepen_recess(p)
    return p


def widen_window(p):
    """Grow the original 30x30 window to 32x32; walls and top fillet hold only corner vertices."""
    dx, dy = p[0] - v4.LID_SQUARE[0], p[1] - v4.LID_SQUARE[1]
    half = max(abs(dx), abs(dy))
    on_bore = abs(half - WINDOW_HALF) < 0.01
    on_fillet = WINDOW_HALF <= half < 16.62 and p[2] > v4.LID_SQUARE_FILLET_TOP
    if not (on_bore or on_fillet):
        if half < 16.62 and p[2] > v4.LID_SQUARE_FILLET_TOP or half < WINDOW_HALF:
            raise ValueError(f"Unexpected vertex near the square window: {p}.")
        return
    if abs(abs(dx) - abs(dy)) > 0.01:
        raise ValueError(f"Square window vertex is not on a corner: {p}.")
    p[0] += math.copysign(WINDOW_STEP, dx)
    p[1] += math.copysign(WINDOW_STEP, dy)


def move_lid(p):
    if shrink_magnet(p, p[2] <= LID_MAGNET_MAX_Z):
        return p
    for centre in v4.LID_BUTTONS:
        if v4.widen(p, centre, v4.LID_BUTTON_R, [(11.7, 13.5)]):
            return p
    widen_window(p)
    return p


def main():
    data, count = v4.read_stl(ROOT.parent / "originals" / "gamepad_case_original.stl")
    case = v4.rewrite(data, count, "V5: V4 case, magnets 10.1, bottom recess +2 mm", move_case)
    (ROOT / "gamepad_case_v5_raw.stl").write_bytes(case)

    data, count = v4.read_stl(ROOT.parent / "originals" / "gamepad_lid_original.stl")
    lid = v4.rewrite(data, count, "V5 lid base: holes 24.6, window 32x32, magnets 10.1", move_lid)
    (ROOT / "gamepad_lid_v5_base.stl").write_bytes(lid)
    print("gamepad_case_v5_raw.stl gamepad_lid_v5_base.stl")


if __name__ == "__main__":
    main()
