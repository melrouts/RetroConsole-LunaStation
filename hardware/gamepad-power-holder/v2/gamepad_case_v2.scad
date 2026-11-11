// V2: unchanged XY coordinates; thin grips at Z=0..22.232, central pod down to -12.
use <../v1/gamepad_power_holder.scad>
use <../v1/gamepad_case.scad>
include <button_profile_v2.scad>

part = "case"; // case | shell | pod | retainers | cutter | electronics | plug | assembly
pod_drop = 12;
floor_t = 1.6;
pod_wall = 1.6;
edge_r = 1;
pod_bottom_r = 2;
pod_blend_r = 2;
pod_corner_r = 3;
pod_w = 60;
pod_d = 56;
pod_y = -14;
pcb_position = [-2.7, 12, -pod_drop];
battery_y = -24;
case_h = 22.232;
$fn = 48;
eps = 0.01;

assert(pod_drop >= 12, "The existing PCB supports and plug clearance require at least 12 mm.");

module thin_raw() {
    import("gamepad_case_v2_thin_raw.stl", convexity = 12);
}

module thin_rounded() {
    difference() {
        intersection() {
            thin_raw();
            union() {
                translate([-100, -80, edge_r]) cube([200, 160, 30]);
                minkowski() {
                    translate([0, 0, edge_r]) linear_extrude(eps)
                        offset(delta = -edge_r) union() {
                        projection(cut = true) translate([0, 0, -0.75]) thin_raw();
                        translate([0,28.75]) circle(r=12.5);
                    }
                    lower_rounding_kernel(edge_r);
                }
            }
        }
        button_rounding_cut();
    }
}

module button_rounding_cut() {
    layers = concat([[-eps,edge_r]],
        [for (i=[0:16]) let(a=i*90/16)
            [edge_r*(1-cos(a)), edge_r*(1-sin(a))]],
        [[edge_r+eps,0]]);
    n = len(button_outline);
    count = len(layers);
    // End just inside the existing bore to avoid coincident STL/CAD faces.
    points = [for (layer=layers, p=button_outline)
        [p[0]+(layer[1]-2*eps)*p[2], p[1]+(layer[1]-2*eps)*p[3], layer[0]]];
    faces = concat([[for(i=[0:n-1]) i]],
        [for(j=[0:count-2],i=[0:n-1]) each
            [[j*n+i,(j+1)*n+i,(j+1)*n+(i+1)%n],
             [j*n+i,(j+1)*n+(i+1)%n,j*n+(i+1)%n]]],
        [[for(i=[n-1:-1:0]) (count-1)*n+i]]);
    polyhedron(points,faces,convexity=10);
}

function ring(inset, z) = [
    for (q = [0:3], i = [0:16])
        let(a = q * 90 + i * 90 / 16,
            cx = (q == 0 || q == 3 ? 1 : -1) * (pod_w / 2 - pod_corner_r),
            cy = pod_y + (q < 2 ? 1 : -1) * (pod_d / 2 - pod_corner_r))
        [cx + (pod_corner_r - inset) * cos(a),
         cy + (pod_corner_r - inset) * sin(a), z]
];

module pod_outer() {
    layers = concat(
        [for (i = [0:16])
            let(a = i * 90 / 16)
            [-pod_drop + pod_bottom_r * (1 - cos(a)), pod_bottom_r * (1 - sin(a))]],
        [for (i = [0:16])
            let(a = i * 90 / 16)
            [-pod_blend_r + pod_blend_r * sin(a), -pod_blend_r * (1 - cos(a))]],
        [[1.6, -pod_blend_r]]
    );
    n = 68;
    count = len(layers);
    points = [for (layer = layers) each ring(layer[1], layer[0])];
    faces = concat(
        [[for (i = [0:n-1]) i]],
        [for (j = [0:count-2], i = [0:n-1])
            each [[j*n+i, (j+1)*n+i, (j+1)*n+(i+1)%n],
                  [j*n+i, (j+1)*n+(i+1)%n, j*n+(i+1)%n]]],
        [[for (i = [n-1:-1:0]) (count-1)*n+i]]
    );
    polyhedron(points, faces, convexity = 12);
}

module cavity_profile() {
    polygon([for (p = ring(pod_wall, 0)) [p[0], p[1]]]);
}

module cavity() {
    translate([0, 0, -pod_drop + floor_t])
        linear_extrude(pod_drop + case_h) cavity_profile();
}

module board_placed() {
    translate(pcb_position) rotate([0, 0, 180]) children();
}

module pcb_retainer() {
    board_placed() intersection() {
        holder();
        translate([-eps, -2-eps, -eps]) cube([26.6+eps, 21.35+eps, 30]);
    }
}

module battery_retainer() {
    translate([0, battery_y, -pod_drop]) {
        difference() {
            translate([-24.85, -17.35, 0]) cube([49.7, 34.7, 8.6]);
            translate([-23.25, -15.75, floor_t]) cube([46.5, 31.5, 20]);
            // Battery wire exit and space for the PCB's rear snap finger.
            translate([-25, 15.7, floor_t]) cube([6, 2, 20]);
            for (x = [-23.25, 23.25], y = [-15.75, 15.75])
                translate([x, y, floor_t]) cylinder(r = 1, h = 20);
        }
        translate([0, -31, 0]) {
            strap_loop(24.85, 1);
            strap_loop(-24.85, -1);
        }
    }
}

module retainers() {
    intersection() {
        pod_outer();
        union() {
            pcb_retainer();
            battery_retainer();
        }
    }
}

module cutter() {
    board_placed() usb_c_cutter(ext = 15);
}

module pod() {
    difference() {
        union() {
            difference() {
                pod_outer();
                cavity();
            }
            retainers();
        }
        cutter();
    }
}

module shell() {
    difference() {
        thin_rounded();
        // Open the floor only; keep the tall wall junctions above the pod.
        intersection() {
            cavity();
            translate([-100, -80, -eps]) cube([200, 160, 1.51+eps]);
        }
    }
}

module complete_case() {
    difference() {
        union() {
            shell();
            pod();
        }
        cutter();
    }
}

module electronics() {
    board_placed() board_model();
    color("lightsteelblue")
        translate([-22.5, battery_y-15, -pod_drop+floor_t]) cube([45, 30, 9]);
}

if (part == "case") complete_case();
else if (part == "shell") shell();
else if (part == "pod") pod();
else if (part == "retainers") retainers();
else if (part == "cutter") cutter();
else if (part == "electronics") electronics();
else if (part == "plug") board_placed() usb_plug_model(length = 50);
else if (part == "assembly") {
    color([0.65, 0.73, 0.82, 0.4]) shell();
    color("orange") pod();
    electronics();
    color("dimgray") board_placed() usb_plug_model(length = 22);
}
