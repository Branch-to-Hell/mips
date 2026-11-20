/* CPU-12: instruction memory with one byte per address, big-endian (contracts.md).
Bank k holds the bytes whose address has addr[1:0] = k, so for a word address:
    bank0 = mem[PC]    (bits 31..24, most significant)
    bank1 = mem[PC+1]  (bits 23..16)
    bank2 = mem[PC+2]  (bits 15..8)
    bank3 = mem[PC+3]  (bits 7..0, least significant)
The 4 banks are read in the same cycle and joined, so a fetch still takes one cycle.
*/
module instruction_memory #(
    // Image prefix: loads <INIT_FILE>_b0.hex .. <INIT_FILE>_b3.hex (one byte per line,
    // made by sw/tools/hex2banks.py). Empty = no init.
    parameter INIT_FILE = ""
)(
    input clk,
    input enable,
    input [31:0] Address, // next PC: the same value that goes into the PC register
    output reg [31:0] Instruction
);

// contracts.md: text region = 16 KB = 4 banks x 4,096 bytes
reg [7:0] bank0 [0:4095];
reg [7:0] bank1 [0:4095];
reg [7:0] bank2 [0:4095];
reg [7:0] bank3 [0:4095];

/* Address[1:0] picks the byte inside the word; fetches are word aligned,
so all 4 banks use the same row: Address[13:2].
The text base is 16 KB-aligned, so the row is the same for 0x0 and 0x00400000.
*/
wire [11:0] Row = Address[13:2];

/* Reading on the clock lets Quartus use the M9K blocks.
The address is the next PC, so right after the edge Instruction = mem[PC_out]..mem[PC_out+3]
*/
always @(posedge clk)
    if (enable) Instruction <= {bank0[Row], bank1[Row], bank2[Row], bank3[Row]};

initial begin
    if (INIT_FILE != "") begin
        $readmemh({INIT_FILE, "_b0.hex"}, bank0);
        $readmemh({INIT_FILE, "_b1.hex"}, bank1);
        $readmemh({INIT_FILE, "_b2.hex"}, bank2);
        $readmemh({INIT_FILE, "_b3.hex"}, bank3);
    end
end

// Simulation helpers so testbenches can write and read whole words (not hardware).
// synthesis translate_off
task write_word(input [11:0] index, input [31:0] word);
begin
    bank0[index] = word[31:24];
    bank1[index] = word[23:16];
    bank2[index] = word[15:8];
    bank3[index] = word[7:0];
end
endtask

function [31:0] read_word(input [11:0] index);
    read_word = {bank0[index], bank1[index], bank2[index], bank3[index]};
endfunction
// synthesis translate_on

endmodule
