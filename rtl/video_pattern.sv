module video_pattern (
    input wire clk,
    input wire reset_n,
    input wire [9:0] x,
    input wire [9:0] y,
    input wire active,
    input wire hsync,
    input wire vsync,
    input wire vblank_start,
    output reg [23:0] rgb,
    output reg active_out,
    output reg hsync_out,
    output reg vsync_out,
    output reg frame_toggle
);
    reg [8:0] marker_x;
    reg direction;
    reg [23:0] color;
    wire [5:0] text_column = x[9:4] - 6'd2;
    reg [6:0] character;
    always @* begin
        case (text_column)
            0: character = 7'("L");
            1: character = 7'("U");
            2: character = 7'("N");
            3: character = 7'("A");
            4: character = 7'("9");
            6: character = 7'("H");
            7: character = 7'("D");
            8: character = 7'("M");
            9: character = 7'("I");
            11: character = 7'("6");
            12: character = 7'("4");
            13: character = 7'("0");
            14: character = 7'("X");
            15: character = 7'("4");
            16: character = 7'("8");
            17: character = 7'("0");
            default: character = 7'(" ");
        endcase
    end
    wire font_pixel;
    font_rom title_font (
        .clk(clk), .character(character), .row(y[3:1]), .column(x[3:1]), .pixel(font_pixel)
    );
    always @* begin
        case (x[9:7])
            0: color = 24'hffffff;
            1: color = 24'hffff00;
            2: color = 24'h00ffff;
            3: color = 24'h00ff00;
            default: color = 24'hff00ff;
        endcase
        if (y >= 240)
            color = {x[7:0], y[7:0], 8'h40};
        if (x >= {1'b0, marker_x} && x < {1'b0, marker_x} + 10'd32 &&
            y >= 320 && y < 352)
            color = 24'hffffff;
        if (x == 0 || x == 639 || y == 0 || y == 479)
            color = 24'hffffff;
        if (x >= 32 && x < 320 && y >= 32 && y < 48)
            color = font_pixel ? 24'hffffff : 24'h000000;
        if (!active)
            color = 0;
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            marker_x <= 0;
            direction <= 0;
            frame_toggle <= 0;
            rgb <= 0;
            active_out <= 0;
            hsync_out <= 1;
            vsync_out <= 1;
        end else begin
            rgb <= color;
            active_out <= active;
            hsync_out <= hsync;
            vsync_out <= vsync;
            if (vblank_start) begin
                frame_toggle <= !frame_toggle;
                if (!direction) begin
                    if (marker_x == 511)
                        direction <= 1;
                    else
                        marker_x <= marker_x + 1'b1;
                end else if (marker_x == 0) begin
                    direction <= 0;
                end else begin
                    marker_x <= marker_x - 1'b1;
                end
            end
        end
    end
endmodule
