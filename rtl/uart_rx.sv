module uart_rx #(
    parameter integer CLOCKS_PER_BIT = 234
) (
    input wire clk,
    input wire reset_n,
    input wire rx,
    output reg [7:0] data,
    output reg valid,
    output reg framing_error
);
    (* async_reg = "true" *) reg [1:0] synchronized;
    localparam integer TIMER_BITS = $clog2(CLOCKS_PER_BIT + 1);
    reg [TIMER_BITS-1:0] timer;
    reg [1:0] state;
    reg [2:0] bit_index;
    reg [7:0] shift;
    always @(posedge clk) begin
        if (!reset_n) begin
            synchronized <= 2'b11;
            timer <= 0;
            state <= 0;
            bit_index <= 0;
            shift <= 0;
            data <= 0;
            valid <= 0;
            framing_error <= 0;
        end else begin
            synchronized <= {synchronized[0], rx};
            valid <= 0;
            framing_error <= 0;
            if (state == 0) begin
                if (!synchronized[1]) begin
                    timer <= TIMER_BITS'(CLOCKS_PER_BIT / 2 - 1);
                    state <= 1;
                end
            end else if (timer != 0) begin
                timer <= timer - 1'b1;
            end else begin
                timer <= TIMER_BITS'(CLOCKS_PER_BIT - 1);
                case (state)
                    1: begin
                        if (synchronized[1])
                            state <= 0;
                        else begin
                            state <= 2;
                            bit_index <= 0;
                        end
                    end
                    2: begin
                        shift <= {synchronized[1], shift[7:1]};
                        if (bit_index == 7)
                            state <= 3;
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                    3: begin
                        state <= 0;
                        if (synchronized[1]) begin
                            data <= shift;
                            valid <= 1;
                        end else begin
                            framing_error <= 1;
                        end
                    end
                    default: state <= 0;
                endcase
            end
        end
    end
endmodule
