`timescale 1ns/1ps
module tb_uart_report;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0, healthy = 1, control_valid = 0;
    reg [7:0] control_data = 0;
    wire tx, control_overflow;
    wire [7:0] data;
    wire valid, framing_error;
    reg [127:0] output_text = 0;
    reg [47:0] last_six = 0;
    uart_report #(.CLOCKS_PER_BIT(8), .REPORT_CYCLES(3000)) dut (.*);
    uart_rx #(.CLOCKS_PER_BIT(8)) monitor (
        .clk(clk), .reset_n(reset_n), .rx(tx), .data(data),
        .valid(valid), .framing_error(framing_error)
    );
    always @(negedge clk) begin
        if (framing_error) $fatal(1, "Report UART framing error");
        if (valid) begin
            output_text = {output_text[119:0], data};
            last_six = {last_six[39:0], data};
        end
    end
    task automatic submit(input reg [7:0] value);
        @(negedge clk); control_valid = 1; control_data = value;
        @(negedge clk); control_valid = 0;
    endtask
    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;
        submit(8'h82);
        repeat (1000) @(negedge clk);
        if (output_text != {"RX 0x82", 8'h0d, 8'h0a} || control_overflow)
            $fatal(1, "Control byte log failed: %s", output_text);
        output_text = 0;
        repeat (2600) @(negedge clk);
        if (output_text != {"PASS", 8'h0d, 8'h0a}) $fatal(1, "Health report changed");
        output_text = 0;
        submit(8'h8f);
        repeat (1000) @(negedge clk);
        if (output_text != {"RX 0x8F", 8'h0d, 8'h0a}) $fatal(1, "Hex conversion failed");
        submit(8'h80);
        repeat (20) @(negedge clk);
        submit(8'h81);
        submit(8'h82);
        if (!control_overflow) $fatal(1, "Dropped log must set overflow");
        output_text = 0;
        repeat (3500) @(negedge clk);
        if (last_six != {"FAIL", 8'h0d, 8'h0a})
            $fatal(1, "Overflow must surface in health report: %s", output_text);
        $display("PASS: UART control logs, health reports, hexadecimal and overflow diagnostics");
        $finish;
    end
endmodule
