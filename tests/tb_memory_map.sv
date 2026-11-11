`timescale 1ns/1ps
module tb_memory_map;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg valid = 0;
    reg [31:0] addr = 0;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    wire ready;
    wire [31:0] rdata;
    reg [3:0] inputs = 0;
    reg [7:0] events = 0;
    reg vblank_tick = 0;
    wire [31:0] audio_control, audio_period, boot_status;
    wire fault;
    wire unused_sd_sck, unused_sd_cs_n, unused_sd_mosi;
    wire unused_video_write, unused_terrain_write;
    wire unused_uart_read, unused_uart_write, audio_link_write, audio_config_write;
    integer audio_writes = 0, config_writes = 0;
    reg [31:0] last_audio_data = 0;
    always @(posedge clk) begin
        if (audio_link_write) begin
            audio_writes <= audio_writes + 1;
            last_audio_data <= wdata;
        end
        if (audio_config_write)
            config_writes <= config_writes + 1;
    end
    memory_map dut (
        .clk(clk), .reset_n(reset_n), .mem_valid(valid), .mem_addr(addr),
        .mem_wdata(wdata), .mem_wstrb(wstrb), .mem_ready(ready), .mem_rdata(rdata),
        .input_state(inputs), .input_events(events), .audio_control(audio_control),
        .video_status(32'b1), .frame_count(32'd123), .vblank_tick(vblank_tick),
        .sd_sck(unused_sd_sck), .sd_cs_n(unused_sd_cs_n),
        .sd_mosi(unused_sd_mosi), .sd_miso(1'b1),
        .video_write(unused_video_write), .terrain_write(unused_terrain_write),
        .video_read_data(32'b0),
        .uart_read(unused_uart_read), .uart_write(unused_uart_write), .uart_read_data(32'b0),
        .audio_link_write(audio_link_write), .audio_config_write(audio_config_write),
        .audio_link_status(32'h41554401),
        .audio_period(audio_period), .boot_status(boot_status), .bus_fault(fault)
    );
    task automatic access(
        input reg [31:0] address, input reg [31:0] data,
        input reg [3:0] strobes, input reg [31:0] expected
    );
        @(negedge clk);
        valid = 1; addr = address; wdata = data; wstrb = strobes;
        @(posedge clk); #1;
        if (!ready) $fatal(1, "Bus did not complete");
        if (!strobes && rdata !== expected)
            $fatal(1, "Address %h: got %h expected %h", address, rdata, expected);
        @(negedge clk);
        valid = 0; wstrb = 0;
        @(posedge clk); #1;
        if (ready) $fatal(1, "Ready did not clear");
    endtask
    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1;
        access(32'h1ffc, 32'h12345678, 4'hf, 0);
        access(32'h1ffc, 32'h0000ab00, 4'h2, 0);
        access(32'h1ffc, 0, 0, 32'h1234ab78);
        access(32'h8000001c, 0, 0, 1);
        access(32'h80000020, 0, 0, 1);
        access(32'h80000008, 32'h87654321, 4'hf, 0);
        access(32'h80000008, 32'hab000000, 4'h8, 0);
        access(32'h80000008, 0, 0, 32'hab654321);
        access(32'h80000070, 0, 0, 32'h41554401);
        access(32'h80000074, 32'h12345678, 4'h2, 0);
        if (config_writes != 0) $fatal(1, "Audio settings accepted a non-low-byte write");
        access(32'h80000074, 32'h0000002f, 4'h1, 0);
        if (config_writes != 1) $fatal(1, "Audio settings write was not delivered once");
        access(32'h80000070, 32'h12345678, 4'h2, 0);
        if (audio_writes != 0) $fatal(1, "Audio link accepted a non-low-byte write");
        access(32'h80000070, 5, 4'h1, 0);
        if (audio_writes != 1 || last_audio_data != 5)
            $fatal(1, "Audio link write was not delivered exactly once");
        access(32'h80000070, 0, 0, 32'h41554401);
        access(32'h800000fc, 0, 0, 0);
        access(32'h80000010, 0, 0, 1);
        access(32'h80000014, 0, 0, 123);
        access(32'h80000018, 0, 0, 0);
        @(negedge clk); vblank_tick = 1;
        @(negedge clk); vblank_tick = 0;
        access(32'h80000018, 0, 0, 1);
        access(32'h80000018, 1, 4'h2, 0);
        access(32'h80000018, 0, 0, 1);
        access(32'h80000018, 1, 4'h1, 0);
        access(32'h80000018, 0, 0, 0);
        @(negedge clk); vblank_tick = 1;
        access(32'h80000018, 1, 4'h1, 0);
        @(negedge clk); vblank_tick = 0;
        access(32'h80000018, 0, 0, 1);
        @(negedge clk); inputs = 4'ha; events = 8'h21;
        @(negedge clk); events = 0;
        access(32'h80000000, 0, 0, 10);
        access(32'h80000004, 0, 0, 32'h21);
        access(32'h80000004, 32'h01, 4'h1, 0);
        access(32'h80000004, 0, 0, 32'h20);
        @(negedge clk); events = 8'h20;
        access(32'h80000004, 32'h20, 4'h1, 0);
        @(negedge clk); events = 0;
        access(32'h80000004, 0, 0, 32'h20);
        access(32'h80000030, 7, 4'h1, 0);
        access(32'h80000030, 0, 0, 7);
        access(32'h2000, 32'hdeadbeef, 4'hf, 0);
        if (!fault) $fatal(1, "Out-of-range RAM must set sticky bus fault");
        access(32'h1ffc, 0, 0, 32'h1234ab78);
        access(32'h10000000, 0, 0, 32'hbad00000);
        access(32'h8000011c, 0, 0, 32'hbad00000);
        $display("PASS: RAM bounds/byte lanes, MMIO, W1C and unmapped transactions");
        $finish;
    end
    initial begin
        repeat (500) @(posedge clk);
        $fatal(1, "Memory test timed out");
    end
endmodule
