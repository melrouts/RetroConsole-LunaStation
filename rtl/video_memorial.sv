module video_memorial (
    input wire clk, reset_n, frame_tick,
    input wire [3:0] state,
    input wire [9:0] x, y,
    output reg [8:0] text_address,
    output reg [2:0] glyph_row, glyph_column,
    output reg text_visible,
    output reg [1:0] photograph_pixel,
    output reg photograph_visible
);
    wire memorial = state == 7 || state == 8;
    reg [3:0] previous_state;
    reg [8:0] phase;
    reg [1:0] caption;
    reg [1:0] photographs [0:16383];
    initial begin
        $readmemh("build/memorial.hex", photographs);
    end
    wire [6:0] photo_x = x[8:2] - 7'd16;
    wire [5:0] photo_y = y[7:2] - 6'd24;
    always @(posedge clk) begin
        photograph_pixel <= photographs[{state == 8, photo_y, photo_x}];
        photograph_visible <= memorial && x >= 64 && x < 576 && y >= 96 && y < 352;
        if (!reset_n) begin
            previous_state <= 0; phase <= 0; caption <= 0;
        end else if (frame_tick) begin
            previous_state <= state;
            if (!memorial || state != previous_state) begin
                phase <= 0; caption <= 0;
            end else if (phase == 303) begin
                phase <= 0;
                caption <= caption == (state == 7 ? 1 : 2) ? 0 : caption + 1'b1;
            end else
                phase <= phase + 1'b1;
        end
    end
    reg [9:0] local_y;
    reg [1:0] item;
    reg [3:0] line_index;
    reg [4:0] column_index;
    always @* begin
        glyph_row = 0; glyph_column = x[3:1];
        text_visible = 0; local_y = 0; item = caption; line_index = 14; column_index = 0;
        if (memorial && x >= 64 && x < 576) begin
            column_index = x[8:4] - 5'd4;
            if (y >= 40 && y < 56) begin
                line_index = state == 7 ? 0 : 1;
                text_visible = 1; glyph_row = y[3:1] - 3'd4;
            end else if (y >= 368 && y < 432) begin
                local_y = y - 10'd384 + (phase >= 240 ? {1'b0, phase} - 10'd239 : 0);
                if (local_y >= 64) begin
                    local_y = local_y - 10'd64;
                    item = caption == (state == 7 ? 1 : 2) ? 0 : caption + 1'b1;
                end
                line_index = (state == 7 ? 4'd2 : 4'd6) + {1'b0, item, 1'b0} +
                             {3'b0, local_y[4]};
                text_visible = local_y < 32;
                glyph_row = local_y[3:1];
            end else if (y >= 456 && y < 464) begin
                line_index = state == 7 ? 12 : 13;
                glyph_column = x[2:0]; glyph_row = y[2:0];
                text_visible = x >= 192 && x < 448;
                column_index = x[7:3] - 5'd24;
            end
        end
        text_address = {line_index, column_index};
    end
endmodule
