`timescale 1ns/1ps
module tb_video_art;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg [9:0] x = 0, y = 0;
    reg active = 1, hsync = 1, vsync = 1;
    reg [9:0] terrain_height = 400;
    reg [223:0] snapshot = 0;
    reg [23:0] pattern_rgb = 0;
    wire [23:0] rgb;
    wire active_out, hsync_out, vsync_out;
    video_game dut (.*);
    integer first_signature, second_signature;
    integer stars = 0, earth_pixels = 0;
    integer output_file;
    reg [23:0] reference_line [0:639];
    reg [23:0] transparent_background;
    task automatic advance_frames(input integer count);
        for (integer frame = 0; frame < count; frame = frame + 1) begin
            @(negedge clk); x = 0; y = 480;
            @(negedge clk); x = 1;
        end
    endtask
    task automatic sample(input integer sx, input integer sy);
        @(negedge clk); x = 10'(sx); y = 10'(sy);
        repeat (3) @(posedge clk);
        #1;
        if (!active_out || !hsync_out || !vsync_out)
            $fatal(1, "Artwork controls misaligned");
    endtask
    task automatic capture(input reg [255:0] filename);
        output_file = $fopen(filename, "wb");
        if (!output_file) $fatal(1, "Cannot open renderer capture");
        $fwrite(output_file, "P6\n640 480\n255\n");
        for (integer row = 0; row < 480; row = row + 1) begin
            for (integer column = 0; column < 640; column = column + 1) begin
                sample(column, row);
                $fwrite(output_file, "%c%c%c", rgb[23:16], rgb[15:8], rgb[7:0]);
            end
        end
        $fclose(output_file);
    endtask
    task automatic menu_signature(output integer signature);
        signature = 0;
        for (integer row = 224; row < 312; row = row + 1) begin
            for (integer column = 396; column < 468; column = column + 1) begin
                sample(column, row);
                if (rgb == 24'hd7f3ff || rgb == 24'h34bde8)
                    signature = signature + row*640 + column;
            end
        end
    endtask
    task automatic streaming_line(input integer row);
        for (integer column = 0; column < 640; column = column + 1) begin
            sample(column, row);
            reference_line[column] = rgb;
        end
        for (integer column = 0; column <= 641; column = column + 1) begin
            @(negedge clk); x = 10'(column); y = 10'(row);
            @(posedge clk); #1;
            if (column > 1 && rgb !== reference_line[column-2])
                $fatal(1, "Artwork/text pipeline shifted at row=%0d column=%0d", row, column-2);
        end
    endtask
    task automatic check_dashboard_geometry;
        integer offset;
        reg expected_text;
        reg [2:0] expected_column;
        reg [31:0] score_example;
        begin
            for (integer py = 0; py < 60; py = py + 1)
                for (integer px = 0; px < 640; px = px + 1) begin
                    x = 10'(px); y = 10'(py);
                    expected_text = (py >= 8 && py < 16) || (py >= 24 && py < 40);
                    offset = 0;
                    if (px >= 16 && px < 96) begin
                        offset = px - 16;
                        expected_text = expected_text && (py < 24 ? offset < 24 : offset < 32);
                    end else if (px >= 112 && px < 256) begin
                        offset = px - 112;
                        expected_text = expected_text && (py < 24 ? offset < 32 : offset < 64);
                    end else if (px >= 272 && px < 352) begin
                        offset = px - 272;
                        expected_text = expected_text && (py < 24 ? offset < 32 : offset < 16);
                    end else if (px >= 368 && px < 624) begin
                        offset = px - 368;
                        expected_text = expected_text && (py < 24 ? offset < 40 : offset < 128);
                    end else expected_text = 0;
                    expected_column = py < 24 ? 3'(offset) : 3'(offset >> 1);
                    #1;
                    if (dut.dashboard_text !== expected_text ||
                        dut.glyph_column !== expected_column)
                        $fatal(1, "Dashboard geometry mismatch at %0d,%0d", px, py);
                end
            score_example = 32'h89abcdef;
            snapshot[127:96] = score_example;
            for (integer index = 0; index < 8; index = index + 1) begin
                y = 24; x = 10'(368 + index * 16); #1;
                if (dut.character !== 7'(7'h30 + 4'(score_example >> ((7-index)*4))))
                    $fatal(1, "HUD score digit mismatch at %0d", index);
                snapshot[39:36] = 1;
                y = 248; x = 10'(64 + index * 16); #1;
                if (dut.character !== 7'(7'h30 + 4'(score_example >> ((7-index)*4))))
                    $fatal(1, "Menu score digit mismatch at %0d", index);
                snapshot[39:36] = 0;
            end
            snapshot[127:96] = 32'h00012345;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk); reset_n = 1;
        snapshot[32] = 1;
        snapshot[9:0] = 320; snapshot[25:16] = 240;
        snapshot[63:56] = 80;
        snapshot[95:64] = 32'h03111200;
        snapshot[127:96] = 32'h00012345;
        for (integer pad = 0; pad < 3; pad = pad + 1)
            snapshot[128 + pad*32 +: 32] = 32'h03e803e8;
        check_dashboard_geometry();
        sample(320, 233);
        if (rgb !== 24'hd7f3ff) $fatal(1, "Upright hull nose missing");
        sample(327, 240);
        if (rgb === 24'hd7f3ff) $fatal(1, "Upright hull extends outside body");
        snapshot[14:10] = 8; // Quarter turn must rotate the hull, not a separate marker.
        sample(327, 240);
        if (rgb !== 24'hd7f3ff) $fatal(1, "Rotated hull nose missing");
        sample(320, 233);
        if (rgb === 24'hd7f3ff) $fatal(1, "Hull remained upright after rotation");
        snapshot[33] = 1;
        sample(307, 240);
        if (rgb !== 24'hffe5a0) $fatal(1, "Thrust flame did not rotate with ship");
        snapshot[33] = 0;
        sample(307, 240);
        if (rgb === 24'hffe5a0) $fatal(1, "Flame visible without thrust");
        for (integer row = 32; row < 240; row = row + 1) begin
            for (integer column = 0; column < 640; column = column + 1) begin
                sample(column, row);
                if (rgb == 24'h829ebc || rgb == 24'h435e7c || rgb == 24'hd7f3ff)
                    stars = stars + 1;
                if (rgb == 24'h279bd1 || rgb == 24'h46917c || rgb == 24'he7f6ff)
                    earth_pixels = earth_pixels + 1;
            end
        end
        if (stars < 60 || earth_pixels < 1000)
            $fatal(1, "Missing star field/Earth: stars=%0d Earth=%0d", stars, earth_pixels);
        streaming_line(8);
        streaming_line(76);
        streaming_line(100);
        streaming_line(240);
        snapshot[51:40] = 12'h045;
        snapshot[55:52] = 4'h3;
        snapshot[95:92] = 4'h2;
        snapshot[31:28] = 4'h1;
        #1;
        if (dut.flight_character(28) != "1" || dut.flight_character(29) != "2" ||
            dut.flight_character(30) != "3")
            $fatal(1, "Altitude digits must decode all three packed BCD fields");
        for (integer risk = 0; risk < 3; risk = risk + 1) begin
            snapshot[35:34] = 2'(risk);
            sample(76, 76);
            if (dut.text_color_q !== (risk == 0 ? 24'h7ef7c0 :
                                    risk == 1 ? 24'hffd451 : 24'hff4f6d))
                $fatal(1, "Speed warning text color mismatch");
            sample(448, 68);
            if (rgb !== (risk == 0 ? 24'h7ef7c0 :
                        risk == 1 ? 24'hffd451 : 24'hff4f6d))
                $fatal(1, "Velocity arrow warning color mismatch");
        end
        snapshot[35:34] = 0;
        for (integer direction = 0; direction < 8; direction = direction + 1) begin
            snapshot[15] = 1'(direction >> 2);
            snapshot[27:26] = 2'(direction);
            case (direction)
                0: sample(448,68);
                1: sample(453,73);
                2: sample(458,78);
                3: sample(453,83);
                4: sample(448,88);
                5: sample(443,83);
                6: sample(438,78);
                7: sample(443,73);
            endcase
            if (rgb !== 24'h7ef7c0) $fatal(1, "Velocity compass tip mismatch");
        end
        snapshot[51:40] = 0;
        sample(448,78);
        if (rgb !== 24'h7ef7c0) $fatal(1, "Stationary ship needs a center dot");
        sample(448,68);
        if (rgb === 24'h7ef7c0) $fatal(1, "Stationary ship must not have a direction arrow");
        snapshot[15] = 0; snapshot[27:26] = 0;
        sample(200, 220); transparent_background = rgb;
        snapshot[39:36] = 2;
        sample(200, 220);
        if (rgb !== transparent_background) $fatal(1, "Message background is not transparent");
        snapshot[39:36] = 0;
        sample(8, 8);
        if (dut.dashboard_text_q) $fatal(1, "Old LUNA9 HUD branding remains");
        snapshot[39:36] = 1;
        streaming_line(96);
        streaming_line(132);
        streaming_line(180);
        streaming_line(224);
        streaming_line(248);
        streaming_line(304);
        streaming_line(448);
        streaming_line(450);
        if (dut.captions[23*32] != "E" || dut.captions[23*32+15] != "j" ||
            dut.captions[23*32+23] != "@")
            $fatal(1, "Creator signature mismatch");
        if (dut.captions[24*32] != "R" || dut.captions[24*32+27] != "6" ||
            dut.captions[25*32] != "C" || dut.captions[26*32] != "C")
            $fatal(1, "Festival text missing");
        advance_frames(132);
        sample(104, 448);
        sample(526, 448);
        if (!dut.festival_text_q) $fatal(1, "Festival year is clipped");
        if (dut.festival_scroll != 1) $fatal(1, "Vertical scroll must advance one pixel per frame");
        advance_frames(1);
        sample(104, 448);
        if (dut.festival_scroll != 2) $fatal(1, "Vertical scroll is not smooth");
        advance_frames(47);
        sample(104, 448);
        if (dut.festival_item != 1 || dut.festival_scroll != 0)
            $fatal(1, "Festival transition must settle on next caption");
        advance_frames(180);
        sample(248, 448);
        if (dut.festival_item != 2) $fatal(1, "Cambridge caption missing");
        advance_frames(180);
        sample(104, 448);
        if (dut.festival_item != 3) $fatal(1, "Creator/contact caption missing");
        advance_frames(180);
        sample(104, 448);
        if (dut.festival_item != 0) $fatal(1, "Festival captions must loop");
        menu_signature(first_signature);
        for (integer frame = 0; frame < 16; frame = frame + 1) begin
            sample(0, 480);
            sample(1, 480);
        end
        menu_signature(second_signature);
        if (first_signature == second_signature) $fatal(1, "Menu lander animation is static");
        snapshot[39:36] = 7;
        advance_frames(1);
        streaming_line(40);
        streaming_line(180);
        streaming_line(390);
        advance_frames(240);
        if (dut.memories.phase != 240) $fatal(1, "Memorial pause must last four seconds");
        advance_frames(1);
        if (dut.memories.phase != 241) $fatal(1, "Memorial scroll must move once per frame");
        advance_frames(63);
        if (dut.memories.caption != 1) $fatal(1, "Luna landing must become FAX caption");
        snapshot[39:36] = 8;
        advance_frames(1);
        advance_frames(304);
        if (dut.memories.caption != 1) $fatal(1, "Apollo humans must become Eagle caption");
        advance_frames(304);
        if (dut.memories.caption != 2) $fatal(1, "Apollo Eagle must become Armstrong quote");
        snapshot[39:36] = 1;
        if ($test$plusargs("telemetrycapture")) begin
            advance_frames(1);
            capture("build/telemetry-menu.ppm");
            advance_frames(540);
            capture("build/telemetry-contact.ppm");
            snapshot[39:36] = 0;
            snapshot[51:40] = 12'h045; snapshot[35:34] = 1;
            snapshot[27:26] = 3; snapshot[15] = 0;
            snapshot[14:10] = 4;
            capture("build/telemetry-flight.ppm");
        end
        if ($test$plusargs("capture")) begin
            capture("build/menu.ppm");
            advance_frames(156);
            capture("build/menu-scroll.ppm");
            advance_frames(24);
            capture("build/menu-centre.ppm");
            advance_frames(180);
            capture("build/menu-cambridge.ppm");
            snapshot[39:36] = 0;
            snapshot[51:40] = 12'h045;
            snapshot[35:34] = 1;
            snapshot[27:26] = 3;
            snapshot[14:10] = 0; snapshot[33] = 1;
            capture("build/flight-upright.ppm");
            snapshot[14:10] = 4;
            capture("build/flight-rotated.ppm");
            snapshot[39:36] = 2;
            capture("build/demo-message.ppm");
            snapshot[39:36] = 7;
            advance_frames(1);
            capture("build/luna9-memorial.ppm");
            advance_frames(272);
            capture("build/luna9-scroll.ppm");
            advance_frames(32);
            capture("build/luna9-fax.ppm");
            snapshot[39:36] = 8;
            advance_frames(1);
            capture("build/apollo11-memorial.ppm");
            advance_frames(304);
            capture("build/apollo11-eagle.ppm");
            advance_frames(304);
            capture("build/apollo11-step.ppm");
        end
        $display("PASS: whole hull and flame rotate, populated stars, Earth, animated menu");
        $finish;
    end
endmodule
