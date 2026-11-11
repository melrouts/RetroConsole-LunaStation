module uart_tx #(
    parameter integer CLOCKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       reset_n,
    input  wire       valid,
    input  wire [7:0] data,
    output wire       ready,
    output wire       tx
);
    localparam integer COUNT_BITS = $clog2(CLOCKS_PER_BIT);
    reg [COUNT_BITS-1:0] count;
    reg [3:0] bits_left;
    reg [9:0] shift;
    assign ready = bits_left == 0;
    assign tx = ready ? 1'b1 : shift[0];

    always @(posedge clk) begin
        if (!reset_n) begin
            count <= 0;
            bits_left <= 0;
            shift <= 10'h3ff;
        end else if (ready) begin
            if (valid) begin
                shift <= {1'b1, data, 1'b0};
                bits_left <= 10;
                count <= COUNT_BITS'(CLOCKS_PER_BIT - 1);
            end
        end else if (count != 0) begin
            count <= count - 1'b1;
        end else begin
            shift <= {1'b1, shift[9:1]};
            bits_left <= bits_left - 1'b1;
            count <= COUNT_BITS'(CLOCKS_PER_BIT - 1);
        end
    end
endmodule
