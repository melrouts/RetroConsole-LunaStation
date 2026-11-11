module button_debounce #(
    parameter int unsigned SYSTEM_CLK_HZ = 27_000_000,
    parameter int unsigned DEBOUNCE_MS = 20,
    parameter bit ACTIVE_LOW = 1'b1,
    parameter int unsigned STABLE_CYCLES =
        (SYSTEM_CLK_HZ * DEBOUNCE_MS + 999) / 1000,
    parameter int unsigned COUNTER_WIDTH =
        (STABLE_CYCLES > 1) ? $clog2(STABLE_CYCLES) : 1
) (
    input  logic clk,
    input  logic reset_n,
    input  logic button_raw,
    output logic held,
    output logic pressed,
    output logic released
);
    logic button_meta;
    logic button_sync;
    logic debounced_level;
    logic [COUNTER_WIDTH-1:0] stable_count;
    logic pressed_level;
    localparam logic [COUNTER_WIDTH-1:0] STABLE_COUNT_LIMIT =
        COUNTER_WIDTH'(STABLE_CYCLES - 1);

    assign pressed_level = ACTIVE_LOW ? ~button_sync : button_sync;
    assign held = debounced_level;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            button_meta <= ACTIVE_LOW;
            button_sync <= ACTIVE_LOW;
            debounced_level <= 1'b0;
            stable_count <= '0;
            pressed <= 1'b0;
            released <= 1'b0;
        end else begin
            button_meta <= button_raw;
            button_sync <= button_meta;
            pressed <= 1'b0;
            released <= 1'b0;

            if (pressed_level == debounced_level) begin
                stable_count <= '0;
            end else if (stable_count == STABLE_COUNT_LIMIT) begin
                debounced_level <= pressed_level;
                stable_count <= '0;
                pressed <= pressed_level;
                released <= ~pressed_level;
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end
endmodule
