module game_font_rom (
    input wire clk,
    input wire dashboard,
    input wire [6:0] character,
    input wire [2:0] row,
    input wire [2:0] column,
    output wire pixel
);
    reg [7:0] font [0:2047];
    wire [6:0] glyph = character - 7'd32;
    wire [7:0] pixels = character >= 32 ? font[{dashboard, glyph, row}] : 8'b0;
    reg [7:0] pixels_q;
    reg [2:0] column_q;
    initial $readmemh("build/hud-font.hex", font);
    always @(posedge clk) begin
        pixels_q <= pixels;
        column_q <= column;
    end
    assign pixel = pixels_q[3'd7 - column_q];
endmodule
