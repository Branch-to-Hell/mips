/* CPU + data memory + MMIO + framebuffer on one bus (PLT-3)
Everything top_life needs except the PLL and the power-up reset,
so the testbench simulates exactly what runs on the board
LIFE-6: the CPU is the pipelined mips_pipeline (hazard unit, 1 delay slot). Programs come
from our assembler, which puts a nop in every delay slot, so they run as on the single-cycle CPU.
CPU-14 halt: the address decoder below sets mem_fault for an address in no region. A halted
CPU shows its error code (unless SW9 picks the debug view):
    LEDR9 = halted, LEDR1-0 = cause (1 = fetch, 2 = lw, 3 = sw)
    HEX5 = E, HEX4 = cause, HEX3-0 = bad address bits 15:0; SW8 up = HEX5-0 = PC bits 23:0
HEX debug view (PLT-4): with SW9 up the displays show a CPU register instead of
the program's HEX: SW4-0 = register, SW5 = half (0 = bits 15:0, 1 = bits 31:16).
The program still reads all the switches as usual
MODE_B = 1 adds video mode B (PLT-6) and the VIDEO_MODE switch; top_life leaves it
off so the Game of Life build doesn't spend 64 KB of M9K on it
*/
module life_system #(
    parameter IMEM_INIT = "",
    parameter DMEM_INIT = "",            // .data image prefix: "../mem/<name>_data" loads <name>_data_b0..b3.hex; "" = all zeros
    parameter DEBOUNCE_CYCLES = 250_000, // 10 ms at 25 MHz; the testbench uses a small value
    parameter CYCLES_PER_MS = 25_000,    // timer: 1 ms at 25 MHz; the testbench uses a small value
    parameter MODE_B = 0,                // 1 = include video mode B
    /* CPU-9: 1 = the SDRAM region (0x2000_0000 - 0x23FF_FFFF, contracts.md "Doom memory") is on the
    ext_* ports, for data and for instruction fetch, and ext_stall reaches the CPU's mem_stall.
    0 = no external memory (top_life, top_program): the region faults and nothing ever waits */
    parameter EXT_BUS = 0,
    parameter RESET_PC = 32'h0000_0000   // first fetch (0x2000_0000 to start in the SDRAM)
)(
    input clk,    // 25 MHz: CPU and VGA share the clock (contracts.md)
    input reset,

    input [9:0] SW,
    input [1:0] KEY,       // raw, active-low
    output [9:0] LEDR,
    output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output [3:0] VGA_R, VGA_G, VGA_B,
    output VGA_HS, VGA_VS,

    // CPU-9: external memory side (EXT_BUS = 1), for the SDRAM bridge and instruction cache
    output [31:0] bus_addr, bus_wdata,  // the CPU's data bus, as on its ports
    output bus_we, bus_re,
    output [3:0] bus_be,
    output ext_sel,                     // bus_addr is in the SDRAM region
    input [31:0] ext_rdata,             // 0 unless answering a read of the region
    input ext_stall,                    // the access in MEM isn't done (holds the CPU)
    output [31:0] ifetch_addr,
    output ifetch_req,
    input [31:0] ifetch_data,
    input ifetch_ready
);

// CPU memory bus
wire [31:0] mem_addr, mem_wdata, mem_rdata, dm_rdata, stack_rdata, mmio_rdata, fb_rdata;
wire video_mode;
wire mem_we, mem_re;
wire [3:0] mem_be;   // CPU-7 byte enables, [3] = bits 31..24 (big-endian)
wire [7:0] io_hex0, io_hex1, io_hex2, io_hex3, io_hex4, io_hex5;  // the program's HEX (MMIO)

// Debug view: the register picked with SW4-0
wire [31:0] dbg_value;

// CPU-14 halt outputs
wire halted;
wire [1:0] halt_cause;
wire [31:0] halt_pc, halt_addr;

/* Address decoder for CPU-14 (contracts.md "Memory map"): 1 = mem_addr is in no region.
It depends only on mem_addr; the CPU checks alignment itself
*/
wire data_sel  = (mem_addr[31:14] == 18'h0400_4);                     // 0x1001_0000 - 0x1001_3FFF
wire stack_sel = (mem_addr[31:12] == 20'h7FFF_E);                     // 0x7FFF_E000 - 0x7FFF_EFFF
wire mmio_sel  = (mem_addr >= 32'hFFFF_0010) && (mem_addr <= 32'hFFFF_0027);
wire fb_sel    = (mem_addr[31:16] == 16'h1004) && (mem_addr[15:14] != 2'b11); // mode A, see below
wire fbb_sel   = MODE_B && (mem_addr[31:16] == 16'h1005) && (mem_addr[15:0] < 16'hFA00);
wire pal_sel   = MODE_B && (mem_addr[31:10] == {16'h1005, 6'b111111});
/* CPU-7: framebuffer A and the palette store 12 bits per word (4 per color), so they only
take whole words: a byte or half access there halts too (store = cause 3, load = 2).
mem_be depends only on the instruction in MEM (size and address), so there is no loop */
wire word_only = (fb_sel || pal_sel) && mem_be != 4'b1111;
assign ext_sel = EXT_BUS && (mem_addr[31:26] == 6'b001000);              // 0x2000_0000 - 0x23FF_FFFF
wire mem_fault = !(data_sel || stack_sel || mmio_sel || fb_sel || fbb_sel || pal_sel || ext_sel) || word_only;
assign bus_addr = mem_addr;
assign bus_wdata = mem_wdata;
assign bus_we = mem_we;
assign bus_re = mem_re;
assign bus_be = mem_be;

mips_pipeline #(.IMEM_INIT(IMEM_INIT), .RESET_PC(RESET_PC), .EXT_TEXT(EXT_BUS)) cpu (
    .clk(clk), .reset(reset),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_be(mem_be), .mem_rdata(mem_rdata), .mem_fault(mem_fault),
    .mem_stall(EXT_BUS ? ext_stall : 1'b0),
    .ifetch_addr(ifetch_addr), .ifetch_req(ifetch_req),
    .ifetch_data(ifetch_data), .ifetch_ready(EXT_BUS ? ifetch_ready : 1'b0),
    .dbg_sel(SW[4:0]), .dbg_value(dbg_value),
    .halted(halted), .halt_cause(halt_cause), .halt_pc(halt_pc), .halt_addr(halt_addr)
);

// Data: 0x1001_0000 - 0x1001_3FFF (16 KB)
data_memory #(.INIT_FILE(DMEM_INIT)) dm (
    .clk(clk), .MemRead(mem_re), .MemWrite(mem_we), .ByteEnable(mem_be),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(dm_rdata)
);

// Stack (PLT-13): 0x7FFF_E000 - 0x7FFF_EFFF (4 KB); $sp starts at 0x7FFF_EFFC
data_memory #(.BASE(32'h7FFF_E000), .WORDS(1024)) stack (
    .clk(clk), .MemRead(mem_re), .MemWrite(mem_we), .ByteEnable(mem_be),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(stack_rdata)
);

wire [9:0] io_ledr;  // the program's LEDs (MMIO)
mmio #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES), .CYCLES_PER_MS(CYCLES_PER_MS)) io (
    .clk(clk), .reset(reset),
    .addr(mem_addr), .wdata(mem_wdata), .we(mem_we), .be(mem_be), .re(mem_re), .rdata(mmio_rdata),
    .SW(SW), .KEY(KEY), .LEDR(io_ledr),
    .HEX0(io_hex0), .HEX1(io_hex1), .HEX2(io_hex2), .HEX3(io_hex3), .HEX4(io_hex4), .HEX5(io_hex5),
    .video_mode(video_mode)
);

/* HEX debug view (PLT-4): SW9 up = show the register instead of the program's HEX.
The switches only drive the displays (no flip-flops), so they need no synchronizing
*/
wire [7:0] dbg_hex0, dbg_hex1, dbg_hex2, dbg_hex3, dbg_hex4, dbg_hex5;
hex_debug dbg (
    .reg_num(SW[4:0]), .half(SW[5]), .value(dbg_value),
    .HEX0(dbg_hex0), .HEX1(dbg_hex1), .HEX2(dbg_hex2),
    .HEX3(dbg_hex3), .HEX4(dbg_hex4), .HEX5(dbg_hex5)
);

/* Halt error code (CPU-14): E, cause, bad address bits 15:0; SW8 up = PC bits 23:0.
The segments are active-low with the decimal point off, like mmio.v
*/
wire [23:0] halt_shown = SW[8] ? halt_pc[23:0] : {4'hE, 2'b00, halt_cause, halt_addr[15:0]};
wire [6:0] err_seg0, err_seg1, err_seg2, err_seg3, err_seg4, err_seg5;
hex7seg err0(.value(halt_shown[3:0]),   .seg(err_seg0));
hex7seg err1(.value(halt_shown[7:4]),   .seg(err_seg1));
hex7seg err2(.value(halt_shown[11:8]),  .seg(err_seg2));
hex7seg err3(.value(halt_shown[15:12]), .seg(err_seg3));
hex7seg err4(.value(halt_shown[19:16]), .seg(err_seg4));
hex7seg err5(.value(halt_shown[23:20]), .seg(err_seg5));

// Priority: SW9 debug view, then the halt error code, then the program's outputs
wire debug_view = SW[9];
wire show_halt = halted && !debug_view;
assign HEX0 = debug_view ? dbg_hex0 : show_halt ? {1'b1, err_seg0} : io_hex0;
assign HEX1 = debug_view ? dbg_hex1 : show_halt ? {1'b1, err_seg1} : io_hex1;
assign HEX2 = debug_view ? dbg_hex2 : show_halt ? {1'b1, err_seg2} : io_hex2;
assign HEX3 = debug_view ? dbg_hex3 : show_halt ? {1'b1, err_seg3} : io_hex3;
assign HEX4 = debug_view ? dbg_hex4 : show_halt ? {1'b1, err_seg4} : io_hex4;
assign HEX5 = debug_view ? dbg_hex5 : show_halt ? {1'b1, err_seg5} : io_hex5;
assign LEDR = halted ? {1'b1, 7'b0, halt_cause} : io_ledr;

/* Framebuffer mode A: 0x1004_0000 - 0x1004_BFFF (128x96 words)
Bits 15:14 = 11 would be 0x1004_C000 and up, outside the 12,288 pixels (fb_sel is above)
*/

/* The framebuffer always drives a_rdata, so it is gated here to keep the OR bus working
(registered on negedge like the read itself, the same way data_memory does it)
*/
reg fb_rd = 1'b0;
always @(negedge clk)
    fb_rd <= mem_re && fb_sel;

wire [3:0] a_r, a_g, a_b;
wire a_hs, a_vs;
video_mode_a video (
    .clk(clk),
    .a_clk(clk), .a_we(mem_we && fb_sel), .a_addr(mem_addr[15:2]),
    .a_wdata(mem_wdata), .a_rdata(fb_rdata),
    .VGA_R(a_r), .VGA_G(a_g), .VGA_B(a_b), .VGA_HS(a_hs), .VGA_VS(a_vs)
);

/* Video mode B (PLT-6), only when MODE_B = 1:
    pixels  0x1005_0000 - 0x1005_F9FF  (320x200 bytes, 4 pixels per word, big-endian)
    palette 0x1005_FC00 - 0x1005_FFFF  (256 words 0x00RRGGBB)
Both modes run all the time from the same clock; VIDEO_MODE picks which one reaches
the monitor. Both have their own vga_sync starting at 0, so their timing is the same
*/
wire [31:0] fbb_rdata, pal_rdata;
wire [3:0] b_r, b_g, b_b;
wire b_hs, b_vs;
reg fbb_rd = 1'b0, pal_rd = 1'b0;
generate
if (MODE_B) begin : mode_b
    // fbb_sel and pal_sel are in the address decoder above
    always @(negedge clk) begin
        fbb_rd <= mem_re && fbb_sel;
        pal_rd <= mem_re && pal_sel;
    end

    video_mode_b video_b (
        .clk(clk), .a_clk(clk),
        .fb_we(mem_we && fbb_sel), .fb_be(mem_be), .fb_addr(mem_addr[15:2]),
        .fb_wdata(mem_wdata), .fb_rdata(fbb_rdata),
        .pal_we(mem_we && pal_sel), .pal_addr(mem_addr[9:2]),
        .pal_wdata(mem_wdata), .pal_rdata(pal_rdata),
        .VGA_R(b_r), .VGA_G(b_g), .VGA_B(b_b), .VGA_HS(b_hs), .VGA_VS(b_vs)
    );
end else begin : no_mode_b
    assign fbb_rdata = 32'b0;
    assign pal_rdata = 32'b0;
    assign {b_r, b_g, b_b} = 12'b0;
    assign {b_hs, b_vs} = 2'b11;
end
endgenerate

wire show_b = MODE_B && video_mode;
assign VGA_R = show_b ? b_r : a_r;
assign VGA_G = show_b ? b_g : a_g;
assign VGA_B = show_b ? b_b : a_b;
assign VGA_HS = show_b ? b_hs : a_hs;
assign VGA_VS = show_b ? b_vs : a_vs;

// Each device returns 0 when it wasn't read, so the read bus is an OR
assign mem_rdata = dm_rdata | stack_rdata | mmio_rdata | (fb_rd ? fb_rdata : 32'b0) | (EXT_BUS ? ext_rdata : 32'b0)
                 | (fbb_rd ? fbb_rdata : 32'b0) | (pal_rd ? pal_rdata : 32'b0);

endmodule
