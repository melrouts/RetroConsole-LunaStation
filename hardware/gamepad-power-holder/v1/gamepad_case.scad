// Supplied gamepad shell, in its original Z-up millimetre coordinates.
use <gamepad_power_holder.scad>

part = "case"; // case | rounded | holder | cutter | assembly | fit_check | plug_check
case_file = "../originals/gamepad_case_original.stl";
bottom_radius = 1.0;
holder_position = [-35.0, -41.7, 1.48];
holder_rotation = 0;
cut_extension = 15;

$fn = 48;
eps = 0.01;
case_height = 25.232;
floor_thickness = 1.5;

assert(bottom_radius >= 0 && bottom_radius <= 1.2,
       "Keep the bottom radius between 0 and 1.2 mm for this 1.5 mm floor.");

module original_case() {
    import(case_file, convexity = 10);
}

module outside_outline() {
    projection(cut = true)
        translate([0, 0, -floor_thickness / 2]) original_case();
    // Fill the central opening in the rounding mask only, not in the case.
    translate([0, 28.75]) circle(r = 12.5);
}

module lower_rounding_kernel(r) {
    // Explicit pole keeps the flat underside at Z=0 after the Minkowski sum.
    rotate_extrude()
        polygon(concat([[0, 0]],
                       [for (a = [-90 : 90 / 16 : 0]) [r * cos(a), r * sin(a)]]));
}

module rounded_case() {
    if (bottom_radius == 0) original_case();
    else intersection() {
        original_case();
        union() {
            translate([-100, -80, bottom_radius])
                cube([200, 160, case_height + eps]);
            minkowski() {
                translate([0, 0, bottom_radius])
                    linear_extrude(height = eps)
                        offset(delta = -bottom_radius) outside_outline();
                lower_rounding_kernel(bottom_radius);
            }
        }
    }
}

module placed() {
    translate(holder_position) rotate([0, 0, holder_rotation]) children();
}

module positioned_cutter() {
    // The curved wall is farther from the socket at the sides of the plug.
    placed() usb_c_cutter(ext = cut_extension);
}

module complete_case() {
    difference() {
        union() {
            rounded_case();
            placed() holder();
        }
        positioned_cutter();
    }
}

module electronics() {
    placed() {
        board_model();
        battery_model();
    }
}

if (part == "case") complete_case();
else if (part == "rounded") rounded_case();
else if (part == "holder") placed() holder();
else if (part == "cutter") positioned_cutter();
else if (part == "assembly") {
    color([0.68, 0.76, 0.83, 0.45]) difference() {
        rounded_case();
        positioned_cutter();
    }
    color("orange") placed() holder();
    electronics();
    color("dimgray") placed() usb_plug_model(length = 20);
}
else if (part == "fit_check") intersection() {
    complete_case();
    electronics();
}
else if (part == "plug_check") intersection() {
    complete_case();
    placed() usb_plug_model(length = 50);
}
