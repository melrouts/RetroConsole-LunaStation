module tb_reason_rows (
    input wire [3:0] cause,
    output wire equivalent
);
    wire [11:0] actual;
    reason_rows dut (.cause(cause), .rows(actual));
    function automatic [2:0] nth_cause(input reg [3:0] bits, input reg [1:0] row);
        reg [2:0] seen;
        nth_cause = 3'd4;
        seen = 0;
        for (integer bit_index = 0; bit_index < 4; bit_index = bit_index + 1)
            if (bits[bit_index]) begin
                if (seen == {1'b0, row})
                    nth_cause = 3'(bit_index);
                seen = seen + 3'd1;
            end
    endfunction
    wire [11:0] expected = {nth_cause(cause, 2'd3), nth_cause(cause, 2'd2),
                            nth_cause(cause, 2'd1), nth_cause(cause, 2'd0)};
    assign equivalent = actual == expected;
endmodule
