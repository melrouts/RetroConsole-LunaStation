module video_timing (
    input wire clk,
    input wire reset_n,
    output reg [9:0] x,
    output reg [9:0] y,
    output wire active,
    output wire hsync,
    output wire vsync,
    output wire vblank_start
);
    assign active = x < 640 && y < 480;
    assign hsync = !(x >= 656 && x < 752);
    assign vsync = !(y >= 490 && y < 492);
    assign vblank_start = x == 0 && y == 480;

    always @(posedge clk) begin
        if (!reset_n) begin
            x <= 0;
            y <= 0;
        end else if (x == 799) begin
            x <= 0;
            y <= y == 524 ? 10'd0 : y + 1'b1;
        end else begin
            x <= x + 1'b1;
        end
    end
endmodule
