// V5 lid: decorated top for multi-colour printing.
// Body, text and accent are separate parts in the supplied lid's coordinates
// (Z 131-138.8). The inlays fill 0.6 mm pockets flush with the flat top,
// so the parts can be loaded together as one multi-part object.
part = "body"; // body | text | accent | preview
top_z = 138.8;
inlay_depth = 0.6;
font = "Liberation Sans:style=Bold";
window = [0, 28.75];
window_edge = 17.62;            // half width of the 32x32 window's top fillet edge
holes = [[0, -17.75], [-43, -24.75], [43, -24.75]]; // THRUST, LEFT, RIGHT
hole_edge_r = 13.95;            // top fillet edge of the 24.6 mm holes
$fn = 96;

// Accent geometry.
ring = [14.9, 16.1];            // rings around the button holes
frame_in = 18.4;                // window frame half widths
frame_out = 19.3;
groove_x = 20.9;                // three grooves on each side of the window
groove_len = [3.6, 5.0, 3.6];
groove_pitch = 4.6;
groove_w = 1.0;
edge_line = [1.4, 2.3];         // accent line inset from the flat-top contour
arrow_r = 18.6;                 // rotate arrows above the side buttons
arrow_w = 1.0;

// Text geometry.
title = "LUNA STATION";
title_size = 3.8;
title_spacing = 1.1;
title_base = 4.1;
label = "THRUST";
label_size = 3.8;
label_spacing = 1.4;
label_base_r = 21.4;            // baseline radius below the THRUST hole
// Stars in the side lobes, polar around the LEFT hole: [angle, radius, size].
// Mirrored for the RIGHT hole.
stars = [[158, 24.5, 2.6], [196, 25.5, 1.7], [232, 23.5, 2.1], [266, 26.5, 1.4]];
// Advance widths of Liberation Sans Bold (metric-compatible with Arial Bold), em units.
advance = [["T", 0.611], ["H", 0.722], ["R", 0.722], ["U", 0.722], ["S", 0.667]];
em_per_size = 1.355;            // OpenSCAD size is the cap height

module lid_base() import("gamepad_lid_v5_base.stl", convexity = 12);

// Contour 0.03 mm below the top, about 0.3 mm outside the flat area. Follows the
// wider fillets in the notches between the lobes; holes are filled.
module flat_outline() {
    union() {
        projection(cut = true) translate([0, 0, -(top_z - 0.03)]) lid_base();
        for (c = holes) translate(c) circle(r = 14.5);
        translate(window) square(36, center = true);
    }
}

module band(r_in, r_out) difference() { circle(r = r_out); circle(r = r_in); }

module rounded_square(half, r) offset(r = r) square(2 * (half - r), center = true);

module bar(p0, p1, w) hull() { translate(p0) circle(d = w); translate(p1) circle(d = w); }

function polar(c, r, a) = [c[0] + r * cos(a), c[1] + r * sin(a)];

module arc_arrow(c, r, a_tail, a_head, w) {
    dir = sign(a_head - a_tail);
    tip = a_head + dir * 2.8 / r * 180 / PI;
    n = 24;
    polygon(concat(
        [for (i = [0:n]) polar(c, r + w / 2, a_tail + (a_head - a_tail) * i / n)],
        [for (i = [n:-1:0]) polar(c, r - w / 2, a_tail + (a_head - a_tail) * i / n)]));
    polygon([polar(c, r + 1.5, a_head), polar(c, r, tip), polar(c, r - 1.5, a_head)]);
}

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
    arc_arrow(holes[1], arrow_r, 62, 112, arrow_w);  // LEFT: counter-clockwise
    arc_arrow(holes[2], arrow_r, 118, 68, arrow_w);  // RIGHT: clockwise
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

module star(size) {
    polygon([for (i = [0 : 7]) let(a = 90 + i * 45, r = i % 2 ? 0.36 * size : size)
             [r * cos(a), r * sin(a)]]);
}

module decor_stars() {
    for (m = [0, 1]) mirror([m, 0]) for (s = stars)
        translate(holes[1] + s[1] * [cos(s[0]), sin(s[0])]) star(s[2]);
}

module decor_text() {
    decor_stars();
    translate([0, title_base])
        text(title, size = title_size, font = font, halign = "center", valign = "baseline",
             spacing = title_spacing);
    bottom_arc_text(label, holes[0], label_base_r, label_size, label_spacing);
}

module inlay(depth = inlay_depth) translate([0, 0, top_z - inlay_depth])
    linear_extrude(depth) children();

if (part == "body") difference() {
    lid_base();
    inlay(inlay_depth + 1) { decor_text(); decor_accent(); }
}
else if (part == "text") inlay() decor_text();
else if (part == "accent") inlay() decor_accent();
else if (part == "preview") {
    color("#30343b") lid_base();
    color("#f2f2ee") translate([0, 0, 0.02]) inlay() decor_text();
    color("#f39a2b") translate([0, 0, 0.02]) inlay() decor_accent();
}
