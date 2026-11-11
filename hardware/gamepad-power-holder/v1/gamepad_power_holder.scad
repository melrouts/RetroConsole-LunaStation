// Gamepad power holder: EEMB LP903042 LiPo (3.7 V 1100 mAh) +
// LN4056H USB-C charge/boost module. Units: mm.
//
// Coordinates are chosen for merging into the gamepad model:
//   X - along the case wall with the USB-C port, 0 = left outer edge of holder;
//   Y - 0 = INNER face of that case wall, +Y into the case,
//       outer case surface is at Y = -case_wall;
//   Z - 0 = inner surface of the case floor.
// Merge: union(gamepad_shell, holder); difference(..., usb_c_case_cutter).
//
// openscad -D 'part="holder"' -o gamepad_power_holder.stl gamepad_power_holder.scad
// openscad -D 'part="cutter"' -o usb_c_case_cutter.stl  gamepad_power_holder.scad

part = "holder"; // holder | cutter | assembly | interference

$fn = 48;
e = 0.01;

// Gamepad case
case_wall = 2.0;            // wall thickness at the USB-C port
include_front_wall = true;  // holder copy of the case wall (needed for standalone use)

// Charge/boost module (measured from photo; verify with calipers)
pcb_w = 23.0;               // along the USB edge
pcb_d = 17.5;               // USB edge to solder-pad edge
pcb_t = 1.2;
usb_w = 8.94;
usb_h = 3.26;
usb_len = 7.3;
usb_cx = 17.5;              // receptacle centre from PCB left edge (USB edge towards you)
usb_overhang = 1.7;         // receptacle beyond PCB edge
usb_z_off = 0;              // receptacle bottom above PCB top (negative for mid-mount)

// LiPo EEMB LP903042 (length includes folded protection board)
batt_w = 30.0;
batt_l = 45.0;
batt_t = 9.0;

// Holder
base_t = 1.6;
wall = 1.6;
standoff = 3.5;             // free space under the PCB
clr_side = 0.2;
clr_back = 0.25;
batt_clr = 0.75;
batt_wall_h = 7.0;
batt_back_h = 5.0;
usb_slot_clr = 0.5;
usb_web = 1.0;              // wall left around the receptacle; the rest is plug relief
relief_w = 13.0;            // USB-C plug overmold relief on the outer face
relief_h = 7.2;
relief_r = 2.5;
strap_w = 10;               // velcro strap / cable tie width
strap_gap = 2.0;
strap_y = 31;
finger_w = 4.0;
finger_t = 0.8;
finger_slit = 0.5;
finger_root = 0.4;
lip = 0.7;
lip_h = 0.7;
left_finger_y = 9.0;
back_finger_cx = 17.75;     // from PCB left edge, between B+ and B- pads

// Derived
bp_x0 = wall;
bp_x1 = bp_x0 + pcb_w + 2 * clr_side;
bp_d = pcb_d + clr_back;
div_x1 = bp_x1 + wall;
bat_x0 = div_x1;
bat_x1 = bat_x0 + batt_w + 2 * batt_clr;
bat_l = batt_l + 2 * batt_clr;
total_x = bat_x1 + wall;
total_y = bat_l + wall;

pcb_x0 = bp_x0 + clr_side;
pcb_z0 = base_t + standoff;
pcb_top = pcb_z0 + pcb_t;
usb_x = pcb_x0 + usb_cx;
usb_z = pcb_top + usb_z_off + usb_h / 2;
slot_w = usb_w + 2 * usb_slot_clr;
slot_h = usb_h + 2 * usb_slot_clr;
front_h = usb_z + relief_h / 2 + 1.5;
bp_wall_top = pcb_top + 1.5;
lip_z0 = pcb_top + 0.1;
lip_z1 = lip_z0 + lip_h;
finger_top = lip_z1 + lip;
bat_top = base_t + batt_wall_h;
back_top = base_t + batt_back_h;
bar_z0 = base_t + 2.5;
bar_top = base_t + 6.0;
back_finger_x = pcb_x0 + back_finger_cx;

module box(p0, p1) translate(p0) cube([p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]]);

module y_rounded_rect(cx, cz, w, h, r, y0, y1) {
    hull() for (sx = [-1, 1], sz = [-1, 1])
        translate([cx + sx * (w / 2 - r), y1, cz + sz * (h / 2 - r)])
            rotate([90, 0, 0]) cylinder(r = r, h = y1 - y0);
}

module usb_c_cutter(ext = 5) {
    y_out = -case_wall - ext;
    y_rounded_rect(usb_x, usb_z, slot_w, slot_h, slot_h / 2 - e, y_out, e);
    y_rounded_rect(usb_x, usb_z, relief_w, relief_h, relief_r, y_out, -usb_web);
}

// Lip profile in the plane (outward distance from wall face, z)
module lip_profile() {
    polygon([[-e, lip_z0], [lip, lip_z0], [lip, lip_z1], [-e, lip_z1 + lip + e]]);
}

module left_finger() {
    translate([wall - finger_t, left_finger_y - finger_w / 2, finger_root])
        cube([finger_t, finger_w, finger_top - finger_root]);
    translate([wall, left_finger_y + finger_w / 2, 0])
        rotate([90, 0, 0]) linear_extrude(finger_w) lip_profile();
}

module back_finger() {
    translate([back_finger_x - finger_w / 2, bp_d, finger_root])
        cube([finger_w, finger_t, finger_top - finger_root]);
    translate([back_finger_x - finger_w / 2, bp_d, 0])
        rotate([90, 0, 90]) linear_extrude(finger_w) mirror([1, 0]) lip_profile();
}

module strap_loop(x_face, dir) {
    y0 = strap_y - strap_w / 2 - 0.5 - wall;
    y1 = strap_y + strap_w / 2 + 0.5 + wall;
    depth = strap_gap + wall;
    translate([x_face, 0, 0]) scale([dir, 1, 1]) {
        box([-e, y0, 0], [depth, y1, base_t]);
        box([-e, y0, 0], [depth, y0 + wall, bar_top]);
        box([-e, y1 - wall, 0], [depth, y1, bar_top]);
        box([strap_gap, y0, bar_z0], [depth, y1, bar_top]);
    }
}

module holder_body() {
    // Base plate
    box([0, 0, 0], [total_x, total_y, base_t]);
    if (include_front_wall) {
        box([0, -case_wall, 0], [div_x1, 0, front_h]);
        box([div_x1 - e, -case_wall, 0], [total_x, 0, bat_top]);
    }
    // Board pocket: left wall, low back wall (wires pass over it)
    box([0, 0, 0], [bp_x0, bp_d + wall, bp_wall_top]);
    box([0, bp_d, 0], [div_x1, bp_d + wall, pcb_top]);
    // PCB ledges, clear of USB-C tabs and pad solder on the underside
    box([bp_x0 - e, 0, 0], [bp_x0 + 1.5, left_finger_y - finger_w / 2 - finger_slit, pcb_z0]);
    box([bp_x0 - e, left_finger_y + finger_w / 2 + finger_slit, 0], [bp_x0 + 1.5, 15.0, pcb_z0]);
    box([bp_x1 - 1.5, 7.0, 0], [bp_x1 + e, 15.0, pcb_z0]);
    // Battery pocket: divider, right wall, back wall
    box([bp_x1, 0, 0], [div_x1, total_y, bat_top]);
    box([bat_x1, 0, 0], [total_x, total_y, bat_top]);
    box([bp_x1, bat_l, 0], [total_x, total_y, back_top]);
    strap_loop(total_x, 1);
    strap_loop(bp_x1, -1);
}

module holder() {
    difference() {
        holder_body();
        if (include_front_wall) usb_c_cutter();
        // Free the snap fingers
        box([-e, left_finger_y - finger_w / 2 - finger_slit, finger_root],
            [bp_x0 + e, left_finger_y + finger_w / 2 + finger_slit, 50]);
        box([back_finger_x - finger_w / 2 - finger_slit, bp_d - e, finger_root],
            [back_finger_x + finger_w / 2 + finger_slit, bp_d + wall + e, 50]);
        // Battery wire exit at the back of the divider
        box([bp_x1 - e, bat_l - 6.5, base_t + 1.0], [div_x1 + e, bat_l + wall + e, 50]);
        // Corner reliefs for the pouch corners
        for (x = [bat_x0, bat_x1], y = [0, bat_l])
            translate([x, y, base_t]) cylinder(r = 1.0, h = 50);
    }
    left_finger();
    back_finger();
}

module board_model() {
    color("black") translate([pcb_x0, 0, pcb_z0]) cube([pcb_w, pcb_d, pcb_t]);
    color("silver") y_rounded_rect(usb_x, pcb_top + usb_z_off + usb_h / 2, usb_w, usb_h,
                                   usb_h / 2 - e, -usb_overhang, usb_len - usb_overhang);
    color("gray") translate([pcb_x0 + 1.2, pcb_d - 10.8, pcb_top]) cube([7, 7, 3.5]);
}

module battery_model() {
    color("lightsteelblue") translate([bat_x0 + batt_clr, batt_clr, base_t])
        cube([batt_w, batt_l, batt_t]);
}

module usb_plug_model(length = 35, clearance = 0.3) {
    y_rounded_rect(usb_x, usb_z, relief_w - 2 * clearance, relief_h - 2 * clearance,
                   relief_r - clearance, -usb_overhang - length, -usb_overhang - e);
}

if (part == "holder") holder();
else if (part == "cutter") usb_c_cutter();
else if (part == "assembly") {
    color("orange") holder();
    board_model();
    battery_model();
}
else if (part == "interference") intersection() {
    holder();
    union() {
        translate([0, e, 0]) board_model();
        battery_model();
    }
}
