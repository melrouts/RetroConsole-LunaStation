module uart_link_tx #(
    parameter integer CLOCKS_PER_BIT = 234
) (
    input wire clk,
    input wire reset_n,
    input wire echo_valid,
    input wire [7:0] echo_data,
    input wire audio_valid,
    input wire [2:0] audio_state,
    input wire config_valid,
    input wire [5:0] config_data,
    output reg echo_overflow,
    output wire tx
);
    reg [7:0] pending_echo_data;
    reg [2:0] pending_audio_state;
    reg [5:0] pending_config_data;
    reg echo_pending, audio_pending, config_pending;
    wire ready;

    // Audio snapshots use 01sss sss; volume settings use 11vvvvvv.
    uart_tx #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) transmitter (
        .clk(clk), .reset_n(reset_n),
        .valid(echo_pending || config_pending || audio_pending),
        .data(echo_pending ? pending_echo_data :
              config_pending ? {2'b11, pending_config_data} :
              {2'b01, pending_audio_state, pending_audio_state}),
        .ready(ready), .tx(tx)
    );

    always @(posedge clk) begin
        if (!reset_n) begin
            pending_echo_data <= 0;
            pending_audio_state <= 0;
            pending_config_data <= 0;
            echo_pending <= 0;
            audio_pending <= 0;
            config_pending <= 0;
            echo_overflow <= 0;
        end else begin
            if (ready) begin
                if (echo_pending)
                    echo_pending <= 0;
                else if (config_pending)
                    config_pending <= 0;
                else if (audio_pending)
                    audio_pending <= 0;
            end
            if (echo_valid) begin
                if (echo_pending && !ready)
                    echo_overflow <= 1;
                else begin
                    pending_echo_data <= echo_data;
                    echo_pending <= 1;
                end
            end
            if (audio_valid) begin
                // A newer snapshot supersedes one waiting behind an echo.
                pending_audio_state <= audio_state;
                audio_pending <= 1;
            end
            if (config_valid) begin
                pending_config_data <= config_data;
                config_pending <= 1;
            end
        end
    end
endmodule
