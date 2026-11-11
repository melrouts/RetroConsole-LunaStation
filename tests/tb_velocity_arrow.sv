module tb_velocity_arrow (
    input wire [9:0] x,
    input wire [9:0] y,
    input wire [2:0] heading,
    input wire stopped,
    output wire equivalent
);
    wire actual;
    velocity_arrow dut (.*,.visible(actual));
    wire signed [10:0] dx = $signed({1'b0, x}) - 11'sd448;
    wire signed [10:0] dy = $signed({1'b0, y}) - 11'sd78;
    reg signed [11:0] arrow_x, arrow_y;
    wire [11:0] abs_x = arrow_x < 0 ? $unsigned(-arrow_x) : $unsigned(arrow_x);
    always @* begin
        case (heading)
            0: begin arrow_x = 12'(dx); arrow_y = 12'(dy); end
            1: begin arrow_x = 12'(dx) + 12'(dy); arrow_y = 12'(dy) - 12'(dx); end
            2: begin arrow_x = 12'(dy); arrow_y = -12'(dx); end
            3: begin arrow_x = 12'(dy) - 12'(dx); arrow_y = -12'(dx) - 12'(dy); end
            4: begin arrow_x = -12'(dx); arrow_y = -12'(dy); end
            5: begin arrow_x = -12'(dx) - 12'(dy); arrow_y = 12'(dx) - 12'(dy); end
            6: begin arrow_x = -12'(dy); arrow_y = 12'(dx); end
            default: begin arrow_x = 12'(dx) - 12'(dy); arrow_y = 12'(dx) + 12'(dy); end
        endcase
    end
    wire expected = stopped ?
        (dx >= -1 && dx <= 1 && dy >= -1 && dy <= 1) :
        ((abs_x <= 1 && arrow_y >= -10 && arrow_y <= 10) ||
         (abs_x <= 6 && arrow_y >= -10 && arrow_y <= -4 &&
          (arrow_y == $signed(abs_x) - 12'sd10 ||
           arrow_y == $signed(abs_x) - 12'sd9)));
    assign equivalent = actual == expected;
endmodule
