// V4: everything inside one 30 mm shell. ESP32 in the left grip, charger in the
// middle with USB-C through the rear wall, LiPo in the right grip.
// Generated inputs: python3 prepare_case_v4.py
use <../v1/gamepad_power_holder.scad>
use <../v1/gamepad_case.scad>
use <../v2/gamepad_case_v2.scad>
use <../v3/gamepad_holder_v3.scad>
include <button_profile_v4.scad>

part = "case"; // case | retainers | electronics | plug | lid | assembly | fit_check | plug_check
edge_r = 2;          // outer bottom edge
button_edge_r = 1;   // bottom-button recess entry
case_h = 30;
lid_drop = case_h - 135; // supplied lid: plate underside at Z=135
charger_position = [-19.3, -42.2, 0]; // USB-C centred on X=0
esp_centre = [-41.5, -15.5];          // Micro-USB faces +X, towards the middle
battery_centre = [43, -24.75];        // portrait, wire exit at the top of the inner wall
$fn = 48;
eps = 0.01;

module case_raw() import("gamepad_case_v4_raw.stl", convexity = 12);

module case_outline() {
    projection(cut = true) translate([0, 0, -0.75]) case_raw();
}

module rounding_envelope() {
    union() {
        translate([-100, -80, edge_r]) cube([200, 160, case_h]);
        minkowski() {
            translate([0, 0, edge_r]) linear_extrude(eps)
                offset(delta = -edge_r) union() {
                    case_outline();
                    translate([0, 28.75]) circle(r = 12.5);
                }
            lower_rounding_kernel(edge_r);
        }
    }
}

module button_rounding_cut_v4() {
    // Stop the arc at 75 deg and close it inside the bore: a tangent end against
    // the slightly tapered recess wall makes CGAL fail.
    end_a = 75;
    layers = concat([[-eps, button_edge_r]],
        [for (i = [0:15]) let(a = i*end_a/15)
            [button_edge_r*(1-cos(a)), button_edge_r*(1-sin(a))]],
        [[button_edge_r*(1-cos(end_a)), -0.15]]);
    n = len(button_outline_v4);
    count = len(layers);
    points = [for (layer = layers, p = button_outline_v4)
        [p[0]+layer[1]*p[2], p[1]+layer[1]*p[3], layer[0]]];
    faces = concat([[for (i = [0:n-1]) i]],
        [for (j = [0:count-2], i = [0:n-1]) each
            [[j*n+i, (j+1)*n+i, (j+1)*n+(i+1)%n],
             [j*n+i, (j+1)*n+(i+1)%n, j*n+(i+1)%n]]],
        [[for (i = [n-1:-1:0]) (count-1)*n+i]]);
    polyhedron(points, faces, convexity = 10);
}

module charger_placed() translate(charger_position) children();

module charger_v4() charger_placed() {
    // Undo the V3 placement to reuse its widened pocket unchanged.
    rotate([0, 0, 180]) translate([8.4, -9.4, 12]) charge_pocket();
    // Close the gap to the curved rear wall around the USB-C tunnel.
    box([10, -8, 0], [27.6, -2.6+eps, 13.03]);
}

module esp_v4() {
    // V3 pocket centre was (14.7, -6.1) with its floor at Z=-12.
    translate([esp_centre[0]-14.7, esp_centre[1]+6.1, 12]) esp_retainer();
}

module esp_usb_access_v4() {
    x = esp_centre[0]+20.5;
    box([x-3, esp_centre[1]-6, 4.1], [x+1.6+1, esp_centre[1]+6, case_h+1]);
}

module battery_v4() {
    translate([battery_centre[0], battery_centre[1], 0])
        mirror([1, 0, 0]) rotate([0, 0, -90])
            translate([0, 24, 12]) battery_retainer();
}

module retainers() {
    intersection() {
        translate([0, 0, -1]) linear_extrude(case_h+2) case_outline();
        union() {
            charger_v4();
            esp_v4();
            battery_v4();
        }
    }
}

module usb_cutter_v4() charger_placed() usb_c_cutter(ext = 20);

module case_v4() {
    difference() {
        intersection() {
            union() {
                case_raw();
                retainers();
            }
            rounding_envelope();
        }
        button_rounding_cut_v4();
        usb_cutter_v4();
        esp_usb_access_v4();
    }
}

module esp_model_v4() {
    x = esp_centre[0];
    y = esp_centre[1];
    color("royalblue") box([x-20, y-16, 5.1], [x+20, y+16, 6.7]);
    // Illustrative Micro-USB envelope; verify against the actual board.
    color("silver") box([x+15, y-4, 6.7], [x+21.5, y+4, 9.7]);
}

module battery_model_v4() {
    color("lightsteelblue")
        box([battery_centre[0]-15, battery_centre[1]-22.5, 1.6],
            [battery_centre[0]+15, battery_centre[1]+22.5, 10.6]);
}

module electronics() {
    charger_placed() board_model();
    esp_model_v4();
    battery_model_v4();
}

module lid_v4() translate([0, 0, lid_drop]) import("gamepad_lid_v4.stl", convexity = 12);

if (part == "case") case_v4();
else if (part == "retainers") retainers();
else if (part == "electronics") electronics();
else if (part == "plug") charger_placed() usb_plug_model(length = 35);
else if (part == "lid") lid_v4();
else if (part == "assembly") {
    color([0.65, 0.73, 0.82, 0.55]) case_v4();
    electronics();
    color("dimgray") charger_placed() usb_plug_model(length = 22);
}
else if (part == "fit_check") intersection() {
    case_v4();
    electronics();
}
else if (part == "plug_check") intersection() {
    case_v4();
    charger_placed() usb_plug_model(length = 35);
}
