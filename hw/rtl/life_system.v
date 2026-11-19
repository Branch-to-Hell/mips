/* CPU + data memory + MMIO + framebuffer on one bus (PLT-3)
Everything top_life needs except the PLL and the power-up reset,
so the testbench simulates exactly what runs on the board
HEX debug view (PLT-4): with SW9 up the displays show a CPU register instead of
the program's HEX: SW4-0 = register, SW5 = half (0 = bits 15:0, 1 = bits 31:16).
The program still reads all the switches as usual
*/
module life_system #(
    parameter IMEM_INIT = "",
    parameter DEBOUNCE_CYCLES = 250_000  // 10 ms at 25 MHz; the testbench uses a small value
)(
    input clk,    // 25 MHz: CPU and VGA share the clock (contracts.md)
    input reset,

    input [9:0] SW,
    input [1:0] KEY,       // raw, active-low
    output [9:0] LEDR,
    output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output [3:0] VGA_R, VGA_G, VGA_B,
    output VGA_HS, VGA_VS
);

// CPU memory bus
wire [31:0] mem_addr, mem_wdata, mem_rdata, dm_rdata, mmio_rdata, fb_rdata;
wire mem_we, mem_re;
wire [7:0] io_hex0, io_hex1, io_hex2, io_hex3, io_hex4, io_hex5;  // the program's HEX (MMIO)

// Debug view: the register picked with SW4-0
wire [31:0] dbg_value;

mips_cpu #(.IMEM_INIT(IMEM_INIT)) cpu (
    .clk(clk), .reset(reset),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata),
    .dbg_sel(SW[4:0]), .dbg_value(dbg_value)
);

// Data and stack would go here; phase 1 only uses the data region
data_memory dm (
    .clk(clk), .MemRead(mem_re), .MemWrite(mem_we),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(dm_rdata)
);

mmio #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) io (
    .clk(clk), .reset(reset),
    .addr(mem_addr), .wdata(mem_wdata), .we(mem_we), .re(mem_re), .rdata(mmio_rdata),
    .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(io_hex0), .HEX1(io_hex1), .HEX2(io_hex2), .HEX3(io_hex3), .HEX4(io_hex4), .HEX5(io_hex5)
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

wire debug_view = SW[9];
assign HEX0 = debug_view ? dbg_hex0 : io_hex0;
assign HEX1 = debug_view ? dbg_hex1 : io_hex1;
assign HEX2 = debug_view ? dbg_hex2 : io_hex2;
assign HEX3 = debug_view ? dbg_hex3 : io_hex3;
assign HEX4 = debug_view ? dbg_hex4 : io_hex4;
assign HEX5 = debug_view ? dbg_hex5 : io_hex5;

/* Framebuffer mode A: 0x1004_0000 - 0x1004_BFFF (128x96 words)
Bits 15:14 = 11 would be 0x1004_C000 and up, outside the 12,288 pixels
*/
wire fb_sel = (mem_addr[31:16] == 16'h1004) && (mem_addr[15:14] != 2'b11);

/* The framebuffer always drives a_rdata, so it is gated here to keep the OR bus working
(registered on negedge like the read itself, the same way data_memory does it)
*/
reg fb_rd = 1'b0;
always @(negedge clk)
    fb_rd <= mem_re && fb_sel;

video_mode_a video (
    .clk(clk),
    .a_clk(clk), .a_we(mem_we && fb_sel), .a_addr(mem_addr[15:2]),
    .a_wdata(mem_wdata), .a_rdata(fb_rdata),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

// Each device returns 0 when it wasn't read, so the read bus is an OR
assign mem_rdata = dm_rdata | mmio_rdata | (fb_rd ? fb_rdata : 32'b0);

endmodule
