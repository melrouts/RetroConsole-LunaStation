module velocity_arrow (
    input wire [9:0] x,
    input wire [9:0] y,
    input wire [2:0] heading,
    input wire stopped,
    output wire visible
);
    // Visible pixels are within 10 of the center, so modular offsets fit in 5 bits.
    wire in_bounds = x >= 10'd438 && x <= 10'd458 && y >= 10'd68 && y <= 10'd88;
    wire signed [4:0] dx_mod = $signed(x[4:0]);
    wire signed [4:0] dy_mod = $signed(y[4:0] - 5'd14);
    wire signed [5:0] dx = $signed({dx_mod[4], dx_mod});
    wire signed [5:0] dy = $signed({dy_mod[4], dy_mod});
    wire signed [5:0] sum_xy = dx + dy;
    wire signed [5:0] diff_yx = dy - dx;
    reg signed [5:0] arrow_x, arrow_y;
    wire [5:0] abs_x = arrow_x < 0 ? $unsigned(-arrow_x) : $unsigned(arrow_x);

    always @* begin
        case (heading)
            0: begin arrow_x = dx; arrow_y = dy; end
            1: begin arrow_x = sum_xy; arrow_y = diff_yx; end
            2: begin arrow_x = dy; arrow_y = -dx; end
            3: begin arrow_x = diff_yx; arrow_y = -sum_xy; end
            4: begin arrow_x = -dx; arrow_y = -dy; end
            5: begin arrow_x = -sum_xy; arrow_y = -diff_yx; end
            6: begin arrow_x = -dy; arrow_y = dx; end
            default: begin arrow_x = -diff_yx; arrow_y = sum_xy; end
        endcase
    end
    assign visible = in_bounds && (stopped ?
        (dx >= -6'sd1 && dx <= 6'sd1 && dy >= -6'sd1 && dy <= 6'sd1) :
        ((abs_x <= 6'd1 && arrow_y >= -6'sd10 && arrow_y <= 6'sd10) ||
         (abs_x <= 6'd6 && arrow_y >= -6'sd10 && arrow_y <= -6'sd4 &&
          (arrow_y == $signed(abs_x) - 6'sd10 ||
           arrow_y == $signed(abs_x) - 6'sd9))));
endmodule
