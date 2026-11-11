`timescale 1ns/1ps
module tb_tmds;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg active = 0;
    reg [1:0] control = 0;
    reg [7:0] data = 0;
    wire [9:0] symbol;
    tmds_encoder dut (.*);
    reg [9:0] expected_control [0:3];
    reg [7:0] transition, decoded;
    integer ones;
    integer running_disparity = 0;
    integer transitions;
    initial begin
        expected_control[0] = 10'b1101010100;
        expected_control[1] = 10'b0010101011;
        expected_control[2] = 10'b0101010100;
        expected_control[3] = 10'b1010101011;
        repeat (3) @(negedge clk);
        reset_n = 1;
        for (integer pass = 0; pass < 16; pass = pass + 1) begin
            active = 0;
            control = 2'(pass);
            @(posedge clk); #1;
            if (symbol !== expected_control[control])
                $fatal(1, "TMDS control symbol mismatch");
            running_disparity = 0;
            @(negedge clk);
            active = 1;
            for (integer value = 0; value < 256; value = value + 1) begin
                data = 8'(value ^ (pass * 37));
                @(posedge clk); #1;
                transition = symbol[9] ? ~symbol[7:0] : symbol[7:0];
                decoded[0] = transition[0];
                for (integer bit_index = 1; bit_index < 8; bit_index = bit_index + 1)
                    decoded[bit_index] = transition[bit_index] ^
                                         transition[bit_index-1] ^ !symbol[8];
                if (decoded !== data)
                    $fatal(1, "TMDS round-trip mismatch for %h: symbol=%b decoded=%h",
                           data, symbol, decoded);
                ones = 0;
                for (integer bit_index = 0; bit_index < 10; bit_index = bit_index + 1)
                    ones = ones + int'(symbol[bit_index]);
                running_disparity = running_disparity + 2*ones - 10;
                if (running_disparity != int'($signed(dut.disparity)) ||
                    running_disparity < -8 || running_disparity > 8)
                    $fatal(1, "TMDS DC balance mismatch: %0d", running_disparity);
                transitions = 0;
                for (integer bit_index = 1; bit_index < 8; bit_index = bit_index + 1)
                    transitions = transitions + int'(transition[bit_index] !=
                                                     transition[bit_index-1]);
                if (transitions > 4)
                    $fatal(1, "TMDS transition minimization failed");
                @(negedge clk);
            end
        end
        active = 0; control = 0;
        @(posedge clk); #1;
        if (dut.disparity !== 0) $fatal(1, "Blanking must reset DC balance");
        $display("PASS: all TMDS control tokens, 4096 data symbols, decode and DC balance");
        $finish;
    end
endmodule
