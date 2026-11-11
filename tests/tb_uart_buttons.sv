`timescale 1ns/1ps
module tb_uart_buttons;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg rx = 1;
    wire [3:0] held;
    wire [7:0] events;
    wire transport_error;
    wire [7:0] received;
    wire packet_valid;
    reg [7:0] observed = 0;
    uart_buttons #(.CLOCKS_PER_BIT(8), .TIMEOUT_CYCLES(200)) dut (.*);
    always @(negedge clk) observed = observed | events;
    task automatic send(input reg [7:0] value, input reg stop_bit);
        @(negedge clk); rx = 0;
        repeat (8) @(negedge clk);
        for (integer index = 0; index < 8; index = index + 1) begin
            rx = value[index];
            repeat (8) @(negedge clk);
        end
        rx = stop_bit;
        repeat (8) @(negedge clk);
        rx = 1;
        repeat (4) @(negedge clk);
    endtask
    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;
        send(8'h83, 1);
        if (held !== 3 || observed !== 8'h03 || transport_error)
            $fatal(1, "UART press/held decode failed");
        observed = 0;
        send(8'h86, 1);
        if (held !== 6 || observed !== 8'h14)
            $fatal(1, "UART simultaneous press/release failed");
        observed = 0;
        repeat (220) @(negedge clk);
        if (held !== 0 || observed !== 8'h60)
            $fatal(1, "UART watchdog must release all held keys");
        send(8'h00, 1);
        if (!transport_error || held) $fatal(1, "Invalid control packet not rejected");
        send(8'h88, 1);
        if (transport_error || held !== 8) $fatal(1, "Valid packet must recover transport");
        send(8'h81, 0);
        if (!transport_error || held) $fatal(1, "Bad UART stop bit must release keys");
        $display("PASS: UART masks, press/release, framing rejection and disconnect watchdog");
        $finish;
    end
endmodule
