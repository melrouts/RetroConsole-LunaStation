`timescale 1ns/1ps
module tb_uart_link_tx;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0, echo_valid = 0, audio_valid = 0, config_valid = 0;
    reg [7:0] echo_data = 0;
    reg [2:0] audio_state = 0;
    reg [5:0] config_data = 0;
    wire tx, echo_overflow;
    wire [7:0] received;
    wire received_valid, framing_error;
    reg [7:0] output_bytes [0:15];
    integer count = 0;

    uart_link_tx #(.CLOCKS_PER_BIT(8)) dut (.*);
    uart_rx #(.CLOCKS_PER_BIT(8)) monitor (
        .clk(clk), .reset_n(reset_n), .rx(tx), .data(received),
        .valid(received_valid), .framing_error(framing_error)
    );
    always @(negedge clk) begin
        if (framing_error) $fatal(1, "Link UART framing error");
        if (received_valid) begin
            output_bytes[count] = received;
            count = count + 1;
        end
    end

    task automatic audio(input reg [2:0] value);
        @(negedge clk); audio_valid = 1; audio_state = value;
        @(negedge clk); audio_valid = 0;
    endtask

    task automatic echo(input reg [7:0] value);
        @(negedge clk); echo_valid = 1; echo_data = value;
        @(negedge clk); echo_valid = 0;
    endtask

    task automatic settings(input reg [5:0] value);
        @(negedge clk); config_valid = 1; config_data = value;
        @(negedge clk); config_valid = 0;
    endtask

    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;
        @(negedge clk);
        echo_valid = 1; echo_data = 8'h82;
        audio_valid = 1; audio_state = 1;
        config_valid = 1; config_data = 6'h15;
        @(negedge clk); echo_valid = 0; audio_valid = 0; config_valid = 0;
        repeat (10) @(negedge clk);
        audio(2);
        audio(5);
        wait (count == 3);
        if (output_bytes[0] != 8'h82 || output_bytes[1] != 8'hd5 ||
            output_bytes[2] != 8'h6d || echo_overflow)
            $fatal(1, "Echo/config priority or latest-state coalescing failed: %h %h %h",
                   output_bytes[0], output_bytes[1], output_bytes[2]);
        repeat (12) @(negedge clk);

        audio(1);
        wait (tx == 0);
        echo(8'h8f);
        wait (count == 5);
        if (output_bytes[3] != 8'h49 || output_bytes[4] != 8'h8f || echo_overflow)
            $fatal(1, "Echo during audio transmission failed: %h %h",
                   output_bytes[3], output_bytes[4]);
        repeat (12) @(negedge clk);

        audio(1);
        wait (tx == 0);
        echo(8'h80);
        echo(8'h81);
        if (!echo_overflow) $fatal(1, "Lost button echo must set overflow");
        wait (count == 7);
        if (output_bytes[5] != 8'h49 || output_bytes[6] != 8'h80)
            $fatal(1, "Unexpected bytes during overflow");
        @(negedge clk); reset_n = 0;
        repeat (3) @(negedge clk);
        reset_n = 1;
        @(negedge clk);
        if (echo_overflow) $fatal(1, "Reset did not clear echo overflow");
        $display("PASS: button echo priority, game state coalescing and overflow");
        $finish;
    end

    initial begin
        repeat (2000) @(posedge clk);
        $fatal(1, "Link UART test timed out");
    end
endmodule
