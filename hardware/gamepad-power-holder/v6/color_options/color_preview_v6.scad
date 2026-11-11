// Colour preview of the V5 case with the V6 lid (body, text inlay, accent inlay).
// Filaments: black #161616, grey #BCBCBC, orange #FF6A13.
// Variants 1-6 in color_options_v6.png (lid / text / accent / case):
// 1 K G O K   2 K O G K   3 G K O K   4 G O K G   5 K G O G   6 K O G O
cb = "#161616"; // lid body
ct = "#BCBCBC"; // LUNA STATION, THRUST
ca = "#FF6A13"; // outline, rings, orbit, frame, markers
cc = "#161616"; // case

color(cc) import("../../v5/gamepad_case_v5.stl");
translate([0, 0, -105]) {
    color(cb) import("../gamepad_lid_v6.stl");
    color(ct) import("../gamepad_lid_v6_text.stl");
    color(ca) import("../gamepad_lid_v6_accent.stl");
}
