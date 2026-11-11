`timescale 1ns/1ps

module tb_input_control;
    logic clk = 1'b0;
    logic async_reset_n = 1'b0;
    logic reset_n;
    logic button_raw = 1'b1;
    logic held;
    logic pressed;
    logic released;

    always #5 clk = ~clk;

    reset_sync reset_dut (
        .clk,
        .async_reset_n,
        .reset_n
    );

    button_debounce #(
        .SYSTEM_CLK_HZ(1000),
        .DEBOUNCE_MS(20)
    ) button_dut (
        .clk,
        .reset_n,
        .button_raw,
        .held,
        .pressed,
        .released
    );

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $error("%s", message);
            $fatal(1);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1;
        check(reset_n == 1'b0, "Reset must remain asserted while async reset is low");

        @(negedge clk);
        async_reset_n = 1'b1;
        repeat (1) @(posedge clk);
        #1;
        check(reset_n == 1'b0, "Reset must take two clocks to deassert");
        @(posedge clk);
        #1;
        check(reset_n == 1'b1, "Reset must deassert after two clocks");

        repeat (4) @(posedge clk);
        #1;
        check(held == 1'b0, "Unpressed active-low button must be released");

        @(negedge clk);
        button_raw = 1'b0;
        repeat (8) @(posedge clk);
        @(negedge clk);
        button_raw = 1'b1;
        repeat (25) @(posedge clk);
        #1;
        check(held == 1'b0 && pressed == 1'b0,
              "Short bounce must not produce a press");

        @(negedge clk);
        button_raw = 1'b0;
        repeat (21) @(posedge clk);
        #1;
        check(held == 1'b0 && pressed == 1'b0,
              "Press must not register before 20 stable samples");
        @(posedge clk);
        #1;
        check(held == 1'b1 && pressed == 1'b1 && released == 1'b0,
              "Press must register on the 20th stable sample");
        @(posedge clk);
        #1;
        check(pressed == 1'b0, "Pressed event must last one clock");

        @(negedge clk);
        button_raw = 1'b1;
        repeat (21) @(posedge clk);
        #1;
        check(held == 1'b1 && released == 1'b0,
              "Release must not register before 20 stable samples");
        @(posedge clk);
        #1;
        check(held == 1'b0 && released == 1'b1 && pressed == 1'b0,
              "Release must register on the 20th stable sample");
        @(posedge clk);
        #1;
        check(released == 1'b0, "Released event must last one clock");

        @(negedge clk);
        async_reset_n = 1'b0;
        #1;
        check(reset_n == 1'b0 && held == 1'b0,
              "Reset assertion must be asynchronous and clear button state");

        $display("PASS: reset synchronization and button debounce");
        $finish;
    end
endmodule
