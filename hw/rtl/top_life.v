/* Top level for PLT-3 / LIFE-5: Game of Life on the board with the single-cycle CPU
Runs hw/mem/life_board.hex (sw/programs/life_board.asm):
    KEY1 = run/pause, KEY0 = load the pattern chosen with SW5-4,
    SW3-0 = speed (15 fastest), LEDR0 = running, HEX = generation
Both keys go to software, so reset comes from power-up (and the PLL lock)
*/
module top_life (
    input MAX10_CLK1_50,
    input [9:0] SW,
    input [1:0] KEY,
    output [9:0] LEDR,
    output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output [3:0] VGA_R, VGA_G, VGA_B,
    output VGA_HS, VGA_VS
);

wire clk25, locked;
pll_25 pll (.inclk0(MAX10_CLK1_50), .c0(clk25), .locked(locked));

// Hold reset for 16 cycles after the PLL locks
reg [4:0] por = 0;
always @(posedge clk25)
    if (!locked) por <= 0;
    else if (!por[4]) por <= por + 1'b1;
wire reset = !por[4];

life_system #(.IMEM_INIT("../mem/life_board.hex")) sys ( // path from hw/quartus
    .clk(clk25), .reset(reset),
    .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

endmodule
