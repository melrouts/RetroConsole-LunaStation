module tb_hud_glyph_column (
    input wire [9:0] x,
    input wire [9:0] y,
    input wire menu,
    output wire equivalent
);
    wire [6:0] actual;
    hud_glyph_column dut (.x(x), .y(y), .menu(menu), .column(actual));
    reg [6:0] expected;
    reg [9:0] offset;
    always @* begin
        expected = x[9:3];
        offset = 0;
        if (!menu && y < 60) begin
            if (x >= 16 && x < 96) begin
                offset = x - 16;
                expected = y < 24 ? 7'd6 + {1'b0, offset[8:3]} :
                                    7'd10 + {2'b0, offset[8:4]};
            end else if (x >= 112 && x < 256) begin
                offset = x - 112;
                expected = y < 24 ? 7'd13 + {1'b0, offset[8:3]} :
                                    7'd18 + {2'b0, offset[8:4]};
            end else if (x >= 272 && x < 352 && y < 24) begin
                offset = x - 272;
                expected = 7'd23 + {1'b0, offset[8:3]};
            end else if (x >= 368 && x < 624) begin
                offset = x - 368;
                expected = y < 24 ? 7'd30 + {1'b0, offset[8:3]} :
                                    7'd36 + {2'b0, offset[8:4]};
            end
        end
    end
    assign equivalent = actual == expected;
endmodule
