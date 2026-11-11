`include "platform_config.vh"

module smoke_soc #(
    parameter RAM_INIT_FILE = "build/smoke.hex",
    parameter bit BOOT_ENABLE = 1'b0
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [3:0]  input_state,
    input  wire [7:0]  input_events,
    input  wire [31:0] video_status,
    input  wire [31:0] frame_count,
    input  wire        vblank_tick,
    output wire [31:0] boot_status,
    output wire        trap,
    output wire        bus_fault,
    output wire        sd_sck,
    output wire        sd_cs_n,
    output wire        sd_mosi,
    input wire         sd_miso,
    output wire        video_write,
    output wire        terrain_write,
    output wire [11:0] peripheral_addr,
    output wire [31:0] peripheral_wdata,
    output wire [3:0]  peripheral_wstrb,
    input wire [31:0]  video_read_data,
    output wire        uart_read,
    output wire        uart_write,
    input wire [31:0]  uart_read_data,
    output wire        audio_link_write,
    output wire        audio_config_write,
    input wire [31:0]  audio_link_status
);
    wire mem_valid;
    wire mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_rdata;
    assign peripheral_addr = mem_addr[11:0];
    assign peripheral_wdata = mem_wdata;
    assign peripheral_wstrb = mem_wstrb;
    wire [31:0] unused_audio_control;
    wire [31:0] unused_audio_period;

    picorv32_wrapper #(.RESET_ADDRESS(BOOT_ENABLE ? `BOOT_BASE : 32'b0)) cpu (
        .clk(clk), .reset_n(reset_n), .trap(trap),
        .mem_valid(mem_valid), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata)
    );
    memory_map #(.RAM_INIT_FILE(RAM_INIT_FILE), .BOOT_ENABLE(BOOT_ENABLE)) memory (
        .clk(clk), .reset_n(reset_n),
        .mem_valid(mem_valid), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .input_state(input_state), .input_events(input_events),
        .video_status(video_status), .frame_count(frame_count), .vblank_tick(vblank_tick),
        .audio_control(unused_audio_control), .audio_period(unused_audio_period),
        .boot_status(boot_status), .bus_fault(bus_fault),
        .sd_sck(sd_sck), .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .video_write(video_write), .terrain_write(terrain_write),
        .video_read_data(video_read_data), .uart_read(uart_read),
        .uart_write(uart_write), .uart_read_data(uart_read_data),
        .audio_link_write(audio_link_write), .audio_config_write(audio_config_write),
        .audio_link_status(audio_link_status)
    );
endmodule
