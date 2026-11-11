`include "platform_config.vh"

module uart_buttons_merge #(
    parameter integer CLOCKS_PER_BIT = (`SYSTEM_CLK_HZ + 57600) / 115200,
    parameter integer TIMEOUT_CYCLES = `SYSTEM_CLK_HZ / 4
) (
    input wire clk,
    input wire reset_n,
    input wire usb_rx,
    input wire link_rx,
    output wire [3:0] held,
    output wire [7:0] events,
    output wire transport_error,
    output wire [7:0] link_received,
    output wire link_valid
);
    wire [3:0] usb_held, link_held;
    wire [7:0] unused_usb_events, unused_link_events;
    wire [7:0] unused_usb_received;
    wire unused_usb_valid;
    wire usb_error, link_error;
    reg [3:0] previous_held;
    uart_buttons #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT), .TIMEOUT_CYCLES(TIMEOUT_CYCLES)) usb (
        .clk(clk), .reset_n(reset_n), .rx(usb_rx),
        .held(usb_held), .events(unused_usb_events), .transport_error(usb_error),
        .received(unused_usb_received), .packet_valid(unused_usb_valid)
    );
    uart_buttons #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT), .TIMEOUT_CYCLES(TIMEOUT_CYCLES)) link (
        .clk(clk), .reset_n(reset_n), .rx(link_rx),
        .held(link_held), .events(unused_link_events), .transport_error(link_error),
        .received(link_received), .packet_valid(link_valid)
    );
    assign held = usb_held | link_held;
    assign events = reset_n ? {previous_held & ~held, held & ~previous_held} : 8'b0;
    assign transport_error = usb_error | link_error;
    always @(posedge clk) begin
        if (!reset_n)
            previous_held <= 0;
        else
            previous_held <= held;
    end
endmodule
