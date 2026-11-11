`timescale 1ns/1ps

module tb_smoke_soc;
    reg clk = 0;
    always #5 clk = ~clk;
    wire tx;
    tangnano9k_smoke #(
        .CLOCKS_PER_BIT(8),
        .REPORT_CYCLES(20000)
    ) dut (.clk(clk), .uart_tx(tx));

    reg [7:0] value;
    reg [47:0] message;
    integer messages = 0;
    initial begin
        for (integer character = 0; character < 18; character = character + 1) begin
            @(negedge tx);
            repeat (4) @(posedge clk);
            #1;
            if (tx !== 0) $fatal(1, "Invalid UART start bit");
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (8) @(posedge clk);
                #1;
                value[bit_index] = tx;
            end
            repeat (8) @(posedge clk);
            #1;
            if (tx !== 1) $fatal(1, "Invalid UART stop bit");
            message = {message[39:0], value};
            if (character % 6 == 5) begin
                if (character < 12 && message !== 48'h504153530d0a)
                    $fatal(1, "Expected PASS report, received %h", message);
                if (character >= 12 && message !== 48'h4641494c0d0a)
                    $fatal(1, "Expected FAIL after injected trap, received %h", message);
                messages = messages + 1;
            end
            if (character == 11) begin
                if (dut.trap || dut.bus_fault || dut.boot_status != 7)
                    $fatal(1, "CPU did not complete firmware cleanly");
                force dut.trap = 1'b1;
            end
        end
        release dut.trap;
        $display("PASS: PicoRV32 firmware, RAM, MMIO and %0d UART reports including trap failure", messages);
        $finish;
    end
    initial begin
        repeat (100000) @(posedge clk);
        $fatal(1, "CPU/UART smoke test timed out");
    end
endmodule
