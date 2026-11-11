module video_art (
    input wire clk,
    input wire [4:0] angle,
    input wire [4:0] ship_x,
    input wire [4:0] ship_y,
    input wire [6:0] earth_x,
    input wire [6:0] earth_y,
    output reg [1:0] ship_pixel,
    output reg [3:0] earth_pixel
);
    reg [1:0] lander [0:32767];
    reg [3:0] earth [0:16383];
    initial begin
        $readmemh("build/lander.hex", lander);
        $readmemh("build/earth.hex", earth);
    end
    always @(posedge clk) begin
        ship_pixel <= lander[{angle, ship_y, ship_x}];
        earth_pixel <= earth[{earth_y, earth_x}];
    end
endmodule
