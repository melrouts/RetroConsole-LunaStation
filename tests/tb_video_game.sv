`timescale 1ns/1ps
module tb_video_game;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg [9:0] x = 0, y = 0;
    reg active = 0, hsync = 1, vsync = 1;
    reg [9:0] terrain_height = 300;
    reg [223:0] snapshot = 0;
    reg [23:0] pattern_rgb = 0;
    wire [23:0] rgb;
    wire active_out, hsync_out, vsync_out;
    reg [23:0] previous_color = 0;
    reg previous_active = 0, previous_hsync = 1, previous_vsync = 1;
    reg [23:0] older_color = 0;
    reg older_active = 0, older_hsync = 1, older_vsync = 1;
    video_game dut (.*);
    always @(posedge clk) begin
        pattern_rgb <= {4'b0, x, y};
        terrain_height <= 300 + {4'b0, x[5:0]};
    end
    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1;
        for (integer mode = 0; mode < 2; mode = mode + 1) begin
            snapshot[32] = 1'(mode);
            snapshot[9:0] = 800;
            snapshot[25:16] = 600;
            for (integer pad = 0; pad < 3; pad = pad + 1)
                snapshot[128 + pad*32 +: 32] = 32'h03e803e8;
            for (integer cycle = 0; cycle < 520; cycle = cycle + 1) begin
                x = 10'(cycle);
                y = 300 + 10'(cycle % 64);
                active = (cycle % 5) != 0;
                hsync = (cycle % 7) != 0;
                vsync = (cycle % 11) != 0;
                @(posedge clk); #1;
                if (cycle > 1) begin
                    if (active_out !== older_active || hsync_out !== older_hsync ||
                        vsync_out !== older_vsync || rgb !== older_color)
                        $fatal(1, "Game/pattern 3-stage RGB/control alignment: mode=%0d pixel=%0d got=%h expected=%h",
                               mode, cycle, rgb, older_color);
                end
                older_color = previous_color;
                older_active = previous_active; older_hsync = previous_hsync; older_vsync = previous_vsync;
                previous_color = mode ? (active ? 24'h7ef7c0 : 0) : {4'b0, x, y};
                previous_active = active; previous_hsync = hsync; previous_vsync = vsync;
                @(negedge clk);
            end
        end
        $display("PASS: game terrain and fallback pattern have aligned 3-stage RGB/sync/blanking");
        $finish;
    end
endmodule
