/* RAM for one region of the memory map (contracts.md)
The defaults are the data region (0x1001_0000, 16 KB). life_system also uses it for
the stack (PLT-13): BASE = 0x7FFF_E000, WORDS = 1024 (4 KB)
BASE must be aligned to the region size (WORDS * 4), so the low address bits are the word index

CPU-7: 4 byte-lane banks, like the instruction memory (CPU-12) and framebuffer_b, so every
byte has its own write enable for sb/sh. Big-endian: bank k holds the bytes with address[1:0] = k,
so bank 0 is bits 31..24 of the word. ByteEnable[3] = bank 0 (the CPU's mem_be); sw = 1111.
Loads always read the whole word; the CPU picks the byte or half.

INIT_FILE: prefix of the program's .data image in 4 lanes, <INIT_FILE>_b0.hex .. _b3.hex
(e.g. "../mem/tc16_trace_data" -> tc16_trace_data_b0.hex ...; one byte per line, line i = word i
from BASE), written by the assembler and elf2hex.py next to <name>_data.hex. Loaded with
$readmemh in ModelSim and as the M9K initial content in Quartus. Bytes the files don't cover
start at 0
*/
module data_memory #(
    parameter [31:0] BASE = 32'h1001_0000,
    parameter WORDS = 4096,                 // a power of 2
    parameter INIT_FILE = ""                // "" = all zeros
)(
    input clk,
    input MemRead,
    input MemWrite,
    input [3:0] ByteEnable,                 // [3] = bits 31..24; 4'b1111 for a word
    input [31:0] Address,
    input [31:0] WriteData,
    output [31:0] ReadData
);

localparam IW = $clog2(WORDS);              // word index width
localparam [31:0] SIZE = WORDS * 4;         // region size in bytes

reg [7:0] bank0 [0:WORDS-1];                // bits 31..24 (address[1:0] = 0)
reg [7:0] bank1 [0:WORDS-1];                // bits 23..16
reg [7:0] bank2 [0:WORDS-1];                // bits 15..8
reg [7:0] bank3 [0:WORDS-1];                // bits 7..0

integer i;
initial begin
    for (i = 0; i < WORDS; i = i + 1) begin
        bank0[i] = 8'd0;
        bank1[i] = 8'd0;
        bank2[i] = 8'd0;
        bank3[i] = 8'd0;
    end
    if (INIT_FILE != "") begin
        $readmemh({INIT_FILE, "_b0.hex"}, bank0);
        $readmemh({INIT_FILE, "_b1.hex"}, bank1);
        $readmemh({INIT_FILE, "_b2.hex"}, bank2);
        $readmemh({INIT_FILE, "_b3.hex"}, bank3);
    end
end

wire ValidAddress;
wire [IW-1:0] WordIndex;
/* Inside this region, and a word access is aligned: the single-cycle mips_cpu has no
alignment halt and relies on this to ignore a misaligned lw/sw. Bytes and halves are
checked by mips_pipeline itself (CPU-14) */
assign ValidAddress = (Address >= BASE) &&
                      (Address < BASE + SIZE) &&
                      (ByteEnable != 4'b1111 || Address[1:0] == 2'b00);
// BASE is aligned to SIZE, so these bits select the word within the region
assign WordIndex = Address[IW+1:2];
wire write = MemWrite && ValidAddress;

/* Reads and writes on negedge so Quartus uses the M9K blocks.
The ALU has the first half of the cycle to compute the address,
and the data is ready before the register file writes on posedge
*/
reg [31:0] q;
reg q_valid;
always @(negedge clk) begin
    if (write && ByteEnable[3]) bank0[WordIndex] <= WriteData[31:24];
    if (write && ByteEnable[2]) bank1[WordIndex] <= WriteData[23:16];
    if (write && ByteEnable[1]) bank2[WordIndex] <= WriteData[15:8];
    if (write && ByteEnable[0]) bank3[WordIndex] <= WriteData[7:0];
    q <= {bank0[WordIndex], bank1[WordIndex], bank2[WordIndex], bank3[WordIndex]};
    q_valid <= MemRead && ValidAddress;
end

// 0 when this region wasn't read, so the top level can OR every device's data
assign ReadData = q_valid ? q : 32'b0;

/* Word view for testbenches: word(i) = what a lw at BASE + 4i returns; write_word(i, w)
sets it at once (like an sw, without the bus) */
function [31:0] word(input integer index);
    word = {bank0[index], bank1[index], bank2[index], bank3[index]};
endfunction

task write_word(input integer index, input [31:0] value);
    begin
        bank0[index] = value[31:24];
        bank1[index] = value[23:16];
        bank2[index] = value[15:8];
        bank3[index] = value[7:0];
    end
endtask

endmodule
