module picorv32_wrapper #(
    parameter [31:0] RESET_ADDRESS = 32'h00000000
) (
    input  wire        clk,
    input  wire        reset_n,
    output wire        trap,
    output wire        mem_valid,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_wstrb,
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata
);
    wire unused_mem_instr, unused_mem_la_read, unused_mem_la_write;
    wire [31:0] unused_mem_la_addr, unused_mem_la_wdata;
    wire [3:0] unused_mem_la_wstrb;
    wire unused_pcpi_valid, unused_trace_valid;
    wire [31:0] unused_pcpi_insn, unused_pcpi_rs1, unused_pcpi_rs2, unused_eoi;
    wire [35:0] unused_trace_data;

    picorv32 #(
        .ENABLE_REGS_DUALPORT(1),
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_MUL(0),
        .ENABLE_FAST_MUL(0),
        .ENABLE_DIV(0),
        .BARREL_SHIFTER(0),
        .TWO_CYCLE_ALU(0),
        .COMPRESSED_ISA(0),
        .ENABLE_IRQ(0),
        .ENABLE_PCPI(0),
        .PROGADDR_RESET(RESET_ADDRESS)
    ) cpu (
        .clk(clk),
        .resetn(reset_n),
        .trap(trap),
        .mem_valid(mem_valid),
        .mem_instr(unused_mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read(unused_mem_la_read),
        .mem_la_write(unused_mem_la_write),
        .mem_la_addr(unused_mem_la_addr),
        .mem_la_wdata(unused_mem_la_wdata),
        .mem_la_wstrb(unused_mem_la_wstrb),
        .pcpi_valid(unused_pcpi_valid),
        .pcpi_insn(unused_pcpi_insn),
        .pcpi_rs1(unused_pcpi_rs1),
        .pcpi_rs2(unused_pcpi_rs2),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'b0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
        .irq(32'b0),
        .eoi(unused_eoi),
        .trace_valid(unused_trace_valid),
        .trace_data(unused_trace_data)
    );
endmodule
