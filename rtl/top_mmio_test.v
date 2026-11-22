/* Top level for PLT-2: CPU + data memory + MMIO on the board
Runs mem/test_mmio_b0..b3.hex: LEDR mirrors SW, HEX counts KEY0 presses
Both keys go to software, so reset comes from power-up (and the PLL lock)
*/
module top_mmio_test (
    input MAX10_CLK1_50,
    input [9:0] SW,
    input [1:0] KEY,
    output [9:0] LEDR,
    output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
);

wire clk25, locked;
pll_25 pll (.inclk0(MAX10_CLK1_50), .c0(clk25), .locked(locked));

// Hold reset for 16 cycles after the PLL locks
reg [4:0] por = 0;
always @(posedge clk25)
    if (!locked) por <= 0;
    else if (!por[4]) por <= por + 1'b1;
wire reset = !por[4];

// CPU and memory bus
wire [31:0] mem_addr, mem_wdata, mem_rdata, dm_rdata, mmio_rdata;
wire mem_we, mem_re;

mips_cpu #(.IMEM_INIT("../mem/test_mmio")) cpu ( // path from quartus
    .clk(clk25), .reset(reset),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata)
);

data_memory dm (
    .clk(clk25), .MemRead(mem_re), .MemWrite(mem_we),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(dm_rdata)
);

mmio io (
    .clk(clk25), .reset(reset),
    .addr(mem_addr), .wdata(mem_wdata), .we(mem_we), .re(mem_re), .rdata(mmio_rdata),
    .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5)
);

/* Each device decodes its own address and returns 0 when it wasn't read,
so the read bus is an OR. top_life (PLT-3) adds the stack and framebuffer the same way
*/
assign mem_rdata = dm_rdata | mmio_rdata;

endmodule
