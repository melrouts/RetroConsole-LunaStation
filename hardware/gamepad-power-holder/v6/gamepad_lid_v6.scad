// V6 lid: V5 lid base with a 45-degree chamfer on the outer edge, "classic"
// decoration for multi-colour printing and an LED-matrix mount underneath.
// Same coordinates as the supplied lid (Z 131-138.8, plate underside Z 135).
// The case is the unchanged V5 case.
include <lid_v6_geometry.scad>  // outline_pts(), frame_pts(): run prepare_lid_v6.py

part = "body"; // body | text | accent | preview | mount
top_z = 138.8;
plate_z = 135;                  // plate underside
inlay_depth = 0.6;
font = "Liberation Sans:style=Bold";
window = [0, 28.75];            // 32x32 LED window
holes = [[0, -17.75], [-43, -24.75], [43, -24.75]]; // THRUST, LEFT, RIGHT
$fn = 96;

// Edge chamfer: 45 degrees, from the flat top down to Z top_z - chamfer.
chamfer = 3.0;
chamfer_step = 0.1;

// LED-matrix mount (below the plate). Bosses take M2 heat-set inserts.
boss_pitch = [40, 24];          // insert centres, X x Y; prepare_lid_v6.py checks the fit
boss_d = 6.5;
insert_d = 3.2;                 // M2 heat-set insert, 3.2-3.5 mm OD
insert_depth = 5.0;             // to the plate underside
mount_h = 5.0;                  // bosses and board stops
frame_h = 4.0;                  // light shroud around the window
stop_d = 4.0;
stops = [[-18.5, 0], [18.5, 0], [0, -18.5]]; // round board stops on the frame, outside the window

// Accent geometry.
ring = [14.9, 16.1];            // rings around the button holes
frame_in = 18.4;                // window frame half widths
frame_out = 19.3;
groove_x = 20.9;                // three grooves on each side of the window
groove_len = [3.6, 5.0, 3.6];
groove_pitch = 4.6;
groove_w = 1.0;
edge_line = [1.2, 2.1];         // accent line inset from the flat-top contour
marker_r = 19.4;                // triangles under the side buttons, pointing at them
marker_size = 3.0;

// Text geometry.
title = "LUNA STATION";
title_size = 3.8;
title_spacing = 1.1;
title_base = 4.1;
label = "THRUST";
label_size = 3.8;
label_spacing = 1.4;
label_base_r = 21.4;            // baseline radius below the THRUST hole
// Advance widths of Liberation Sans Bold (metric-compatible with Arial Bold), em units.
advance = [["T", 0.611], ["H", 0.722], ["R", 0.722], ["U", 0.722], ["S", 0.667]];
em_per_size = 1.355;            // OpenSCAD size is the cap height

module lid_base() import("../v5/gamepad_lid_v5_base.stl", convexity = 12);

module outline() polygon(outline_pts());

// Keeps everything below the chamfer, then shrinks the contour by 45 degrees.
module chamfer_envelope() {
    n = round(chamfer / chamfer_step);
    translate([0, 0, plate_z - 10]) linear_extrude(top_z - chamfer - plate_z + 10)
        offset(delta = 1) outline();
    for (i = [0 : n - 1])
        translate([0, 0, top_z - chamfer + i * chamfer_step])
            linear_extrude(chamfer_step + 0.001) offset(r = -(i + 0.5) * chamfer_step) outline();
}

module mount() {
    translate(window) {
        for (sx = [-1, 1], sy = [-1, 1])
            translate([sx * boss_pitch[0] / 2, sy * boss_pitch[1] / 2, plate_z - mount_h])
                difference() {
                    cylinder(d = boss_d, h = mount_h + 0.2);
                    translate([0, 0, -0.01]) cylinder(d = insert_d, h = insert_depth + 0.01);
                    translate([0, 0, -0.01]) cylinder(d1 = insert_d + 0.8, d2 = insert_d, h = 0.4);
                }
        for (s = stops) translate([s[0], s[1], plate_z - mount_h]) cylinder(d = stop_d, h = mount_h + 0.2);
    }
    translate([0, 0, plate_z - frame_h]) linear_extrude(frame_h + 0.2)
        for (p = frame_pts()) polygon(concat([for (r = p) each r]),
            [for (k = [0 : len(p) - 1]) [for (j = [0 : len(p[k]) - 1])
                j + (k == 0 ? 0 : len([for (m = [0 : k - 1]) each p[m]]))]]);
}

// Flat top after the chamfer, holes filled.
module flat_outline() {
    offset(r = -chamfer) outline();
}

module band(r_in, r_out) difference() { circle(r = r_out); circle(r = r_in); }

module rounded_square(half, r) offset(r = r) square(2 * (half - r), center = true);

module bar(p0, p1, w) hull() { translate(p0) circle(d = w); translate(p1) circle(d = w); }

function polar(c, r, a) = [c[0] + r * cos(a), c[1] + r * sin(a)];

function bezier(p, t) =
    pow(1 - t, 3) * p[0] + 3 * pow(1 - t, 2) * t * p[1] + 3 * (1 - t) * t * t * p[2] + pow(t, 3) * p[3];

module orbit() {
    p = [[-21.3, 2.3], [-6, 0.2], [21.0, -1.5], [23.9, 5.1]];
    n = 60;
    pts = [for (i = [0:n]) bezier(p, i / n)];
    w = [for (i = [0:n]) 0.3 + 0.95 * pow(sin(180 * i / n), 0.8)];
    normal = [for (i = [0:n]) let(
        d = pts[min(i + 1, n)] - pts[max(i - 1, 0)], l = norm(d)) [-d[1] / l, d[0] / l]];
    polygon(concat(
        [for (i = [0:n]) pts[i] + normal[i] * w[i] / 2],
        [for (i = [n:-1:0]) pts[i] - normal[i] * w[i] / 2]));
    translate(p[3] + [-0.1, 0.6]) circle(d = 2.0);
}

// Upward triangle below a side button, tip towards the button.
module marker(c) translate(c + [0, -marker_r])
    polygon([[0, 0], [-marker_size / 2, -marker_size * 0.87], [marker_size / 2, -marker_size * 0.87]]);

module decor_accent() {
    for (c = holes) translate(c) band(ring[0], ring[1]);
    translate(window) difference() {
        rounded_square(frame_out, 2.2);
        rounded_square(frame_in, 1.3);
    }
    for (s = [-1, 1], i = [0:2]) let(y = window[1] + (i - 1) * groove_pitch)
        bar([s * groove_x, y], [s * (groove_x + groove_len[i]), y], groove_w);
    difference() {
        offset(r = -edge_line[0]) flat_outline();
        offset(r = -edge_line[1]) flat_outline();
    }
    marker(holes[1]);
    marker(holes[2]);
    orbit();
}

function lookup_advance(ch) = advance[search([ch], advance)[0]][1];
function advances(s, i = 0) = i >= len(s) ? [] : concat([lookup_advance(s[i])], advances(s, i + 1));
function prefix(v, i) = i == 0 ? 0 : prefix(v, i - 1) + v[i - 1];

// Upright text centred on the bottom of a circle, letters facing the centre.
module bottom_arc_text(s, c, r, size, spacing) {
    em = size * em_per_size;
    w = advances(s);
    total = prefix(w, len(s)) * em * spacing;
    for (i = [0:len(s) - 1]) {
        along = prefix(w, i) * em * spacing + w[i] * em / 2 - total / 2;
        a = 270 + along / r * 180 / PI;
        translate(polar(c, r, a)) rotate(a + 90)
            text(s[i], size = size, font = font, halign = "center", valign = "baseline");
    }
}

module decor_text() {
    translate([0, title_base])
        text(title, size = title_size, font = font, halign = "center", valign = "baseline",
             spacing = title_spacing);
    bottom_arc_text(label, holes[0], label_base_r, label_size, label_spacing);
}

module inlay(depth = inlay_depth) translate([0, 0, top_z - inlay_depth])
    linear_extrude(depth) children();

module body() difference() {
    union() {
        intersection() {
            lid_base();
            chamfer_envelope();
        }
        mount();
    }
    inlay(inlay_depth + 1) { decor_text(); decor_accent(); }
}

if (part == "body") body();
else if (part == "text") inlay() decor_text();
else if (part == "accent") inlay() decor_accent();
else if (part == "mount") mount();
else if (part == "preview") {
    color("#30343b") body();
    color("#f2f2ee") translate([0, 0, 0.02]) inlay() decor_text();
    color("#f39a2b") translate([0, 0, 0.02]) inlay() decor_accent();
}
