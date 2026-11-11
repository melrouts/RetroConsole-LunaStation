module hud_glyph_column (
    input wire [9:0] x,
    input wire [9:0] y,
    input wire menu,
    output reg [6:0] column
);
    always @* begin
        column = x[9:3];
        if (!menu && y < 60) begin
            if (x >= 16 && x < 96)
                column = y < 24 ? x[9:3] + 7'd4 : {1'b0, x[9:4]} + 7'd9;
            else if (x >= 112 && x < 256)
                column = y < 24 ? x[9:3] - 7'd1 : {1'b0, x[9:4]} + 7'd11;
            else if (x >= 272 && x < 352 && y < 24)
                column = x[9:3] - 7'd11;
            else if (x >= 368 && x < 624)
                column = y < 24 ? x[9:3] - 7'd16 : {1'b0, x[9:4]} + 7'd13;
        end
    end
endmodule
