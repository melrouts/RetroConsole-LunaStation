// V7 case: the V5 case with the inside unchanged, on a floor 1 mm thicker.
// Bottom: 2.5 mm 45-degree chamfer on the outer edge, two contour grooves with
// 45-degree sides and a 45-degree chamfer at the bottom-button recess.
// Built in V5 coordinates (extra floor at Z -1..0), then lifted to Z 0-31.
// Lid: V6 (../v6), unchanged.
use <../v1/gamepad_power_holder.scad>
use <../v4/gamepad_case_v4.scad>

part = "case"; // case | assembly | fit_check | plug_check | lid_check
base = 1.0;                     // extra floor under the V5 case
case_h = 30 + base;
lid_drop = case_h - 135;        // V6 lid: plate underside at Z=135
chamfer = 2.5;                  // outer bottom edge, 45 degrees; ends below the inner floor (min wall 1.07 mm)
button_chamfer = 1.5;           // bottom-button recess entry, 45 degrees
button_centre = [0, 28.75];
groove_insets = [6.0, 10.5];    // groove centre lines, inset from the outer contour
groove_depth = 1.0;
groove_floor = 1.0;             // flat groove bottom; 3 mm wide at the surface
groove_step = 0.1;
$fn = 48;
eps = 0.01;

module case_raw_v5() import("../v5/gamepad_case_v5_raw.stl", convexity = 12);

module outline() union() {
    case_outline();
    translate(button_centre) circle(r = 12.5);
}

// Recess opening at the original underside.
module button_hole_2d() difference() {
    translate(button_centre) circle(r = 12.5);
    projection(cut = true) translate([0, 0, -0.05]) case_raw_v5();
}

module extra_floor() translate([0, 0, -base])
    linear_extrude(base + 0.05) difference() {
        outline();
        button_hole_2d();
    }

// The cone runs 1 mm past the contour so the chamfer crosses the wall cleanly.
module chamfer_envelope() {
    over = 1.0;
    union() {
        translate([-100, -80, -base + chamfer + over / 2]) cube([200, 160, case_h]);
        minkowski() {
            translate([0, 0, -base]) linear_extrude(eps) offset(delta = -chamfer) outline();
            cylinder(h = chamfer + over, r1 = 0, r2 = chamfer + over);
        }
    }
}

// Ends 0.2 mm inside the bore so the cut crosses the recess wall at 45 degrees.
module button_chamfer_cut() {
    inner = 0.2;
    top = -base + button_chamfer + inner;
    minkowski() {
        translate([0, 0, top]) linear_extrude(eps) offset(delta = -inner) button_hole_2d();
        translate([0, 0, -(button_chamfer + inner)])
            cylinder(h = button_chamfer + inner, r1 = button_chamfer + inner, r2 = 0);
    }
    translate([0, 0, -base - 1]) linear_extrude(1 + eps) offset(r = button_chamfer) button_hole_2d();
}

module band(d, half) difference() {
    offset(r = -(d - half)) outline();
    offset(r = -(d + half)) outline();
}

// Stepped 45-degree sides; the steps are finer than a printed layer.
module grooves() {
    n = round(groove_depth / groove_step);
    for (d = groove_insets) {
        translate([0, 0, -base - 1]) linear_extrude(1 + eps)
            band(d, groove_floor / 2 + groove_depth);
        for (i = [0:n-1])
            translate([0, 0, -base + i * groove_step])
                linear_extrude(groove_step + eps)
                    band(d, groove_floor / 2 + groove_depth - (i + 0.5) * groove_step);
    }
}

module case_v7_local() {
    difference() {
        intersection() {
            union() {
                case_raw_v5();
                retainers();
                extra_floor();
            }
            chamfer_envelope();
        }
        button_chamfer_cut();
        grooves();
        usb_cutter_v4();
        esp_usb_access_v4();
    }
}

module case_v7() translate([0, 0, base]) case_v7_local();

module lid_v6_placed() translate([0, 0, lid_drop]) {
    import("../v6/gamepad_lid_v6.stl", convexity = 12);
    import("../v6/gamepad_lid_v6_text.stl", convexity = 12);
    import("../v6/gamepad_lid_v6_accent.stl", convexity = 12);
}

if (part == "case") case_v7();
else if (part == "assembly") {
    color([0.65, 0.73, 0.82, 0.55]) case_v7();
    translate([0, 0, base]) {
        electronics();
        color("dimgray") charger_placed() usb_plug_model(length = 22);
    }
}
else if (part == "fit_check") intersection() {
    case_v7_local();
    electronics();
}
else if (part == "plug_check") intersection() {
    case_v7_local();
    charger_placed() usb_plug_model(length = 35);
}
else if (part == "lid_check") intersection() {
    case_v7();
    lid_v6_placed();
}
