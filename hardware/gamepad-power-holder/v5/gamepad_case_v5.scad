// V5 case: the V4 all-in-one case with fit fixes from prepare_case_v5.py
// (magnet pockets 10.1 mm, bottom-button recess 2 mm deeper). Retainers,
// rounding, USB-C tunnel and ESP32 USB access are the unchanged V4 modules.
use <../v1/gamepad_power_holder.scad>
use <../v4/gamepad_case_v4.scad>

part = "case"; // case | lid | assembly | fit_check | plug_check | lid_check
case_h = 30;
lid_drop = case_h - 135; // supplied lid: plate underside at Z=135

module case_raw_v5() import("gamepad_case_v5_raw.stl", convexity = 12);

module case_v5() {
    difference() {
        intersection() {
            union() {
                case_raw_v5();
                retainers();
            }
            rounding_envelope();
        }
        button_rounding_cut_v4();
        usb_cutter_v4();
        esp_usb_access_v4();
    }
}

module lid_v5_placed() translate([0, 0, lid_drop]) {
    import("gamepad_lid_v5.stl", convexity = 12);
    import("gamepad_lid_v5_text.stl", convexity = 12);
    import("gamepad_lid_v5_accent.stl", convexity = 12);
}

if (part == "case") case_v5();
else if (part == "lid") lid_v5_placed();
else if (part == "assembly") {
    color([0.65, 0.73, 0.82, 0.55]) case_v5();
    electronics();
    color("dimgray") charger_placed() usb_plug_model(length = 22);
}
else if (part == "fit_check") intersection() {
    case_v5();
    electronics();
}
else if (part == "plug_check") intersection() {
    case_v5();
    charger_placed() usb_plug_model(length = 35);
}
else if (part == "lid_check") intersection() {
    case_v5();
    lid_v5_placed();
}
