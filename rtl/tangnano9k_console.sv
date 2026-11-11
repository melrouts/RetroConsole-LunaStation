module tangnano9k_console (
    input wire clk,
    input wire uart_rx,
    output wire uart_tx,
    input wire link_uart_rx,
    output wire link_uart_tx,
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n,
    output wire sd_sck,
    output wire sd_cs_n,
    output wire sd_mosi,
    input wire sd_miso
);
    console_core #(.BOOT_ENABLE(1'b1)) core (.*);
endmodule
