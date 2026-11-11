"""V4 sources: 30 mm tall shell and all button holes 1 mm larger in diameter.

Only selected vertices are moved; the floor, walls, posts and lid plate keep their
original thickness. Writes gamepad_case_v4_raw.stl, button_profile_v4.scad and
gamepad_lid_v4.stl (same coordinates as the supplied lid).
"""

from pathlib import Path
import math
import shutil
import struct
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent / "v2"))
from prepare_case_v2 import button_outline

LID_SOURCE = Path.home() / "Downloads" / "Лунный Контроллер.stl"

CASE_HEIGHT = 30.0
ORIGINAL_HEIGHT = 25.232
DIAMETER_INCREASE = 1.0
CASE_BUTTON = (0.0, 28.75)
CASE_BUTTON_R = 10.5
LID_BUTTONS = [(0.0, -17.75), (-43.0, -24.75), (43.0, -24.75)]
LID_BUTTON_R = 14.0
LID_SQUARE = (0.0, 28.75)
LID_SQUARE_HALF = 15.0
LID_SQUARE_FILLET_TOP = 137.1


def read_stl(path):
    data = path.read_bytes()
    count = struct.unpack_from("<I", data, 80)[0]
    if len(data) != 84 + count * 50:
        raise ValueError(f"{path.name}: expected a binary STL.")
    return data, count


def rewrite(data, count, header, move):
    result = bytearray(header.encode().ljust(80, b"\0")[:80])
    result.extend(struct.pack("<I", count))
    for offset in range(84, len(data), 50):
        values = struct.unpack_from("<12fH", data, offset)
        points = [move(list(values[i:i + 3])) for i in (3, 6, 9)]
        a, b, c = points
        u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
        normal = [u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0]]
        length = math.sqrt(sum(n*n for n in normal))
        if length == 0:
            raise ValueError("Degenerate triangle after editing.")
        result.extend(struct.pack("<12fH", *(n / length for n in normal),
                                  *(x for p in points for x in p), values[-1]))
    return bytes(result)


def widen(p, centre, limit, allowed):
    dx, dy = p[0] - centre[0], p[1] - centre[1]
    r = math.hypot(dx, dy)
    if r >= limit:
        return False
    if not any(lo <= r <= hi for lo, hi in allowed):
        raise ValueError(f"Unexpected vertex at r={r:.3f} near {centre}.")
    k = (r + DIAMETER_INCREASE / 2) / r
    p[0], p[1] = centre[0] + dx * k, centre[1] + dy * k
    return True


def move_case(p):
    if 10.51 < p[2] < 23.5:
        raise ValueError("Unexpected intermediate feature: stretching must be reconsidered.")
    if p[2] >= 23.5:
        p[2] += CASE_HEIGHT - ORIGINAL_HEIGHT
    # Finger recess, button bore and its top chamfer; the boss stays at r>=11.
    widen(p, CASE_BUTTON, CASE_BUTTON_R, [(6.2, 7.3), (9.9, 10.2)])
    return p


def widen_square(p):
    """Grow the 30x30 window by 1 mm; its walls and top fillet hold only corner vertices."""
    dx, dy = p[0] - LID_SQUARE[0], p[1] - LID_SQUARE[1]
    half = max(abs(dx), abs(dy))
    on_bore = abs(half - LID_SQUARE_HALF) < 0.01
    on_fillet = LID_SQUARE_HALF <= half < 16.62 and p[2] > LID_SQUARE_FILLET_TOP
    if not (on_bore or on_fillet):
        if half < 16.62 and p[2] > LID_SQUARE_FILLET_TOP or half < LID_SQUARE_HALF:
            raise ValueError(f"Unexpected vertex near the square window: {p}.")
        return False
    if abs(abs(dx) - abs(dy)) > 0.01:
        raise ValueError(f"Square window vertex is not on a corner: {p}.")
    step = DIAMETER_INCREASE / 2
    p[0] += math.copysign(step, dx)
    p[1] += math.copysign(step, dy)
    return True


def move_lid(p):
    for centre in LID_BUTTONS:
        # Bore and top fillet; the nearest other lid feature is >20 mm away.
        if widen(p, centre, LID_BUTTON_R, [(11.7, 13.5)]):
            return p
    # Nearest other feature is 19.47 mm from the window centre.
    widen_square(p)
    return p


def main():
    data, count = read_stl(ROOT.parent / "originals" / "gamepad_case_original.stl")
    case = rewrite(data, count, "V4: 30 mm shell, bottom button opening +1 mm", move_case)
    (ROOT / "gamepad_case_v4_raw.stl").write_bytes(case)
    outline = button_outline(case, 1.0)
    (ROOT / "button_profile_v4.scad").write_text(
        "// Generated from the enlarged V4 button opening at Z=1 mm.\nbutton_outline_v4 = [\n"
        + ",\n".join("    [" + ", ".join(f"{v:.9f}" for v in p) + "]" for p in outline)
        + "\n];\n"
    )

    original_lid = ROOT.parent / "originals" / "gamepad_lid_original.stl"
    if not original_lid.exists():
        shutil.copyfile(LID_SOURCE, original_lid)
    data, count = read_stl(original_lid)
    lid = rewrite(data, count, "V4 lid: button holes and square window +1 mm", move_lid)
    (ROOT / "gamepad_lid_v4.stl").write_bytes(lid)
    print("gamepad_case_v4_raw.stl button_profile_v4.scad gamepad_lid_v4.stl")


if __name__ == "__main__":
    main()
