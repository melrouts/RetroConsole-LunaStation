`include "platform_config.vh"

module console_core #(
    parameter bit BOOT_ENABLE = 1'b0
) (
    input wire clk,
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
    input wire sd_miso,
    input wire uart_rx
);
    reg [3:0] power_on_count;
    reg power_on_reset_n;
    initial begin
        power_on_count = 0;
        power_on_reset_n = 0;
    end
    always @(posedge clk) begin
        if (!(&power_on_count))
            power_on_count <= power_on_count + 1'b1;
        else
            power_on_reset_n <= 1;
    end
    wire reset_n;
    reset_sync system_reset (
        .clk(clk), .async_reset_n(power_on_reset_n), .reset_n(reset_n)
    );
    wire pixel_clk;
    wire locked;
    wire pixel_reset_n;
    reset_sync pixel_reset (
        .clk(pixel_clk), .async_reset_n(power_on_reset_n && locked),
        .reset_n(pixel_reset_n)
    );
    wire [9:0] x, y;
    wire active, hsync, vsync, vblank_start;
    video_timing timing (
        .clk(pixel_clk), .reset_n(pixel_reset_n), .x(x), .y(y),
        .active(active), .hsync(hsync), .vsync(vsync), .vblank_start(vblank_start)
    );
    wire [23:0] rgb, pattern_rgb;
    wire active_delayed, hsync_delayed, vsync_delayed, frame_toggle;
    wire unused_pattern_active, unused_pattern_hsync, unused_pattern_vsync;
    video_pattern compositor (
        .clk(pixel_clk), .reset_n(pixel_reset_n), .x(x), .y(y),
        .active(active), .hsync(hsync), .vsync(vsync), .vblank_start(vblank_start),
        .rgb(pattern_rgb), .active_out(unused_pattern_active), .hsync_out(unused_pattern_hsync),
        .vsync_out(unused_pattern_vsync), .frame_toggle(frame_toggle)
    );
    wire video_write, terrain_write, video_busy, video_error;
    wire [11:0] peripheral_addr;
    wire [31:0] peripheral_wdata, video_read_data;
    wire [3:0] peripheral_wstrb;
    wire [9:0] terrain_height;
    wire [223:0] snapshot;
    wire [1:0] unused_peripheral_byte_offset = peripheral_addr[1:0];
    video_snapshot frames (
        .clk(clk), .reset_n(reset_n), .write_valid(video_write),
        .write_index(peripheral_addr[4:2]), .write_data(peripheral_wdata),
        .write_strobes(peripheral_wstrb), .read_data(video_read_data),
        .terrain_write(terrain_write), .terrain_index(peripheral_addr[11:2]),
        .busy(video_busy), .error(video_error),
        .pixel_clk(pixel_clk), .pixel_reset_n(pixel_reset_n),
        .vblank_start(vblank_start), .pixel_x(x), .terrain_height(terrain_height),
        .snapshot(snapshot)
    );
    video_game renderer (
        .clk(pixel_clk), .reset_n(pixel_reset_n), .x(x), .y(y),
        .active(active), .hsync(hsync), .vsync(vsync),
        .terrain_height(terrain_height), .snapshot(snapshot), .pattern_rgb(pattern_rgb),
        .rgb(rgb), .active_out(active_delayed), .hsync_out(hsync_delayed),
        .vsync_out(vsync_delayed)
    );
    wire [9:0] blue, green, red;
    tmds_encoder blue_encoder (
        .clk(pixel_clk), .reset_n(pixel_reset_n), .active(active_delayed),
        .control({vsync_delayed, hsync_delayed}), .data(rgb[7:0]), .symbol(blue)
    );
    tmds_encoder green_encoder (
        .clk(pixel_clk), .reset_n(pixel_reset_n), .active(active_delayed),
        .control(2'b0), .data(rgb[15:8]), .symbol(green)
    );
    tmds_encoder red_encoder (
        .clk(pixel_clk), .reset_n(pixel_reset_n), .active(active_delayed),
        .control(2'b0), .data(rgb[23:16]), .symbol(red)
    );
    gowin_video_output output_stage (
        .clk(clk), .reset_n(power_on_reset_n), .pixel_clk(pixel_clk),
        .locked(locked), .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n),
        .red(red), .green(green), .blue(blue), .pixel_reset_n(pixel_reset_n)
    );

    (* async_reg = "true" *) reg [1:0] frame_sync;
    (* async_reg = "true" *) reg [1:0] lock_sync;
    reg frame_previous;
    reg [31:0] frame_count;
    reg [24:0] frame_watchdog;
    wire frame_tick = frame_sync[1] ^ frame_previous;
    always @(posedge clk) begin
        if (!reset_n) begin
            frame_sync <= 0;
            lock_sync <= 0;
            frame_previous <= 0;
            frame_count <= 0;
            frame_watchdog <= 25'd27000000;
        end else begin
            frame_sync <= {frame_sync[0], frame_toggle};
            lock_sync <= {lock_sync[0], locked};
            frame_previous <= frame_sync[1];
            if (frame_tick) begin
                frame_count <= frame_count + 1'b1;
                frame_watchdog <= 0;
            end else if (frame_watchdog < 25'd27000000) begin
                frame_watchdog <= frame_watchdog + 1'b1;
            end
        end
    end
    wire [31:0] boot_status;
    wire trap, bus_fault;
    wire [3:0] held;
    wire [7:0] input_events;
    wire transport_error;
    wire [7:0] link_received;
    wire link_valid, audio_link_write, audio_config_write, link_echo_overflow;
    wire unused_control_overflow;
    wire update_mode, cpu_reset_n, update_tx, report_tx, uart_read, uart_write;
    wire [31:0] uart_read_data;
    uart_update updater (
        .clk(clk), .reset_n(reset_n), .rx(uart_rx),
        .read_valid(uart_read), .write_valid(uart_write),
        .address(peripheral_addr[3:2]), .write_data(peripheral_wdata[7:0]),
        .read_data(uart_read_data), .update_mode(update_mode),
        .cpu_reset_n(cpu_reset_n), .tx(update_tx)
    );
    assign uart_tx = update_mode ? update_tx : report_tx;
    uart_link_tx #(.CLOCKS_PER_BIT((`SYSTEM_CLK_HZ + 57600) / 115200)) link_output (
        .clk(clk), .reset_n(reset_n && !update_mode),
        .echo_valid(link_valid), .echo_data(link_received),
        .audio_valid(audio_link_write), .audio_state(peripheral_wdata[2:0]),
        .config_valid(audio_config_write), .config_data(peripheral_wdata[5:0]),
        .echo_overflow(link_echo_overflow), .tx(link_uart_tx)
    );
    uart_buttons_merge keyboard (
        .clk(clk), .reset_n(reset_n && !update_mode),
        .usb_rx(uart_rx), .link_rx(link_uart_rx),
        .held(held), .events(input_events), .transport_error(transport_error),
        .link_received(link_received), .link_valid(link_valid)
    );
    smoke_soc #(.BOOT_ENABLE(BOOT_ENABLE)) soc (
        .clk(clk), .reset_n(cpu_reset_n), .input_state(held), .input_events(input_events),
        .video_status({29'b0, video_error, video_busy, lock_sync[1]}), .frame_count(frame_count),
        .vblank_tick(frame_tick), .boot_status(boot_status),
        .trap(trap), .bus_fault(bus_fault),
        .sd_sck(sd_sck), .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .video_write(video_write), .terrain_write(terrain_write),
        .peripheral_addr(peripheral_addr), .peripheral_wdata(peripheral_wdata),
        .peripheral_wstrb(peripheral_wstrb), .video_read_data(video_read_data),
        .uart_read(uart_read), .uart_write(uart_write), .uart_read_data(uart_read_data),
        .audio_link_write(audio_link_write), .audio_config_write(audio_config_write),
        .audio_link_status(32'h41554401)
    );
    uart_report report (
        .clk(clk), .reset_n(reset_n),
        .control_valid(link_valid && !update_mode), .control_data(link_received),
        .control_overflow(unused_control_overflow),
        .healthy(boot_status == 7 && !trap && !bus_fault && !video_error &&
                 !transport_error && !link_echo_overflow && lock_sync[1] &&
                 frame_watchdog < 25'd2700000),
        .tx(report_tx)
    );
endmodule
