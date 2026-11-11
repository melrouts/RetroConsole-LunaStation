"""Shorten the supplied shell without scaling its floor, button seat or screw pockets."""

from pathlib import Path
import math
import struct

ROOT = Path(__file__).resolve().parent
HEIGHT_REDUCTION = 3.0


def button_outline(data, height=1.0):
    neighbours = {}
    coordinates = {}
    for offset in range(84, len(data), 50):
        values = struct.unpack_from("<12fH", data, offset)
        vertices = [values[i:i + 3] for i in (3, 6, 9)]
        hits = []
        for a, b in zip(vertices, vertices[1:] + vertices[:1]):
            if (a[2] - height) * (b[2] - height) < 0:
                t = (height - a[2]) / (b[2] - a[2])
                p = tuple(a[i] + t * (b[i] - a[i]) for i in (0, 1))
                key = tuple(round(x, 5) for x in p)
                coordinates[key] = p
                hits.append(key)
        if len(hits) == 2:
            a, b = hits
            neighbours.setdefault(a, []).append(b)
            neighbours.setdefault(b, []).append(a)
    if any(len(n) != 2 for n in neighbours.values()):
        raise ValueError("Section is not a set of closed contours.")
    loops, remaining = [], set(neighbours)
    while remaining:
        start = next(iter(remaining))
        previous, current, loop = None, start, []
        while current != start or not loop:
            loop.append(coordinates[current])
            remaining.remove(current)
            following = next(n for n in neighbours[current] if n != previous)
            previous, current = current, following
        loops.append(loop)
    if len(loops) != 2:
        raise ValueError("Expected one outside contour and one button opening.")

    def area(points):
        return sum(a[0]*b[1] - a[1]*b[0] for a, b in zip(points, points[1:] + points[:1]))

    points = min(loops, key=lambda p: abs(area(p)))
    if area(points) < 0:
        points.reverse()
    result = []
    for i, p in enumerate(points):
        before, after = points[i-1], points[(i+1) % len(points)]
        normals = []
        for a, b in [(before, p), (p, after)]:
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            normals.append((dy / length, -dx / length))
        nx, ny = (normals[0][j] + normals[1][j] for j in (0, 1))
        denominator = nx * normals[0][0] + ny * normals[0][1]
        if denominator < 0.1:
            raise ValueError("Unexpected sharp corner in button contour.")
        result.append([p[0], p[1], nx / denominator, ny / denominator])
    return result


def main():
    data = (ROOT.parent / "originals" / "gamepad_case_original.stl").read_bytes()
    count = struct.unpack_from("<I", data, 80)[0]
    if len(data) != 84 + count * 50:
        raise ValueError("Expected the original binary STL.")
    result = bytearray(b"V2: upper rim and mounting pockets lowered by 3 mm".ljust(80, b"\0"))
    result.extend(struct.pack("<I", count))
    for offset in range(84, len(data), 50):
        values = struct.unpack_from("<12fH", data, offset)
        points = [list(values[i:i + 3]) for i in (3, 6, 9)]
        for p in points:
            if 10.51 < p[2] < 23.5:
                raise ValueError("Unexpected intermediate feature: shortening must be reconsidered.")
            if p[2] >= 23.5:
                p[2] -= HEIGHT_REDUCTION
        a, b, c = points
        u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
        normal = [u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0]]
        length = math.sqrt(sum(n*n for n in normal))
        if length == 0:
            raise ValueError("Degenerate triangle after shortening.")
        result.extend(struct.pack("<12fH", *(n / length for n in normal),
                                  *(x for p in points for x in p), values[-1]))
    target = ROOT / "gamepad_case_v2_thin_raw.stl"
    target.write_bytes(result)
    outline = button_outline(data)
    (ROOT / "button_profile_v2.scad").write_text(
        "// Generated from the original button opening at Z=1 mm.\nbutton_outline = [\n"
        + ",\n".join("    [" + ", ".join(f"{v:.9f}" for v in p) + "]" for p in outline)
        + "\n];\n"
    )
    print(target.name)


if __name__ == "__main__":
    main()
