module uart_update #(
    parameter integer CLOCKS_PER_BIT = 234
) (
    input wire clk, reset_n, rx,
    input wire read_valid, write_valid,
    input wire [1:0] address,
    input wire [7:0] write_data,
    output wire [31:0] read_data,
    output reg update_mode,
    output wire cpu_reset_n,
    output wire tx
);
    wire [7:0] received;
    wire received_valid, framing_error;
    uart_rx #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) receiver (
        .clk(clk), .reset_n(reset_n), .rx(rx), .data(received),
        .valid(received_valid), .framing_error(framing_error)
    );
    reg [55:0] unlock;
    reg [3:0] reset_cycles;
    reg [7:0] fifo [0:31];
    reg [4:0] head, tail;
    reg [5:0] count;
    reg overrun;
    wire tx_ready;
    wire pop = read_valid && address == 1 && count != 0;
    wire push = update_mode && received_valid && (count < 32 || pop);
    wire send = write_valid && address == 1 && update_mode && tx_ready;
    uart_tx #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) transmitter (
        .clk(clk), .reset_n(reset_n), .valid(send), .data(write_data),
        .ready(tx_ready), .tx(tx)
    );
    assign read_data = address == 0 ? {28'b0, update_mode, overrun, !tx_ready, count != 0} :
                       address == 1 ? {24'b0, fifo[head]} : 32'b0;
    assign cpu_reset_n = reset_n && reset_cycles == 0;
    always @(posedge clk) begin
        if (!reset_n) begin
            unlock <= 0; update_mode <= 0; reset_cycles <= 0;
            head <= 0; tail <= 0; count <= 0; overrun <= 0;
        end else begin
            if (reset_cycles != 0)
                reset_cycles <= reset_cycles - 1'b1;
            if (!update_mode && received_valid) begin
                unlock <= {unlock[47:0], received};
                if ({unlock[55:0], received} == 64'h4c554e4155504421) begin
                    update_mode <= 1;
                    reset_cycles <= 8;
                    count <= 0; head <= 0; tail <= 0; overrun <= 0;
                end
            end
            if (update_mode) begin
                if (push) begin
                    fifo[tail] <= received;
                    tail <= tail + 1'b1;
                end
                if (pop)
                    head <= head + 1'b1;
                case ({push, pop})
                    2'b10: count <= count + 1'b1;
                    2'b01: count <= count - 1'b1;
                    default: begin end
                endcase
                if ((received_valid && !push) || framing_error ||
                    (write_valid && address == 1 && !tx_ready))
                    overrun <= 1;
                if (write_valid && address == 2 && write_data == 1 && tx_ready) begin
                    update_mode <= 0; unlock <= 0; reset_cycles <= 8;
                    count <= 0; head <= 0; tail <= 0; overrun <= 0;
                end
            end
        end
    end
endmodule
