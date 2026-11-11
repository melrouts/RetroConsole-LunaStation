`timescale 1ns/1ps
module tb_sd_boot;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    wire [31:0] boot_status;
    wire trap, bus_fault;
    wire sd_sck, sd_cs_n, sd_mosi, sd_miso;
    wire video_write, terrain_write;
    wire uart_read, uart_write, audio_link_write, audio_config_write;
    wire update_mode, cpu_reset_n, update_tx;
    wire [31:0] uart_read_data;
    reg host_rx = 1;
    uart_update #(.CLOCKS_PER_BIT(8)) updater (
        .clk(clk), .reset_n(reset_n), .rx(host_rx), .read_valid(uart_read),
        .write_valid(uart_write), .address(peripheral_addr[3:2]),
        .write_data(peripheral_wdata[7:0]), .read_data(uart_read_data),
        .update_mode(update_mode), .cpu_reset_n(cpu_reset_n), .tx(update_tx)
    );
    wire [7:0] reply;
    wire reply_valid, reply_error;
    uart_rx #(.CLOCKS_PER_BIT(8)) host_receiver (
        .clk(clk), .reset_n(reset_n), .rx(update_tx), .data(reply),
        .valid(reply_valid), .framing_error(reply_error)
    );
    reg [255:0] last_line = 0, line_buffer = 0;
    always @(posedge clk) begin
        if (reply_valid) begin
            if (reply == 10) begin
                last_line <= line_buffer;
                line_buffer <= 0;
            end else
                line_buffer <= {line_buffer[247:0], reply};
        end
        if (reply_error) $fatal(1, "Update reply UART framing error");
    end
    task automatic send(input reg [7:0] value);
        @(negedge clk); host_rx = 0; repeat (8) @(negedge clk);
        for (integer b = 0; b < 8; b = b + 1) begin
            host_rx = value[b]; repeat (8) @(negedge clk);
        end
        host_rx = 1; repeat (10) @(negedge clk);
    endtask
    reg [7:0] upload_bytes [0:1023];
    task automatic upload_game;
        reg [63:0] magic;
        integer offset, count, source, image_size, writes_before;
        $readmemh("build/test-upload.hex", upload_bytes);
        image_size = {upload_bytes[7], upload_bytes[6], upload_bytes[5], upload_bytes[4]};
        magic = "LUNAUPD!";
        for (integer i = 7; i >= 0; i = i - 1) send(magic[i*8 +: 8]);
        wait (last_line == "READY LUP1");
        $display("UPDATE: ready");
        for (integer i = 0; i < 12; i = i + 1) send(upload_bytes[i]);
        wait (last_line == "SEND");
        $display("UPDATE: sending image");
        source = 12;
        for (offset = 0; offset < image_size; offset = offset + 64) begin
            count = offset + 64 > image_size ? image_size - offset : 64;
            @(negedge clk); last_line = 0;
            for (integer i = 0; i < count + 6; i = i + 1) begin
                send(upload_bytes[source]); source = source + 1;
            end
            wait (last_line == "ACK");
        end
        if ($test$plusargs("write-reject")) begin
            wait (last_line == "ERR write");
            wait (!update_mode);
            wait (boot_status == 7);
            if (card.writes != 0) $fatal(1, "Rejected SD write modified card");
            $display("PASS: real CPU CMD24 rejection reports ERR and returns to boot menu");
            $finish;
        end
        wait (last_line == "DONE");
        $display("UPDATE: committed, rebooting");
        wait (!update_mode);
        wait (boot_status == 7);
        wait (snapshot[39:36] == 9);
        writes_before = ram_writes;
        @(negedge clk); input_events = 2; input_state = 2;
        @(negedge clk); input_events = 0;
        wait (ram_writes >= writes_before + 404);
        if (card.writes != 2 + (image_size + 511)/512 ||
            card.card[85*512] != "U" || card.card[85*512+4] != 1)
            $fatal(1, "Update was not committed to inactive slot");
        if (dut.memory.ram[32] !== {card.card[86*512+163], card.card[86*512+162],
                                  card.card[86*512+161], card.card[86*512+160]})
            $fatal(1, "Factory LUNAR ran instead of uploaded SMOKE");
        $display("PASS: real UART upload, CMD24+CRC16, slot readback/commit, CPU reboot from new image");
        $finish;
    endtask
    wire [11:0] peripheral_addr;
    wire [31:0] peripheral_wdata, video_read_data;
    wire [3:0] peripheral_wstrb;
    wire video_busy, video_error;
    wire [223:0] snapshot;
    wire [9:0] unused_terrain_height;
    reg [31:0] frame_count = 0;
    reg [18:0] frame_cycles = 0;
    wire vblank_tick = frame_cycles == 449999;
    reg [3:0] input_state = 0;
    reg [7:0] input_events = 0;
    always @(posedge clk) begin
        if (vblank_tick) begin
            frame_cycles <= 0;
            frame_count <= frame_count + 1;
        end else begin
            frame_cycles <= frame_cycles + 1;
        end
    end
    video_snapshot frames (
        .clk(clk), .reset_n(reset_n), .write_valid(video_write),
        .write_index(peripheral_addr[4:2]), .write_data(peripheral_wdata),
        .write_strobes(peripheral_wstrb), .read_data(video_read_data),
        .terrain_write(terrain_write), .terrain_index(peripheral_addr[11:2]),
        .busy(video_busy), .error(video_error),
        .pixel_clk(clk), .pixel_reset_n(reset_n), .vblank_start(vblank_tick),
        .pixel_x(10'b0), .terrain_height(unused_terrain_height), .snapshot(snapshot)
    );
    smoke_soc #(.BOOT_ENABLE(1'b1)) dut (
        .clk(clk), .reset_n(cpu_reset_n), .input_state(input_state), .input_events(input_events),
        .video_status({29'b0, video_error, video_busy, 1'b1}),
        .frame_count(frame_count), .vblank_tick(vblank_tick),
        .boot_status(boot_status), .trap(trap), .bus_fault(bus_fault),
        .sd_sck(sd_sck), .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .video_write(video_write), .terrain_write(terrain_write),
        .peripheral_addr(peripheral_addr), .peripheral_wdata(peripheral_wdata),
        .peripheral_wstrb(peripheral_wstrb), .video_read_data(video_read_data),
        .uart_read(uart_read), .uart_write(uart_write), .uart_read_data(uart_read_data),
        .audio_link_write(audio_link_write), .audio_config_write(audio_config_write),
        .audio_link_status($test$plusargs("no-audio") ? 32'b0 : 32'h41554401)
    );
    sd_card_model card (.sck(sd_sck), .cs_n(sd_cs_n), .mosi(sd_mosi), .miso(sd_miso));
    integer expected_status;
    integer ram_writes = 0;
    integer audio_writes = 0;
    reg [2:0] last_audio = 0;
    always @(posedge clk) begin
        if (reset_n && dut.mem_valid && dut.mem_ready && dut.mem_addr < 8192 &&
            (|dut.mem_wstrb))
            ram_writes <= ram_writes + 1;
        if (reset_n && audio_link_write) begin
            audio_writes <= audio_writes + 1;
            last_audio <= peripheral_wdata[2:0];
        end
    end
    initial begin
        expected_status = 7;
        repeat (5) @(negedge clk);
        reset_n = 1;
        wait (boot_status != 0 || trap || bus_fault);
        #1;
        if (boot_status != 32'(expected_status) || trap || bus_fault)
            $fatal(1, "SD boot failed: status=%0d trap=%b bus_fault=%b",
                   boot_status, trap, bus_fault);
        wait (snapshot[39:36] == 9);
        if ($test$plusargs("no-audio")) begin
            $display("PASS: boot menu remains available without audio support");
            $finish;
        end
        @(negedge clk); input_events = 2; input_state = 2;
        @(negedge clk); input_events = 0;
        if ($test$plusargs("bad-crc")) begin
            wait (boot_status == 7 && ram_writes >= 404 && snapshot[47:44] == 4);
        end else begin
            wait (boot_status == 32'(expected_status) && ram_writes >= 404);
        end
        if (ram_writes < 404)
            $fatal(1, "Application RAM must be populated from SD before image validation");
        if ($test$plusargs("update")) begin
            wait (snapshot[32]);
            upload_game();
        end
        if ($test$plusargs("game") && expected_status == 7 &&
            !$test$plusargs("bad-crc")) begin
            wait (snapshot[32] && snapshot[39:36] == 1);
            repeat (3) @(negedge clk);
            if (unused_terrain_height >= 479 || video_error || audio_writes == 0 ||
                last_audio != 4)
                $fatal(1, "Game startup: writes=%0d terrain=%0d audio_writes=%0d audio=%0d video_error=%b",
                       ram_writes, unused_terrain_height, audio_writes, last_audio, video_error);
            @(negedge clk); input_events = 2; input_state = 2;
            @(negedge clk); input_events = 0;
            wait (snapshot[39:36] == 0 && snapshot[79:64] < 16'h1200);
            if (trap || bus_fault || video_error || last_audio != 5)
                $fatal(1, "Game PLAY/thrust execution fault");
            $display("PASS: LUNAR preferred over SMOKE, main screen, START, physics, fuel and vblank snapshots");
        end
        $display("PASS: real PicoRV32 boot ROM, SPI SDHC, FAT GAMES, image CRC; status=%0d writes=%0d",
                 boot_status, ram_writes);
        $finish;
    end
    initial begin
        repeat (300000000) @(posedge clk);
        $fatal(1, "SD CPU boot timeout: status=%0d mode=%b trap=%b fault=%b last=%s",
               boot_status, update_mode, trap, bus_fault, last_line);
    end
endmodule
