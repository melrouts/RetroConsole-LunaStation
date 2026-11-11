`timescale 1ns/1ps
module tb_uart_buttons_merge;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg usb_rx = 1, link_rx = 1;
    wire [3:0] held;
    wire [7:0] events;
    wire transport_error;
    wire [7:0] link_received;
    wire link_valid;
    reg [7:0] observed = 0;
    uart_buttons_merge #(.CLOCKS_PER_BIT(8), .TIMEOUT_CYCLES(2000)) dut (.*);
    always @(negedge clk) observed = observed | events;
    task automatic send(input reg link_port, input reg [7:0] value);
        @(negedge clk);
        if (link_port) link_rx = 0; else usb_rx = 0;
        repeat (8) @(negedge clk);
        for (integer i = 0; i < 8; i = i + 1) begin
            if (link_port) link_rx = value[i]; else usb_rx = value[i];
            repeat (8) @(negedge clk);
        end
        if (link_port) link_rx = 1; else usb_rx = 1;
        repeat (12) @(negedge clk);
    endtask
    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;
        send(1, 8'h83);
        if (held !== 3 || observed !== 8'h03) $fatal(1, "Link press failed");
        observed = 0;
        send(1, 8'h83);
        if (held !== 3 || observed !== 0) $fatal(1, "Hold repeat created an event");
        send(0, 8'h82);
        if (held !== 3 || observed !== 0) $fatal(1, "Shared press created an event");
        send(1, 8'h80);
        if (held !== 2 || observed !== 8'h10) $fatal(1, "Shared hold was released");
        observed = 0;
        send(1, 8'h84);
        if (held !== 6 || observed !== 8'h04) $fatal(1, "Combined mask failed");
        observed = 0;
        send(1, 8'h00);
        if (held !== 2 || observed !== 8'h40 || !transport_error)
            $fatal(1, "Invalid link packet affected USB hold");
        observed = 0;
        send(1, 8'h84);
        if (held !== 6 || observed !== 8'h04 || transport_error)
            $fatal(1, "Link recovery failed");
        observed = 0;
        repeat (2100) @(negedge clk);
        if (held !== 0 || observed !== 8'h60) $fatal(1, "Disconnect watchdog failed");
        send(0, 8'h8f);
        observed = 0;
        reset_n = 0;
        repeat (4) @(negedge clk);
        if (held !== 0 || events !== 0) $fatal(1, "Reset did not clear held state");
        $display("PASS: dual UART masks, repeated hold, shared sources, recovery and timeout");
        $finish;
    end
endmodule
