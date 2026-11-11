module reset_sync (
    input  logic clk,
    input  logic async_reset_n,
    output logic reset_n
);
    logic [1:0] reset_pipe;

    always_ff @(posedge clk or negedge async_reset_n) begin
        if (!async_reset_n)
            reset_pipe <= 2'b00;
        else
            reset_pipe <= {reset_pipe[0], 1'b1};
    end

    assign reset_n = reset_pipe[1];
endmodule
