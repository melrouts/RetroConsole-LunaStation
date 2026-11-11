`timescale 1ns/1ps
// Pad score labels and the end-of-flight result block of the video_game renderer.
module tb_video_result;
    localparam [23:0] FILL = 24'h102a38, WHITE = 24'hffffff, RED = 24'hff728c,
                      CYAN = 24'hc4f9ef, GOLD = 24'hffd451, BORDER = 24'h286077,
                      SPACE = 24'h020813, DIMMED_SPACE = 24'h000204;
    localparam integer PLAY = 0, MENU = 1, LANDED = 3, CRASHED = 4, GAME_OVER = 5;

    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg [9:0] x = 0, y = 0;
    reg active = 1, hsync = 1, vsync = 1;
    reg [9:0] terrain_height = 0;
    reg [223:0] snapshot = 0;
    reg [23:0] pattern_rgb = 0;
    wire [23:0] rgb;
    wire active_out, hsync_out, vsync_out;
    video_game dut (.*);

    reg [7:0] font [0:767];
    reg [9:0] ground [0:639];
    reg [23:0] frame [0:307199];
    reg [31:0] scene_file [0:642];
    integer pad_left [0:2];
    integer pad_right [0:2];
    integer ship_px, ship_py;
    integer label_cycles = 0, points_cycles = 0, reason_cycles = 0, panel_cycles = 0;
    integer output_file;
    reg [1023:0] scene_path;
    initial $readmemh("build/font.hex", font);

    // Like the snapshot block, the terrain height is registered with the pixel
    // position so that it arrives together with x_q inside the renderer.
    always @(posedge clk) begin
        terrain_height <= ground[x < 640 ? x : 639];
        if (dut.label_text_q) label_cycles = label_cycles + 1;
        if (dut.points_text_q) points_cycles = points_cycles + 1;
        if (dut.reason_text_q) reason_cycles = reason_cycles + 1;
        if (dut.panel_qq || dut.panel_edge_qq) panel_cycles = panel_cycles + 1;
    end

    function automatic [19:0] to_bcd(input integer value);
        integer remaining;
        begin
            to_bcd = 0;
            remaining = value;
            for (integer digit_index = 0; digit_index < 5; digit_index = digit_index + 1) begin
                to_bcd[digit_index*4 +: 4] = 4'(remaining % 10);
                remaining = remaining / 10;
            end
        end
    endfunction

    // Columns 7..12 of the points row: right-aligned "+N" without leading zeros.
    function automatic [47:0] number_text(input integer value);
        integer remaining, position;
        begin
            number_text = {6{8'h20}};
            remaining = value;
            position = 0;
            do begin
                number_text[8*position +: 8] = 8'(8'h30 + remaining % 10);
                remaining = remaining / 10;
                position = position + 1;
            end while (remaining != 0);
            number_text[8*position +: 8] = "+";
        end
    endfunction

    function automatic [23:0] pad_color(input integer pad);
        pad_color = pad == 0 ? 24'h7ef7c0 : pad == 1 ? 24'h34d9ff : 24'hffd451;
    endfunction

    function automatic integer pad_center(input integer pad);
        pad_center = (pad_left[pad] + pad_right[pad]) / 2;
    endfunction

    function automatic integer reasons_used(input reg [3:0] cause);
        reasons_used = cause[0] + cause[1] + cause[2] + cause[3];
    endfunction

    function automatic integer panel_bottom(input integer used);
        panel_bottom = used == 4 ? 250 : 160 + 24*used;
    endfunction

    task automatic flat_ground(input integer pad, input integer height);
        begin
            for (integer column = pad_left[pad]; column <= pad_right[pad]; column = column + 1)
                ground[column] = 10'(height);
        end
    endtask

    task automatic default_scene;
        begin
            for (integer column = 0; column < 640; column = column + 1)
                ground[column] = 10'(300 + (column*7) % 41);
            pad_left[0] = 96;  pad_right[0] = 200; flat_ground(0, 350);
            pad_left[1] = 300; pad_right[1] = 360; flat_ground(1, 400);
            pad_left[2] = 496; pad_right[2] = 536; flat_ground(2, 430);
            ship_px = pad_center(1);
            ship_py = 400 - 9;
        end
    endtask

    task automatic load_scene(input reg [1023:0] path);
        begin
            $readmemh(path, scene_file);
            for (integer column = 0; column < 640; column = column + 1)
                ground[column] = scene_file[column][9:0];
            for (integer pad = 0; pad < 3; pad = pad + 1) begin
                pad_left[pad] = int'(scene_file[640 + pad][9:0]);
                pad_right[pad] = int'(scene_file[640 + pad][25:16]);
            end
            ship_px = pad_center(1);
            ship_py = int'(ground[pad_center(1)]) - 9;
        end
    endtask

    task automatic set_snapshot(input integer state, input integer points,
                                input reg [3:0] cause);
        reg [23:0] result;
        begin
            result = {cause, to_bcd(points)};
            snapshot = 0;
            snapshot[9:0] = 10'(ship_px);
            snapshot[25:16] = 10'(ship_py);
            snapshot[32] = 1'b1;
            snapshot[39:36] = 4'(state);
            snapshot[63:56] = 8'd70;
            snapshot[95:64] = 32'h03030845;
            snapshot[127:96] = 32'h00001437;
            for (integer pad = 0; pad < 3; pad = pad + 1)
                snapshot[128 + pad*32 +: 32] = {result[pad*12 + 6 +: 6], 10'(pad_right[pad]),
                                                 result[pad*12 +: 6], 10'(pad_left[pad])};
        end
    endtask

    task automatic clear_monitors;
        begin
            label_cycles = 0; points_cycles = 0; reason_cycles = 0; panel_cycles = 0;
        end
    endtask

    // One pixel per clock, the way the video timing block drives the renderer.
    task automatic stream(input integer first_row, input integer last_row);
        integer total, step, index;
        begin
            total = (last_row - first_row + 1) * 640;
            for (step = 0; step < total + 2; step = step + 1) begin
                @(negedge clk);
                if (step < total) begin
                    x = 10'(step % 640);
                    y = 10'(first_row + step / 640);
                end
                @(posedge clk); #1;
                if (step >= 2) begin
                    index = step - 2;
                    frame[(first_row + index / 640)*640 + index % 640] = rgb;
                end
            end
        end
    endtask

    task automatic expect_text(input integer left, input integer top,
                               input reg [255:0] text, input integer length,
                               input reg [23:0] color, input integer exact_background,
                               input reg [23:0] background, input reg [255:0] name);
        reg [7:0] character;
        reg lit;
        reg [23:0] got;
        begin
            for (integer column = 0; column < length; column = column + 1) begin
                character = text[8*(length-1-column) +: 8];
                for (integer row = 0; row < 16; row = row + 1)
                    for (integer pixel = 0; pixel < 16; pixel = pixel + 1) begin
                        lit = character != 8'h20 &&
                              font[(int'(character) - 32)*8 + row/2][7 - pixel/2];
                        got = frame[(top + row)*640 + left + column*16 + pixel];
                        if (lit && got !== color)
                            $fatal(1, "%0s: glyph %0d pixel (%0d,%0d) is %h, want %h",
                                   name, column, pixel, row, got, color);
                        if (!lit && got === color)
                            $fatal(1, "%0s: glyph %0d pixel (%0d,%0d) has the text color",
                                   name, column, pixel, row);
                        if (!lit && exact_background != 0 && got !== background)
                            $fatal(1, "%0s: glyph %0d pixel (%0d,%0d) is %h, want background %h",
                                   name, column, pixel, row, got, background);
                    end
            end
        end
    endtask

    function automatic integer count_pixels(input integer left, input integer top,
                                            input integer width, input integer height,
                                            input reg [23:0] color);
        integer count;
        begin
            count = 0;
            for (integer row = top; row < top + height; row = row + 1)
                for (integer column = left; column < left + width; column = column + 1)
                    if (frame[row*640 + column] === color) count = count + 1;
            count_pixels = count;
        end
    endfunction

    task automatic check_labels(input reg [255:0] name);
        reg [15:0] text;
        begin
            for (integer pad = 0; pad < 3; pad = pad + 1) begin
                text = pad == 0 ? "X1" : pad == 1 ? "X2" : "X4";
                expect_text(pad_center(pad) - 16, int'(ground[pad_center(pad)]) + 8,
                            256'(text), 2, pad_color(pad), 1, FILL, name);
            end
        end
    endtask

    task automatic check_reason_rows(input reg [3:0] cause, input reg [255:0] name);
        integer row;
        begin
            row = 0;
            if (cause[0]) begin
                expect_text(144, 160 + 24*row, "MISSED THE LANDING PAD", 22, RED, 0, 0, name);
                row = row + 1;
            end
            if (cause[1]) begin
                expect_text(144, 160 + 24*row, "DESCENT SPEED TOO HIGH", 22, RED, 0, 0, name);
                row = row + 1;
            end
            if (cause[2]) begin
                expect_text(160, 160 + 24*row, "SIDE SPEED TOO HIGH", 19, RED, 0, 0, name);
                row = row + 1;
            end
            if (cause[3]) begin
                expect_text(160, 160 + 24*row, "TILT ANGLE TOO LARGE", 20, RED, 0, 0, name);
                row = row + 1;
            end
            for (integer unused = row; unused < 4; unused = unused + 1)
                if (count_pixels(64, 160 + 24*unused, 512, 16, RED) != 0)
                    $fatal(1, "%0s: unused reason row %0d is not empty", name, unused);
        end
    endtask

    task automatic check_panel(input integer used, input reg [255:0] name);
        integer bottom;
        begin
            bottom = panel_bottom(used);
            if (count_pixels(66, 100, 5, 5, DIMMED_SPACE) < 20 ||
                count_pixels(66, 100, 5, 5, SPACE) != 0)
                $fatal(1, "%0s: panel interior is not dimmed", name);
            if (count_pixels(50, 100, 5, 5, SPACE) < 20 ||
                count_pixels(50, 100, 5, 5, DIMMED_SPACE) != 0)
                $fatal(1, "%0s: area left of the panel must not be dimmed", name);
            if (count_pixels(100, 98, 1, 1, BORDER) != 1 ||
                count_pixels(100, bottom - 1, 1, 1, BORDER) != 1 ||
                count_pixels(64, 150, 1, 1, BORDER) != 1 ||
                count_pixels(575, 150, 1, 1, BORDER) != 1)
                $fatal(1, "%0s: panel border is missing", name);
            if (count_pixels(100, 97, 1, 1, BORDER) != 0 ||
                count_pixels(100, bottom, 1, 1, BORDER) != 0 ||
                count_pixels(63, 150, 1, 1, BORDER) != 0 ||
                count_pixels(576, 150, 1, 1, BORDER) != 0)
                $fatal(1, "%0s: panel border is too large", name);
            if (count_pixels(60, bottom + 1, 8, 4, SPACE) < 28)
                $fatal(1, "%0s: panel must end at y=%0d", name, bottom);
        end
    endtask

    task automatic check_result(input integer state, input integer points,
                                input reg [3:0] cause, input reg [255:0] name);
        integer used;
        begin
            used = reasons_used(cause);
            set_snapshot(state, points, cause);
            clear_monitors();
            stream(96, 254);
            if (state == LANDED)
                expect_text(104, 112, "LANDED! NEXT RELEASE WINDOW", 27, WHITE, 0, 0, name);
            else if (state == CRASHED)
                expect_text(144, 112, "CRASHED - CAPSULE LOST", 22, RED, 0, 0, name);
            else
                expect_text(128, 112, "GAME OVER - W TO RESTART", 24, WHITE, 0, 0, name);
            expect_text(216, 136, "POINTS", 6, CYAN, 0, 0, name);
            expect_text(328, 136, 256'(number_text(points)), 6, GOLD, 0, 0, name);
            check_reason_rows(cause, name);
            check_panel(used, name);
            if (points_cycles == 0 || panel_cycles == 0)
                $fatal(1, "%0s: result block was not drawn", name);
            if ((used != 0) != (reason_cycles != 0))
                $fatal(1, "%0s: reason rows do not follow the failure bits", name);
        end
    endtask

    task automatic check_result_blanking;
        begin
            set_snapshot(CRASHED, 0, 4'hf);
            for (integer point = 0; point < 3; point = point + 1) begin
                @(negedge clk);
                active = 0; hsync = 0; vsync = 0;
                x = point == 0 ? 64 : point == 1 ? 100 : 216;
                y = point == 0 ? 150 : point == 1 ? 100 : 136;
                repeat (3) @(posedge clk);
                #1;
                if (rgb !== 24'h000000 || active_out !== 0 ||
                    hsync_out !== 0 || vsync_out !== 0)
                    $fatal(1, "Result panel drew during blanking at point %0d", point);
            end
            @(negedge clk);
            active = 1; hsync = 1; vsync = 1;
        end
    endtask

    task automatic check_points_format(input integer value);
        reg [47:0] expected;
        begin
            set_snapshot(LANDED, value, 0);
            #1;
            expected = number_text(value);
            if (dut.result_points !== to_bcd(value) || dut.result_cause !== 0)
                $fatal(1, "Result fields of %0d decode as %h/%h", value,
                       dut.result_points, dut.result_cause);
            for (integer column = 7; column < 13; column = column + 1)
                if (dut.points_character(5'(column)) !== expected[8*(12-column) +: 8])
                    $fatal(1, "Points %0d column %0d shows %c, want %c", value, column,
                           dut.points_character(5'(column)), expected[8*(12-column) +: 8]);
        end
    endtask

    task automatic check_cause_packing;
        integer seen, wanted;
        begin
            for (integer cause = 0; cause < 16; cause = cause + 1) begin
                set_snapshot(CRASHED, 0, 4'(cause));
                #1;
                if (dut.result_cause !== 4'(cause))
                    $fatal(1, "Failure bits %0d decode as %0d", cause, dut.result_cause);
                for (integer row = 0; row < 4; row = row + 1) begin
                    seen = 0;
                    wanted = 4;
                    for (integer bit_index = 0; bit_index < 4; bit_index = bit_index + 1)
                        if (cause[bit_index]) begin
                            if (seen == row) wanted = bit_index;
                            seen = seen + 1;
                        end
                    if (dut.next_reason_rows[row*3 +: 3] !== 3'(wanted))
                        $fatal(1, "Failure bits %0d: row %0d shows %0d, want %0d", cause,
                               row, dut.next_reason_rows[row*3 +: 3], wanted);
                end
            end
        end
    endtask

    task automatic check_labels_hidden(input integer state, input reg [255:0] name);
        begin
            set_snapshot(state, 0, 0);
            for (integer pad = 0; pad < 3; pad = pad + 1)
                for (integer row = 0; row < 16; row = row + 1)
                    for (integer column = 0; column < 32; column = column + 1) begin
                        x = 10'(pad_center(pad) - 16 + column);
                        y = 10'(int'(ground[pad_center(pad)]) + 8 + row);
                        #1;
                        if (dut.label_text !== 1'b0)
                            $fatal(1, "%0s: pad label must not be drawn", name);
                    end
        end
    endtask

    task automatic check_labels_visible(input integer state, input reg [255:0] name);
        begin
            set_snapshot(state, 0, 0);
            for (integer pad = 0; pad < 3; pad = pad + 1) begin
                x = 10'(pad_center(pad));
                y = 10'(int'(ground[pad_center(pad)]) + 8);
                #1;
                if (dut.label_text !== 1'b1)
                    $fatal(1, "%0s: pad %0d label is missing", name, pad);
                x = 10'(pad_center(pad) - 17);
                #1;
                if (dut.label_text !== 1'b0)
                    $fatal(1, "%0s: pad %0d label starts too early", name, pad);
                x = 10'(pad_center(pad) + 16);
                #1;
                if (dut.label_text !== 1'b0)
                    $fatal(1, "%0s: pad %0d label ends too late", name, pad);
            end
        end
    endtask

    task automatic write_ppm(input reg [255:0] filename);
        begin
            output_file = $fopen(filename, "wb");
            if (!output_file) $fatal(1, "Cannot open renderer capture");
            $fwrite(output_file, "P6\n640 480\n255\n");
            for (integer index = 0; index < 640*480; index = index + 1)
                $fwrite(output_file, "%c%c%c", frame[index][23:16], frame[index][15:8],
                        frame[index][7:0]);
            $fclose(output_file);
        end
    endtask

    task automatic capture_screen(input integer state, input integer points,
                                  input reg [3:0] cause, input reg [255:0] filename);
        begin
            set_snapshot(state, points, cause);
            stream(0, 479);
            write_ppm(filename);
        end
    endtask

    initial begin
        default_scene();
        repeat (3) @(negedge clk);
        reset_n = 1;

        for (integer value = 0; value < 1200; value = value + 1)
            check_points_format(value);
        for (integer value = 1200; value < 100000; value = value + 997)
            check_points_format(value);
        check_points_format(9999);
        check_points_format(10000);
        check_points_format(12210);
        check_points_format(99999);
        check_cause_packing();

        // Flight: every pad carries its multiplier; stale result bits stay hidden.
        set_snapshot(PLAY, 4321, 4'hf);
        stream(0, 0);
        clear_monitors();
        stream(330, 470);
        check_labels("play labels");
        if (points_cycles != 0 || reason_cycles != 0 || panel_cycles != 0)
            $fatal(1, "Result block must only appear on end-of-flight screens");
        if (label_cycles < 3*2*16*16/4)
            $fatal(1, "Pad labels were not drawn");

        check_labels_visible(0, "play");
        check_labels_visible(2, "demo");
        check_labels_visible(6, "exit confirmation");
        check_labels_hidden(MENU, "menu");
        check_labels_hidden(7, "Luna 9 memorial");
        check_labels_hidden(8, "Apollo 11 memorial");

        set_snapshot(LANDED, 1437, 0);
        stream(0, 0);
        stream(330, 470);
        check_labels("landed labels");
        check_result(LANDED, 1437, 4'b0000, "landed");
        check_result(GAME_OVER, 0, 4'b0001, "game over off pad");
        check_result(CRASHED, 0, 4'b1001, "crash off pad and tilted");
        check_result(GAME_OVER, 0, 4'b1110, "game over after a hard landing");
        check_result(CRASHED, 0, 4'b1111, "crash with every failure");
        check_result_blanking();

        if ($test$plusargs("capture")) begin
            if ($value$plusargs("scene=%s", scene_path))
                load_scene(scene_path);
            capture_screen(PLAY, 0, 0, "build/result-play.ppm");
            capture_screen(LANDED, 1437, 4'b0000, "build/result-landed.ppm");
            capture_screen(CRASHED, 0, 4'b0010, "build/result-crashed.ppm");
            capture_screen(CRASHED, 0, 4'b1111, "build/result-all-causes.ppm");
            capture_screen(GAME_OVER, 0, 4'b0101, "build/result-game-over.ppm");
        end
        $display("PASS: pad multiplier labels and end-of-flight points/reason block");
        $finish;
    end
endmodule
