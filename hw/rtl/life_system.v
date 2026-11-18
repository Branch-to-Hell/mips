/* CPU + data memory + MMIO + framebuffer on one bus (PLT-3)
Everything top_life needs except the PLL and the power-up reset,
so the testbench simulates exactly what runs on the board
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

mips_cpu #(.IMEM_INIT(IMEM_INIT)) cpu (
    .clk(clk), .reset(reset),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata)
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
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5)
);

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
