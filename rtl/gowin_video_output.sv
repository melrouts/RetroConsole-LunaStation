module gowin_video_output (
    input wire clk,
    input wire reset_n,
    output wire pixel_clk,
    output wire locked,
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n,
    input wire [9:0] red,
    input wire [9:0] green,
    input wire [9:0] blue,
    input wire pixel_reset_n
);
    wire serial_clk;
    wire unused_clkoutp;
    wire unused_clkoutd;
    wire unused_clkoutd3;
    // 27 / 3 * 14 = 126 MHz; CLKDIV /5 gives 25.2 MHz (exactly 60 Hz).
    rPLL #(
        .FCLKIN("27"), .IDIV_SEL(2), .FBDIV_SEL(13), .ODIV_SEL(4),
        .CLKFB_SEL("internal"), .DEVICE("GW1NR-9C")
    ) video_pll (
        .CLKIN(clk), .CLKFB(1'b0), .RESET(!reset_n), .RESET_P(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
        .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
        .CLKOUT(serial_clk), .LOCK(locked), .CLKOUTP(unused_clkoutp),
        .CLKOUTD(unused_clkoutd), .CLKOUTD3(unused_clkoutd3)
    );
    CLKDIV #(.DIV_MODE("5"), .GSREN("false")) pixel_divider (
        .HCLKIN(serial_clk), .RESETN(locked), .CALIB(1'b0), .CLKOUT(pixel_clk)
    );
    wire [29:0] symbols = {red, green, blue};
    wire [2:0] serial_data;
    generate for (genvar lane = 0; lane < 3; lane = lane + 1) begin: lanes
        OSER10 serializer (
            .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(!pixel_reset_n),
            .D0(symbols[lane*10]), .D1(symbols[lane*10+1]),
            .D2(symbols[lane*10+2]), .D3(symbols[lane*10+3]),
            .D4(symbols[lane*10+4]), .D5(symbols[lane*10+5]),
            .D6(symbols[lane*10+6]), .D7(symbols[lane*10+7]),
            .D8(symbols[lane*10+8]), .D9(symbols[lane*10+9]),
            .Q(serial_data[lane])
        );
        ELVDS_OBUF data_buffer (
            .I(serial_data[lane]), .O(tmds_d_p[lane]), .OB(tmds_d_n[lane])
        );
    end endgenerate
    ELVDS_OBUF clock_buffer (.I(pixel_clk), .O(tmds_clk_p), .OB(tmds_clk_n));
endmodule
