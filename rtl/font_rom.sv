module font_rom #(
    parameter bit REGISTERED = 0
) (
    input wire clk,
    input wire [6:0] character,
    input wire [2:0] row,
    input wire [2:0] column,
    output wire pixel
);
    reg [7:0] font [0:767];
    wire [6:0] glyph = character - 7'd32;
    wire [7:0] pixels = character >= 32 ? font[{glyph, row}] : 8'b0;
    initial $readmemh("build/font.hex", font);
    reg [7:0] pixels_q;
    reg [2:0] column_q;
    always @(posedge clk) begin
        pixels_q <= pixels;
        column_q <= column;
    end
    assign pixel = REGISTERED ? pixels_q[3'd7 - column_q] : pixels[3'd7 - column];
endmodule
