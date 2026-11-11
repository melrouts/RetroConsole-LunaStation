// V1 concept with measured cable envelopes and PCB-relative port centres.
// Coordinates: PCB centre = XY origin; bottom of enclosure = Z 0.
use <../../gamepad-power-holder/v6/gamepad_lid_v6.scad>

part = "assembly"; // bottom | base_text | base_accent | lid | text | accent | bridge | fit_test | fit_preview | assembly | exploded | inside | section | pcb | speaker | parameters
palette = 0; // 0 graphite/orange, 1 silver/orange, 2 navy/cyan
// Orbital graphite is the selected finish.
show_pcb = true; // fit_preview only
base_style = 3; // 0 plain, 1 equalizer, 2 lander chevrons, 3 crater halftone (selected)
$fn = 96;
eps = 0.01;

pcb = [160, 80];
pcb_t = 1.6;                  // provisional
hole_inset = [5, 5];           // provisional, measured from each PCB edge
pcb_hole_d = 3.4;              // provisional
board_z = 10;                 // underside of PCB, provisional
component_h = 17;              // provisional keep-out, NOT measured electronics
pcb_top = board_z + pcb_t;

case_xy = [188, 120];
corner_r = 18;
total_h = 44;
base_h = 36.5;
wall = 3.2;
floor_t = 3.2;
roof_t = 3.2;
edge_chamfer = 2.4;
seam_gap = 0.15;
lip_t = 1.6;
lip_h = 3;
fit_gap = 0.3;                 // radial clearance, each side

boss_d = 9.2;
insert_bore = 4.2;             // provisional: tune to actual M3 insert
insert_depth = 5.4;
bolt_d = 3.4;
magnet_d = 10;
magnet_t = 1.5;
magnet_clearance = 0.3;        // diametral
magnet_depth = 1.7;            // includes glue allowance
magnet_boss_d = 15.6;
magnet_x = [-40, 60];         // non-speaker pair moved clear of the cable paths
magnet_y = 49.5;

// Top view with the lid text readable (speaker on the right): HDMI is in the
// upper (+Y) long wall, USB-C in the lower (-Y) one. Seen from the -X end
// towards the speaker, that is HDMI on the left, USB-C on the right.
hdmi_side = 1;
usb_c_side = -1;
// Measurements are from the main PCB top and its non-speaker short edge.
port_clearance = 0.5;         // each side of the measured plastic plug body
hdmi_plug = [22, 10.5];
hdmi_axis_above_pcb = 16.7;
hdmi_from_edge = 15.75;
hdmi_x = -pcb[0] / 2 + hdmi_from_edge;
hdmi_z = pcb_top + hdmi_axis_above_pcb;
hdmi_window = hdmi_plug + [2 * port_clearance, 2 * port_clearance];
hdmi_r = 1.5;
usb_c_plug = [13, 6.5];
usb_c_axis_above_pcb = 15;
usb_c_from_edge = 15.75;
usb_c_x = -pcb[0] / 2 + usb_c_from_edge;
usb_c_z = pcb_top + usb_c_axis_above_pcb;
usb_c_window = usb_c_plug + [2 * port_clearance, 2 * port_clearance];
usb_c_r = 1.5;
port_bevel = 0.6;
ports = [
    ["HDMI", hdmi_side, hdmi_x, hdmi_z, hdmi_window, hdmi_r],
    ["USB-C", usb_c_side, usb_c_x, usb_c_z, usb_c_window, usb_c_r]
];
port_measurements = [
    ["HDMI", hdmi_plug, hdmi_axis_above_pcb, hdmi_from_edge],
    ["USB-C", usb_c_plug, usb_c_axis_above_pcb, usb_c_from_edge]
];

speaker_xy = [45, 0];         // provisional; PCB below must be clear
speaker_magnet_d = 32;
speaker_bore_clearance = 0.4; // diametral
speaker_outer_d = 50;         // provisional basket diameter
speaker_magnet_h = 8;         // provisional, below bridge seating plane
speaker_front_h = 11;         // provisional, above bridge seating plane
bridge_ring_d = 46;
bridge_t = 3.2;
bridge_rise = 10.6;           // PCB top to underside of bridge
strap_slot = [1.8, 4];        // provisional basket retention with narrow ties

// Fit test: a quick single-colour print cut from the real bottom. The thin floor
// replaces the case floor; posts, insert bores and window walls are unchanged.
fit_floor = 1.6;
fit_cut = floor_t - fit_floor;  // case Z that becomes the print bed
fit_bar = 6;
fit_spine = 8;
fit_wall_x = [-86, -48.5];      // wall pieces stop short of the X -40 magnet posts
fit_wall_y = 36;                // wall pieces and their floor start inside the PCB ring
fit_tab = [76, 112, 56];        // x0, x1, half height of the calibration tab
fit_coupon_x = 88;
fit_label_x = 98;
fit_magnet_y = [44, 26, 8];
fit_insert_y = [-8, -22, -36];
fit_steps = [-0.2, 0, 0.2];
fit_magnet_d = [for (s = fit_steps) magnet_d + magnet_clearance + s];
fit_insert_d = [for (s = fit_steps) insert_bore + s];
fit_magnet_pad = magnet_depth + 1;
fit_gusset = [2, 12, 14];       // thickness, reach from the wall, height
fit_text_h = 0.6;

// Base styling. Side vents stay between the magnet posts on the long walls and
// below the cable windows; everything prints without support (vertical, 45° or
// small round openings only).
foot_d = 13;                    // pocket for 12.7 mm adhesive bumpers
foot_depth = 1.2;
feet = [for (sx = [-1, 1], sy = [-1, 1]) [sx * 73, sy * 39]];
vent_x = [-26, 46];             // long-wall vent band between the magnet posts
vent_end_y = 26;                // half-span of vents on the short ends
vent_z = [6, 21];
vent_w = 3;
vent_pitch = 6;
moon_r = 31;                   // halftone disk under the speaker (style 3)
moon_ring = [32.6, 33.8];       // accent ring around it, like the lid grille ring
moon_pitch = 6.2;
moon_d = [1.6, 5.4];            // smallest and largest dot
eq_levels = [0.35, 0.6, 0.85, 0.55, 1, 0.75, 0.45, 0.9, 0.65, 1, 0.5, 0.8, 0.4];

inlay_depth = 0.6;
font = "Liberation Sans:style=Bold";
logo_xy = [-34, 5];
logo_scale = 1.45;
slot_w = 2.2;
rib_w = 2.4;
grille_radii = [4.5, 9, 13.5, 18, 22.5];

lid_z = base_h + seam_gap;
roof_z = total_h - roof_t;
bridge_z = pcb_top + bridge_rise;
bridge_top = bridge_z + bridge_t;
holes = [for (sx = [-1, 1], sy = [-1, 1])
    [sx * (pcb[0] / 2 - hole_inset[0]), sy * (pcb[1] / 2 - hole_inset[1])]];
bridge_feet = [for (sy = [-1, 1])
    [pcb[0] / 2 - hole_inset[0], sy * (pcb[1] / 2 - hole_inset[1])]];
magnets = [for (x = magnet_x, sy = [-1, 1]) [x, sy * magnet_y]];
colours = [
    ["#282D36", "#282D36", "#ECECE4", "#FF8B25"],
    ["#282D36", "#BFC4C8", "#282D36", "#FF781F"],
    ["#172C46", "#172C46", "#F2EEE3", "#42D6D1"]
][palette];
// Lunar silver has graphite lettering on the lid; use the silver on the graphite base.
base_text_colour = colours[2] == colours[0] ? colours[1] : colours[2];

assert(wall > lip_t + fit_gap && corner_r > wall + fit_gap);
assert(board_z - insert_depth > floor_t);
assert(magnet_depth >= magnet_t && magnet_d + magnet_clearance < magnet_boss_d);
assert(bridge_top + speaker_front_h < roof_z);
assert(bridge_top - speaker_magnet_h > pcb_top);
assert(roof_t > inlay_depth && bridge_ring_d > speaker_magnet_d + speaker_bore_clearance);
assert(lid_z + lip_h + fit_gap < roof_z, "Leave backing above the lid's locating socket");
assert(lid_z + magnet_depth < roof_z, "Lid magnet pockets must remain blind");
assert(port_clearance > 0 && port_bevel > 0 && port_bevel < wall / 2);
assert(hdmi_side * usb_c_side == -1, "HDMI and USB-C belong on opposite long walls");
for (p = ports) {
    assert(min(p[4]) > 0 && p[5] > 0 && 2 * p[5] <= min(p[4]));
    assert(p[2] + p[4][0] / 2 + port_bevel < 0, "Ports must remain on the non-speaker half");
    // The shallow exterior bevel may meet the corner; the full throat may not.
    assert(abs(p[2]) + p[4][0] / 2 < case_xy[0] / 2 - corner_r,
           "Port throat crosses the rounded end");
    assert(p[3] - p[4][1] / 2 - port_bevel > floor_t);
    assert(p[3] + p[4][1] / 2 + port_bevel <= base_h - 1.6,
           "Keep a solid web below the seam and locating lip");
    assert(p[2] - p[4][0] / 2 - port_bevel > fit_wall_x[0] + 1 + fit_gusset[0]
           && p[2] + p[4][0] / 2 + port_bevel < fit_wall_x[1] - 1 - fit_gusset[0],
           "Fit-test wall pieces must contain the whole window and clear the gussets");
}
assert(fit_cut > 0 && fit_cut < edge_chamfer && fit_floor > 1);
assert(fit_wall_x[1] < min(magnet_x) - magnet_boss_d / 2 - 0.5,
       "Fit-test wall pieces must not cut through a magnet post");
assert(fit_coupon_x - magnet_boss_d / 2 > pcb[0] / 2
       && fit_tab[0] < pcb[0] / 2 - hole_inset[0] + fit_bar / 2,
       "Calibration coupons sit outside the PCB and the tab joins the post ring");
assert(floor_t + fit_gusset[2] < min([for (p = ports) p[3] - p[4][1] / 2 - port_bevel]),
       "Fit-test gussets stay below the cable paths");

module rounded_rect(size, r) {
    assert(r > 0 && 2 * r <= min(size));
    hull() for (sx = [-1, 1], sy = [-1, 1])
        translate([sx * (size[0] / 2 - r), sy * (size[1] / 2 - r)]) circle(r = r);
}

module outline(inset = 0)
    rounded_rect(case_xy - [2 * inset, 2 * inset], corner_r - inset);

module contour(outer, inner) difference() {
    outline(outer);
    outline(inner);
}

module slab(z, h) translate([0, 0, z]) linear_extrude(h) children();

module bottom_envelope() union() {
    hull() {
        slab(0, eps) outline(edge_chamfer);
        slab(edge_chamfer, eps) outline();
    }
    slab(edge_chamfer, base_h - edge_chamfer) outline();
}

module lid_envelope() union() {
    slab(lid_z, total_h - edge_chamfer - lid_z) outline();
    hull() {
        slab(total_h - edge_chamfer - eps, eps) outline();
        slab(total_h - eps, eps) outline(edge_chamfer);
    }
}

module pcb_posts() for (p = holes) translate([p[0], p[1], floor_t - eps])
    cylinder(d = boss_d, h = board_z - floor_t + eps);

module insert_cut(d = insert_bore) {
    translate([0, 0, -insert_depth]) cylinder(d = d, h = insert_depth + eps);
    translate([0, 0, -0.3]) cylinder(d1 = d, d2 = d + 0.6, h = 0.3 + eps);
}

module insert_cuts() for (p = holes) translate([p[0], p[1], board_z]) insert_cut();

module magnet_posts(z0, z1) for (p = magnets)
    translate([p[0], p[1], z0]) cylinder(d = magnet_boss_d, h = z1 - z0);

module magnet_bore(d = magnet_d + magnet_clearance) {
    cylinder(d = d, h = magnet_depth + eps);
    translate([0, 0, magnet_depth - 0.25])
        cylinder(d1 = d, d2 = d + 0.5, h = 0.25 + eps);
}

module port_cuts() for (p = ports)
    translate([p[2], p[1] * (case_xy[1] / 2 + eps), p[3]])
        rotate([p[1] * 90, 0, 0]) {
            linear_extrude(wall + 2 * eps) rounded_rect(p[4], p[5]);
            hull() {
                linear_extrude(eps) offset(delta = port_bevel) rounded_rect(p[4], p[5]);
                translate([0, 0, port_bevel]) linear_extrude(eps) rounded_rect(p[4], p[5]);
            }
        }

module bottom(styled = true) difference() {
    union() {
        difference() {
            bottom_envelope();
            slab(floor_t, base_h) outline(wall);
        }
        pcb_posts();
        magnet_posts(floor_t - eps, base_h);
        slab(base_h - eps, lip_h + eps) contour(wall - lip_t, wall);
    }
    insert_cuts();
    port_cuts();
    for (p = magnets) translate([p[0], p[1], base_h - magnet_depth]) magnet_bore();
    if (styled) slab(-eps, inlay_depth + eps) { base_text_2d(); base_accent_2d(); }
    else for (d = [8, 12]) slab(-eps, 0.6 + eps) contour(d - 0.7, d + 0.7);
    translate([0, -case_xy[1] / 2 - eps, base_h])
        rotate([-90, 0, 0]) linear_extrude(1.2) rounded_rect([14, 5], 2.4);
    if (styled) base_cuts();
}

// 2D (x, z) profile cut through both long walls.
module long_walls() for (s = [-1, 1])
    translate([0, s * (case_xy[1] / 2 - wall / 2), 0])
        rotate([90, 0, 0]) linear_extrude(wall + 2, center = true) children();

// 2D (y, z) profile cut through both short ends.
module end_walls() for (s = [-1, 1])
    translate([s * (case_xy[0] / 2 - wall / 2), 0, 0])
        rotate([90, 0, 90]) linear_extrude(wall + 2, center = true) children();

module floor_cut() slab(-eps, floor_t + 2 * eps) children();

// Keep floor openings clear of posts, feet, the outline grooves and fit-test pieces.
module floor_keepout() {
    for (p = holes) translate(p) circle(d = boss_d + 3);
    for (p = magnets) translate(p) circle(d = magnet_boss_d + 3);
    for (p = feet) translate(p) circle(d = foot_d + 4);
    difference() { outline(-1); outline(15); }
    translate([fit_wall_x[0] - 2, fit_wall_y - 3]) square([fit_wall_x[1] - fit_wall_x[0] + 4, 40]);
    translate([fit_wall_x[0] - 2, -fit_wall_y - 37]) square([fit_wall_x[1] - fit_wall_x[0] + 4, 40]);
}

module vslot(h) translate([-vent_w / 2, 0]) hull() {
    translate([vent_w / 2, vent_w / 2]) circle(d = vent_w, $fn = 24);
    translate([vent_w / 2, h - vent_w / 2]) circle(d = vent_w, $fn = 24);
}

module equalizer(span) let(n = floor((span[1] - span[0]) / vent_pitch) + 1,
                            x0 = (span[0] + span[1] - (n - 1) * vent_pitch) / 2)
    for (i = [0:n - 1]) let(h = vent_w + (vent_z[1] - vent_z[0] - vent_w) * eq_levels[i % len(eq_levels)])
        translate([x0 + i * vent_pitch, vent_z[0]]) vslot(h);

module slant(h, w = vent_w) polygon([[0, 0], [w, 0], [w + h, h], [h, h]]);

module chevron(arm, w = 2.4) for (s = [-1, 1]) hull() {
    circle(d = w, $fn = 24);
    translate([-arm, s * arm]) circle(d = w, $fn = 24);
}

module halftone(centre, r_max, d_max, pitch = 7) difference() {
    for (i = [-14:14], j = [-9:9]) let(p = [i * pitch + (j % 2) * pitch / 2, j * pitch * 0.866],
                                       d = d_max * (1 - norm(p - centre) / r_max))
        if (d > 1.6) translate(p) circle(d = d, $fn = 20);
    floor_keepout();
}

// Dots grow left to right, like the side rows: a lit lunar disk under the speaker.
module moon_2d() translate(speaker_xy) difference() {
    for (i = [-6:6], j = [-6:6]) let(
        p = [i * moon_pitch + (abs(j) % 2) * moon_pitch / 2, j * moon_pitch * sqrt(3) / 2],
        t = (p[0] + moon_r) / (2 * moon_r),
        d = moon_d[0] + (moon_d[1] - moon_d[0]) * t)
        if (norm(p) + d / 2 <= moon_r) translate(p) circle(d = d, $fn = 20);
    translate(-speaker_xy) floor_keepout();
}

// Bottom-face inlays read correctly once the case is flipped about its long (X) axis.
module base_brand() mirror([0, 1, 0]) children();

module base_text_2d() if (base_style == 3) base_brand() {
    translate([logo_xy[0], 8])
        text("LUNA STATION", size = 3.8 * logo_scale, spacing = 1.1,
             font = font, halign = "center");
    for (line = [[-14, "RETRO GAME CONSOLE"], [-21, "2026"], [-27, "retro@lea.lt"]])
        translate([logo_xy[0], line[0]])
            text(line[1], size = 2.6, spacing = 1.15, font = font, halign = "center");
}

module base_accent_2d() {
    for (d = [8, 12]) contour(d - 0.7, d + 0.7);
    if (base_style == 3) {
        translate(speaker_xy) difference() { circle(r = moon_ring[1]); circle(r = moon_ring[0]); }
        base_brand() translate([logo_xy[0], 0]) scale([logo_scale, logo_scale]) orbit();
    }
}

module base_cuts() {
    for (p = feet) translate([p[0], p[1], -eps]) cylinder(d = foot_d, h = foot_depth + eps);
    if (base_style == 1) {
        long_walls() equalizer(vent_x);
        end_walls() equalizer([-vent_end_y, vent_end_y]);
        floor_cut() difference() {
            translate(speaker_xy) for (r = [6, 11, 16, 21, 26], q = [0:3])
                let(gap = asin((rib_w + slot_w) / (2 * r)))
                    arc_slot(r, 30 + q * 90 + gap, 30 + (q + 1) * 90 - gap);
            floor_keepout();
        }
    } else if (base_style == 2) {
        h = vent_z[1] - vent_z[0];
        long_walls() for (x = [vent_x[0]:vent_pitch:vent_x[1] - h])
            translate([x, vent_z[0]]) slant(h);
        end_walls() for (y = [-vent_end_y:vent_pitch:vent_end_y - h])
            translate([y, vent_z[0]]) slant(h);
        floor_cut() difference() {
            for (x = [-28:8:20]) translate([x, 0]) chevron(16);
            floor_keepout();
        }
    } else if (base_style == 3) {
        long_walls() for (x = [vent_x[0]:vent_pitch:vent_x[1]], z = [9, 14.5, 20])
            let(d = 1.6 + 3.2 * (x - vent_x[0]) / (vent_x[1] - vent_x[0]))
                translate([x, z]) circle(d = d, $fn = 20);
        end_walls() for (y = [-vent_end_y:vent_pitch:vent_end_y], z = [9, 14.5, 20])
            translate([y, z]) circle(d = 3.2, $fn = 20);
        floor_cut() moon_2d();
    }
}

module arc_slot(r, a0, a1) {
    steps = ceil((a1 - a0) / 3);
    polygon(concat(
        [for (i = [0:steps]) let(a = a0 + (a1 - a0) * i / steps)
            (r + slot_w / 2) * [cos(a), sin(a)]],
        [for (i = [steps:-1:0]) let(a = a0 + (a1 - a0) * i / steps)
            (r - slot_w / 2) * [cos(a), sin(a)]]));
    for (a = [a0, a1]) translate(r * [cos(a), sin(a)]) circle(d = slot_w, $fn = 24);
}

module grille() translate(speaker_xy)
    for (r = grille_radii, q = [0:3]) let(gap = asin((rib_w + slot_w) / (2 * r)))
        arc_slot(r, 30 + q * 90 + gap, 30 + (q + 1) * 90 - gap);

module accent_2d() {
    contour(6.2, 7.3);
    translate(logo_xy) scale([logo_scale, logo_scale]) orbit();
    translate(speaker_xy) difference() { circle(r = 28.2); circle(r = 27); }
    for (i = [-1:1]) {
        translate([speaker_xy[0] + i * 5, -35])
            rounded_rect([1.2, i == 0 ? 6 : 3.8], 0.6);
        translate([-56 + i * 6, -25])
            rounded_rect([i == 0 ? 6 : 3.8, 1.2], 0.6);
    }
}

module text_2d() {
    translate(logo_xy + [0, 4.1 * logo_scale])
        text("LUNA STATION", size = 3.8 * logo_scale, spacing = 1.1,
             font = font, halign = "center");
    translate([-34, -9])
        text("RETRO GAME CONSOLE", size = 2.6, spacing = 1.15,
             font = font, halign = "center");
}

module inlay() slab(total_h - inlay_depth, inlay_depth) children();

module lid() difference() {
    union() {
        difference() {
            lid_envelope();
            slab(lid_z - eps, roof_z - lid_z + eps) outline(wall);
        }
        magnet_posts(lid_z, roof_z + eps);
    }
    // An annular socket preserves the magnet posts inside the locating lip.
    slab(lid_z - eps, lip_h + fit_gap + eps)
        contour(wall - lip_t - fit_gap, wall + fit_gap);
    for (p = magnets)
        translate([p[0], p[1], lid_z + magnet_depth]) rotate([180, 0, 0]) magnet_bore();
    slab(roof_z - eps, roof_t + 2 * eps) grille();
    slab(total_h - inlay_depth, inlay_depth + eps) {
        text_2d();
        accent_2d();
    }
}

module bridge_footprint() {
    translate(speaker_xy) circle(d = bridge_ring_d);
    for (i = [0:1]) hull() {
        translate(bridge_feet[i]) circle(d = boss_d);
        translate(speaker_xy + [8, (i == 0 ? -1 : 1) * 18]) circle(d = 9.2);
    }
}

module bridge() difference() {
    union() {
        slab(bridge_z, bridge_t) bridge_footprint();
        for (p = bridge_feet) translate([p[0], p[1], pcb_top])
            cylinder(d = boss_d, h = bridge_rise + eps);
    }
    translate([speaker_xy[0], speaker_xy[1], bridge_z - eps])
        cylinder(d = speaker_magnet_d + speaker_bore_clearance, h = bridge_t + 2 * eps);
    for (p = bridge_feet) translate([p[0], p[1], pcb_top - eps])
        cylinder(d = bolt_d, h = bridge_rise + bridge_t + 2 * eps);
    for (sx = [-1, 1], sy = [-1, 1])
        slab(bridge_z - eps, bridge_t + 2 * eps)
            translate(speaker_xy + [sx * 20.5, sy * 3.5])
                rounded_rect(strap_slot, 0.5);
}

module pcb_reference() difference() {
    slab(board_z, pcb_t) square(pcb, center = true);
    for (p = holes) translate([p[0], p[1], board_z - eps])
        cylinder(d = pcb_hole_d, h = pcb_t + 2 * eps);
}

function f1(x) = let(r = round(x * 10)) str(floor(r / 10), ".", r % 10);

module fit_label(t, size = 4.5, halign = "center")
    slab(floor_t - eps, fit_text_h + eps)
        text(t, size = size, font = font, halign = halign, valign = "center");

module fit_floor_2d() difference() {
    union() {
        difference() {
            square([2 * holes[3][0] + fit_bar, 2 * holes[3][1] + fit_bar], center = true);
            square([2 * holes[3][0] - fit_bar, 2 * holes[3][1] - fit_bar], center = true);
        }
        for (p = holes) translate(p) circle(d = boss_d + 4);
        square([2 * holes[3][0], fit_spine], center = true);
        translate(speaker_xy) circle(d = bridge_ring_d);
        translate([(fit_tab[0] + fit_tab[1]) / 2, 0])
            rounded_rect([fit_tab[1] - fit_tab[0], 2 * fit_tab[2]], 4);
    }
    translate(speaker_xy) circle(d = speaker_magnet_d + speaker_bore_clearance);
}

// Window wall pieces with the floor beneath them, cut from the real bottom.
module fit_wall_keep() for (s = [-1, 1])
    translate([fit_wall_x[0], s > 0 ? fit_wall_y : -case_xy[1] / 2 - 1, fit_cut])
        cube([fit_wall_x[1] - fit_wall_x[0], case_xy[1] / 2 + 1 - fit_wall_y, base_h - fit_cut]);

// Inner ribs that stop the wall pieces flexing on the thin floor.
module fit_gussets() for (s = [-1, 1], x = [fit_wall_x[0] + 1, fit_wall_x[1] - 1 - fit_gusset[0]])
    mirror([0, s < 0 ? 1 : 0, 0]) hull() {
        translate([x, case_xy[1] / 2 - 4 - fit_gusset[1], floor_t - eps])
            cube([fit_gusset[0], fit_gusset[1] + 1, eps]);
        translate([x, case_xy[1] / 2 - 4, floor_t - eps])
            cube([fit_gusset[0], 1, fit_gusset[2]]);
    }

module fit_coupons() {
    for (i = [0:2]) translate([fit_coupon_x, fit_magnet_y[i], floor_t - eps]) difference() {
        cylinder(d = magnet_boss_d, h = fit_magnet_pad + eps);
        translate([0, 0, fit_magnet_pad + eps - magnet_depth]) magnet_bore(fit_magnet_d[i]);
    }
    for (i = [0:2]) translate([fit_coupon_x, fit_insert_y[i], 0]) difference() {
        translate([0, 0, floor_t - eps]) cylinder(d = boss_d, h = board_z - floor_t + eps);
        translate([0, 0, board_z]) insert_cut(fit_insert_d[i]);
    }
}

module fit_labels() {
    translate([-30, 0]) fit_label("LUNA FIT V1");
    for (p = ports) translate([p[2], p[1] * 48.4]) fit_label(p[0], 5);
    translate(speaker_xy + [0, -19.6])
        fit_label(f1(speaker_magnet_d + speaker_bore_clearance), 3.5);
    for (i = [0:2]) {
        translate([fit_label_x, fit_magnet_y[i]]) fit_label(f1(fit_magnet_d[i]), 4.5, "left");
        translate([fit_label_x, fit_insert_y[i]]) fit_label(f1(fit_insert_d[i]), 4.5, "left");
    }
}

// Print as modelled. Case Z equals fit-test Z + fit_cut, so the PCB, posts and
// windows keep their real relative heights.
module fit_test() translate([0, 0, -fit_cut]) {
    intersection() {
        bottom(styled = false);
        union() {
            fit_wall_keep();
            for (p = holes) translate([p[0], p[1], fit_cut])
                cylinder(d = boss_d + 1, h = board_z - fit_cut + 1);
        }
    }
    slab(fit_cut, fit_floor) fit_floor_2d();
    fit_gussets();
    fit_coupons();
    fit_labels();
}

module fit_preview() {
    color(colours[0]) fit_test();
    if (show_pcb) color("#39765F", 0.85) translate([0, 0, -fit_cut]) pcb_reference();
}

module speaker_reference() translate([speaker_xy[0], speaker_xy[1], bridge_top]) {
    color("#636D76") translate([0, 0, -speaker_magnet_h])
        cylinder(d = speaker_magnet_d, h = speaker_magnet_h);
    // Simplified basket/cone envelope, not a model of the actual driver.
    color("#30343B") cylinder(d1 = 37, d2 = speaker_outer_d, h = speaker_front_h - 1);
    color("#626B74") translate([0, 0, speaker_front_h - 1])
        cylinder(d = speaker_outer_d, h = 1);
}

module magnet_references(lift = 0, show_lid = true) for (p = magnets) {
    color("#B8BDC5") translate([p[0], p[1], base_h - magnet_depth])
        cylinder(d = magnet_d, h = magnet_t);
    if (show_lid)
        color("#B8BDC5") translate([p[0], p[1], lid_z + lift + magnet_depth - magnet_t])
            cylinder(d = magnet_d, h = magnet_t);
}

module coloured_lid() {
    color(colours[1]) lid();
    color(colours[2]) inlay() text_2d();
    color(colours[3]) inlay() accent_2d();
}

module assembly(lift = 0, show_lid = true) {
    color(colours[0]) bottom();
    color(base_text_colour) slab(0, inlay_depth) base_text_2d();
    color(colours[3]) slab(0, inlay_depth) base_accent_2d();
    color("#39765F") pcb_reference();
    color("#FFAE48") bridge();
    speaker_reference();
    if (show_lid) translate([0, 0, lift]) coloured_lid();
    magnet_references(lift, show_lid);
}

if (part == "bottom") bottom();
else if (part == "lid") lid();
else if (part == "text") inlay() text_2d();
else if (part == "accent") inlay() accent_2d();
else if (part == "base_text") slab(0, inlay_depth) base_text_2d();
else if (part == "base_accent") slab(0, inlay_depth) base_accent_2d();
else if (part == "bridge") bridge();
else if (part == "fit_test") fit_test();
else if (part == "fit_preview") fit_preview();
else if (part == "pcb") pcb_reference();
else if (part == "speaker") speaker_reference();
else if (part == "assembly") assembly();
else if (part == "exploded") assembly(lift = 43);
else if (part == "inside") assembly(show_lid = false);
else if (part == "section") intersection() {
    assembly();
    translate([-150, 0, -1]) cube([300, 150, 150]);
}
else if (part == "parameters") echo([
    ["case_xy", case_xy], ["total_h", total_h], ["base_h", base_h], ["lid_z", lid_z],
    ["floor_t", floor_t], ["roof_z", roof_z], ["wall", wall],
    ["pcb", pcb], ["board_z", board_z], ["pcb_top", pcb_top], ["pcb_hole_d", pcb_hole_d],
    ["holes", holes], ["insert_bore", insert_bore], ["insert_depth", insert_depth],
    ["magnets", magnets], ["magnet_d", magnet_d], ["magnet_t", magnet_t],
    ["magnet_depth", magnet_depth], ["magnet_bore", magnet_d + magnet_clearance],
    ["lip_h", lip_h], ["fit_gap", fit_gap], ["inlay_depth", inlay_depth],
    ["speaker_xy", speaker_xy], ["speaker_magnet_d", speaker_magnet_d],
    ["speaker_bore", speaker_magnet_d + speaker_bore_clearance],
    ["speaker_outer_d", speaker_outer_d], ["bridge_z", bridge_z], ["bridge_top", bridge_top],
    ["bridge_feet", bridge_feet], ["bolt_d", bolt_d], ["component_h", component_h],
    ["ports", ports], ["port_bevel", port_bevel],
    ["port_measurements", port_measurements], ["port_clearance", port_clearance],
    ["fit_cut", fit_cut], ["fit_floor", fit_floor], ["fit_wall_x", fit_wall_x],
    ["fit_wall_y", fit_wall_y], ["fit_coupon_x", fit_coupon_x],
    ["fit_magnet_y", fit_magnet_y], ["fit_magnet_d", fit_magnet_d],
    ["fit_insert_y", fit_insert_y], ["fit_insert_d", fit_insert_d],
    ["fit_magnet_pad", fit_magnet_pad], ["fit_gusset", fit_gusset], ["fit_text_h", fit_text_h],
    ["magnet_boss_d", magnet_boss_d], ["boss_d", boss_d],
    ["base_style", base_style], ["feet", feet], ["foot_d", foot_d], ["foot_depth", foot_depth],
    ["moon_r", moon_r], ["moon_ring", moon_ring], ["moon_d", moon_d], ["vent_x", vent_x], ["vent_z", vent_z]
]);
else assert(false, str("Unknown part: ", part));
