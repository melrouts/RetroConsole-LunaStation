`include "platform_config.vh"

module memory_map #(
    parameter integer MAIN_RAM_BYTES = `MAIN_RAM_BYTES,
    parameter RAM_INIT_FILE = "build/smoke.hex",
    parameter bit BOOT_ENABLE = 1'b0,
    parameter BOOT_INIT_FILE = "build/boot.hex"
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        mem_valid,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output reg         mem_ready,
    output reg  [31:0] mem_rdata,
    input  wire [3:0]  input_state,
    input  wire [7:0]  input_events,
    input  wire [31:0] video_status,
    input  wire [31:0] frame_count,
    input  wire        vblank_tick,
    output reg  [31:0] audio_control,
    output reg  [31:0] audio_period,
    output reg  [31:0] boot_status,
    output reg         bus_fault,
    output wire        sd_sck,
    output wire        sd_cs_n,
    output wire        sd_mosi,
    input wire         sd_miso,
    output wire        video_write,
    output wire        terrain_write,
    input wire [31:0]  video_read_data,
    output wire        uart_read,
    output wire        uart_write,
    input wire [31:0]  uart_read_data,
    output wire        audio_link_write,
    output wire        audio_config_write,
    input wire [31:0]  audio_link_status
);
    localparam integer RAM_WORDS = MAIN_RAM_BYTES / 4;
    localparam integer RAM_ADDR_BITS = $clog2(RAM_WORDS);
    reg [31:0] ram [0:RAM_WORDS-1];
    wire [RAM_ADDR_BITS-1:0] word_addr = mem_addr[RAM_ADDR_BITS+1:2];
    wire ram_selected = mem_addr < MAIN_RAM_BYTES;
    localparam integer BOOT_WORDS = BOOT_ENABLE ? `BOOT_RAM_BYTES / 4 : 1;
    localparam integer BOOT_ADDR_BITS = BOOT_ENABLE ? $clog2(BOOT_WORDS) : 1;
    reg [31:0] boot_ram [0:BOOT_WORDS-1];
    wire [BOOT_ADDR_BITS-1:0] boot_word = mem_addr[BOOT_ADDR_BITS+1:2];
    wire boot_selected = BOOT_ENABLE && mem_addr >= `BOOT_BASE &&
                         mem_addr - `BOOT_BASE < `BOOT_RAM_BYTES;
    wire mmio_selected = mem_addr[31:8] == 24'h800000;
    wire terrain_selected = mem_addr[31:12] == 20'h81000;
    wire [31:0] write_mask = {
        {8{mem_wstrb[3]}}, {8{mem_wstrb[2]}},
        {8{mem_wstrb[1]}}, {8{mem_wstrb[0]}}
    };
    reg [7:0] pending_events;
    reg pending_vblank;
    wire transaction = reset_n && mem_valid && !mem_ready;
    assign video_write = transaction && mmio_selected &&
                         mem_addr[7:5] == 3'b010 && (|mem_wstrb);
    assign terrain_write = transaction && terrain_selected && (|mem_wstrb);
    assign uart_read = transaction && mmio_selected && mem_addr[7:4] == 6 &&
                       !(|mem_wstrb);
    assign uart_write = transaction && mmio_selected && mem_addr[7:4] == 6 &&
                        mem_wstrb[0];
    assign audio_link_write = transaction && mmio_selected &&
                              mem_addr[7:0] == 8'h70 && mem_wstrb[0];
    assign audio_config_write = transaction && mmio_selected &&
                                mem_addr[7:0] == 8'h74 && mem_wstrb[0];
    wire clear_events = transaction && mmio_selected && mem_addr[7:0] == 8'h04;
    wire [7:0] event_clear_mask = clear_events && mem_wstrb[0] ? mem_wdata[7:0] : 8'b0;
    wire clear_vblank = transaction && mmio_selected && mem_addr[7:0] == 8'h18 &&
                        mem_wstrb[0] && mem_wdata[0];
    wire [31:0] sd_status;
    wire [7:0] sd_rx;
    reg [7:0] sd_tx;
    wire sd_command_valid = transaction && mmio_selected &&
                            mem_addr[7:0] == 8'h28 && mem_wstrb[0];
    generate if (BOOT_ENABLE) begin: sd_enabled
        sd_spi controller (
            .clk(clk), .reset_n(reset_n), .command_valid(sd_command_valid),
            .command(mem_wdata), .tx_data(sd_tx), .status(sd_status), .rx_data(sd_rx),
            .sck(sd_sck), .cs_n(sd_cs_n), .mosi(sd_mosi), .miso(sd_miso)
        );
    end else begin: sd_disabled
        assign sd_status = 0;
        assign sd_rx = 0;
        assign sd_sck = 0;
        assign sd_cs_n = 1;
        assign sd_mosi = 1;
        wire unused_sd_miso = sd_miso;
        wire unused_sd_command_valid = sd_command_valid;
        wire [7:0] unused_sd_tx = sd_tx;
    end endgenerate

    initial begin
        if (BOOT_ENABLE) begin
            for (integer word_index = 0; word_index < RAM_WORDS; word_index = word_index + 1)
                ram[word_index] = 0;
        end else begin
            $readmemh(RAM_INIT_FILE, ram);
        end
    end
    initial if (BOOT_ENABLE) $readmemh(BOOT_INIT_FILE, boot_ram);

    always @(posedge clk) begin
        if (transaction && ram_selected) begin
            mem_rdata <= ram[word_addr];
            for (integer lane = 0; lane < 4; lane = lane + 1)
                if (mem_wstrb[lane])
                    ram[word_addr][lane*8 +: 8] <= mem_wdata[lane*8 +: 8];
        end
        if (!reset_n) begin
            mem_ready <= 1'b0;
            pending_events <= 8'b0;
            pending_vblank <= 0;
            audio_control <= 32'b0;
            audio_period <= 32'b0;
            boot_status <= 32'b0;
            bus_fault <= 1'b0;
            sd_tx <= 0;
        end else begin
            mem_ready <= transaction;
            pending_events <= (pending_events & ~event_clear_mask) | input_events;
            pending_vblank <= (pending_vblank && !clear_vblank) || vblank_tick;
            if (transaction && !ram_selected) begin
                mem_rdata <= 32'b0;
                if (terrain_selected) begin
                    mem_rdata <= 0;
                end else if (boot_selected) begin
                    mem_rdata <= boot_ram[boot_word];
                    if (mem_addr - `BOOT_BASE >= `BOOT_CODE_BYTES) begin
                        for (integer lane = 0; lane < 4; lane = lane + 1)
                            if (mem_wstrb[lane])
                                boot_ram[boot_word][lane*8 +: 8] <= mem_wdata[lane*8 +: 8];
                    end else if (|mem_wstrb) begin
                        bus_fault <= 1;
                    end
                end else if (mmio_selected) begin
                    case (mem_addr[7:0])
                        8'h00: mem_rdata <= {28'b0, input_state};
                        8'h04: mem_rdata <= {24'b0, pending_events};
                        8'h08: begin
                            mem_rdata <= audio_control;
                            audio_control <= (audio_control & ~write_mask) |
                                             (mem_wdata & write_mask);
                        end
                        8'h0c: begin
                            mem_rdata <= audio_period;
                            audio_period <= (audio_period & ~write_mask) |
                                            (mem_wdata & write_mask);
                        end
                        8'h10: mem_rdata <= video_status;
                        8'h14: mem_rdata <= frame_count;
                        8'h18: mem_rdata <= {31'b0, pending_vblank};
                        8'h1c: mem_rdata <= `HARDWARE_VERSION;
                        8'h20: mem_rdata <= `ABI_VERSION;
                        8'h24: mem_rdata <= sd_status;
                        8'h2c: begin
                            mem_rdata <= {24'b0, sd_rx};
                            if (mem_wstrb[0])
                                sd_tx <= mem_wdata[7:0];
                        end
                        8'h30: begin
                            mem_rdata <= boot_status;
                            boot_status <= (boot_status & ~write_mask) |
                                           (mem_wdata & write_mask);
                        end
                        8'h40,8'h44,8'h48,8'h4c,8'h50,8'h54,8'h58,8'h5c:
                            mem_rdata <= video_read_data;
                        8'h60,8'h64,8'h68: mem_rdata <= uart_read_data;
                        8'h70: mem_rdata <= audio_link_status;
                        default: mem_rdata <= 32'b0;
                    endcase
                end else begin
                    mem_rdata <= 32'hbad00000;
                    bus_fault <= 1'b1;
                end
            end
        end
    end
endmodule
