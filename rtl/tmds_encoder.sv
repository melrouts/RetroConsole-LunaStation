module tmds_encoder (
    input wire clk,
    input wire reset_n,
    input wire active,
    input wire [1:0] control,
    input wire [7:0] data,
    output reg [9:0] symbol
);
    reg [3:0] data_ones;
    reg [3:0] encoded_ones;
    wire [8:0] transition;
    wire use_xnor = data_ones > 4 || (data_ones == 4 && !data[0]);
    wire signed [5:0] balance = $signed({1'b0, encoded_ones, 1'b0}) - 6'sd8;
    reg signed [5:0] disparity;
    assign transition[0] = data[0];
    assign transition[8] = !use_xnor;
    generate for (genvar bit_index = 1; bit_index < 8; bit_index = bit_index + 1) begin: encode
        assign transition[bit_index] = transition[bit_index-1] ^ data[bit_index] ^ use_xnor;
    end endgenerate
    always_comb begin
        data_ones = 0;
        for (integer i = 0; i < 8; i = i + 1)
            data_ones = data_ones + {3'b0, data[i]};
        encoded_ones = 0;
        for (integer i = 0; i < 8; i = i + 1)
            encoded_ones = encoded_ones + {3'b0, transition[i]};
    end

    always @(posedge clk) begin
        if (!reset_n || !active) begin
            disparity <= 0;
            case (control)
                2'b00: symbol <= 10'b1101010100;
                2'b01: symbol <= 10'b0010101011;
                2'b10: symbol <= 10'b0101010100;
                2'b11: symbol <= 10'b1010101011;
            endcase
        end else if (disparity == 0 || balance == 0) begin
            symbol <= {~transition[8], transition[8],
                       transition[8] ? transition[7:0] : ~transition[7:0]};
            disparity <= disparity + (transition[8] ? balance : -balance);
        end else if ((disparity > 0 && balance > 0) ||
                     (disparity < 0 && balance < 0)) begin
            symbol <= {1'b1, transition[8], ~transition[7:0]};
            disparity <= disparity - balance + (transition[8] ? 6'sd2 : 6'sd0);
        end else begin
            symbol <= {1'b0, transition};
            disparity <= disparity + balance - (transition[8] ? 6'sd0 : 6'sd2);
        end
    end
endmodule
