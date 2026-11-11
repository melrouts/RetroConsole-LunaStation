module sd_spi (
    input wire clk,
    input wire reset_n,
    input wire command_valid,
    input wire [31:0] command,
    input wire [7:0] tx_data,
    output wire [31:0] status,
    output reg [7:0] rx_data,
    output reg sck,
    output reg cs_n,
    output reg mosi,
    input wire miso
);
    reg busy, done, overrun;
    reg [7:0] divider, countdown, rx_shift;
    reg [6:0] tx_shift;
    reg [2:0] bit_count;
    wire [7:0] requested_divider = command[15:8] == 0 ? 8'd1 : command[15:8];
    assign status = {29'b0, overrun, done, busy};
    always @(posedge clk) begin
        if (!reset_n) begin
            busy <= 0;
            done <= 0;
            overrun <= 0;
            rx_data <= 0;
            sck <= 0;
            cs_n <= 1;
            mosi <= 1;
            divider <= 1;
            countdown <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
            bit_count <= 0;
        end else begin
            if (command_valid) begin
                if (command[2])
                    overrun <= 0;
                if (busy || (|command[31:16]) || (|command[7:3])) begin
                    overrun <= 1;
                end else begin
                    cs_n <= command[1];
                    if (command[0]) begin
                        busy <= 1;
                        done <= 0;
                        divider <= requested_divider;
                        countdown <= requested_divider - 1'b1;
                        tx_shift <= tx_data[6:0];
                        rx_shift <= 0;
                        bit_count <= 0;
                        mosi <= tx_data[7];
                    end
                end
            end
            if (busy) begin
                if (countdown != 0) begin
                    countdown <= countdown - 1'b1;
                end else begin
                    countdown <= divider - 1'b1;
                    sck <= !sck;
                    if (!sck) begin
                        rx_shift <= {rx_shift[6:0], miso};
                    end else if (bit_count == 7) begin
                        busy <= 0;
                        done <= 1;
                        rx_data <= rx_shift;
                        mosi <= 1;
                    end else begin
                        tx_shift <= {tx_shift[5:0], 1'b1};
                        mosi <= tx_shift[6];
                        bit_count <= bit_count + 1'b1;
                    end
                end
            end
        end
    end
endmodule
