module video_snapshot (
    input wire clk,
    input wire reset_n,
    input wire write_valid,
    input wire [2:0] write_index,
    input wire [31:0] write_data,
    input wire [3:0] write_strobes,
    output wire [31:0] read_data,
    input wire terrain_write,
    input wire [9:0] terrain_index,
    output wire busy,
    output reg error,
    input wire pixel_clk,
    input wire pixel_reset_n,
    input wire vblank_start,
    input wire [9:0] pixel_x,
    output reg [9:0] terrain_height,
    output reg [223:0] snapshot
);
    reg [31:0] shadow [0:6];
    reg [223:0] pending;
    reg request;
    reg acknowledge;
    (* async_reg = "true" *) reg [1:0] request_sync;
    (* async_reg = "true" *) reg [1:0] acknowledge_sync;
    reg terrain_dirty, committed_bank, pending_bank, active_bank;
    reg [9:0] terrain [0:2047];
    wire [31:0] mask = {{8{write_strobes[3]}}, {8{write_strobes[2]}},
                        {8{write_strobes[1]}}, {8{write_strobes[0]}}};
    wire commit = write_valid && write_index == 7 && write_strobes[0] && write_data[0];
    assign busy = request != acknowledge_sync[1];
    assign read_data = write_index == 7 ? {30'b0, error, busy} : shadow[write_index];
    initial begin
        for (integer index = 0; index < 2048; index = index + 1)
            terrain[index] = 10'd479;
    end
    // The pending bundle stays unchanged until the vblank acknowledgement crosses back.
    always @(posedge clk) begin
        if (!reset_n) begin
            for (integer index = 0; index < 7; index = index + 1)
                shadow[index] <= 0;
            pending <= 0;
            request <= 0;
            acknowledge_sync <= 0;
            terrain_dirty <= 0;
            committed_bank <= 0;
            pending_bank <= 0;
            error <= 0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[0], acknowledge};
            if (write_valid && write_index < 7)
                shadow[write_index] <= (shadow[write_index] & ~mask) | (write_data & mask);
            if (terrain_write) begin
                if (busy || terrain_index >= 640 || !write_strobes[0] || !write_strobes[1] ||
                    write_data[31:10] != 0) begin
                    error <= 1;
                end else begin
                    terrain_dirty <= 1;
                end
            end
            if (commit) begin
                if (busy) begin
                    error <= 1;
                end else begin
                    for (integer index = 0; index < 7; index = index + 1)
                        pending[index*32 +: 32] <= shadow[index];
                    pending_bank <= terrain_dirty ? !committed_bank : committed_bank;
                    committed_bank <= terrain_dirty ? !committed_bank : committed_bank;
                    terrain_dirty <= 0;
                    request <= !request;
                end
            end
        end
    end
    always @(posedge clk) begin
        if (reset_n && terrain_write && !busy && terrain_index < 640 &&
            write_strobes[0] && write_strobes[1] && write_data[31:10] == 0)
            terrain[{!committed_bank, terrain_index}] <= write_data[9:0];
    end
    always @(posedge pixel_clk) begin
        if (!pixel_reset_n) begin
            request_sync <= 0;
            acknowledge <= 0;
            active_bank <= 0;
            snapshot <= 0;
        end else begin
            request_sync <= {request_sync[0], request};
            if (vblank_start && request_sync[1] != acknowledge) begin
                snapshot <= pending;
                active_bank <= pending_bank;
                acknowledge <= request_sync[1];
            end
        end
        terrain_height <= terrain[{active_bank, pixel_x}];
    end
endmodule
