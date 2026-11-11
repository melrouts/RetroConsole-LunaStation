// Standalone V3 holder. The gamepad shell and V1/V2 files are not changed.
use <../v1/gamepad_power_holder.scad>
use <../v2/gamepad_case_v2.scad>

part = "holder"; // holder | assembly | electronics | charger | esp32 | battery | cutter | plug
$fn = 48;
eps = 0.01;
floor_t = 1.6;
wall_t = 1.6;
bottom_z = -12;
width = 74;
depth = 72;
centre_y = -22;
corner_r = 3;
lower_r = 2;
blend_r = 2;

charge_extra = 1;
charge_position = [-8.4, 9.4, bottom_z];
charge_x0 = 1.6-charge_extra;
charge_x1 = 25.0+charge_extra;
charge_y0 = -charge_extra;
charge_y1 = 17.75+charge_extra;
charge_pcb_bottom = 5.1;
charge_pcb_top = 6.3;
charge_lip = 0.7+charge_extra;
charge_finger_top = charge_pcb_top+0.8+charge_lip;

esp_size = [40, 32];
esp_clearance = 0.5;
esp_thickness = 1.6; // Assumed; verify with the actual board.
esp_bottom = floor_t+3.5;
esp_top = esp_bottom+esp_thickness;
esp_pocket_x0 = -5.8;
esp_pocket_y0 = -22.6;
esp_pocket_w = esp_size[0]+2*esp_clearance;
esp_pocket_d = esp_size[1]+2*esp_clearance;
esp_cx = esp_pocket_x0+esp_pocket_w/2;
esp_cy = esp_pocket_y0+esp_pocket_d/2;
esp_lip = 0.9;
esp_finger_top = esp_top+0.8+esp_lip;
battery_shift_y = -16;

function outer_ring(inset, z) = [
    for (q=[0:3], i=[0:16])
        let(a=q*90+i*90/16,
            cx=(q==0 || q==3 ? 1 : -1)*(width/2-corner_r),
            cy=centre_y+(q<2 ? 1 : -1)*(depth/2-corner_r))
        [cx+(corner_r-inset)*cos(a),cy+(corner_r-inset)*sin(a),z]
];

module outer_body() {
    layers = concat(
        [for(i=[0:16]) let(a=i*90/16)
            [bottom_z+lower_r*(1-cos(a)),lower_r*(1-sin(a))]],
        [for(i=[0:16]) let(a=i*90/16)
            [-blend_r+blend_r*sin(a),-blend_r*(1-cos(a))]],
        [[1.6,-blend_r]]);
    n=68;
    count=len(layers);
    polyhedron(
        points=[for(layer=layers) each outer_ring(layer[1],layer[0])],
        faces=concat([[for(i=[0:n-1]) i]],
            [for(j=[0:count-2],i=[0:n-1]) each
                [[j*n+i,(j+1)*n+i,(j+1)*n+(i+1)%n],
                 [j*n+i,(j+1)*n+(i+1)%n,j*n+(i+1)%n]]],
            [[for(i=[n-1:-1:0]) (count-1)*n+i]]),convexity=12);
}

module outer_shell() {
    difference() {
        outer_body();
        translate([0,0,bottom_z+floor_t]) linear_extrude(30)
            polygon([for(p=outer_ring(wall_t,0)) [p[0],p[1]]]);
    }
}

module charge_placed() {
    translate(charge_position) rotate([0,0,180]) children();
}

module lip_section(z, reach) {
    polygon([[-eps,z+0.1],[reach,z+0.1],[reach,z+0.8],[-eps,z+0.8+reach]]);
}

module charge_fingers() {
    translate([charge_x0-0.8,7,0.4]) cube([0.8,4,charge_finger_top-0.4]);
    translate([charge_x0,11,0])
        rotate([90,0,0]) linear_extrude(4) lip_section(charge_pcb_top,charge_lip);
    translate([17.55,charge_y1,0.4]) cube([4,0.8,charge_finger_top-0.4]);
    translate([17.55,charge_y1,0])
        rotate([90,0,90]) linear_extrude(4)
            mirror([1,0]) lip_section(charge_pcb_top,charge_lip);
}

module charge_pocket() {
    charge_placed() difference() {
        union() {
            difference() {
                union() {
                    box([charge_x0-wall_t,charge_y0-wall_t,0],
                        [charge_x1+wall_t,charge_y1+wall_t,floor_t]);
                    box([charge_x0-wall_t,charge_y0,0],
                        [charge_x0,charge_y1+wall_t,7.8]);
                    box([charge_x1,charge_y0,0],
                        [charge_x1+wall_t,charge_y1+wall_t,7.8]);
                    box([charge_x0-wall_t,charge_y1,0],
                        [charge_x1+wall_t,charge_y1+wall_t,charge_pcb_top]);
                    box([charge_x0-wall_t,charge_y0-wall_t,0],
                        [charge_x1+wall_t,charge_y0,13.03]);
                    // Ledges still reach the original PCB outline despite the wider pocket.
                    box([charge_x0-eps,0,0],[3.1,6.5,charge_pcb_bottom]);
                    box([charge_x0-eps,11.5,0],[3.1,15,charge_pcb_bottom]);
                    box([23.5,7,0],[charge_x1+eps,15,charge_pcb_bottom]);
                    // Capture the USB shell above the PCB, without taking away PCB clearance.
                    box([12.83,charge_y0-eps,charge_pcb_top+0.1],[25.77,0,13.03]);
                }
                box([charge_x0-wall_t-eps,6.5,0.4],[charge_x0+eps,11.5,30]);
                box([17.05,charge_y1-eps,0.4],[22.05,charge_y1+wall_t+eps,30]);
            }
            charge_fingers();
        }
        usb_c_cutter(ext=20);
    }
}

module esp_hook(y, direction) {
    translate([esp_cx,y,0]) scale([1,direction,1]) {
        translate([-2,0,0]) rotate([90,0,90])
            linear_extrude(4) mirror([1,0]) lip_section(esp_top,esp_lip);
    }
}

module esp_finger(y) {
    translate([esp_cx-2,y,0.4]) cube([4,0.8,esp_finger_top-0.4]);
    esp_hook(y,1);
}

module esp_retainer() {
    translate([0,0,bottom_z]) {
        difference() {
            difference() {
                // Overlap the adjacent charger frame instead of leaving coincident faces.
                box([esp_pocket_x0-wall_t-eps,esp_pocket_y0-wall_t,-eps],
                    [esp_pocket_x0+esp_pocket_w+wall_t,
                     esp_pocket_y0+esp_pocket_d+wall_t+eps,esp_bottom+1]);
                box([esp_pocket_x0,esp_pocket_y0,floor_t],
                    [esp_pocket_x0+esp_pocket_w,esp_pocket_y0+esp_pocket_d,30]);
            }
            y=esp_pocket_y0+esp_pocket_d;
            box([esp_cx-2.5,y-wall_t-eps,0.4],[esp_cx+2.5,y+wall_t+eps,30]);
        }
        // Pads are inset from the GPIO rows; no mounting-hole positions are assumed.
        for(x=[esp_cx-14,esp_cx+14],y=[esp_cy-9,esp_cy+9])
            translate([x,y,floor_t]) cylinder(r=1.5,h=esp_bottom-floor_t);
        // The rear hook is fixed against the battery divider; only the front finger flexes.
        box([esp_cx-2,esp_pocket_y0-wall_t,0],
            [esp_cx+2,esp_pocket_y0,esp_finger_top]);
        esp_hook(esp_pocket_y0,-1);
        esp_finger(esp_pocket_y0+esp_pocket_d);
    }
}

module battery_v3() {
    // Keep the entire V2 battery pocket, strap loops and wire exit unchanged.
    translate([0,battery_shift_y,0]) battery_retainer();
}

module esp_usb_access() {
    // Open-ended access, rather than a tight connector cutout based on an unmeasured photo.
    box([esp_pocket_x0+esp_pocket_w-3,esp_cy-6,bottom_z+esp_bottom-1],
        [width/2+5,esp_cy+6,10]);
}

module holder_v3() {
    difference() {
        intersection() {
            outer_body();
            union() {
                outer_shell();
                charge_pocket();
                esp_retainer();
                battery_v3();
            }
        }
        charge_placed() usb_c_cutter(ext=20);
        esp_usb_access();
    }
}

module esp_model() {
    color("royalblue")
        box([esp_pocket_x0+esp_clearance,esp_pocket_y0+esp_clearance,bottom_z+esp_bottom],
            [esp_pocket_x0+esp_pocket_w-esp_clearance,
             esp_pocket_y0+esp_pocket_d-esp_clearance,bottom_z+esp_top]);
    // Illustrative Micro-USB envelope; its exact offset/height is not yet measured.
    color("silver") box(
        [esp_pocket_x0+esp_pocket_w-esp_clearance-5,esp_cy-4,bottom_z+esp_top],
        [esp_pocket_x0+esp_pocket_w-esp_clearance+1.5,esp_cy+4,bottom_z+esp_top+3]);
}

module components_v3() {
    charge_placed() board_model();
    esp_model();
    color("lightsteelblue")
        translate([-22.5,-39+battery_shift_y,bottom_z+floor_t]) cube([45,30,9]);
}

if(part=="holder") holder_v3();
else if(part=="assembly") {
    color("orange") holder_v3();
    components_v3();
}
else if(part=="electronics") components_v3();
else if(part=="charger") charge_pocket();
else if(part=="esp32") esp_retainer();
else if(part=="battery") battery_v3();
else if(part=="cutter") charge_placed() usb_c_cutter(ext=20);
else if(part=="plug") charge_placed() usb_plug_model(length=35);
