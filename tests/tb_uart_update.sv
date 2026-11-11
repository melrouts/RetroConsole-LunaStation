`timescale 1ns/1ps
module tb_uart_update;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0, rx = 1, read_valid = 0, write_valid = 0;
    reg [1:0] address = 0;
    reg [7:0] write_data = 0;
    wire [31:0] read_data;
    wire update_mode, cpu_reset_n, tx;
    uart_update #(.CLOCKS_PER_BIT(8)) dut (.*);
    task automatic send(input reg [7:0] value);
        @(negedge clk); rx = 0; repeat (8) @(negedge clk);
        for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            rx = value[bit_index]; repeat (8) @(negedge clk);
        end
        rx = 1; repeat (10) @(negedge clk);
    endtask
    task automatic unlock;
        reg [63:0] magic;
        magic = "LUNAUPD!";
        for (integer i = 7; i >= 0; i = i - 1)
            send(magic[i*8 +: 8]);
    endtask
    initial begin
        repeat (4) @(negedge clk); reset_n = 1;
        send(8'h83);
        send("L");
        if (update_mode) $fatal(1, "Keyboard/partial magic entered update");
        unlock();
        if (!update_mode) $fatal(1, "Unlock did not enter update mode");
        repeat (10) @(negedge clk);
        if (!cpu_reset_n) $fatal(1, "CPU reset never released");
        for (integer i = 0; i < 32; i = i + 1)
            send(8'(i));
        address = 0;
        if (read_data[2] || !read_data[0]) $fatal(1, "FIFO status incorrect");
        for (integer i = 0; i < 32; i = i + 1) begin
            address = 1; #1;
            if (read_data[7:0] !== 8'(i)) $fatal(1, "FIFO byte order mismatch");
            read_valid = 1;
            @(negedge clk); read_valid = 0;
            @(negedge clk);
        end
        address = 0; #1;
        if (read_data[0]) $fatal(1, "FIFO pop failed");
        for (integer i = 0; i < 33; i = i + 1)
            send(8'(i));
        if (!read_data[2]) $fatal(1, "FIFO overrun not reported");
        address = 2; write_data = 1; write_valid = 1;
        @(negedge clk); write_valid = 0;
        if (update_mode || cpu_reset_n) $fatal(1, "Exit must reset CPU and clear mode");
        repeat (10) @(negedge clk);
        if (!cpu_reset_n) $fatal(1, "Restart reset stuck");
        $display("PASS: update unlock, CPU restart, UART FIFO, overflow and exit");
        $finish;
    end
endmodule
