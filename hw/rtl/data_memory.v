/* Word-organized RAM for one region of the memory map (contracts.md)
The defaults are the data region (0x1001_0000, 16 KB). life_system also uses it for
the stack (PLT-13): BASE = 0x7FFF_E000, WORDS = 1024 (4 KB)
BASE must be aligned to the region size (WORDS * 4), so the low address bits are the word index
*/
module data_memory #(
    parameter [31:0] BASE = 32'h1001_0000,
    parameter WORDS = 4096                  // a power of 2
)(
    input clk,
    input MemRead,
    input MemWrite,
    input [31:0] Address,
    input [31:0] WriteData,
    output [31:0] ReadData
);

localparam IW = $clog2(WORDS);              // word index width
localparam [31:0] SIZE = WORDS * 4;         // region size in bytes

reg [31:0] mem [0:WORDS-1];

// Only aligned accesses inside this region are supported
wire ValidAddress;
wire [IW-1:0] WordIndex;
assign ValidAddress = (Address >= BASE) &&
                      (Address < BASE + SIZE) &&
                      (Address[1:0] == 2'b00);
// BASE is aligned to SIZE, so these bits select the word within the region
assign WordIndex = Address[IW+1:2];

/* Reads and writes on negedge so Quartus uses the M9K blocks.
The ALU has the first half of the cycle to compute the address,
and the data is ready before the register file writes on posedge
*/
reg [31:0] q;
reg q_valid;
always @(negedge clk) begin
    if (MemWrite && ValidAddress)
        mem[WordIndex] <= WriteData;
    q <= mem[WordIndex];
    q_valid <= MemRead && ValidAddress;
end

// 0 when this region wasn't read, so the top level can OR every device's data
assign ReadData = q_valid ? q : 32'b0;

endmodule
