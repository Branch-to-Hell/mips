`timescale 1ns/1ps
// CPU-12 test: byte-per-address, big-endian instruction memory. Run from hw/sim: do instruction_memory.do
/* Loads life_board through the 4 bank files and checks every instruction against
the two other images of the same program:
  - life_board.hex        one 32-bit word per line (assembler output)
  - life_board_bytes.hex  one byte per address, big-endian (the professor's image)
For each fetch: the 4 bytes mem[PC]..mem[PC+3], the joined word, and that the
word only changes on the clock edge.
*/
module instruction_memory_tb;
localparam N = 232; // instructions in life_board.hex

reg clk = 0;
reg [31:0] Address = 0;
wire [31:0] Instruction;
instruction_memory #(.INIT_FILE("../mem/life_board")) dut(.clk(clk), .Address(Address), .Instruction(Instruction));
always #5 clk = ~clk;

reg [31:0] words [0:4095];
reg [7:0] image [0:16383];
reg [7:0] b [0:3];
integer i, k, errors = 0, fetches = 0;

task fail(input [8*64-1:0] what, input [31:0] pc, input [31:0] got, input [31:0] exp);
begin
    $display("FAIL  %0s at PC %h: got %h, expected %h", what, pc, got, exp);
    errors = errors + 1;
end
endtask

// Present the next PC, wait for the edge, then check what came out.
task fetch(input [31:0] pc, input show);
begin
    @(negedge clk);
    Address = pc;
    for (k = 0; k < 4; k = k + 1) b[k] = image[pc[13:0] + k];
    @(posedge clk); #1;
    fetches = fetches + 1;
    if (Instruction !== {b[0], b[1], b[2], b[3]}) fail("word vs byte image", pc, Instruction, {b[0], b[1], b[2], b[3]});
    if (Instruction !== words[pc[13:2]]) fail("word vs word image", pc, Instruction, words[pc[13:2]]);
    if (dut.bank0[pc[13:2]] !== b[0]) fail("bank0 = mem[PC]", pc, dut.bank0[pc[13:2]], b[0]);
    if (dut.bank1[pc[13:2]] !== b[1]) fail("bank1 = mem[PC+1]", pc, dut.bank1[pc[13:2]], b[1]);
    if (dut.bank2[pc[13:2]] !== b[2]) fail("bank2 = mem[PC+2]", pc, dut.bank2[pc[13:2]], b[2]);
    if (dut.bank3[pc[13:2]] !== b[3]) fail("bank3 = mem[PC+3]", pc, dut.bank3[pc[13:2]], b[3]);
    if (show)
        $display("ok    PC %h: mem[PC..PC+3] = %h %h %h %h -> Instruction %h",
            pc, b[0], b[1], b[2], b[3], Instruction);
end
endtask

initial begin
    for (i = 0; i < 4096; i = i + 1) words[i] = 32'hx;
    $readmemh("../mem/life_board.hex", words);
    $readmemh("../mem/life_board_bytes.hex", image);
    if (words[N - 1] === 32'hx || words[N] !== 32'hx) $fatal(1, "life_board.hex should have %0d words", N);

    // Every instruction of the program, text base 0 (CPU-13) and MARS base 0x00400000.
    for (i = 0; i < N; i = i + 1) fetch(32'h0000_0000 + 4 * i, i < 3);
    for (i = 0; i < N; i = i + 1) fetch(32'h0040_0000 + 4 * i, i < 1);

    // Synchronous read: a new address doesn't change Instruction before the edge.
    fetch(32'h0000_0000, 0);
    @(negedge clk); Address = 32'h0000_0004; #2;
    if (Instruction !== words[0]) fail("changed before the clock edge", 32'h4, Instruction, words[0]);
    @(posedge clk); #1;
    if (Instruction !== words[1]) fail("not updated on the clock edge", 32'h4, Instruction, words[1]);
    else $display("ok    Instruction only changes on the clock edge");

    // Simulation helpers used by the other testbenches.
    dut.write_word(12'd4095, 32'h2408_0005);
    if (dut.bank0[4095] !== 8'h24 || dut.bank1[4095] !== 8'h08 || dut.bank2[4095] !== 8'h00 || dut.bank3[4095] !== 8'h05)
        fail("write_word big-endian split", 32'h3ffc, {dut.bank0[4095], dut.bank1[4095], dut.bank2[4095], dut.bank3[4095]}, 32'h24080005);
    if (dut.read_word(12'd4095) !== 32'h2408_0005) fail("read_word", 32'h3ffc, dut.read_word(12'd4095), 32'h24080005);
    else $display("ok    write_word/read_word: addiu $t0, $zero, 5 -> bytes 24 08 00 05");

    if (errors) $fatal(1, "CPU-12: %0d errors", errors);
    $display("PASS: CPU-12 byte-per-address big-endian fetch, %0d fetches", fetches);
    $finish;
end
initial begin #100000; $fatal(1, "CPU-12 timeout"); end
endmodule
