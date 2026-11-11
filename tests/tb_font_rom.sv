`timescale 1ns/1ps
module tb_font_rom;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [6:0] character = 7'h7f;
    reg [2:0] row = 0, column = 0;
    reg dashboard_mode = 0;
    wire normal, normal_registered, game_glyph;
    reg [7:0] expected_font [0:767];
    reg [34:0] expected_instrument;
    reg expected_normal, expected_dashboard;

    font_rom normal_font (
        .clk(clk), .character(character), .row(row), .column(column), .pixel(normal)
    );
    font_rom #(.REGISTERED(1)) registered_font (
        .clk(clk), .character(character), .row(row), .column(column),
        .pixel(normal_registered)
    );
    game_font_rom game_font (
        .clk(clk), .dashboard(dashboard_mode), .character(character),
        .row(row), .column(column), .pixel(game_glyph)
    );

    function automatic [34:0] instrument_glyph(input reg [6:0] ch);
        case ({1'b0, ch})
            "0": instrument_glyph = 35'b01110_11011_11011_11011_11011_11011_01110;
            "1": instrument_glyph = 35'b00110_01110_00110_00110_00110_00110_01111;
            "2": instrument_glyph = 35'b11110_00011_00011_01110_11000_11000_11111;
            "3": instrument_glyph = 35'b11110_00011_00011_01110_00011_00011_11110;
            "4": instrument_glyph = 35'b11011_11011_11011_11111_00011_00011_00011;
            "5": instrument_glyph = 35'b11111_11000_11000_11110_00011_00011_11110;
            "6": instrument_glyph = 35'b01110_11000_11000_11110_11011_11011_01110;
            "7": instrument_glyph = 35'b11111_00011_00110_00110_01100_01100_01100;
            "8": instrument_glyph = 35'b01110_11011_11011_01110_11011_11011_01110;
            "9": instrument_glyph = 35'b01110_11011_11011_01111_00011_00011_01110;
            "L": instrument_glyph = 35'b11000_11000_11000_11000_11000_11000_11111;
            "E": instrument_glyph = 35'b11111_11000_11000_11110_11000_11000_11111;
            "V": instrument_glyph = 35'b11011_11011_11011_11011_11011_01110_00100;
            "F": instrument_glyph = 35'b11111_11000_11000_11110_11000_11000_11000;
            "U": instrument_glyph = 35'b11011_11011_11011_11011_11011_11011_01110;
            "I": instrument_glyph = 35'b01110_00100_00100_00100_00100_00100_01110;
            "S": instrument_glyph = 35'b01111_11000_11000_01110_00011_00011_11110;
            "C": instrument_glyph = 35'b01111_11000_11000_11000_11000_11000_01111;
            "O": instrument_glyph = 35'b01110_11011_11011_11011_11011_11011_01110;
            "R": instrument_glyph = 35'b11110_11011_11011_11110_11100_11010_11011;
            "P": instrument_glyph = 35'b11110_11011_11011_11110_11000_11000_11000;
            "D": instrument_glyph = 35'b11110_11011_11011_11011_11011_11011_11110;
            "A": instrument_glyph = 35'b01110_11011_11011_11111_11011_11011_11011;
            "T": instrument_glyph = 35'b11111_00100_00100_00100_00100_00100_00100;
            "M": instrument_glyph = 35'b10001_11011_11111_10101_10001_10001_10001;
            "/": instrument_glyph = 35'b00001_00011_00110_00100_01100_11000_10000;
            default: instrument_glyph = 0;
        endcase
    endfunction

    initial begin
        $readmemh("build/font.hex", expected_font);
        for (integer ch = 0; ch < 128; ch = ch + 1)
            for (integer r = 0; r < 8; r = r + 1)
                for (integer c = 0; c < 8; c = c + 1) begin
                    @(negedge clk);
                    character = 7'(ch); row = 3'(r); column = 3'(c);
                    dashboard_mode = 0;
                    expected_instrument = instrument_glyph(character);
                    expected_normal = ch >= 32 ? expected_font[(ch - 32)*8 + r][7 - c] : 0;
                    expected_dashboard = r < 7 && c >= 1 && c < 6 ?
                                         expected_instrument[34 - (r*5 + c-1)] : 0;
                    #1;
                    if (normal !== expected_normal)
                        $fatal(1, "Combinational glyph mismatch at %0d,%0d,%0d", ch, r, c);
                    @(posedge clk); #1;
                    if (normal_registered !== expected_normal ||
                        game_glyph !== expected_normal)
                        $fatal(1, "Registered glyph mismatch at %0d,%0d,%0d", ch, r, c);
                    @(negedge clk); dashboard_mode = 1;
                    @(posedge clk); #1;
                    if (game_glyph !== expected_dashboard)
                        $fatal(1, "Dashboard glyph mismatch at %0d,%0d,%0d", ch, r, c);
                end
        $display("PASS: normal and dashboard glyphs match for all characters and pixels");
        $finish;
    end
endmodule
