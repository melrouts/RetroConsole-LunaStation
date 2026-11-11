module tangnano9k_video (
    input wire clk,
    output wire uart_tx,
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);
    wire unused_sd_sck, unused_sd_cs_n, unused_sd_mosi;
    console_core core (
        .clk(clk), .uart_tx(uart_tx),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n),
        .sd_sck(unused_sd_sck), .sd_cs_n(unused_sd_cs_n),
        .sd_mosi(unused_sd_mosi), .sd_miso(1'b1), .uart_rx(1'b1)
    );
endmodule
