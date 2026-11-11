// LUNA-9K badge: the Luna 9 lander on the Moon, simplified for FDM printing.
//
// Everything is a straight extrusion (no overhangs, no supports) and the
// smallest feature is ~1 mm. Three levels, so it prints flat on the bed either
// in one colour or in three colours:
//   base    Z 0.0 .. 1.6   sky disc
//   relief  Z 1.6 .. 2.4   rim, Moon, petals, Earth, stars
//   lander  Z 1.6 .. 3.2   body (sphere, turret, antennas), in a groove cut
//                          through the relief, standing 0.8 above it
//
// Colours: for AMS / multi-part printing load the three part STLs together.
// With plain filament changes (at Z 1.6 and 2.4) the lower 0.8 mm of the body
// is printed in the relief colour.
//
// part: "badge" = one STL | "base", "relief", "lander" = separate parts for AMS
//       "two_color_top" = relief + lander combined as the second colour
//       "flat_base", "flat_relief", "flat_lander" = 2D layers (used for the SVG)

part = "badge";
d = 60;               // badge diameter in mm; only X/Y are scaled, heights stay

base_h = 1.6;
relief_h = 0.8;       // Moon, rim, Earth, stars above the base
lander_h = 0.8;       // lander above the relief level
groove = 1.0;         // gap between the lander and the Moon

$fn = 96;

// All 2D shapes below are drawn for d = 60.
R = 30;               // outer radius
rim = 2.6;
Rf = R - rim;         // sky radius inside the rim

horizon = -5;         // Moon surface height on the centre line
moon_r = 50;

sph = [0, 2];         // lander body centre
sph_r = 9;
rod_w = 1.9;
antennas = [[-42, 10.5], [-18, 13.5], [18, 13.5], [42, 10.5]]; // [angle from vertical, length past the body]
turret = [4.8, 3.4];  // width, height above the body

earth = [18, 11];
earth_r = 3.4;
star = 1.8;
stars = [[-19, 10], [-11, 20], [21, 0]];
craters = [[-11, -20, 4.6, 1.6], [11.5, -17.5, 3.6, 1.3]]; // x, y, radius x, radius y

module disc2d() circle(r = R);

module rim2d() difference() { circle(r = R); circle(r = Rf); }

module moon2d() intersection() {
    circle(r = Rf + 0.01);
    translate([0, horizon - moon_r]) circle(r = moon_r, $fn = 180);
}

module sky_objects2d() {
    translate(earth) circle(r = earth_r);
    for (p = stars) translate(p) square(star, center = true);
}

module rod(a, b, w) hull() {
    translate(a) circle(d = w, $fn = 24);
    translate(b) circle(d = w, $fn = 24);
}

// Flared scoop with rounded corners; rot = 0 points down, +/-70 almost sideways.
module petal(hinge, rot, len, w0, w1, r = 1.2) translate(hinge) rotate(rot)
    offset(r = r) offset(delta = -r)
        polygon([[-w0 / 2, 0], [w0 / 2, 0], [w1 / 2, -len], [-w1 / 2, -len]]);

module petals2d() {
    for (s = [-1, 1]) petal(sph + [s * 6, -4.5], s * 64, 12.5, 3.4, 9.2);
    petal(sph + [0, -6], 0, 11.5, 4.4, 13);
}

module body2d() {
    for (a = antennas)
        rod(sph, sph + (sph_r + a[1]) * [sin(a[0]), cos(a[0])], rod_w);
    translate(sph + [-turret[0] / 2, sph_r - 1.2]) square([turret[0], turret[1] + 1.2]);
    translate(sph) circle(r = sph_r);
}

module craters2d() for (c = craters) translate([c[0], c[1]]) scale([c[2], c[3]]) circle(r = 1);

// Moon level: petals are cut out of the Moon with a groove and put back, then the
// groove around the body (sphere, turret, antennas) is cut through both.
module relief2d() difference() {
    union() {
        difference() {
            union() { rim2d(); moon2d(); sky_objects2d(); }
            offset(r = groove) petals2d();
            craters2d();
        }
        petals2d();
    }
    offset(r = groove) body2d();
}

module slab(z0, z1) translate([0, 0, z0]) linear_extrude(height = z1 - z0) children();

module base3d() slab(0, base_h) disc2d();
module relief3d() slab(base_h, base_h + relief_h) relief2d();
module lander3d() slab(base_h, base_h + relief_h + lander_h) body2d();
module two_color_top3d() { relief3d(); lander3d(); }

k = d / R / 2;

if (part == "badge") scale([k, k, 1]) { base3d(); relief3d(); lander3d(); }
else if (part == "base") scale([k, k, 1]) base3d();
else if (part == "relief") scale([k, k, 1]) relief3d();
else if (part == "lander") scale([k, k, 1]) lander3d();
else if (part == "two_color_top") scale([k, k, 1]) two_color_top3d();
else if (part == "flat_base") scale([k, k]) disc2d();
else if (part == "flat_relief") scale([k, k]) relief2d();
else if (part == "flat_lander") scale([k, k]) body2d();
