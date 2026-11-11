`include "platform_config.vh"

module tangnano9k_smoke #(
    parameter integer CLOCKS_PER_BIT = (`SYSTEM_CLK_HZ + 57600) / 115200,
    parameter integer REPORT_CYCLES = `SYSTEM_CLK_HZ
) (
    input  wire clk,
    output wire uart_tx
);
    reg [3:0] power_on_count;
    reg power_on_reset_n;
    wire reset_n;
    initial begin
        power_on_count = 0;
        power_on_reset_n = 0;
    end
    always @(posedge clk) begin
        if (!(&power_on_count))
            power_on_count <= power_on_count + 1'b1;
        else
            power_on_reset_n <= 1'b1;
    end

    reset_sync reset_control (
        .clk(clk), .async_reset_n(power_on_reset_n), .reset_n(reset_n)
    );
    wire [31:0] boot_status;
    wire trap;
    wire bus_fault;
    wire unused_sd_sck, unused_sd_cs_n, unused_sd_mosi;
    wire unused_video_write, unused_terrain_write;
    wire unused_uart_read, unused_uart_write;
    wire unused_audio_link_write, unused_audio_config_write;
    wire [11:0] unused_peripheral_addr;
    wire [31:0] unused_peripheral_wdata;
    wire [3:0] unused_peripheral_wstrb;
    wire unused_control_overflow;
    smoke_soc soc (
        .clk(clk), .reset_n(reset_n),
        .input_state(4'b0), .input_events(8'b0),
        .video_status(32'b0), .frame_count(32'b0), .vblank_tick(1'b0),
        .sd_sck(unused_sd_sck), .sd_cs_n(unused_sd_cs_n),
        .sd_mosi(unused_sd_mosi), .sd_miso(1'b1),
        .video_write(unused_video_write), .terrain_write(unused_terrain_write),
        .peripheral_addr(unused_peripheral_addr), .peripheral_wdata(unused_peripheral_wdata),
        .peripheral_wstrb(unused_peripheral_wstrb), .video_read_data(32'b0),
        .uart_read(unused_uart_read), .uart_write(unused_uart_write), .uart_read_data(32'b0),
        .audio_link_write(unused_audio_link_write),
        .audio_config_write(unused_audio_config_write), .audio_link_status(32'b0),
        .boot_status(boot_status), .trap(trap), .bus_fault(bus_fault)
    );

    uart_report #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT), .REPORT_CYCLES(REPORT_CYCLES))
        report (.clk(clk), .reset_n(reset_n),
                .control_valid(1'b0), .control_data(8'b0),
                .control_overflow(unused_control_overflow),
                .healthy(boot_status == 7 && !trap && !bus_fault), .tx(uart_tx));
endmodule
