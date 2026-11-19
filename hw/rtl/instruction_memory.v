module instruction_memory #(
    parameter INIT_FILE = ""  // .hex file for simulation; empty = no init
)(
    input clk,
    input enable, // synchronous read enable; holds the output when low
    input [31:0] Address, // next PC: the same value that goes into the PC register
    output reg [31:0] Instruction
);

reg [31:0] mem [0:4095]; // contracts.md: text region = 16 KB (4,096 instructions)
/* The PC has to be divided by 4 to go from "byte address" to "instruction number"; to do that, just drop the last two bits */
// The text base 0x00400000 is 16 KB-aligned (its low 14 bits are 0),
// so Address[13:2] is already the instruction number inside the region.
/* Reading on the clock lets Quartus use the M9K blocks. The address is the next PC, so right after the edge Instruction = mem[PC_out] */
always @(posedge clk) if (enable) Instruction <= mem[Address[13:2]];
initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
end
endmodule
