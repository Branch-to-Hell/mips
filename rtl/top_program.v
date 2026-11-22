/* Top level for any program from our assembler (Quartus revision "program": TC-15, TC-12)
Same hardware as top_life (life_system with the pipelined CPU), but the program is picked
in quartus/program.qsf, so loading a new program never touches the Game of Life build:
    set_parameter -name PROGRAM "count_value_in1"   -> mem/count_value_in1_b0..b3.hex
    set_parameter -name WITH_DATA 1                 -> also mem/count_value_in1_data.hex
                                                       (0 if the program has no .data)
Steps: python src/assembler/assembler.py src/programs/<name>.asm, edit the two lines above,
compile the "program" revision, program the board.
Outputs as in top_life: SW9 up = register debug view (SW4-0 = register, SW5 = half),
CPU halt = LEDR9 + cause and HEX = E, cause, address (SW8 up = PC)
*/
module top_program #(
    parameter PROGRAM = "test_halt",
    parameter WITH_DATA = 0
)(
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

life_system #(.IMEM_INIT({"../mem/", PROGRAM}),                     // paths from quartus
              .DMEM_INIT(WITH_DATA ? {"../mem/", PROGRAM, "_data.hex"} : "")) sys (
    .clk(clk25), .reset(reset),
    .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

endmodule
