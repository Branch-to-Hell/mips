/* PLT-11: top level for Doom (Quartus revision top_doom), docs/contracts.md "Doom memory"
    pll_sdram (25 MHz system + shifted DRAM_CLK)
    life_system (MODE_B = 1, EXT_BUS = 1): pipelined CPU, on-chip text with the boot code
        (mem/doom_boot, src/doom/boot.S), data/stack on chip, MMIO, timer, video modes A and B
    ext_memory: SDRAM bridge (PLT-8) + instruction cache (PLT-12) + arbiter
    sdram_sys (Platform Designer): SDRAM controller + JTAG to Avalon master (PLT-10)
On the board:
  1. Program the .sof. The CPU runs boot.S: it waits for KEY0.
  2. Load the image and the WAD over JTAG (System Console, src/tools/wad_load.tcl):
         wad_load build/doom/doom.bin 0          -> 0x2000_0000
         wad_load build/wad/doom1.wad            -> 0x2300_0000 (default offset 0x0300_0000)
  3. KEY0: boot.S jumps to Doom at 0x2000_0000.
Resets: the PLL lock resets everything. KEY1 resets the CPU side only (life_system and
ext_memory), never the SDRAM controller: resetting it stops the refresh and the SDRAM loses
the image and the WAD. After KEY1 the CPU is back in boot.S, waiting for KEY0 again.
*/
module top_doom (
    input MAX10_CLK1_50,
    input [9:0] SW,
    input [1:0] KEY,
    output [9:0] LEDR,
    output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output [3:0] VGA_R, VGA_G, VGA_B,
    output VGA_HS, VGA_VS,

    // SDRAM (ISSI IS42S16320D, 32M x 16)
    output [12:0] DRAM_ADDR,
    output [1:0] DRAM_BA,
    output DRAM_CAS_N, DRAM_RAS_N, DRAM_WE_N, DRAM_CS_N,
    output DRAM_CKE, DRAM_CLK,
    output DRAM_LDQM, DRAM_UDQM,
    inout [15:0] DRAM_DQ
);

wire clk, locked;
pll_sdram pll (.inclk0(MAX10_CLK1_50), .c0(clk), .c1(DRAM_CLK), .locked(locked));

// SDRAM controller reset: only until the PLL locks (+16 cycles)
reg [4:0] por = 0;
always @(posedge clk)
    if (!locked) por <= 0;
    else if (!por[4]) por <= por + 1'b1;
wire sdram_reset = !por[4];

// CPU reset: the same, or KEY1 (debounced; life_system's MMIO still sees the raw key too)
wire key1;
debounce db1 (.clk(clk), .key_n(KEY[1]), .pressed(key1));
reg [4:0] cpu_por = 0;
always @(posedge clk)
    if (sdram_reset || key1) cpu_por <= 0;
    else if (!cpu_por[4]) cpu_por <= cpu_por + 1'b1;
wire cpu_reset = !cpu_por[4];

// ---- CPU, on-chip memory, MMIO and video ----
wire [31:0] bus_addr, bus_wdata, ext_rdata, ifetch_addr, ifetch_next, ifetch_data;
wire [3:0] bus_be;
wire bus_we, bus_re, ext_sel, ext_stall, ifetch_req, ifetch_ready;

life_system #(.IMEM_INIT("../mem/doom_boot"), .MODE_B(1), .EXT_BUS(1)) sys ( // path from quartus
    .clk(clk), .reset(cpu_reset),
    .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
    .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we), .bus_re(bus_re), .bus_be(bus_be),
    .ext_sel(ext_sel), .ext_rdata(ext_rdata), .ext_stall(ext_stall),
    .ifetch_addr(ifetch_addr), .ifetch_req(ifetch_req), .ifetch_next(ifetch_next),
    .ifetch_data(ifetch_data), .ifetch_ready(ifetch_ready)
);

// ---- SDRAM side ----
wire [25:0] avm_address;
wire [31:0] avm_writedata, avm_readdata;
wire [3:0] avm_byteenable;
wire avm_read, avm_write, avm_readdatavalid, avm_waitrequest;

ext_memory xm (
    .clk(clk), .reset(cpu_reset),
    .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_be(bus_be), .bus_re(bus_re), .bus_we(bus_we),
    .ext_sel(ext_sel), .ext_rdata(ext_rdata), .ext_stall(ext_stall),
    .ifetch_addr(ifetch_addr), .ifetch_req(ifetch_req), .ifetch_next(ifetch_next),
    .ifetch_data(ifetch_data), .ifetch_ready(ifetch_ready),
    .avm_address(avm_address), .avm_read(avm_read), .avm_write(avm_write),
    .avm_writedata(avm_writedata), .avm_byteenable(avm_byteenable),
    .avm_readdata(avm_readdata), .avm_readdatavalid(avm_readdatavalid),
    .avm_waitrequest(avm_waitrequest)
);

sdram_sys sdram (
    .clk_clk(clk),
    .reset_reset_n(!sdram_reset),
    .mem_address(avm_address),
    .mem_read(avm_read),
    .mem_write(avm_write),
    .mem_writedata(avm_writedata),
    .mem_byteenable(avm_byteenable),
    .mem_burstcount(1'b1),
    .mem_debugaccess(1'b0),
    .mem_readdata(avm_readdata),
    .mem_readdatavalid(avm_readdatavalid),
    .mem_waitrequest(avm_waitrequest),
    .wire_addr(DRAM_ADDR),
    .wire_ba(DRAM_BA),
    .wire_cas_n(DRAM_CAS_N),
    .wire_ras_n(DRAM_RAS_N),
    .wire_we_n(DRAM_WE_N),
    .wire_cs_n(DRAM_CS_N),
    .wire_cke(DRAM_CKE),
    .wire_dq(DRAM_DQ),
    .wire_dqm({DRAM_UDQM, DRAM_LDQM})
);

endmodule
