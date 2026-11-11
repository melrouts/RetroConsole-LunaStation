module reason_rows (
    input wire [3:0] cause,
    output wire [11:0] rows
);
    wire [2:0] first = cause[0] ? 3'd0 : cause[1] ? 3'd1 :
                       cause[2] ? 3'd2 : cause[3] ? 3'd3 : 3'd4;
    wire [2:0] second = cause[1] && cause[0] ? 3'd1 :
                        cause[2] && (|cause[1:0]) ? 3'd2 :
                        cause[3] && (|cause[2:0]) ? 3'd3 : 3'd4;
    wire two_of_first_three = (cause[0] && cause[1]) ||
                              (cause[0] && cause[2]) ||
                              (cause[1] && cause[2]);
    wire [2:0] third = (&cause[2:0]) ? 3'd2 :
                       cause[3] && two_of_first_three ? 3'd3 : 3'd4;
    wire [2:0] fourth = (&cause) ? 3'd3 : 3'd4;
    assign rows = {fourth, third, second, first};
endmodule
