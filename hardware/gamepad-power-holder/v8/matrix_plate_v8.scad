// V8: adapter plate for the 30x30 mm 4x4 LED matrix.
// The matrix is screwed (M2) to four standoffs on the plate; the plate is bolted
// from below (M2x6) into the four heat-set inserts of the V6 lid bosses.
// Same coordinates as the V6 lid: boss and stop ends at Z 130, lid top Z 138.8.
// The lid (V6) and the case (V7) are unchanged.
part = "plate"; // plate | board | screws | assembly
cut = false;    // assembly preview only: remove everything in front of the plane Y = window[1] + cut_dy
cut_dy = 0;
$fn = 64;

// V6 lid mount (gamepad_lid_v6.scad).
window = [0, 28.75];            // centre of the 32x32 window
boss_pitch = [40, 24];          // M2 heat-set insert centres, X x Y
mount_z = 130;                  // boss/stop ends = top face of the plate
top_z = 138.8;                  // lid top face

// LED matrix: 30x30x1.5, four holes on a 16x16 square.
pcb = 30;
pcb_t = 1.5;
pcb_pitch = 16;
pcb_hole_d = 3.4;               // measured 3-4 mm; only used for the preview
led = 5;                        // 5050 LEDs, 8 mm pitch
led_h = 1.6;
led_pitch = 8;

// Plate.
plate_t = 3.5;                  // Z 126.5-130
ear_r = 4;                      // rounding around the lid bolts
bolt_d = 2.4;                   // M2 clearance
head_d = 4.4;                   // counterbore for the head, from below
head_h = 2.0;
wire_window = 10;               // opening for the matrix wires
wire_r = 1.5;

// Matrix standoffs: M2 heat-set inserts like in the lid.
led_recess = 1.5;               // LED tops below the lid top face; raise it to sink the matrix
standoff_d = 6;
insert_d = 3.2;                 // M2 heat-set insert, 3.2-3.5 mm OD
insert_depth = 4.5;
standoff_h = top_z - led_recess - led_h - pcb_t - mount_z;  // plate top to the back of the matrix
board_z = mount_z + standoff_h;

pcb_holes = [for (sx = [-1, 1], sy = [-1, 1]) [sx * pcb_pitch / 2, sy * pcb_pitch / 2]];
bolts = [for (sx = [-1, 1], sy = [-1, 1]) [sx * boss_pitch[0] / 2, sy * boss_pitch[1] / 2]];

echo(standoff_h = standoff_h, led_top_z = board_z + pcb_t + led_h,
     pocket_floor = board_z - insert_depth - (mount_z - plate_t));

module outline() hull() for (b = bolts) translate(b) circle(r = ear_r);

module plate() translate(window) difference() {
    union() {
        translate([0, 0, mount_z - plate_t]) linear_extrude(plate_t) outline();
        for (p = pcb_holes) translate([p[0], p[1], mount_z - 0.01]) cylinder(d = standoff_d, h = standoff_h + 0.01);
    }
    translate([0, 0, mount_z - plate_t - 1]) linear_extrude(plate_t + 2)
        offset(r = wire_r) square(wire_window - 2 * wire_r, center = true);
    for (b = bolts) translate([b[0], b[1], 0]) {
        translate([0, 0, mount_z - plate_t - 1]) cylinder(d = bolt_d, h = plate_t + 2);
        translate([0, 0, mount_z - plate_t - 0.01]) cylinder(d = head_d, h = head_h + 0.01);
    }
    for (p = pcb_holes) translate([p[0], p[1], board_z - insert_depth]) {
        cylinder(d = insert_d, h = insert_depth + 0.01);
        translate([0, 0, insert_depth - 0.4]) cylinder(d1 = insert_d, d2 = insert_d + 0.8, h = 0.41);
    }
}

// Preview only: the matrix as measured.
module board() translate(window) translate([0, 0, board_z]) {
    color([0.05, 0.3, 0.12]) linear_extrude(pcb_t) difference() {
        square(pcb, center = true);
        for (p = pcb_holes) translate(p) circle(d = pcb_hole_d);
    }
    color([0.95, 0.95, 0.9]) for (i = [-1.5 : 1 : 1.5], j = [-1.5 : 1 : 1.5])
        translate([i * led_pitch - led / 2, j * led_pitch - led / 2, pcb_t]) cube([led, led, led_h]);
}

// Preview only: M2x6 pan head bolts from below, M2x5 pan head screws through the matrix.
module screws() color([0.72, 0.72, 0.75]) translate(window) {
    for (b = bolts) translate([b[0], b[1], mount_z - plate_t + head_h]) {
        cylinder(d = 2, h = 6);
        translate([0, 0, -1.6]) cylinder(d = 3.9, h = 1.6);
    }
    for (p = pcb_holes) translate([p[0], p[1], board_z + pcb_t]) {
        translate([0, 0, -5]) cylinder(d = 2, h = 5);
        cylinder(d = 3.9, h = 1.6);
    }
}

module lid() color([0.3, 0.33, 0.38]) import("../v6/gamepad_lid_v6.stl", convexity = 12);

module assembly() {
    lid();
    color([0.95, 0.55, 0.15]) plate();
    board();
    screws();
}

if (part == "plate") color([0.95, 0.55, 0.15]) plate();
else if (part == "board") board();
else if (part == "screws") screws();
else if (part == "assembly") {
    if (cut) difference() {
        assembly();
        translate([-100, window[1] + cut_dy - 100, 100]) cube([200, 100, 60]);
    } else assembly();
}
