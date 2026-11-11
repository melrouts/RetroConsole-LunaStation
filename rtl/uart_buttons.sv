`include "platform_config.vh"

module uart_buttons #(
    parameter integer CLOCKS_PER_BIT = (`SYSTEM_CLK_HZ + 57600) / 115200,
    parameter integer TIMEOUT_CYCLES = `SYSTEM_CLK_HZ / 4
) (
    input wire clk,
    input wire reset_n,
    input wire rx,
    output reg [3:0] held,
    output reg [7:0] events,
    output reg transport_error,
    output wire [7:0] received,
    output wire packet_valid
);
    wire valid, framing_error;
    assign packet_valid = valid && received[7:4] == 4'h8;
    uart_rx #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) receiver (
        .clk(clk), .reset_n(reset_n), .rx(rx),
        .data(received), .valid(valid), .framing_error(framing_error)
    );
    localparam integer TIMEOUT_BITS = $clog2(TIMEOUT_CYCLES + 1);
    reg [TIMEOUT_BITS-1:0] timeout_count;
    reg [3:0] next_held;
    always @* begin
        next_held = held;
        if (framing_error || (valid && received[7:4] != 4'h8) ||
            timeout_count == TIMEOUT_BITS'(TIMEOUT_CYCLES))
            next_held = 0;
        if (valid && received[7:4] == 4'h8)
            next_held = received[3:0];
    end
    always @(posedge clk) begin
        if (!reset_n) begin
            held <= 0;
            events <= 0;
            timeout_count <= 0;
            transport_error <= 0;
        end else begin
            held <= next_held;
            events <= {held & ~next_held, next_held & ~held};
            if (valid && received[7:4] == 4'h8) begin
                timeout_count <= 0;
                transport_error <= 0;
            end else if (timeout_count != TIMEOUT_BITS'(TIMEOUT_CYCLES)) begin
                timeout_count <= timeout_count + 1'b1;
            end
            if (framing_error || (valid && received[7:4] != 4'h8))
                transport_error <= 1;
        end
    end
endmodule
