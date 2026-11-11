`timescale 1ns/1ps
module tb_sd_spi;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg command_valid = 0;
    reg [31:0] command = 0;
    reg [7:0] tx_data = 0;
    wire [31:0] status;
    wire [7:0] rx_data;
    wire sck, cs_n, mosi;
    wire miso = mosi;
    sd_spi dut (.*);
    integer cycles = 0;
    always @(posedge clk) cycles <= cycles + 1;
    reg [7:0] captured;
    integer edges;
    always @(posedge sck) begin
        captured = {captured[6:0], mosi};
        edges = edges + 1;
    end
    task automatic transfer(input reg [7:0] value, input integer divider);
        integer started;
        @(negedge clk);
        captured = 0; edges = 0;
        tx_data = value;
        command = (32'(divider) << 8) | 1;
        command_valid = 1;
        @(posedge clk); #1;
        started = cycles;
        if (!status[0] || cs_n || sck) $fatal(1, "Invalid SPI start state");
        @(negedge clk); command_valid = 0;
        while (status[0]) begin
            @(posedge clk); #1;
        end
        if (cycles - started != divider * 16 || edges != 8 || sck)
            $fatal(1, "SPI transfer length/phase mismatch");
        if (!status[1] || status[2] || rx_data !== value || captured !== value)
            $fatal(1, "SPI MSB-first full-duplex mismatch");
    endtask
    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1;
        if (!cs_n || !mosi || sck) $fatal(1, "Unsafe SD reset state");
        transfer(8'ha6, 1);
        transfer(8'h52, 2);
        transfer(8'h81, 34);
        @(negedge clk);
        command = (34 << 8) | 1; command_valid = 1;
        @(negedge clk);
        command = 2;
        @(posedge clk); #1;
        if (!status[2] || cs_n) $fatal(1, "Busy command must flag overrun, not change CS");
        @(negedge clk); command_valid = 0;
        repeat (10) @(negedge clk);
        reset_n = 0;
        @(negedge clk);
        if (status || !cs_n || sck || !mosi) $fatal(1, "Reset did not abort SPI safely");
        $display("PASS: SPI mode 0, MSB-first duplex, dividers 1/2/34, overrun and reset");
        $finish;
    end
    initial begin
        #20000;
        $fatal(1, "SPI test timeout");
    end
endmodule
