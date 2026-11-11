#!/usr/bin/env python3
"""Export and check the V1 concept. Run with the project's .venv Python."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont
from shapely.affinity import translate
from shapely.geometry import Point, Polygon, box
from shapely.ops import unary_union
import trimesh

ROOT = Path(__file__).resolve().parent
SCAD = ROOT / "luna_station.scad"
PARTS = ("bottom", "base_text", "base_accent", "lid", "text", "accent", "bridge")
FIT = "fit_test"  # one-colour test print, cut from the real bottom
PRINTED = PARTS + (FIT,)
REFERENCES = ("pcb", "speaker")
# 3MF object id and material index; ids 7 and 11 are the three-colour lid and base groups.
OBJECTS = {"bottom": (2, 0), "lid": (3, 1), "text": (4, 2), "accent": (5, 3),
           "bridge": (6, 0), FIT: (8, 0), "base_text": (9, 2), "base_accent": (10, 3)}
GROUPS = {"lid": (7, "Lid - three colours", (3, 4, 5)),
          "bottom": (11, "Base - three colours", (2, 9, 10))}
PALETTES = [
    ("Orbital graphite", ["#282D36", "#282D36", "#ECECE4", "#FF8B25"]),
    ("Lunar silver", ["#282D36", "#BFC4C8", "#282D36", "#FF781F"]),
    ("Deep space", ["#172C46", "#172C46", "#F2EEE3", "#42D6D1"]),
]
NS = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
ET.register_namespace("", NS)

# P1S system profile: 256 mm bed, front-left 18 x 28 mm exclusion.
PRINT_BED = box(0, 0, 256, 256)
PRINT_EXCLUSION = box(0, 0, 18, 28)
PRINT_MARGIN = 6  # room for a 5 mm brim plus 1 mm clearance
# Reserved prime-tower areas, including the tower's own brim.
TOWER_SPACE = {"lid": box(28, 170, 228, 250), "base": box(110, 150, 250, 250)}
PRINT_PLATES = {
    "lid": (("lid", "text", "accent"), ((7, 128, 90),)),
    "base": (("bottom", "base_text", "base_accent", "bridge"), ((11, 128, 70), (6, 60, 196))),
    FIT: ((FIT,), ((8, 128, 128),)),
}

# Reuse the project's existing mesh-section implementation.
spec = importlib.util.spec_from_file_location(
    "lid_geometry", ROOT.parents[1] / "gamepad-power-holder/v6/prepare_lid_v6.py")
geometry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(geometry)


def openscad():
    exe = os.environ.get("OPENSCAD") or shutil.which("openscad")
    if not exe:
        exe = "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD"
    if not Path(exe).is_file():
        raise SystemExit("OpenSCAD not found. Set OPENSCAD to its executable.")
    return exe


def render(part, output, *options):
    log = ROOT / "checks" / (output.stem + ".log")
    command = [openscad(), "--hardwarnings", "-o", str(output), "-D", f'part="{part}"',
               *options, str(SCAD)]
    result = subprocess.run(command, capture_output=True, text=True)
    log.write_text(result.stdout + result.stderr)
    if result.returncode or not output.is_file() or "ERROR:" in log.read_text():
        raise RuntimeError(f"OpenSCAD failed for {output.name}:\n{log.read_text()}")
    print(f"exported {output.relative_to(ROOT)}", flush=True)


def export_meshes():
    for part in PRINTED + REFERENCES:
        folder = ROOT / ("stl" if part in PRINTED else "checks")
        render(part, folder / f"{part}.stl", "--export-format", "binstl")
    echo = ROOT / "checks/parameters.echo"
    render("parameters", echo)
    line = next(s for s in echo.read_text().splitlines() if s.startswith("ECHO: "))
    parameters = dict(json.loads(line.removeprefix("ECHO: ")))
    (ROOT / "checks/parameters.json").write_text(json.dumps(parameters, indent=2) + "\n")


def section(mesh, z):
    if not mesh.bounds[0, 2] < z < mesh.bounds[1, 2]:
        return Polygon()
    return geometry.section(mesh, z)


def hole_at(poly, point):
    candidates = []
    for item in getattr(poly, "geoms", [poly]):
        for ring in item.interiors:
            hole = Polygon(ring)
            if hole.contains(Point(point)):
                candidates.append(hole)
    # A post is an island inside the enclosure cavity: choose its bore, not
    # the enclosing cavity's ring.
    return min(candidates, key=lambda h: h.area) if candidates else None


def overlap_volume(a, b):
    overlap = trimesh.boolean.intersection([a, b], engine="manifold")
    triangles = overlap.triangles
    return abs(np.einsum("ij,ij->i", triangles[:, 0],
                        np.cross(triangles[:, 1], triangles[:, 2])).sum() / 6)


def check_meshes():
    p = json.loads((ROOT / "checks/parameters.json").read_text())
    meshes = {name: trimesh.load_mesh(ROOT / ("stl" if name in PRINTED else "checks") / f"{name}.stl")
              for name in PRINTED + REFERENCES}
    checks = []

    def check(condition, message):
        checks.append({"passed": bool(condition), "description": message})
        print(("PASS " if condition else "FAIL ") + message, flush=True)

    def hole(name, z, xy, diameter):
        h = hole_at(section(meshes[name], z), xy)
        actual = 0 if h is None else 2 * np.sqrt(h.area / np.pi)
        check(abs(actual - diameter) < 0.04, f"{name} bore at {xy}, Z {z:g}: "
              f"{actual:.3f} mm (target {diameter:g})")

    for name, mesh in meshes.items():
        check(mesh.is_volume, f"{name}: watertight, consistently oriented, positive volume")
        if name in ("bottom", "lid", "bridge", FIT):
            check(len(mesh.split()) == 1, f"{name}: one connected solid")

    check(np.allclose(meshes["bottom"].extents, [*p["case_xy"], p["base_h"] + p["lip_h"]], atol=0.02),
          "bottom extents match the CAD parameters, including lip")
    check(abs(meshes["lid"].bounds[1, 2] - p["total_h"]) < 0.01,
          "assembled height matches the CAD parameters")
    check(np.allclose(meshes["pcb"].extents[:2], p["pcb"], atol=0.01), "PCB is 160 x 80 mm")

    for xy in p["holes"]:
        hole("bottom", p["board_z"] - 1, xy, p["insert_bore"])
        check(section(meshes["bottom"], p["board_z"] - p["insert_depth"] - 0.1).contains(Point(xy)),
              f"M3 insert pocket at {xy} has a closed floor")
        hole("pcb", p["board_z"] + 0.5, xy, p["pcb_hole_d"])

    for xy in p["magnets"]:
        for name, z in (("bottom", p["base_h"] - 0.7), ("lid", p["lid_z"] + 0.7)):
            hole(name, z, xy, p["magnet_bore"])
        check(section(meshes["bottom"], p["base_h"] - p["magnet_depth"] - 0.1).contains(Point(xy))
              and section(meshes["lid"], p["lid_z"] + p["magnet_depth"] + 0.1).contains(Point(xy)),
              f"paired magnet pockets at {xy} are blind")
        magnet = Point(xy).buffer(p["magnet_d"] / 2)
        check(magnet.difference(hole_at(section(meshes["bottom"], p["base_h"] - 0.7), xy)).area < 0.001,
              f"10 mm magnet fits the lower pocket at {xy}")

    # Rotate Y into Z so the existing section helper can inspect the side walls.
    side_mesh = meshes["bottom"].copy()
    side_mesh.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [1, 0, 0]))
    measurements = {name: (plug, above_pcb, from_edge)
                    for name, plug, above_pcb, from_edge in p["port_measurements"]}
    openings, corridors = {}, {}
    for name, side, x, z, (width, height), radius in p["ports"]:
        (plug_w, plug_h), above_pcb, from_edge = measurements[name]
        check(np.allclose([x, z], [-p["pcb"][0] / 2 + from_edge, p["pcb_top"] + above_pcb]),
              f"{name}: centre follows measured PCB-relative offsets")
        check(np.allclose([width, height], np.array([plug_w, plug_h]) + 2 * p["port_clearance"]),
              f"{name}: {p['port_clearance']:g} mm clearance per side of measured plug")
        check(side == (1 if name == "HDMI" else -1) and x + width / 2 < 0,
              f"{name}: correct wall in the top view with readable text (HDMI +Y, USB-C -Y)")
        expected = unary_union([
            Point(x + sx * (width / 2 - radius), -z + sz * (height / 2 - radius))
            .buffer(radius, quad_segs=24)
            for sx in (-1, 1) for sz in (-1, 1)
        ]).convex_hull
        plug_profile = box(x - plug_w / 2, -z - plug_h / 2, x + plug_w / 2, -z + plug_h / 2)
        check(expected.covers(plug_profile),
              f"{name}: rounded corners do not clip the measured rectangular plug envelope")
        throat_y = side * (p["case_xy"][1] / 2 - p["wall"] / 2)
        opening = hole_at(section(side_mesh, throat_y), (x, -z))
        openings[name] = opening
        actual = np.zeros(2) if opening is None else np.subtract(opening.bounds[2:], opening.bounds[:2])
        check(np.allclose(actual, [width, height], atol=0.03),
              f"{name}: side-wall aperture {actual.round(3).tolist()} mm (target {width} x {height})")
        check(opening is not None and opening.symmetric_difference(expected).area < 0.05,
              f"{name}: rounded throat matches its complete specified profile")
        for depth in (0.05, p["wall"] / 2, p["wall"] + 0.1,
                      p["case_xy"][1] / 2 - abs(p["magnets"][0][1]),
                      (p["case_xy"][1] - p["pcb"][1]) / 2 - 0.1):
            obstruction = section(side_mesh, side * (p["case_xy"][1] / 2 - depth))
            check(obstruction.intersection(expected).area < 0.02,
                  f"{name}: clear from exterior to PCB edge at depth {depth:g} mm")
        entry = hole_at(section(side_mesh, side * (p["case_xy"][1] / 2 - 0.05)), (x, -z))
        check(entry is not None and opening is not None and entry.area > opening.area + 1,
              f"{name}: exterior lead-in bevel opens outwards")
        web = p["base_h"] - z - height / 2 - p["port_bevel"]
        check(web >= 1.6, f"{name}: {web:.2f} mm web beneath seam; locating lip is continuous")
        path = trimesh.convex.convex_hull([
            [px, side * y, -pz]
            for y in (p["pcb"][1] / 2 + 0.01, p["case_xy"][1] / 2 + 0.1)
            for px, pz in expected.exterior.coords[:-1]
        ])
        corridors[name] = path
        for part in ("bottom", "lid", "bridge"):
            volume = overlap_volume(path, meshes[part])
            check(volume < 0.002,
                  f"{name}: entire aperture corridor to PCB edge clears {part} ({volume:.6f} mm3)")

    hole("bridge", p["bridge_top"] - 1, p["speaker_xy"], p["speaker_bore"])
    for xy in p["bridge_feet"]:
        hole("bridge", p["pcb_top"] + 1, xy, p["bolt_d"])
        hole("bridge", p["bridge_top"] - 1, xy, p["bolt_d"])

    pairs = [
        ("bottom", "lid"), ("bottom", "pcb"), ("bottom", "bridge"),
        ("lid", "pcb"), ("lid", "bridge"), ("bridge", "pcb"),
        ("speaker", "bottom"), ("speaker", "lid"), ("speaker", "bridge"), ("speaker", "pcb"),
        ("lid", "text"), ("lid", "accent"), ("text", "accent"),
        ("bottom", "base_text"), ("bottom", "base_accent"), ("base_text", "base_accent"),
    ]
    for a, b in pairs:
        volume = overlap_volume(meshes[a], meshes[b])
        check(volume < 0.002, f"{a} / {b}: intersection {volume:.6f} mm3")

    inlay_z = p["total_h"] - p["inlay_depth"] / 2
    roof = section(meshes["lid"], inlay_z)
    for name in ("text", "accent"):
        colour = section(meshes[name], inlay_z)
        backing = section(meshes["lid"], p["total_h"] - p["inlay_depth"] - 0.1)
        check(colour.difference(backing).area < 0.02, f"{name}: all islands have solid backing")
        check(colour.intersection(roof).area < 0.02, f"{name}: no overlap with lid body at the colour layer")
        check(abs(meshes[name].extents[2] - p["inlay_depth"]) < 0.001,
              f"{name}: exactly {p['inlay_depth']:g} mm deep")

    # Base: bottom-face colour inlays, feet pockets and styled vents.
    base_colour_z = p["inlay_depth"] / 2
    floor_face = section(meshes["bottom"], base_colour_z)
    for name in ("base_text", "base_accent"):
        mesh = meshes[name]
        colour = section(mesh, base_colour_z)
        backing = section(meshes["bottom"], p["inlay_depth"] + 0.1)
        check(abs(mesh.bounds[0, 2]) < 0.001 and abs(mesh.extents[2] - p["inlay_depth"]) < 0.001,
              f"{name}: on the bed, exactly {p['inlay_depth']:g} mm deep")
        check(colour.difference(backing).area < 0.02, f"{name}: all islands have solid backing")
        check(colour.intersection(floor_face).area < 0.02, f"{name}: no overlap with the base body")
    check(not section(meshes["base_text"], base_colour_z).intersects(section(meshes["base_accent"], base_colour_z)),
          "base_text / base_accent: colours do not touch")
    for xy in p["feet"]:
        hole("bottom", p["foot_depth"] / 2, xy, p["foot_d"])
        check(section(meshes["bottom"], p["foot_depth"] + 0.1).contains(Point(xy).buffer(p["foot_d"] / 2)),
              f"bottom: foot pocket at {xy} is blind, {p['foot_depth']:g} mm deep")
    moon = Point(p["speaker_xy"]).buffer(p["moon_r"], quad_segs=96)
    floor_mid = section(meshes["bottom"], p["floor_t"] / 2)
    open_ratio = moon.difference(floor_mid).area / moon.area
    check(0.15 <= open_ratio <= 0.5, f"bottom: halftone disk open area {100 * open_ratio:.1f}%")
    floor_parts = getattr(floor_mid, "geoms", [floor_mid])
    floor_holes = unary_union([Polygon(g.exterior) for g in floor_parts]).difference(floor_mid)
    stray = floor_holes.difference(moon).area
    check(stray < 0.01, f"bottom: floor openings stay inside the halftone disk ({stray:.4f} mm2)")
    damaged = []
    posts = [(xy, p["magnet_boss_d"], p["base_h"], p["magnet_d"] + 0.8) for xy in p["magnets"]]
    posts += [(xy, p["boss_d"], p["board_z"], p["insert_bore"] + 0.6) for xy in p["holes"]]
    for z in np.arange(p["floor_t"] + 0.5, p["base_h"], 1.5):
        level = section(meshes["bottom"], z)
        for xy, boss, top, bore in posts:
            if z < top and Point(xy).buffer(boss / 2 - 0.05).difference(level).area > np.pi * bore ** 2 / 4:
                damaged.append((xy, float(z)))
    check(not damaged, f"bottom: vents leave every PCB and magnet post intact {damaged[:3]}")
    side = section(meshes["bottom"], 14.5)
    wall_band = box(p["vent_x"][0] - 3, p["case_xy"][1] / 2 - p["wall"], p["vent_x"][1] + 3, p["case_xy"][1] / 2)
    check(wall_band.difference(side).area > 1, "bottom: side vents open through the long walls")

    pcb_edge = section(meshes["pcb"], p["board_z"] + 0.5)
    case_wall = section(meshes["bottom"], p["board_z"] + 0.5)
    clearance = pcb_edge.distance(case_wall)
    check(clearance >= 1.5, f"PCB edge to wall/magnet posts: {clearance:.2f} mm")
    check(p["roof_z"] - meshes["speaker"].bounds[1, 2] >= 3,
          f"provisional speaker front clearance: {p['roof_z'] - meshes['speaker'].bounds[1, 2]:.2f} mm")
    collar = section(meshes["bottom"], p["base_h"] + 1)
    socket = section(meshes["lid"], p["base_h"] + 1)
    check(collar.distance(socket) >= p["fit_gap"] - 0.02,
          f"locating lip clearance: {collar.distance(socket):.3f} mm")
    check(p["lid_z"] + p["lip_h"] + p["fit_gap"] < p["roof_z"],
          "raised seam leaves solid backing above the lid's locating socket")
    grille_disk = Point(p["speaker_xy"]).buffer(23.6, quad_segs=96)
    open_area = grille_disk.difference(section(meshes["lid"], p["roof_z"] + 1)).area
    ratio = open_area / grille_disk.area
    check(ratio >= 0.40, f"grille open area within 47.2 mm diameter: {100 * ratio:.1f}%")

    # Fit test: the bottom's locating regions, lowered by fit_cut onto a thin frame.
    fit, cut = meshes[FIT], p["fit_cut"]
    check(abs(fit.bounds[0, 2]) < 0.001 and abs(fit.bounds[1, 2] - (p["base_h"] - cut)) < 0.01,
          f"{FIT}: starts on the bed; window walls keep full height to the seam")
    top = p["board_z"] - cut
    for xy in p["holes"]:
        hole(FIT, top - 1, xy, p["insert_bore"])
        check(section(fit, top - p["insert_depth"] - 0.1).contains(Point(xy))
              and section(fit, top - 0.1).contains(Point(xy[0] + p["insert_bore"] / 2 + 0.5, xy[1]))
              and not section(fit, top + 0.1).intersects(Point(xy).buffer(p["boss_d"] / 2 + 0.5)),
              f"{FIT}: post at {xy} has a blind insert pocket and ends at the PCB underside")
    pad_top = p["floor_t"] + p["fit_magnet_pad"] - cut
    for y, d in zip(p["fit_magnet_y"], p["fit_magnet_d"]):
        xy = (p["fit_coupon_x"], y)
        hole(FIT, pad_top - 0.7, xy, d)
        check(section(fit, pad_top - p["magnet_depth"] - 0.1).contains(Point(xy)),
              f"{FIT}: magnet coupon {d:.1f} mm is blind, {p['magnet_depth']:g} mm deep")
    for y, d in zip(p["fit_insert_y"], p["fit_insert_d"]):
        xy = (p["fit_coupon_x"], y)
        hole(FIT, top - 1, xy, d)
        check(section(fit, top - p["insert_depth"] - 0.1).contains(Point(xy)),
              f"{FIT}: insert coupon {d:.1f} mm has a closed floor")
    hole(FIT, p["fit_floor"] / 2, p["speaker_xy"], p["speaker_bore"])

    def band(lo, hi):
        return box(p["fit_wall_x"][0], lo, p["fit_wall_x"][1], hi)

    walls = band(p["fit_wall_y"], p["case_xy"][1]).union(band(-p["case_xy"][1], -p["fit_wall_y"]))
    posts = unary_union([Point(xy).buffer(p["boss_d"] / 2 + 0.4) for xy in p["holes"]])
    levels = [("posts", posts, z) for z in (p["floor_t"] + 1, p["board_z"] - 0.5)]
    levels += [("window walls", walls, z) for z in (
        p["floor_t"] + p["fit_gusset"][2] + 0.5, *(port[3] for port in p["ports"]), p["base_h"] - 0.2)]
    for label, region, z in levels:
        copy = section(fit, z - cut).intersection(region)
        error = copy.symmetric_difference(section(meshes["bottom"], z).intersection(region)).area
        check(error < 0.05, f"{FIT}: {label} at case Z {z:g} copy the bottom ({error:.4f} mm2)")
    fit_side = fit.copy()
    fit_side.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [1, 0, 0]))
    for name, side, x, z, _, _ in p["ports"]:
        throat_y = side * (p["case_xy"][1] / 2 - p["wall"] / 2)
        window = hole_at(section(fit_side, throat_y), (x, cut - z))
        error = np.inf if window is None else \
            translate(window, yoff=-cut).symmetric_difference(openings[name]).area
        check(error < 0.05, f"{FIT}: {name} window matches the case aperture ({error:.4f} mm2)")
        path = corridors[name].copy()
        path.apply_translation([0, 0, -cut])
        volume = overlap_volume(path, fit)
        check(volume < 0.002, f"{FIT}: {name} aperture corridor to PCB edge is clear ({volume:.6f} mm3)")
    board = meshes["pcb"].copy()
    board.apply_translation([0, 0, -cut])
    volume = overlap_volume(board, fit)
    check(volume < 0.002, f"{FIT} / pcb: intersection {volume:.6f} mm3")
    under = box(*np.divide(p["pcb"], -2), *np.divide(p["pcb"], 2)).difference(posts.buffer(0.2))
    for z in (p["fit_floor"] + p["fit_text_h"] + 0.2, top - 0.2):
        area = section(fit, z).intersection(under).area
        check(area < 0.01, f"{FIT}: only the four posts rise under the PCB at Z {z:g} ({area:.4f} mm2)")

    report = {"scope": "CAD concept only; no physical fit, thermal or acoustic verification",
              "checks": checks,
              "parts": {name: {"extents_mm": mesh.extents.tolist(), "volume_cm3": mesh.volume / 1000}
                        for name, mesh in meshes.items()}}
    (ROOT / "checks/report.json").write_text(json.dumps(report, indent=2) + "\n")
    if not all(c["passed"] for c in checks):
        raise SystemExit("Geometry checks failed. See checks/report.json.")
    return meshes, p


def xml_child(parent, name, attributes=None):
    return ET.SubElement(parent, f"{{{NS}}}{name}", attributes or {})


def check_print_layout(scene, plate):
    expected, _ = PRINT_PLATES[plate]
    if set(scene.geometry) != set(expected) or len(scene.graph.nodes_geometry) != len(expected):
        raise RuntimeError(f"{plate}: incomplete 3MF round trip")
    footprints = {}
    bounds = {}
    for node in scene.graph.nodes_geometry:
        transform, key = scene.graph[node]
        restored = scene.geometry[key].copy()
        restored.apply_transform(transform)
        if not restored.is_volume or abs(restored.bounds[0, 2]) > 0.001:
            raise RuntimeError(f"{plate}: invalid print orientation or solid: {node}")
        lo, hi = restored.bounds
        footprint = box(*lo[:2], *hi[:2])
        envelope = footprint.buffer(PRINT_MARGIN, join_style=2)
        if not PRINT_BED.covers(envelope):
            raise RuntimeError(f"{plate}: {key} exceeds the P1S bed with {PRINT_MARGIN} mm margin")
        if envelope.intersects(PRINT_EXCLUSION):
            raise RuntimeError(f"{plate}: {key} is too close to the P1S exclusion area")
        if plate in TOWER_SPACE and envelope.intersects(TOWER_SPACE[plate]):
            raise RuntimeError(f"{plate}: {key} intrudes into reserved tower space")
        footprints[key] = footprint
        bounds[key] = restored.bounds.tolist()
    if plate == "base" and footprints["bottom"].distance(footprints["bridge"]) < 2 * PRINT_MARGIN:
        raise RuntimeError("base: bottom and bridge brim envelopes overlap")
    return {"parts": bounds, "margin_mm": PRINT_MARGIN,
            "exclusion_xy": list(PRINT_EXCLUSION.bounds),
            "reserved_tower_xy": list(TOWER_SPACE[plate].bounds) if plate in TOWER_SPACE else None}


def export_3mf(meshes, p):
    """Two core 3MF files per palette plus one fit test; no printer, process or filament presets."""
    layouts = {}
    jobs = [(ROOT / f"luna_station_{index + 1}_{plate}.3mf", name, colours, plate)
            for index, (name, colours) in enumerate(PALETTES)
            for plate in PRINT_PLATES if plate != FIT]
    jobs.append((ROOT / f"luna_station_{FIT}.3mf", "Fit test", PALETTES[0][1], FIT))
    for path, name, colours, plate in jobs:
        write_3mf(path, meshes, p, name, colours, *PRINT_PLATES[plate])
        layouts[path.name] = check_print_layout(trimesh.load(path), plate)
        print(f"exported {path.name}", flush=True)
    (ROOT / "checks/print_layout.json").write_text(json.dumps(layouts, indent=2) + "\n")


def write_3mf(path, meshes, p, name, colours, parts, placements):
    model = ET.Element(f"{{{NS}}}model", {"unit": "millimeter"})
    xml_child(model, "metadata", {"name": "Title"}).text = f"Luna Station V1 CONCEPT - {name}"
    resources = xml_child(model, "resources")
    materials = xml_child(resources, "basematerials", {"id": "1"})
    for label, colour in zip(("Bottom", "Lid", "Lettering", "Accent"), colours):
        xml_child(materials, "base", {"name": label, "displaycolor": colour + "FF"})
    for part, (oid, material) in OBJECTS.items():
        if part not in parts:
            continue
        mesh = meshes[part].copy()
        if part in ("lid", "text", "accent", "bridge"):
            top = p["bridge_top"] if part == "bridge" else p["total_h"]
            mesh.apply_transform(np.array([[1, 0, 0, 0], [0, -1, 0, 0],
                                           [0, 0, -1, top], [0, 0, 0, 1]]))
        if part in ("bridge", FIT):
            mesh.apply_translation([-mesh.bounds[:, 0].mean(), -mesh.bounds[:, 1].mean(), 0])
        if part == "base_text" and colours[2] == colours[0]:
            material = 1  # graphite lettering would vanish on a graphite base
        obj = xml_child(resources, "object", {"id": str(oid), "type": "model",
                                             "name": part, "pid": "1", "pindex": str(material)})
        element = xml_child(obj, "mesh")
        vertices = xml_child(element, "vertices")
        for x, y, z in mesh.vertices:
            xml_child(vertices, "vertex", dict(zip(("x", "y", "z"), (f"{v:.6f}" for v in (x, y, z)))))
        triangles = xml_child(element, "triangles")
        for face in mesh.faces:
            xml_child(triangles, "triangle", {f"v{i + 1}": str(v) for i, v in enumerate(face)})
    for part, (gid, label, members) in GROUPS.items():
        if part not in parts:
            continue
        obj = xml_child(resources, "object", {"id": str(gid), "type": "model", "name": label})
        components = xml_child(obj, "components")
        for oid in members:
            xml_child(components, "component", {"objectid": str(oid)})
    build = xml_child(model, "build")
    for oid, x, y in placements:
        xml_child(build, "item", {"objectid": str(oid), "transform": f"1 0 0 0 1 0 0 0 1 {x} {y} 0"})
    rels = ('<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Target="/3D/3dmodel.model" Id="rel0" '
            'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>')
    content = ('<?xml version="1.0" encoding="UTF-8"?>'
               '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
               '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
               '<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>'
               '</Types>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content)
        archive.writestr("_rels/.rels", rels)
        archive.writestr("3D/3dmodel.model", ET.tostring(model, encoding="utf-8", xml_declaration=True))


def export_previews():
    style = ("--projection", "o", "--colorscheme", "Tomorrow")
    fit = ("--viewall", "--autocenter")
    common = ("--imgsize", "1400,1050", *style, *fit)
    for i in range(3):
        for view, camera in (("iso", "0,0,20,52,0,22,360"), ("top", "0,0,20,0,0,0,360")):
            render("assembly", ROOT / "previews" / f"variant_{i + 1}_{view}.png",
                   *common, "--camera", camera, "-D", f"palette={i}")
    for part, camera in (("inside", "0,0,15,28,0,18,360"),
                         ("exploded", "0,0,40,58,0,24,430"),
                         ("section", "0,0,20,75,0,12,360"),
                         ("bridge", "45,0,20,40,0,25,180")):
        render(part, ROOT / "previews" / f"{part}.png", *common, "--camera", camera)
    render("assembly", ROOT / "previews/port_top.png", "--imgsize", "2000,1500", *style, *fit,
           "--camera", "0,0,20,0,0,0,360", "-D", "palette=0")
    parameters = json.loads((ROOT / "checks/parameters.json").read_text())
    for name, side, x, z, _, _ in parameters["ports"]:
        # Outside view of the wall with the window: azimuth 22 sees -Y, 202 sees +Y.
        # The target is 10 mm inboard so the window sits off-centre and the corner stays in frame.
        camera = (f"{x + 10:g},{side * parameters['case_xy'][1] / 2:g},{z - 4:g},"
                  f"76,0,{22 if side < 0 else 202},150")
        render("assembly", ROOT / "previews" / f"port_{name.lower().replace('-', '_')}.png",
               "--imgsize", "1400,800", *style, "--camera", camera, "-D", "palette=0")
    for view, camera, pcb in (("iso", "0,0,10,55,0,25,300", "true"),
                              ("top", "0,0,10,0,0,0,300", "false")):
        render("fit_preview", ROOT / "previews" / f"fit_{view}.png", *common,
               "--camera", camera, "-D", f"show_pcb={pcb}")
    # Base views: flipped about X (how the underside is read) and two low obliques.
    for view, camera, projection in (("bottom", "0,0,15,180,0,0,320", "o"),
                                     ("under", "0,0,15,215,0,20,440", "p"),
                                     ("side", "0,0,14,78,0,205,360", "p")):
        render("assembly", ROOT / "previews" / f"base_{view}.png", "--imgsize", "1500,1000",
               "--projection", projection, "--colorscheme", "Tomorrow", "--camera", camera,
               "-D", "palette=0")
    contact_sheet()
    port_sheet()
    fit_sheet()
    base_sheet()


def base_sheet():
    font = "/System/Library/Fonts/Supplemental/Arial.ttf"
    bold = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
    title, body = ImageFont.truetype(bold, 44), ImageFont.truetype(font, 25)
    image = Image.new("RGB", (2000, 1110), "#F1F2F4")
    draw = ImageDraw.Draw(image)
    draw.text((50, 36), "LUNA STATION / ДНО «КРАТЕРЫ»", font=title, fill="#212A36")
    draw.text((52, 100), "Три цвета на нижней грани (0.6 мм) · точки по бокам и полутоновая луна под динамиком · "
              "4 выемки под ножки", font=body, fill="#596475")

    def crop(name, size):
        frame = Image.open(ROOT / "previews" / f"base_{name}.png").convert("RGB")
        background = Image.new("RGB", frame.size, frame.getpixel((0, 0)))
        frame = frame.crop(ImageChops.difference(frame, background).getbbox())
        frame.thumbnail(size, Image.Resampling.LANCZOS)
        return frame

    bottom = crop("bottom", (1100, 1100))
    image.paste(bottom, (50, 170))
    y = 170
    for name in ("under", "side"):
        frame = crop(name, (780, 520))
        image.paste(frame, (1180 + (780 - frame.width) // 2, y))
        y += frame.height + 40
    draw.text((52, 1050), "Вид снизу — корпус перевёрнут через длинную сторону; надпись читается.",
              font=body, fill="#596475")
    image.save(ROOT / "previews/base.png")
    print("exported previews/base.png", flush=True)


def contact_sheet():
    image = Image.new("RGB", (2400, 1440), "#F1F2F4")
    draw = ImageDraw.Draw(image)
    font = "/System/Library/Fonts/Supplemental/Arial.ttf"
    title = ImageFont.truetype(font, 58)
    heading = ImageFont.truetype(font, 32)
    small = ImageFont.truetype(font, 26)
    draw.text((64, 42), "LUNA STATION / V1 CONCEPT", font=title, fill="#212A36")
    draw.text((66, 122), "188 x 120 x 44 mm  |  PCB 160 x 80 mm  |  magnetic split shell",
              font=small, fill="#596475")
    for i, (name, colours) in enumerate(PALETTES):
        x = 40 + i * 790
        draw.rounded_rectangle((x, 205, x + 760, 1330), radius=20, fill="white")
        label = f"0{i + 1} / {name}" + (" / SELECTED" if i == 0 else "")
        draw.text((x + 30, 238), label, font=heading, fill="#212A36")
        for view, y, height in (("iso", 315, 510), ("top", 835, 390)):
            frame = Image.open(ROOT / "previews" / f"variant_{i + 1}_{view}.png").convert("RGB")
            bg = Image.new("RGB", frame.size, frame.getpixel((0, 0)))
            bbox = ImageChops.difference(frame, bg).getbbox()
            frame = frame.crop(bbox)
            frame.thumbnail((710, height), Image.Resampling.LANCZOS)
            image.paste(frame, (x + (760 - frame.width) // 2, y + (height - frame.height) // 2))
        for j, colour in enumerate(colours[1:]):
            draw.rounded_rectangle((x + 30 + j * 75, 1260, x + 85 + j * 75, 1294),
                                   radius=8, fill=colour, outline="#C5C9CD")
    draw.text((65, 1370), "Measured cable windows; PCB mounting, connector reach and speaker fit still need confirmation.",
              font=small, fill="#596475")
    image.save(ROOT / "previews/color_options.png")

def port_sheet():
    p = json.loads((ROOT / "checks/parameters.json").read_text())
    case_x, case_y = p["case_xy"]

    def num(value):
        return f"{value:g}".replace("-", "−").replace(".", ",")

    image = Image.new("RGB", (2000, 1220), "#F1F2F4")
    draw = ImageDraw.Draw(image)
    font = "/System/Library/Fonts/Supplemental/Arial.ttf"
    bold = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
    title = ImageFont.truetype(font, 44)
    heading = ImageFont.truetype(font, 30)
    callout = ImageFont.truetype(bold, 32)
    small = ImageFont.truetype(font, 25)
    ink, accent = "#212A36", "#FF8B25"
    draw.text((50, 36), "LUNA STATION / ORBITAL GRAPHITE", font=title, fill=ink)
    draw.text((52, 100), "Вид сверху, текст читается, динамик справа: HDMI вверху (+Y), USB-C внизу (−Y).",
              font=small, fill="#596475")

    draw.rounded_rectangle((35, 160, 1285, 1140), radius=20, fill="white")
    draw.text((60, 182), "Вид сверху: окна в длинных боковых стенках", font=heading, fill=ink)
    frame = Image.open(ROOT / "previews/port_top.png").convert("RGB")
    background = Image.new("RGB", frame.size, frame.getpixel((0, 0)))
    outline = ImageChops.difference(frame, background)
    frame = frame.crop(outline.getbbox())
    if abs(frame.width / frame.height - case_x / case_y) > 0.01:
        raise RuntimeError("port_top.png: silhouette does not match the case outline")
    mask = outline.crop(outline.getbbox()).convert("L").point(lambda v: 255 if v else 0)
    frame = Image.composite(frame, Image.new("RGB", frame.size, "white"), mask)
    frame = frame.resize((1100, round(1100 * frame.height / frame.width)), Image.Resampling.LANCZOS)
    left, top = 110, 330
    image.paste(frame, (left, top))
    for name, side, x, z, (width, height), _ in p["ports"]:
        edge = top if side > 0 else top + frame.height
        x0, x1 = (left + (x + sign * width / 2 + case_x / 2) / case_x * frame.width for sign in (-1, 1))
        draw.rounded_rectangle((x0, edge - 9, x1, edge + 9), radius=9, fill=accent,
                               outline="white", width=2)
        label = f"{name}  {num(width)} × {num(height)} мм · Z{num(z)}"
        label_x = max(60, (x0 + x1) / 2 - draw.textlength(label, font=callout) / 2)
        label_y = edge - 85 if side > 0 else edge + 45
        lead = (edge - 45, edge - 9) if side > 0 else (edge + 9, edge + 45)
        draw.line(((x0 + x1) / 2, lead[0], (x0 + x1) / 2, lead[1]), fill=accent, width=4)
        draw.text((label_x, label_y), label, font=callout, fill=ink)

    panels = [("HDMI", "верхняя стенка (+Y)"), ("USB-C", "нижняя стенка (−Y)")]
    for i, (name, wall) in enumerate(panels):
        port = next(item for item in p["ports"] if item[0] == name)
        x, y = 1305, 160 + i * 505
        draw.rounded_rectangle((x, y, x + 660, y + 475), radius=20, fill="white")
        draw.text((x + 25, y + 20), f"{name} / {wall}", font=heading, fill=ink)
        draw.text((x + 25, y + 62), f"Вид снаружи · окно {num(port[4][0])} × {num(port[4][1])} мм · X{num(port[2])}",
                  font=small, fill="#596475")
        close = Image.open(ROOT / "previews" / f"port_{name.lower().replace('-', '_')}.png").convert("RGB")
        close = close.resize((620, round(620 * close.height / close.width)), Image.Resampling.LANCZOS)
        image.paste(close, (x + 20, y + 105))
    draw.text((52, 1166), f"По замерам кабелей, зазор {num(p['port_clearance'])} мм на сторону. Шов Z{num(p['base_h'])}. Глубина подключения ещё не измерена.",
              font=small, fill="#596475")
    image.save(ROOT / "previews/ports.png")


def fit_sheet():
    p = json.loads((ROOT / "checks/parameters.json").read_text())
    fit = trimesh.load_mesh(ROOT / "stl" / f"{FIT}.stl")
    (x_min, y_min, _), (x_max, y_max, height) = fit.bounds

    def num(value, digits=1):
        return f"{value:.{digits}f}".replace(".", ",")

    def silhouette(name):
        frame = Image.open(ROOT / "previews" / name).convert("RGB")
        background = Image.new("RGB", frame.size, frame.getpixel((0, 0)))
        outline = ImageChops.difference(frame, background)
        frame = frame.crop(outline.getbbox())
        mask = outline.crop(outline.getbbox()).convert("L").point(lambda v: 255 if v else 0)
        return Image.composite(frame, Image.new("RGB", frame.size, "white"), mask)

    image = Image.new("RGB", (2000, 1310), "#F1F2F4")
    draw = ImageDraw.Draw(image)
    font = "/System/Library/Fonts/Supplemental/Arial.ttf"
    bold = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
    title = ImageFont.truetype(font, 44)
    heading = ImageFont.truetype(font, 30)
    marker = ImageFont.truetype(bold, 30)
    body = ImageFont.truetype(font, 25)
    ink, grey, accent = "#212A36", "#596475", "#FF8B25"
    draw.text((50, 36), "LUNA STATION / ТЕСТ ПОСАДКИ", font=title, fill=ink)
    draw.text((52, 100), f"Один цвет, тот же пластик и профиль, что у корпуса · "
              f"{num(x_max - x_min, 0)} × {num(y_max - y_min, 0)} × {num(height)} мм · "
              f"каркас {num(p['fit_floor'])} мм", font=body, fill=grey)

    draw.rounded_rectangle((35, 160, 1285, 1240), radius=20, fill="white")
    draw.text((60, 182), "Вид сверху: части дна корпуса в реальных координатах", font=heading, fill=ink)
    top_view = silhouette("fit_top.png")
    if abs(top_view.width / top_view.height - (x_max - x_min) / (y_max - y_min)) > 0.01:
        raise RuntimeError("fit_top.png: silhouette does not match the fit-test outline")
    top_view = top_view.resize((1000, round(1000 * top_view.height / top_view.width)),
                               Image.Resampling.LANCZOS)
    left, top = 110, 380
    image.paste(top_view, (left, top))

    def pixel(x, y):
        return (left + (x - x_min) / (x_max - x_min) * top_view.width,
                top + (y_max - y) / (y_max - y_min) * top_view.height)

    def callout(number, target, offset):
        tx, ty = pixel(*target)
        mx, my = tx + offset[0], ty + offset[1]
        if offset != (0, 0):
            draw.line((tx, ty, mx, my), fill=accent, width=4)
            draw.ellipse((tx - 7, ty - 7, tx + 7, ty + 7), fill=accent)
        draw.ellipse((mx - 27, my - 27, mx + 27, my + 27), fill=accent, outline="white", width=3)
        draw.text((mx, my), str(number), font=marker, fill="white", anchor="mm")

    ports = {name: (x, side * p["case_xy"][1] / 2) for name, side, x, *_ in p["ports"]}
    callout(1, p["holes"][1], (95, 70))
    callout(2, ports["HDMI"], (0, -95))
    callout(3, ports["USB-C"], (0, 95))
    callout(4, p["speaker_xy"], (0, 0))
    coupon_edge = p["fit_coupon_x"] + p["magnet_boss_d"] / 2
    callout(5, (coupon_edge, p["fit_magnet_y"][0]), (0, -130))
    callout(6, (p["fit_coupon_x"] + p["boss_d"] / 2, p["fit_insert_y"][-1]), (0, 150))
    draw.text((60, 1185), "Плата ложится на стойки 1 на высоте корпуса; окна 2–3 — стенки, "
              "вырезанные из дна.", font=body, fill=grey)

    x0 = 1305
    draw.rounded_rectangle((x0, 160, x0 + 660, 620), radius=20, fill="white")
    draw.text((x0 + 25, 182), "С платой: высоты как в корпусе", font=heading, fill=ink)
    iso = silhouette("fit_iso.png")
    iso.thumbnail((610, 370), Image.Resampling.LANCZOS)
    image.paste(iso, (x0 + (660 - iso.width) // 2, 235 + (370 - iso.height) // 2))

    draw.rounded_rectangle((x0, 640, x0 + 660, 1240), radius=20, fill="white")
    draw.text((x0 + 25, 662), "Как проверить", font=heading, fill=ink)
    magnets = " / ".join(num(d) for d in p["fit_magnet_d"])
    inserts = " / ".join(num(d) for d in p["fit_insert_d"])
    steps = [
        "Вплавьте вставки M3, положите плату и вкрутите 4 винта: без перекоса и усилия.",
        f"HDMI входит в окно прямо, зазор ≈{num(p['port_clearance'])} мм по кругу.",
        "USB-C — так же; штекер доходит до разъёма платы.",
        f"Магнит динамика проходит в Ø{num(p['speaker_bore'])}.",
        f"Магнит 10 × 1,5: выберите {magnets}.",
        f"Вставка M3: выберите {inserts}.",
    ]
    y = 720
    for number, text in enumerate(steps, start=1):
        draw.ellipse((x0 + 25, y - 2, x0 + 63, y + 36), fill=accent)
        draw.text((x0 + 44, y + 17), str(number), font=body, fill="white", anchor="mm")
        line = ""
        for word in text.split():
            trial = f"{line} {word}".strip()
            if draw.textlength(trial, font=body) > 560 and line:
                draw.text((x0 + 80, y), line, font=body, fill=ink)
                y += 33
                line = word
            else:
                line = trial
        draw.text((x0 + 80, y), line, font=body, fill=ink)
        y += 52
    draw.text((52, 1262), "CAD-проверки пройдены; реальную посадку покажет только печать. "
              "Если что-то смещено — напишите, на сколько мм и в какую сторону.", font=body, fill=grey)
    image.save(ROOT / "previews/fit_test.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", choices=("meshes", "check", "previews", "package"))
    args = parser.parse_args()
    for folder in ("stl", "previews", "checks"):
        (ROOT / folder).mkdir(exist_ok=True)
    if args.only in (None, "meshes"):
        export_meshes()
    if args.only in (None, "check", "package"):
        meshes, parameters = check_meshes()
        if args.only != "check":
            export_3mf(meshes, parameters)
    if args.only in (None, "previews"):
        export_previews()


if __name__ == "__main__":
    main()
