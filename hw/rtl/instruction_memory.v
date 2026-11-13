module instruction_memory #(
    parameter INIT_FILE = ""  // .hex file for simulation; empty = no init
)(
    input  [31:0] Address,
    output [31:0] Instruction
);

reg [31:0] mem [0:4095]; // contracts.md: text region = 16 KB (4,096 instructions)
/* The PC has to be divided by 4 to go from
"byte address" to "instruction number";
to do that, just drop the last two bits
*/
// The text base 0x00400000 is 16 KB-aligned (its low 14 bits are 0),
// so Address[13:2] is already the instruction number inside the region.
assign Instruction = mem[Address[13:2]];

initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
end

endmodule