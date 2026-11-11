module video_game (
    input wire clk,
    input wire reset_n,
    input wire [9:0] x,
    input wire [9:0] y,
    input wire active,
    input wire hsync,
    input wire vsync,
    input wire [9:0] terrain_height,
    input wire [223:0] snapshot,
    input wire [23:0] pattern_rgb,
    output reg [23:0] rgb,
    output reg active_out,
    output reg hsync_out,
    output reg vsync_out
);
    reg [9:0] x_q, y_q;
    reg active_q, hsync_q, vsync_q;
    wire [9:0] ship_x = snapshot[9:0];
    wire [9:0] ship_y = snapshot[25:16];
    wire [31:0] flags = snapshot[63:32];
    wire [31:0] hud = snapshot[95:64];
    wire [31:0] score = snapshot[127:96];
    wire [11:0] speed_bcd = flags[19:8];
    wire [11:0] altitude_bcd = {snapshot[31:28], hud[31:28], flags[23:20]};
    wire [2:0] heading = {snapshot[15], snapshot[27:26]};
    wire [23:0] speed_color = flags[3:2] >= 2 ? 24'hff4f6d :
                              flags[3:2] == 1 ? 24'hffd451 : 24'h7ef7c0;
    wire [3:0] state = flags[7:4];
    wire [223:0] unused_snapshot_fields = snapshot;
    wire console_menu = state == 9;
    wire [2:0] console_volume_segment = x_q[7:5] - 3'd2;
    wire [2:0] console_volume_level = y_q < 10'd260 ?
                                      flags[18:16] : flags[26:24];
    wire menu = state == 1 || console_menu;
    wire memorial = state == 7 || state == 8;
    wire result_state = state == 3 || state == 4 || state == 5;
    // The landing result rides in the unused bits [15:10] and [31:26] of the pad
    // words: five BCD digits of points earned, then the four failure bits.
    wire [11:0] result_low = {snapshot[159:154], snapshot[143:138]};
    wire [11:0] result_high = {snapshot[191:186], snapshot[175:170]};
    wire [19:0] result_points = {result_high[7:0], result_low};
    wire [3:0] result_cause = result_high[11:8];
    wire [8:0] memorial_address;
    wire [2:0] memorial_row, memorial_column;
    wire memorial_text, photograph_visible;
    wire [1:0] photograph_pixel;
    reg memorial_text_q;
    video_memorial memories (
        .clk(clk), .reset_n(reset_n), .frame_tick(x == 0 && y == 480),
        .state(state), .x(x), .y(y), .text_address(memorial_address),
        .glyph_row(memorial_row), .glyph_column(memorial_column),
        .text_visible(memorial_text), .photograph_pixel(photograph_pixel),
        .photograph_visible(photograph_visible)
    );
    wire [9:0] message_left = state == 3 ? 10'd104 : state == 5 ? 10'd128 : 10'd144;
    reg [9:0] animation_frame;
    reg [7:0] festival_phase;
    reg [1:0] festival_item;
    always @(posedge clk) begin
        if (!reset_n) begin
            animation_frame <= 0;
            festival_phase <= 0;
            festival_item <= 0;
        end else if (x == 0 && y == 480) begin
            animation_frame <= animation_frame + 1'b1;
            if (menu && !console_menu) begin
                if (festival_phase == 179) begin
                    festival_phase <= 0;
                    festival_item <= festival_item + 1'b1;
                end else
                    festival_phase <= festival_phase + 1'b1;
            end else begin
                festival_phase <= 0;
                festival_item <= 0;
            end
        end
    end
    wire [3:0] bob = animation_frame[5] ? ~animation_frame[4:1] : animation_frame[4:1];
    wire [2:0] tilt = animation_frame[8] ? ~animation_frame[7:5] : animation_frame[7:5];
    wire [9:0] center_x = menu ? 10'd432 : ship_x;
    wire [9:0] center_y = menu ? 10'd260 + {6'b0, bob} : ship_y;
    wire signed [10:0] raw_dx = $signed({1'b0, x}) - $signed({1'b0, center_x});
    wire signed [10:0] raw_dy = $signed({1'b0, y}) - $signed({1'b0, center_y});
    wire signed [10:0] local_x = (menu ? (raw_dx >>> 1) : raw_dx) + 11'sd16;
    wire signed [10:0] local_y = (menu ? (raw_dy >>> 1) : raw_dy) + 11'sd16;
    wire [4:0] angle = menu ? {2'b0, tilt} - 5'd3 : snapshot[14:10];
    wire [1:0] ship_pixel;
    wire [3:0] earth_pixel;
    reg ship_visible, earth_visible;
    video_art artwork (
        .clk(clk), .angle(angle), .ship_x(local_x[4:0]), .ship_y(local_y[4:0]),
        .earth_x(x[6:0] - 7'd48), .earth_y(y[6:0] - (menu ? 7'd48 : 7'd112)),
        .ship_pixel(ship_pixel), .earth_pixel(earth_pixel)
    );
    always @(posedge clk) begin
        ship_visible <= local_x >= 0 && local_x < 32 && local_y >= 0 && local_y < 32;
        earth_visible <= x >= 432 && x < 560 &&
                         (menu ? y >= 48 && y < 176 : y >= 112 && y < 240);
    end
    wire [4:0] tile_x = x_q[9:5], tile_y = y_q[9:5];
    wire [7:0] star_hash = {tile_x[2:0], tile_y} ^
                          {tile_y[1:0], tile_x, tile_y[4]} ^
                          {tile_x[0], tile_y[3:0], tile_x[4:2]};
    wire [4:0] star_x = star_hash[4:0];
    wire [4:0] star_y = {star_hash[6:4], star_hash[1:0]} ^ 5'h16;
    wire star = star_hash[7:6] != 0 && x_q[4:0] == star_x && y_q[4:0] == star_y;
    wire twinkle = (animation_frame[6:3] ^ star_hash[3:0]) == 0;
    wire signed [10:0] dx = $signed({1'b0, x_q}) - $signed({1'b0, ship_x});
    wire signed [10:0] dy = $signed({1'b0, y_q}) - $signed({1'b0, ship_y});
    function automatic [5:0] planet_color(input reg [3:0] pixel);
        case (pixel)
            1: planet_color = 6'd4;
            2: planet_color = 6'd5;
            3: planet_color = 6'd6;
            4: planet_color = 6'd7;
            5: planet_color = 6'd8;
            6: planet_color = 6'd9;
            7: planet_color = 6'd10;
            8: planet_color = 6'd11;
            9: planet_color = 6'd12;
            10: planet_color = 6'd13;
            11: planet_color = 6'd14;
            12: planet_color = 6'd15;
            default: planet_color = 6'd0;
        endcase
    endfunction
    function automatic [23:0] palette_color(input reg [5:0] index);
        case (index)
            1: palette_color = 24'hd7f3ff;
            2: palette_color = 24'h829ebc;
            3: palette_color = 24'h435e7c;
            4: palette_color = 24'h63caff;
            5: palette_color = 24'h153457;
            6: palette_color = 24'h081a31;
            7: palette_color = 24'h123b72;
            8: palette_color = 24'h176cb0;
            9: palette_color = 24'h279bd1;
            10: palette_color = 24'h236461;
            11: palette_color = 24'h46917c;
            12: palette_color = 24'h8ab893;
            13: palette_color = 24'h5c829b;
            14: palette_color = 24'ha9cbdc;
            15: palette_color = 24'he7f6ff;
            16: palette_color = 24'h102a38;
            17: palette_color = 24'h7ef7c0;
            18: palette_color = 24'h34d9ff;
            19: palette_color = 24'hffd451;
            20: palette_color = 24'hff4f6d;
            21: palette_color = 24'h34bde8;
            22: palette_color = 24'hffb347;
            23: palette_color = 24'hffe5a0;
            24: palette_color = 24'h0a1e2d;
            25: palette_color = 24'h081724;
            26: palette_color = 24'h286077;
            27: palette_color = 24'h183343;
            28: palette_color = 24'h327283;
            29: palette_color = 24'h050a10;
            30: palette_color = 24'h425564;
            31: palette_color = 24'h92a6ae;
            32: palette_color = 24'he7f3ed;
            33: palette_color = 24'h000000;
            default: palette_color = 24'h020813;
        endcase
    endfunction

    function automatic [6:0] digit(input reg [3:0] value);
        digit = {3'b011, value};
    endfunction
    function automatic [6:0] console_character(input reg [2:0] row,
                                                input reg [4:0] column);
        reg [31:0] title_word;
        case (row)
            0: case (column)
                0: console_character = 7'("L");
                1: console_character = 7'("U");
                2: console_character = 7'("N");
                3: console_character = 7'("A");
                4: console_character = 7'(" ");
                5: console_character = 7'("9");
                6: console_character = 7'("K");
                default: console_character = 7'(" ");
            endcase
            1: begin
                if (flags[3]) begin
                    case (column)
                        0: console_character = 7'("S");
                        1: console_character = 7'("E");
                        2: console_character = 7'("T");
                        3: console_character = 7'("T");
                        4: console_character = 7'("I");
                        5: console_character = 7'("N");
                        6: console_character = 7'("G");
                        7: console_character = 7'("S");
                        default: console_character = 7'(" ");
                    endcase
                end else begin
                    case (column)
                        0: console_character = 7'("B");
                        1: console_character = 7'("I");
                        2: console_character = 7'("N");
                        4: console_character = 7'("G");
                        5: console_character = 7'("A");
                        6: console_character = 7'("M");
                        7: console_character = 7'("E");
                        8: console_character = 7'("S");
                        default: console_character = 7'(" ");
                    endcase
                end
            end
            2, 3, 4: begin
                case (({2'b0, row} - 5'd2) * 5'd2 + {2'b0, column[4:2]})
                    0: title_word = snapshot[31:0];
                    1: title_word = snapshot[95:64];
                    2: title_word = snapshot[127:96];
                    3: title_word = snapshot[159:128];
                    4: title_word = snapshot[191:160];
                    default: title_word = snapshot[223:192];
                endcase
                console_character = column < 8 ?
                                   title_word[(column % 4) * 8 +: 7] : 7'(" ");
            end
            5: begin
                case (flags[15:12])
                    0: begin
                        if (flags[3]) begin
                            case (column)
                                0: console_character = 7'("M");
                                1: console_character = 7'("E");
                                2: console_character = 7'("N");
                                3: console_character = 7'("U");
                                5: console_character = 7'("B");
                                6: console_character = 7'("A");
                                7: console_character = 7'("C");
                                8: console_character = 7'("K");
                                default: console_character = 7'(" ");
                            endcase
                        end else begin
                            case (column)
                                0: console_character = 7'("M");
                                1: console_character = 7'("E");
                                2: console_character = 7'("N");
                                3: console_character = 7'("U");
                                5: console_character = 7'("S");
                                6: console_character = 7'("E");
                                7: console_character = 7'("T");
                                8: console_character = 7'("T");
                                9: console_character = 7'("I");
                                10: console_character = 7'("N");
                                11: console_character = 7'("G");
                                12: console_character = 7'("S");
                                default: console_character = 7'(" ");
                            endcase
                        end
                    end
                    1: case (column)
                        0: console_character = 7'("N");
                        1: console_character = 7'("O");
                        3: console_character = 7'("S");
                        4: console_character = 7'("D");
                        6: console_character = 7'("C");
                        7: console_character = 7'("A");
                        8: console_character = 7'("R");
                        9: console_character = 7'("D");
                        default: console_character = 7'(" ");
                    endcase
                    2: case (column)
                        0: console_character = 7'("N");
                        1: console_character = 7'("O");
                        3: console_character = 7'("G");
                        4: console_character = 7'("A");
                        5: console_character = 7'("M");
                        6: console_character = 7'("E");
                        7: console_character = 7'("S");
                        9: console_character = 7'("F");
                        10: console_character = 7'("O");
                        11: console_character = 7'("U");
                        12: console_character = 7'("N");
                        13: console_character = 7'("D");
                        default: console_character = 7'(" ");
                    endcase
                    3: case (column)
                        0: console_character = 7'("S");
                        1: console_character = 7'("A");
                        2: console_character = 7'("V");
                        3: console_character = 7'("E");
                        5: console_character = 7'("F");
                        6: console_character = 7'("A");
                        7: console_character = 7'("I");
                        8: console_character = 7'("L");
                        9: console_character = 7'("E");
                        10: console_character = 7'("D");
                        default: console_character = 7'(" ");
                    endcase
                    default: case (column)
                        0: console_character = 7'("I");
                        1: console_character = 7'("M");
                        2: console_character = 7'("A");
                        3: console_character = 7'("G");
                        4: console_character = 7'("E");
                        6: console_character = 7'("E");
                        7: console_character = 7'("R");
                        8: console_character = 7'("R");
                        9: console_character = 7'("O");
                        10: console_character = 7'("R");
                        default: console_character = 7'(" ");
                    endcase
                endcase
            end
            6: begin
                if (flags[3]) begin
                    case (column)
                        0: console_character = 7'("U");
                        1: console_character = 7'("P");
                        2: console_character = 7'("/");
                        3: console_character = 7'("D");
                        4: console_character = 7'("O");
                        5: console_character = 7'("W");
                        6: console_character = 7'("N");
                        8: console_character = 7'("A");
                        9: console_character = 7'("D");
                        10: console_character = 7'("J");
                        11: console_character = 7'("U");
                        12: console_character = 7'("S");
                        13: console_character = 7'("T");
                        15: console_character = 7'("A");
                        17: console_character = 7'("S");
                        18: console_character = 7'("E");
                        19: console_character = 7'("L");
                        20: console_character = 7'("E");
                        21: console_character = 7'("C");
                        22: console_character = 7'("T");
                        23: console_character = 7'("M");
                        24: console_character = 7'("E");
                        25: console_character = 7'("N");
                        26: console_character = 7'("U");
                        28: console_character = 7'("B");
                        29: console_character = 7'("A");
                        30: console_character = 7'("C");
                        31: console_character = 7'("K");
                        default: console_character = 7'(" ");
                    endcase
                end else begin
                    case (column)
                        0: console_character = 7'("U");
                        1: console_character = 7'("P");
                        2: console_character = 7'("/");
                        3: console_character = 7'("D");
                        4: console_character = 7'("O");
                        5: console_character = 7'("W");
                        6: console_character = 7'("N");
                        8: console_character = 7'("S");
                        9: console_character = 7'("E");
                        10: console_character = 7'("L");
                        11: console_character = 7'("E");
                        12: console_character = 7'("C");
                        13: console_character = 7'("T");
                        15: console_character = 7'("A");
                        17: console_character = 7'("L");
                        18: console_character = 7'("A");
                        19: console_character = 7'("U");
                        20: console_character = 7'("N");
                        21: console_character = 7'("C");
                        22: console_character = 7'("H");
                        default: console_character = 7'(" ");
                    endcase
                end
            end
            7: case (column)
                0: console_character = 7'("M");
                1: console_character = 7'("U");
                2: console_character = 7'("S");
                3: console_character = 7'("I");
                4: console_character = 7'("C");
                6: console_character = 7'("E");
                7: console_character = 7'("F");
                8: console_character = 7'("F");
                9: console_character = 7'("E");
                10: console_character = 7'("C");
                11: console_character = 7'("T");
                12: console_character = 7'("S");
                default: console_character = 7'(" ");
            endcase
            default: console_character = 7'(" ");
        endcase
    endfunction
    function automatic [6:0] console_title_character(input reg [2:0] row,
                                                       input reg [4:0] column);
        reg [31:0] title_word;
        case (({2'b0, row} - 5'd2) * 5'd2 + {2'b0, column[4:2]})
            0: title_word = snapshot[31:0];
            1: title_word = snapshot[95:64];
            2: title_word = snapshot[127:96];
            3: title_word = snapshot[159:128];
            4: title_word = snapshot[191:160];
            default: title_word = snapshot[223:192];
        endcase
        console_title_character = column < 8 ?
                                  title_word[(column % 4) * 8 +: 7] : 7'(" ");
    endfunction
    wire [6:0] hud_column;
    hud_glyph_column hud_column_select (
        .x(x), .y(y), .menu(state == 1), .column(hud_column)
    );
    wire menu_score = state == 1 && x >= 64 && x < 192 && y >= 248 && y < 264;
    wire [2:0] score_index = menu_score ? x[6:4] - 3'd4 : hud_column[2:0] - 3'd4;
    wire [3:0] score_digit = score[{~score_index, 2'b00} +: 4];
    function automatic [6:0] hud_character(input reg [6:0] column, input reg [3:0] score_value);
        case (column)
            6: hud_character = 7'("L");
            7: hud_character = 7'("V");
            8: hud_character = 7'("L");
            10: hud_character = digit(hud[23:20]);
            11: hud_character = digit(hud[19:16]);
            13: hud_character = 7'("F");
            14: hud_character = 7'("U");
            15: hud_character = 7'("E");
            16: hud_character = 7'("L");
            18: hud_character = digit(hud[15:12]);
            19: hud_character = digit(hud[11:8]);
            20: hud_character = digit(hud[7:4]);
            21: hud_character = digit(hud[3:0]);
            23: hud_character = 7'("L");
            24: hud_character = 7'("I");
            25: hud_character = 7'("F");
            26: hud_character = 7'("E");
            28: hud_character = digit(hud[27:24]);
            30: hud_character = 7'("S");
            31: hud_character = 7'("C");
            32: hud_character = 7'("O");
            33: hud_character = 7'("R");
            34: hud_character = 7'("E");
            36,37,38,39,40,41,42,43: hud_character = digit(score_value);
            default: hud_character = 7'(" ");
        endcase
    endfunction
    function automatic [6:0] flight_character(input reg [5:0] column);
        case (column)
            0: flight_character = 7'("S");
            1: flight_character = 7'("P");
            2,3: flight_character = 7'("E");
            4: flight_character = 7'("D");
            7: flight_character = digit(speed_bcd[11:8]);
            8: flight_character = digit(speed_bcd[7:4]);
            9: flight_character = digit(speed_bcd[3:0]);
            14,35: flight_character = 7'("M");
            15: flight_character = 7'("/");
            16: flight_character = 7'("S");
            23: flight_character = 7'("A");
            24: flight_character = 7'("L");
            25: flight_character = 7'("T");
            28: flight_character = digit(altitude_bcd[11:8]);
            29: flight_character = digit(altitude_bcd[7:4]);
            30: flight_character = digit(altitude_bcd[3:0]);
            43: flight_character = 7'("V");
            44: flight_character = 7'("E");
            45: flight_character = 7'("L");
            default: flight_character = 7'(" ");
        endcase
    endfunction
    // Right-aligned "+NNNNN" in columns 7..12 of the points row, leading zeros dropped.
    function automatic [6:0] points_character(input reg [4:0] column);
        reg [2:0] place;
        reg [7:0] shown;
        place = 3'(5'd12 - column);
        shown = {3'b000, |result_points[19:16], |result_points[19:12],
                 |result_points[19:8], |result_points[19:4], 1'b1};
        if (shown[place])
            points_character = digit(4'(result_points >> {place, 2'b00}));
        else if (place != 0 && shown[place - 3'd1])
            points_character = 7'("+");
        else
            points_character = 7'(" ");
    endfunction
    reg [6:0] character;
    reg [2:0] glyph_row, glyph_column;
    reg menu_text;
    reg [2:0] menu_line;
    reg [4:0] menu_column;
    reg [6:0] character_q;
    reg [2:0] glyph_row_q, glyph_column_q, menu_line_q;
    reg menu_text_q;
    reg dashboard_text, dashboard_text_q, message_text, message_text_q;
    reg festival_text, festival_text_q;
    reg points_text, points_text_q, reason_text, reason_text_q;
    reg [6:0] captions [0:2047];
    initial $readmemh("build/memorial-text.hex", captions);
    reg [10:0] text_address;
    reg static_text, static_text_q;
    reg [6:0] text_character_q;
    reg [9:0] text_x, text_y;
    reg [1:0] festival_line;
    wire [7:0] festival_scroll = festival_phase >= 132 ? festival_phase - 8'd131 : 0;
    reg [29:0] label_center, pad_top;
    reg [2:0] pad_valid;
    always @* begin
        for (integer index = 0; index < 3; index = index + 1) begin
            label_center[index*10 +: 10] = 10'((11'(snapshot[128 + index*32 +: 10]) +
                                                11'(snapshot[144 + index*32 +: 10])) >> 1);
            pad_valid[index] = snapshot[144 + index*32 +: 10] > snapshot[128 + index*32 +: 10];
        end
    end
    always @(posedge clk) begin
        for (integer index = 0; index < 3; index = index + 1) begin
            if (!reset_n || !pad_valid[index])
                pad_top[index*10 +: 10] <= 10'd600;
            else if (active_q && x_q == label_center[index*10 +: 10])
                pad_top[index*10 +: 10] <= terrain_height + 10'd8;
        end
    end
    reg [9:0] label_dx, label_dy;
    reg label_text, label_text_q;
    reg [1:0] label_index, label_index_q;
    // Result rows hold the failed checks packed from the first row down.
    reg [11:0] reason_row_q;
    wire [11:0] next_reason_rows;
    reason_rows reason_decoder (.cause(result_cause), .rows(next_reason_rows));
    reg [1:0] reason_row;
    reg reason_band;
    reg [2:0] reason;
    wire [3:0] reason_used = {~reason_row_q[11], ~reason_row_q[8],
                              ~reason_row_q[5], ~reason_row_q[2]};
    wire [9:0] panel_bottom = reason_used[3] ? 10'd250 : reason_used[2] ? 10'd232 :
                              reason_used[1] ? 10'd208 : reason_used[0] ? 10'd184 : 10'd160;
    wire panel_hit = active && flags[0] && result_state && x >= 64 && x < 576 &&
                     y >= 98 && y < panel_bottom;
    wire panel_edge = panel_hit && (x == 64 || x == 575 || y == 98 || y == panel_bottom - 10'd1);
    reg panel_q, panel_qq, panel_edge_q, panel_edge_qq;
    wire glyph;
    game_font_rom hud_font (
        .clk(clk), .dashboard(dashboard_text_q),
        .character(dashboard_text_q || !static_text_q ? character_q : text_character_q),
        .row(glyph_row_q), .column(glyph_column_q), .pixel(glyph)
    );
    always @* begin
        character = hud_character(hud_column, score_digit);
        glyph_row = y[2:0];
        glyph_column = x[2:0];
        menu_text = 0;
        menu_line = 0;
        menu_column = 0;
        dashboard_text = 0; message_text = 0; festival_text = 0;
        points_text = 0; reason_text = 0; label_text = 0; label_index = 0;
        text_x = 0; text_y = 0; festival_line = 0;
        text_address = 0; static_text = 0;
        reason_band = 1; reason_row = 0;
        if (y >= 160 && y < 176) reason_row = 0;
        else if (y >= 184 && y < 200) reason_row = 1;
        else if (y >= 208 && y < 224) reason_row = 2;
        else if (y >= 232 && y < 248) reason_row = 3;
        else reason_band = 0;
        case (reason_row)
            0: reason = reason_row_q[2:0];
            1: reason = reason_row_q[5:3];
            2: reason = reason_row_q[8:6];
            default: reason = reason_row_q[11:9];
        endcase
        if (!menu && y < 60) begin
            dashboard_text = (y >= 8 && y < 16) || (y >= 24 && y < 40);
            glyph_column = 0;
            if (x >= 16 && x < 96) begin
                dashboard_text = dashboard_text && (y < 24 ? x < 40 : x < 48);
                glyph_column = y < 24 ? x[2:0] : x[3:1];
            end else if (x >= 112 && x < 256) begin
                dashboard_text = dashboard_text && (y < 24 ? x < 144 : x < 176);
                glyph_column = y < 24 ? x[2:0] : x[3:1];
            end else if (x >= 272 && x < 352) begin
                if (y >= 24) character = digit(hud[27:24]);
                dashboard_text = dashboard_text && (y < 24 ? x < 304 : x < 288);
                glyph_column = y < 24 ? x[2:0] : x[3:1];
            end else if (x >= 368 && x < 624) begin
                dashboard_text = dashboard_text && (y < 24 ? x < 408 : x < 496);
                glyph_column = y < 24 ? x[2:0] : x[3:1];
            end else dashboard_text = 0;
            glyph_row = y < 24 ? y[2:0] : y[3:1] - 3'd4;
        end else if (!menu && y >= 64 && y < 88 && x >= 16 && x < 384) begin
            dashboard_text = y >= 72;
            character = flight_character(x[8:3] - 6'd2);
            glyph_row = y[3:1] - 3'd4;
            glyph_column = x[2:0];
        end else if (!menu && state != 0 && x >= message_left &&
                     x < 10'd640 - message_left && y[9:4] == (result_state ? 6'd7 : 6'd14)) begin
            message_text = 1;
            text_x = x - message_left;
            static_text = 1;
            text_address = {1'b0, 5'd25 + {1'b0, state}, text_x[8:4]};
            glyph_row = y[3:1]; glyph_column = text_x[3:1];
        end else if (result_state && y >= 136 && y < 152 && x >= 216 && x < 424) begin
            points_text = 1;
            text_x = x - 216;
            static_text = text_x[8:4] < 7;
            text_address = {6'd36, text_x[8:4]};
            character = points_character(text_x[8:4]);
            glyph_row = y[3:1] - 3'd4; glyph_column = text_x[3:1];
        end else if (result_state && reason_band && x >= 64 && x < 576 && !reason[2]) begin
            reason_text = 1;
            text_x = x - 64;
            static_text = 1;
            text_address = {4'b1000, reason[1:0], text_x[8:4]};
            glyph_row = reason_row[0] ? y[3:1] - 3'd4 : y[3:1];
            glyph_column = text_x[3:1];
        end
        if (console_menu) begin
            if (x >= 10'd64 && x < 10'd320 && y >= 10'd80 && y < 10'd112) begin
                menu_text = 1'b1; menu_line = 3'd0;
                menu_column = {1'b0, x[8:5]} - 5'd2;
                static_text = 1'b1;
                text_address = {6'd37, menu_column};
                glyph_row = y[4:2] - 3'd4; glyph_column = x[4:2];
            end else if (x >= 10'd96 && x < 10'd320 &&
                         y >= 10'd160 && y < 10'd176) begin
                menu_text = 1'b1; menu_line = 3'd1;
                menu_column = x[8:4] - 5'd6;
                static_text = 1'b1;
                text_address = {flags[3] ? 6'd39 : 6'd38, menu_column};
                glyph_row = y[3:1]; glyph_column = x[3:1];
            end else if (!flags[3] && x >= 10'd128 && x < 10'd256 &&
                         ((y >= 10'd224 && y < 10'd240) ||
                          (y >= 10'd272 && y < 10'd288) ||
                          (y >= 10'd320 && y < 10'd336))) begin
                menu_line = y < 10'd240 ? 3'd2 : y < 10'd288 ? 3'd3 : 3'd4;
                menu_column = {1'b0, x[7:4]} - 5'd8;
                menu_text = 1'b1;
                character = console_title_character(menu_line, menu_column);
                glyph_row = y[3:1]; glyph_column = x[3:1];
            end else if (!flags[3] && flags[15:12] != 0 &&
                         x >= 10'd192 && x < 10'd448 &&
                         y >= 10'd256 && y < 10'd272) begin
                menu_text = 1'b1; menu_line = 3'd5;
                menu_column = x[8:4] - 5'd12;
                static_text = 1'b1;
                case (flags[15:12])
                    1: text_address = {6'd41, menu_column};
                    2: text_address = {6'd42, menu_column};
                    3: text_address = {6'd43, menu_column};
                    default: text_address = {6'd44, menu_column};
                endcase
                glyph_row = y[3:1]; glyph_column = x[3:1];
            end else if (flags[3] && x >= 10'd144 && x < 10'd272 &&
                         ((y >= 10'd216 && y < 10'd232) ||
                          (y >= 10'd280 && y < 10'd296))) begin
                menu_text = 1'b1; menu_line = 3'd7;
                menu_column = {1'b0, x[7:4]} - 5'd9;
                if (y >= 10'd280)
                    menu_column = menu_column + 5'd6;
                static_text = 1'b1;
                text_address = {6'd47, menu_column};
                glyph_row = y[3:1]; glyph_column = x[3:1];
            end else if (x >= 10'd64 && x < 10'd576 &&
                         y >= 10'd400 && y < 10'd416) begin
                menu_text = 1'b1; menu_line = 3'd6;
                menu_column = x[8:4] - 5'd4;
                static_text = 1'b1;
                text_address = {flags[3] ? 6'd46 : 6'd45, menu_column};
                glyph_row = y[3:1]; glyph_column = x[3:1];
            end else if (x >= 10'd64 && x < 10'd576 &&
                         y >= 10'd424 && y < 10'd440) begin
                menu_text = 1'b1; menu_line = 3'd6;
                menu_column = x[8:4] - 5'd4;
                static_text = 1'b1;
                text_address = {flags[3] ? 6'd40 : 6'd48, menu_column};
                glyph_row = y[3:1]; glyph_column = x[3:1];
            end
        end
        if (menu && !console_menu) begin
            if (x >= 64 && x < 320 && y >= 92 && y < 124) begin
                menu_text = 1; menu_line = 0;
                menu_column = {2'b0, x[7:5]} - 5'd2;
                glyph_row = y[4:2] - 3'd7; glyph_column = x[4:2];
            end else if (x >= 64 && x < 320 && y >= 132 && y < 164) begin
                menu_text = 1; menu_line = 1;
                menu_column = {2'b0, x[7:5]} - 5'd2;
                glyph_row = y[4:2] - 3'd1; glyph_column = x[4:2];
            end else if (x >= 64 && x < 320 && y >= 180 && y < 188) begin
                menu_text = 1; menu_line = 2;
                menu_column = x[7:3] - 5'd8;
                glyph_row = y[2:0] - 3'd4;
            end else if (x >= 64 && x < 320 && y >= 224 && y < 240) begin
                menu_text = 1; menu_line = 3;
                menu_column = {1'b0, x[7:4]} - 5'd4;
                glyph_row = y[3:1]; glyph_column = x[3:1];
            end else if (x >= 64 && x < 192 && y >= 248 && y < 264) begin
                menu_text = 1; menu_line = 4;
                menu_column = {1'b0, x[7:4]} - 5'd4;
                glyph_row = y[3:1] - 3'd4; glyph_column = x[3:1];
            end else if (x >= 64 && x < 400 && y >= 304 && y < 320) begin
                menu_text = 1; menu_line = 5;
                menu_column = x[8:4] - 5'd4;
                glyph_row = y[3:1]; glyph_column = x[3:1];
            end else if (x >= 64 && x < 320 && y >= 336 && y < 344) begin
                menu_text = 1; menu_line = 6;
                menu_column = x[7:3] - 5'd8;
            end
            if (menu_line == 4) begin
                character = digit(score_digit);
            end else begin
                static_text = 1;
                text_address = {3'b010, menu_line, menu_column};
            end
            if (y >= 432 && y < 480) begin
                text_y = y + {2'b0, festival_scroll} - 10'd448;
                festival_line = festival_item;
                if (text_y >= 48) begin
                    text_y = text_y - 10'd48;
                    festival_line = festival_item + 1'b1;
                end
                case (festival_line)
                    0: text_x = x - 10'd96;
                    1: text_x = x - 10'd104;
                    2: text_x = x - 10'd248;
                    default: text_x = x - 10'd80;
                endcase
                festival_text = text_y < 16 &&
                    text_x < (festival_line == 2 ? 144 : festival_line == 1 ? 432 :
                              festival_line == 3 ? 480 : 448);
                static_text = 1;
                text_address = {1'b0, festival_line == 3 ? 5'd23 : 5'd24 + {3'b0, festival_line},
                                text_x[8:4]};
                glyph_row = text_y[3:1]; glyph_column = text_x[3:1];
            end
        end
        if (memorial) begin
            character = 32;
            static_text = 1; text_address = {2'b00, memorial_address};
            glyph_row = memorial_row; glyph_column = memorial_column;
            dashboard_text = 0; message_text = 0; menu_text = 0; festival_text = 0;
        end
        if (!menu && !memorial) begin
            for (integer index = 2; index >= 0; index = index - 1) begin
                label_dx = x - (label_center[index*10 +: 10] - 10'd16);
                label_dy = y - pad_top[index*10 +: 10];
                if (label_dx < 10'd32 && label_dy < 10'd16) begin
                    label_text = 1; label_index = 2'(index);
                    static_text = 0;
                    character = !label_dx[4] ? 7'("X") : index == 0 ? 7'("1") :
                                index == 1 ? 7'("2") : 7'("4");
                    glyph_row = label_dy[3:1]; glyph_column = label_dx[3:1];
                end
            end
        end
    end
    reg [5:0] color_index;
    reg [23:0] color;
    reg [23:0] scene_q, text_color, text_color_q;
    reg text_enabled, text_enabled_q;
    reg active_qq, hsync_qq, vsync_qq;
    reg [19:0] pad;
    wire arrow_visible;
    velocity_arrow arrow (
        .x(x_q), .y(y_q), .heading(heading),
        .stopped(speed_bcd == 0), .visible(arrow_visible)
    );
    always @* begin
        color_index = 6'd0;
        pad = 0;
        if (star)
            color_index = twinkle ? 6'd1 : star_hash[5] ? 6'd2 : 6'd3;
        if (earth_visible && earth_pixel != 0)
            color_index = planet_color(earth_pixel);
        if (y_q >= terrain_height)
            color_index = 6'd16;
        if (y_q == terrain_height || y_q + 10'd1 == terrain_height)
            color_index = 6'd17;
        for (integer index = 0; index < 3; index = index + 1) begin
            pad = {snapshot[144 + index*32 +: 10], snapshot[128 + index*32 +: 10]};
            if (x_q >= pad[9:0] && x_q <= pad[19:10] &&
                y_q + 10'd2 >= terrain_height && y_q <= terrain_height) begin
                case (index)
                    0: color_index = 6'd17;
                    1: color_index = 6'd18;
                    default: color_index = 6'd19;
                endcase
            end
        end
        if (ship_visible) begin
            if (ship_pixel == 1)
                color_index = state == 4 ? 6'd20 : 6'd1;
            if (ship_pixel == 2)
                color_index = 6'd21;
            if (ship_pixel == 3 && (menu ? animation_frame[3:2] != 0 : flags[1]))
                color_index = animation_frame[2] ? 6'd22 : 6'd23;
        end
        if (state == 4 && dx >= -12 && dx <= 12 && dy >= -12 && dy <= 12 &&
            (dx == dy || dx == -dy))
            color_index = 6'd20;
        if (!menu && y_q < 96) begin
            color_index = y_q[2] ? 6'd24 : 6'd25;
            if (y_q == 0 || y_q == 58 || y_q == 94 || x_q == 0 || x_q == 639 ||
                (y_q < 60 && (x_q == 100 || x_q == 260 || x_q == 356)))
                color_index = 6'd26;
            if (y_q >= 48 && y_q < 52 && x_q >= 112 && x_q < 237) begin
                color_index = x_q < 10'd112 + {2'b0, flags[31:24]} +
                                        {4'b0, flags[31:26]} ?
                              (flags[31:24] < 20 ? 6'd20 : 6'd17) : 6'd27;
                if (x_q[3:0] == 0) color_index = 6'd25;
            end
            if (y_q >= 64 && arrow_visible)
                color_index = flags[3:2] >= 2 ? 6'd20 :
                              flags[3:2] == 1 ? 6'd19 : 6'd17;
        end
        if (state == 1) begin
            if (x_q >= 64 && x_q < 272 && y_q >= 207 && y_q < 209)
                color_index = 6'd28;
        end
        if (console_menu) begin
            if (flags[3] && x_q >= 10'd320 && x_q < 10'd544 &&
                x_q[4:0] < 5'd24 &&
                ((y_q >= 10'd216 && y_q < 10'd240) ||
                 (y_q >= 10'd280 && y_q < 10'd304))) begin
                color_index = console_volume_segment < console_volume_level ?
                              6'd17 : 6'd27;
            end
        end
        if (memorial) begin
            color_index = 6'd0;
            if (photograph_visible) begin
                case (photograph_pixel)
                    0: color_index = 6'd29;
                    1: color_index = 6'd30;
                    2: color_index = 6'd31;
                    3: color_index = 6'd32;
                endcase
            end
            if (x_q >= 62 && x_q < 578 && (y_q == 94 || y_q == 353))
                color_index = 6'd28;
        end
        if (!active_q)
            color_index = 6'd33;
        color = palette_color(color_index);
    end
    always @* begin
        text_enabled = dashboard_text_q || message_text_q || menu_text_q ||
                       festival_text_q || memorial_text_q || points_text_q ||
                       reason_text_q || label_text_q;
        text_color = 24'hffffff;
        if (dashboard_text_q) begin
            text_color = y_q < 24 ? 24'h75a5b8 : x_q < 272 && x_q >= 112 ?
                         24'hffd451 : 24'hc4f9ef;
            if (y_q >= 64)
                text_color = x_q >= 72 && x_q < 96 ? speed_color : 24'hc4f9ef;
        end
        if (message_text_q && state == 4)
            text_color = 24'hff728c;
        if (points_text_q)
            text_color = x_q >= 328 ? 24'hffd451 : 24'hc4f9ef;
        if (reason_text_q)
            text_color = 24'hff728c;
        if (label_text_q) begin
            case (label_index_q)
                0: text_color = 24'h7ef7c0;
                1: text_color = 24'h34d9ff;
                default: text_color = 24'hffd451;
            endcase
        end
        if (menu_text_q) begin
            if (console_menu) begin
                case (menu_line_q)
                    0: text_color = 24'hffd451;
                    1: text_color = 24'h34d9ff;
                    2,3,4: text_color = menu_line_q - 3'd2 ==
                                         {1'b0, flags[2:1]} ?
                                         24'h7ef7c0 : 24'hd7f3ff;
                    5: text_color = 24'hff728c;
                    6: text_color = 24'h90bdcb;
                    7: text_color = menu_line_q - 3'd7 ==
                                         {1'b0, flags[2:1]} ?
                                         24'hffd451 : 24'hd7f3ff;
                    default: text_color = 24'hffffff;
                endcase
            end else begin
                case (menu_line_q)
                    0: text_color = 24'hd7f3ff;
                    1: text_color = 24'h7ef7c0;
                    3, 7: text_color = 24'h8aacc2;
                    4: text_color = 24'hffd451;
                    5: text_color = animation_frame[5] ? 24'h7ef7c0 : 24'hc0f7df;
                    default: text_color = 24'h90bdcb;
                endcase
            end
        end
        if (festival_text_q) text_color = 24'h9ae6ec;
        if (memorial_text_q) text_color = y_q < 96 ? 24'hffd451 : 24'hc4f9ef;
    end
    always @(posedge clk) begin
        if (!reset_n) begin
            x_q <= 0; y_q <= 0;
            active_q <= 0; hsync_q <= 1; vsync_q <= 1;
            rgb <= 0; active_out <= 0; hsync_out <= 1; vsync_out <= 1;
            character_q <= 0; glyph_row_q <= 0; glyph_column_q <= 0;
            menu_line_q <= 0; menu_text_q <= 0;
            dashboard_text_q <= 0; message_text_q <= 0; festival_text_q <= 0;
            memorial_text_q <= 0;
            points_text_q <= 0; reason_text_q <= 0; label_text_q <= 0; label_index_q <= 0;
            reason_row_q <= 12'b100_100_100_100;
            panel_q <= 0; panel_qq <= 0; panel_edge_q <= 0; panel_edge_qq <= 0;
            static_text_q <= 0; text_character_q <= 0;
            scene_q <= 0; text_color_q <= 0; text_enabled_q <= 0;
            active_qq <= 0; hsync_qq <= 1; vsync_qq <= 1;
        end else begin
            x_q <= x; y_q <= y;
            character_q <= character;
            glyph_row_q <= glyph_row; glyph_column_q <= glyph_column;
            menu_line_q <= menu_line; menu_text_q <= menu_text;
            dashboard_text_q <= dashboard_text; message_text_q <= message_text;
            festival_text_q <= festival_text;
            memorial_text_q <= memorial_text;
            points_text_q <= points_text; reason_text_q <= reason_text;
            label_text_q <= label_text; label_index_q <= label_index;
            reason_row_q <= next_reason_rows;
            panel_q <= panel_hit; panel_qq <= panel_q;
            panel_edge_q <= panel_edge; panel_edge_qq <= panel_edge_q;
            static_text_q <= static_text;
            text_character_q <= captions[text_address];
            active_q <= active; hsync_q <= hsync; vsync_q <= vsync;
            scene_q <= flags[0] ? color : pattern_rgb;
            text_color_q <= text_color;
            text_enabled_q <= text_enabled && active_q && flags[0];
            active_qq <= active_q; hsync_qq <= hsync_q; vsync_qq <= vsync_q;
            rgb <= text_enabled_q && glyph ? text_color_q :
                   panel_edge_qq ? 24'h286077 :
                   panel_qq ? (scene_q >> 2) & 24'h3f3f3f : scene_q;
            active_out <= active_qq; hsync_out <= hsync_qq; vsync_out <= vsync_qq;
        end
    end
endmodule
