`timescale 1ns/1ps
module tb_video_snapshot;
    reg clk = 0;
    always #5 clk = ~clk;
    reg pixel_clk = 0;
    always #7 pixel_clk = ~pixel_clk;
    reg reset_n = 0, pixel_reset_n = 0;
    reg write_valid = 0, terrain_write = 0, vblank_start = 0;
    reg [2:0] write_index = 0;
    reg [31:0] write_data = 0;
    reg [3:0] write_strobes = 4'hf;
    reg [9:0] terrain_index = 0, pixel_x = 0;
    wire [31:0] read_data;
    wire busy, error;
    wire [9:0] terrain_height;
    wire [223:0] snapshot;
    video_snapshot dut (.*);
    task automatic write_reg(input reg [2:0] index, input reg [31:0] value);
        @(negedge clk);
        write_index = index; write_data = value; write_valid = 1;
        @(negedge clk); write_valid = 0;
    endtask
    task automatic write_terrain(input reg [31:0] value);
        @(negedge clk);
        write_data = value; terrain_write = 1;
        @(negedge clk); terrain_write = 0;
    endtask
    task automatic vblank;
        repeat (5) @(negedge pixel_clk);
        vblank_start = 1;
        @(negedge pixel_clk); vblank_start = 0;
        repeat (5) @(negedge clk);
        repeat (3) @(negedge pixel_clk);
    endtask
    initial begin
        repeat (4) @(negedge pixel_clk);
        reset_n = 1; pixel_reset_n = 1;
        write_terrain(300);
        write_reg(0, 32'h01400040);
        write_reg(1, 1);
        write_reg(7, 1);
        if (!busy) $fatal(1, "Commit must remain pending until vblank");
        write_reg(0, 32'h00001234);
        repeat (8) @(negedge pixel_clk);
        if (snapshot !== 0 || terrain_height !== 479)
            $fatal(1, "Pending state/terrain leaked before frame boundary");
        vblank();
        if (busy || error || snapshot[31:0] !== 32'h01400040 || terrain_height !== 300)
            $fatal(1, "Vblank bundled snapshot/terrain exchange failed");
        write_reg(7, 1);
        vblank();
        if (snapshot[31:0] !== 32'h00001234 || terrain_height !== 300)
            $fatal(1, "Unchanged terrain must keep the active bank");
        write_terrain(400);
        if (terrain_height !== 300) $fatal(1, "Inactive terrain writes caused tearing");
        write_reg(7, 1);
        write_terrain(123);
        if (!error) $fatal(1, "Busy terrain write must report an error");
        vblank();
        if (terrain_height !== 400) $fatal(1, "Rejected write modified pending terrain");
        $display("PASS: asynchronous vblank snapshot handshake, frozen bundle, terrain banks and overrun");
        $finish;
    end
    initial begin
        #20000;
        $fatal(1, "Snapshot test timed out");
    end
endmodule
