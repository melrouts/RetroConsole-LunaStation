#!/usr/bin/env python3
"""Build a Bambu Studio project with the V6 lid and the (unchanged) V5 case.

Plate 1: the lid, one object made of three parts (body, light inlay, accent
inlay), each assigned to its own filament. Plate 2: the case.

--face down (default): the lid lies on its decorated face, colours change in the
first three layers, the LED-matrix mount points up, no supports. --face up: the lid stands on its locating lip,
colours change in the last three layers; the plate overhangs the 4 mm lip, so
the lid gets supports, with blockers keeping the magnet pockets clean.

Printer, process and filament settings are copied from an existing Bambu Studio
project (Metadata/project_settings.config), so the result matches that printer,
plate and loaded filaments:

    python3 v6/make_3mf_v6.py TEMPLATE.3mf --filaments 2,3,4 [--face up]

--filaments: 1-based filament numbers for body, light inlay and accent (default 1,2,3).

The process is reset to 0.2 mm layers (three layers per 0.6 mm inlay), no
supports for the case and the system "Standard" infill, whatever the template used.
"""
import argparse
import json
import math
import re
import struct
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LID_TOP_Z = 138.8
LID_BOTTOM_Z = 130.0  # LED-matrix mount
# Lid magnet pockets (prepare_case_v5.py): open downwards, ceiling at Z 136.71.
MAGNETS = [(2.144, 53.331), (71.575, -26.897), (-30.239, -50.408), (-70.965, -18.365)]
POCKET_TOP_Z = 136.71
PLATE_STEP = 1.2  # Bambu places plate N+1 one bed width plus 20 % to the right
IDENTITY = "1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1"
LAYER = {"layer_height": "0.2", "initial_layer_print_height": "0.2"}
# Bambu system defaults (fdm_process_common). Supports would fill the USB-C tunnel.
PROCESS = {"enable_support": "0", "sparse_infill_density": "15%", "sparse_infill_pattern": "grid",
           "skeleton_infill_density": "15%", "skin_infill_density": "15%"}


def read_stl(path):
    data = path.read_bytes()
    count = struct.unpack_from("<I", data, 80)[0]
    if 84 + 50 * count != len(data):
        raise ValueError(f"{path.name}: expected a binary STL")
    index, verts, tris = {}, [], []
    for i in range(count):
        values = struct.unpack_from("<12f", data, 84 + 50 * i)
        tri = []
        for k in range(3):
            v = values[3 + 3 * k: 6 + 3 * k]
            if v not in index:
                index[v] = len(verts)
                verts.append(v)
            tri.append(index[v])
        if len(set(tri)) == 3:
            tris.append(tri)
    return verts, tris


def transform(verts, fn):
    return [fn(*v) for v in verts]


def bounds(meshes):
    pts = [v for verts, _ in meshes for v in verts]
    return [min(p[k] for p in pts) for k in range(3)], [max(p[k] for p in pts) for k in range(3)]


def cylinders(centres, r, z0, z1, n=48):
    verts, tris = [], []
    for cx, cy in centres:
        b = len(verts)
        for z in (z0, z1):
            verts += [(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n), z)
                      for k in range(n)]
        verts += [(cx, cy, z0), (cx, cy, z1)]
        for k in range(n):
            a0, a1 = b + k, b + (k + 1) % n
            tris += [(a0, a1, a1 + n), (a0, a1 + n, a0 + n), (b + 2 * n, a1, a0), (b + 2 * n + 1, a0 + n, a1 + n)]
    return verts, tris


def mesh_xml(obj_id, verts, tris):
    out = [f'  <object id="{obj_id}" p:UUID="{uuid.uuid4()}" type="model">\n   <mesh>\n    <vertices>\n']
    out += [f'     <vertex x="{x:.6g}" y="{y:.6g}" z="{z:.6g}"/>\n' for x, y, z in verts]
    out.append("    </vertices>\n    <triangles>\n")
    out += [f'     <triangle v1="{a}" v2="{b}" v3="{c}"/>\n' for a, b, c in tris]
    out.append("    </triangles>\n   </mesh>\n  </object>\n")
    return "".join(out)


HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<model unit="millimeter" xml:lang="en-US" '
        'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" '
        'xmlns:BambuStudio="http://schemas.bambulab.com/package/2021" '
        'xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06" '
        'requiredextensions="p">\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("template", type=Path, help="Bambu Studio .3mf with the wanted printer/filament settings")
    ap.add_argument("--filaments", default="1,2,3")
    ap.add_argument("--face", choices=("down", "up"), default="down", help="lid decorated face on the bed or on top")
    ap.add_argument("-o", "--output", type=Path)
    args = ap.parse_args()
    up = args.face == "up"
    args.output = args.output or ROOT / ("luna_station_v6_face_up.3mf" if up else "luna_station_v6.3mf")

    with zipfile.ZipFile(args.template) as z:
        settings = z.read("Metadata/project_settings.config")
        app = re.search(rb'name="Application">([^<]+)<', z.read("3D/3dmodel.model")).group(1).decode()
    config = json.loads(settings)
    changed = [k for k, v in {**LAYER, **PROCESS}.items() if config.get(k) != v]
    diff = config.get("different_settings_to_system")
    if changed and diff:
        keys = [k for k in diff[0].split(";") if k and k not in PROCESS]
        keys += [k for k in LAYER if k in changed and k not in keys]
        diff[0] = ";".join(sorted(keys))
    config.update(LAYER)
    config.update(PROCESS)
    settings = json.dumps(config, indent=4).encode()
    colours = config["filament_colour"]
    slots = [int(s) for s in args.filaments.split(",")]
    if len(slots) != 3 or not all(1 <= s <= len(colours) for s in slots):
        raise SystemExit(f"--filaments needs three numbers in 1..{len(colours)}")
    bed = [float(v) for v in re.findall(r"[-\d.]+", ",".join(config["printable_area"]))]
    bed_w = max(bed[0::2]) - min(bed[0::2])
    bed_h = max(bed[1::2]) - min(bed[1::2])

    lid = [(name, *read_stl(ROOT / f)) for name, f in (
        ("Lid body", "gamepad_lid_v6.stl"),
        ("Lid inlay light: LUNA STATION, THRUST", "gamepad_lid_v6_text.stl"),
        ("Lid inlay accent: orbit, frames, rings, markers", "gamepad_lid_v6_accent.stl"))]
    if up:
        place = lambda x, y, z: (x, y, z - LID_BOTTOM_Z)
    else:  # rotate 180 degrees about X, decorated face on the bed
        place = lambda x, y, z: (x, -y, LID_TOP_Z - z)
    lid = [(n, transform(v, place), t) for n, v, t in lid]
    lo, hi = bounds([(v, t) for _, v, t in lid])
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    lid = [(n, transform(v, lambda x, y, z: (x - cx, y - cy, z)), t) for n, v, t in lid]
    blocker = None
    if up:
        blocker = cylinders([(x - cx, y - cy) for x, y in MAGNETS], 6.0, 0.0, POCKET_TOP_Z - LID_BOTTOM_Z + 0.2)

    case_v, case_t = read_stl(ROOT.parent / "v5" / "gamepad_case_v5.stl")
    lo, hi = bounds([(case_v, case_t)])
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    case_v = transform(case_v, lambda x, y, z: (x - cx, y - cy, z - lo[2]))

    # Sub-model files: object ids 1-3 (lid parts), 7 (support blocker) and 5 (case); 4 and 6 are the assemblies.
    lid_ids = [1, 2, 3] + ([7] if up else [])
    lid_model = HEAD + " <resources>\n" + "".join(
        mesh_xml(i + 1, v, t) for i, (_, v, t) in enumerate(lid)) + (
        mesh_xml(7, *blocker) if up else "") + " </resources>\n <build/>\n</model>\n"
    case_model = HEAD + " <resources>\n" + mesh_xml(5, case_v, case_t) + " </resources>\n <build/>\n</model>\n"

    def component(path, oid):
        return (f'    <component p:path="{path}" objectid="{oid}" p:UUID="{uuid.uuid4()}" '
                f'transform="1 0 0 0 1 0 0 0 1 0 0 0"/>\n')

    cx0, cy0 = bed_w / 2, bed_h / 2
    main = (HEAD + f' <metadata name="Application">{app}</metadata>\n'
            ' <metadata name="BambuStudio:3mfVersion">1</metadata>\n'
            ' <metadata name="Title">Luna station gamepad V6</metadata>\n'
            ' <resources>\n'
            f'  <object id="4" p:UUID="{uuid.uuid4()}" type="model">\n   <components>\n'
            + "".join(component("/3D/Objects/object_1.model", i) for i in lid_ids)
            + '   </components>\n  </object>\n'
            f'  <object id="6" p:UUID="{uuid.uuid4()}" type="model">\n   <components>\n'
            + component("/3D/Objects/object_2.model", 5)
            + '   </components>\n  </object>\n'
            ' </resources>\n'
            f' <build p:UUID="{uuid.uuid4()}">\n'
            f'  <item objectid="4" p:UUID="{uuid.uuid4()}" transform="1 0 0 0 1 0 0 0 1 {cx0:g} {cy0:g} 0" printable="1"/>\n'
            f'  <item objectid="6" p:UUID="{uuid.uuid4()}" transform="1 0 0 0 1 0 0 0 1 '
            f'{cx0 + bed_w * PLATE_STEP:g} {cy0:g} 0" printable="1"/>\n'
            ' </build>\n</model>\n')

    def part(pid, name, slot, faces, subtype="normal_part"):
        return (f'    <part id="{pid}" subtype="{subtype}">\n'
                f'      <metadata key="name" value="{name}"/>\n'
                f'      <metadata key="matrix" value="{IDENTITY}"/>\n'
                f'      <metadata key="extruder" value="{slot}"/>\n'
                f'      <mesh_stat face_count="{faces}" edges_fixed="0" degenerate_facets="0" '
                f'facets_removed="0" facets_reversed="0" backwards_edges="0"/>\n    </part>\n')

    def plate(n, oid):
        return (f'  <plate>\n    <metadata key="plater_id" value="{n}"/>\n'
                '    <metadata key="plater_name" value=""/>\n    <metadata key="locked" value="false"/>\n'
                '    <model_instance>\n'
                f'      <metadata key="object_id" value="{oid}"/>\n'
                '      <metadata key="instance_id" value="0"/>\n'
                f'      <metadata key="identify_id" value="{100 + n}"/>\n'
                '    </model_instance>\n  </plate>\n')

    settings_xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<config>\n'
                    '  <object id="4">\n    <metadata key="name" value="Luna station lid V6"/>\n'
                    f'    <metadata key="extruder" value="{slots[0]}"/>\n'
                    + ('    <metadata key="enable_support" value="1"/>\n' if up else "")
                    + "".join(part(i + 1, n, slots[i], len(t)) for i, (n, _, t) in enumerate(lid))
                    + (part(7, "Support blocker: magnet pockets", slots[0], len(blocker[1]), "support_blocker")
                       if up else "")
                    + '  </object>\n'
                    '  <object id="6">\n    <metadata key="name" value="Luna station case V6"/>\n'
                    f'    <metadata key="extruder" value="{slots[0]}"/>\n'
                    + part(5, "Case", slots[0], len(case_t))
                    + '  </object>\n' + plate(1, 4) + plate(2, 6) + '</config>\n')

    content_types = ('<?xml version="1.0" encoding="UTF-8"?>\n'
                     '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\n'
                     ' <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\n'
                     ' <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>\n'
                     ' <Default Extension="png" ContentType="image/png"/>\n'
                     ' <Default Extension="gcode" ContentType="text/x.gcode"/>\n</Types>\n')
    rel = '<Relationship Target="{}" Id="rel-{}" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>'
    rels_head = ('<?xml version="1.0" encoding="UTF-8"?>\n'
                 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n')

    with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", rels_head + " " + rel.format("/3D/3dmodel.model", 1) + "\n</Relationships>\n")
        z.writestr("3D/_rels/3dmodel.model.rels", rels_head + "".join(
            " " + rel.format(f"/3D/Objects/object_{i}.model", i) + "\n" for i in (1, 2)) + "</Relationships>\n")
        z.writestr("3D/3dmodel.model", main)
        z.writestr("3D/Objects/object_1.model", lid_model)
        z.writestr("3D/Objects/object_2.model", case_model)
        z.writestr("Metadata/project_settings.config", settings)
        z.writestr("Metadata/model_settings.config", settings_xml)
    names = ["body", "light inlay", "accent"]
    print(args.output.name, "|", ", ".join(f"{n} -> filament {s} {colours[s - 1]}" for n, s in zip(names, slots)),
          "|", config.get("printer_settings_id"), "|", config.get("print_settings_id"),
          "| reset:", ", ".join(changed) or "none")


if __name__ == "__main__":
    main()
