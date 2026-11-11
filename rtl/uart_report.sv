`include "platform_config.vh"

module uart_report #(
    parameter integer CLOCKS_PER_BIT = (`SYSTEM_CLK_HZ + 57600) / 115200,
    parameter integer REPORT_CYCLES = `SYSTEM_CLK_HZ
) (
    input wire clk,
    input wire reset_n,
    input wire healthy,
    input wire control_valid,
    input wire [7:0] control_data,
    output reg control_overflow,
    output wire tx
);
    localparam integer REPORT_BITS = $clog2(REPORT_CYCLES);
    reg [REPORT_BITS-1:0] report_count;
    reg [3:0] byte_index;
    reg sending;
    reg report_pass;
    reg control_pending, sending_control;
    reg [7:0] pending_control, active_control;
    wire uart_ready;
    reg [7:0] tx_data;
    always @* begin
        if (sending_control) begin
            case (byte_index)
                0: tx_data = "R";
                1: tx_data = "X";
                2: tx_data = " ";
                3: tx_data = "0";
                4: tx_data = "x";
                5: tx_data = active_control[7:4] < 10 ?
                             8'h30 + {4'b0, active_control[7:4]} :
                             8'h41 + {4'b0, active_control[7:4]} - 8'd10;
                6: tx_data = active_control[3:0] < 10 ?
                             8'h30 + {4'b0, active_control[3:0]} :
                             8'h41 + {4'b0, active_control[3:0]} - 8'd10;
                7: tx_data = 8'h0d;
                default: tx_data = 8'h0a;
            endcase
        end else case (byte_index)
            0: tx_data = report_pass ? "P" : "F";
            1: tx_data = "A";
            2: tx_data = report_pass ? "S" : "I";
            3: tx_data = report_pass ? "S" : "L";
            4: tx_data = 8'h0d;
            default: tx_data = 8'h0a;
        endcase
    end
    uart_tx #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) serial_output (
        .clk(clk), .reset_n(reset_n), .valid(sending), .data(tx_data),
        .ready(uart_ready), .tx(tx)
    );
    always @(posedge clk) begin
        if (!reset_n) begin
            report_count <= 0;
            byte_index <= 0;
            sending <= 0;
            report_pass <= 0;
            control_pending <= 0;
            sending_control <= 0;
            pending_control <= 0;
            active_control <= 0;
            control_overflow <= 0;
        end else begin
            if (report_count != REPORT_BITS'(REPORT_CYCLES - 1))
                report_count <= report_count + 1'b1;
            if (sending && uart_ready) begin
                if (byte_index == (sending_control ? 8 : 5)) begin
                    sending <= 0;
                    byte_index <= 0;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end else if (!sending) begin
                if (report_count == REPORT_BITS'(REPORT_CYCLES - 1)) begin
                    report_count <= 0;
                    sending <= 1;
                    sending_control <= 0;
                    report_pass <= healthy && !control_overflow;
                end else if (control_pending) begin
                    sending <= 1;
                    sending_control <= 1;
                    active_control <= pending_control;
                    control_pending <= 0;
                end
            end
            if (control_valid) begin
                if (control_pending &&
                    (sending || report_count == REPORT_BITS'(REPORT_CYCLES - 1))) begin
                    control_overflow <= 1;
                end else begin
                    pending_control <= control_data;
                    control_pending <= 1;
                end
            end
        end
    end
endmodule
