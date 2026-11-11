`timescale 1ns/1ps
module tb_video;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    wire [9:0] x, y;
    wire active, hsync, vsync, vblank_start;
    video_timing timing (.*);
    wire [23:0] rgb;
    wire active_out, hsync_out, vsync_out, frame_toggle;
    video_pattern compositor (.*);
    integer active_pixels = 0;
    integer horizontal_sync_pixels = 0;
    integer vertical_sync_pixels = 0;
    integer vblanks = 0;
    integer expected_x;
    integer expected_y;
    reg expected_active, expected_hsync, expected_vsync, expected_vblank;
    reg [8:0] previous_marker;
    reg previous_toggle;
    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1;
        for (integer frame = 0; frame < 3; frame = frame + 1) begin
            active_pixels = 0;
            horizontal_sync_pixels = 0;
            vertical_sync_pixels = 0;
            vblanks = 0;
            for (integer pixel = 0; pixel < 800*525; pixel = pixel + 1) begin
                expected_x = pixel % 800;
                expected_y = pixel / 800;
                if (x != expected_x || y != expected_y)
                    $fatal(1, "Raster dropped or repeated a pixel");
                expected_active = expected_x < 640 && expected_y < 480;
                expected_hsync = !(expected_x >= 656 && expected_x < 752);
                expected_vsync = !(expected_y >= 490 && expected_y < 492);
                expected_vblank = expected_x == 0 && expected_y == 480;
                if (active !== expected_active || hsync !== expected_hsync ||
                    vsync !== expected_vsync || vblank_start !== expected_vblank)
                    $fatal(1, "Video timing/porch/polarity mismatch");
                active_pixels = active_pixels + int'(active);
                horizontal_sync_pixels = horizontal_sync_pixels + int'(!hsync);
                vertical_sync_pixels = vertical_sync_pixels + int'(!vsync);
                vblanks = vblanks + int'(vblank_start);
                previous_marker = compositor.marker_x;
                previous_toggle = frame_toggle;
                @(posedge clk); #1;
                if (active_out !== expected_active || hsync_out !== expected_hsync ||
                    vsync_out !== expected_vsync)
                    $fatal(1, "Compositor must delay RGB and control exactly one clock");
                if (!expected_active && rgb !== 0)
                    $fatal(1, "RGB must be zero during blanking");
                if (expected_active && (expected_x == 0 || expected_x == 639 ||
                                       expected_y == 0 || expected_y == 479) &&
                    rgb !== 24'hffffff)
                    $fatal(1, "Active border pixel misaligned");
                if (!expected_vblank && (compositor.marker_x !== previous_marker ||
                                         frame_toggle !== previous_toggle))
                    $fatal(1, "Snapshot changed outside vblank boundary");
                if (expected_vblank && frame_toggle === previous_toggle)
                    $fatal(1, "Missing frame CDC toggle");
                @(negedge clk);
            end
            if (active_pixels != 640*480 || horizontal_sync_pixels != 96*525 ||
                vertical_sync_pixels != 2*800 || vblanks != 1)
                $fatal(1, "Invalid full-frame totals");
        end
        $display("PASS: 3 complete 800x525 frames, 640x480 active, sync, 1-cycle compositor and snapshot");
        $finish;
    end
    initial begin
        #13000000;
        $fatal(1, "Video test timeout");
    end
endmodule
