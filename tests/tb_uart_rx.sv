`timescale 1ns/1ps
module tb_uart_rx;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0, rx = 1;
    wire [7:0] data;
    wire valid, framing_error;
    reg [7:0] expected = 0;
    integer received = 0;
    integer errors = 0;
    uart_rx #(.CLOCKS_PER_BIT(8)) dut (.*);
    always @(negedge clk) begin
        if (valid) begin
            if (data !== expected)
                $fatal(1, "UART byte %0d decoded as %h, expected %h", received, data, expected);
            received = received + 1;
        end
        if (framing_error)
            errors = errors + 1;
    end
    task automatic send(input reg [7:0] value);
        @(negedge clk); rx = 0; repeat (8) @(negedge clk);
        for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            rx = value[bit_index]; repeat (8) @(negedge clk);
        end
        rx = 1; repeat (10) @(negedge clk);
    endtask
    initial begin
        repeat (4) @(negedge clk); reset_n = 1;
        for (integer value = 0; value < 256; value = value + 1) begin
            expected = 8'(value);
            send(expected);
            if (received != value + 1 || errors != 0)
                $fatal(1, "UART lost or rejected byte %0d", value);
        end
        $display("PASS: UART receives all 256 byte values in LSB-first order");
        $finish;
    end
endmodule
