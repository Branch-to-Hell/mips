`timescale 1ns/1ps
// CPU-6: branches and jumps resolved in ID with one delay slot, on mips_pipeline.
// Checks, cycle by cycle, the sequence of PCs that reach ID (the executed path)
// and, at the end, every register: delay slots run, skipped instructions never
// write, jal links PC + 8, jr follows any register.
// No hazard unit yet (CPU-5): every operand is preset or written >= 3 instructions
// before it is read.
// Run from verif in ModelSim: do cpu6.do
module cpu6_tb;
reg clk = 0, reset = 1;
wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire mem_we, mem_re;
integer i, k, errors = 0;
reg [31:0] expected_reg [0:31];
integer path [0:63];
integer path_len = 0;

mips_pipeline dut(.clk(clk), .reset(reset), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(32'd0), .mem_fault(1'b0), .mem_stall(1'b0), .ifetch_addr(), .ifetch_req(), .ifetch_data(32'd0), .ifetch_ready(1'b0), .dbg_sel(5'd0), .dbg_value());
always #5 clk = ~clk;

// Encoders (word index i lives at byte address 4 * i).
function [31:0] addi(input [4:0] rt, input [15:0] imm); addi = {6'h08, 5'd0, rt, imm}; endfunction
function [31:0] beq(input [4:0] rs, rt, input [15:0] off); beq = {6'h04, rs, rt, off}; endfunction
function [31:0] bne(input [4:0] rs, rt, input [15:0] off); bne = {6'h05, rs, rt, off}; endfunction
function [31:0] j_to(input [25:0] index); j_to = {6'h02, index}; endfunction
function [31:0] jal_to(input [25:0] index); jal_to = {6'h03, index}; endfunction
function [31:0] jr(input [4:0] rs); jr = {6'h00, rs, 15'd0, 6'h08}; endfunction
localparam [31:0] NOP = 32'h0000_0000;
localparam [31:0] BAD = {6'h08, 5'd0, 5'd9, 16'h0bad}; // addi $t1, $zero, 0xbad: must never run

task put(input integer index, input [31:0] word); dut.if_id.im.write_word(index, word); endtask
task step(input integer index); begin path[path_len] = index; path_len = path_len + 1; end endtask

initial begin
    #1;
    for (i = 0; i < 4096; i = i + 1) put(i, BAD);
    for (i = 0; i < 32; i = i + 1) begin dut.rf.registers[i] = 0; expected_reg[i] = 0; end
    dut.rf.registers[17] = 5;  expected_reg[17] = 5;     // $s1
    dut.rf.registers[18] = 5;  expected_reg[18] = 5;     // $s2
    dut.rf.registers[19] = 7;  expected_reg[19] = 7;     // $s3
    dut.rf.registers[20] = 88; expected_reg[20] = 88;    // $s4 = address of word 22 (jr target)
    expected_reg[29] = 32'h7fffeffc;                     // $sp after reset (contracts.md)

    // Branch offsets count words from the delay slot (branch index + 1).
    put(0,  beq(17, 18, 16'd3));     // taken -> 4
    put(1,  addi(8, 1));             //   delay slot runs
    // 2, 3: BAD (skipped)
    put(4,  bne(17, 18, 16'd5));     // not taken
    put(5,  addi(10, 2));            //   delay slot runs
    put(6,  addi(11, 3));            // fall-through runs
    put(7,  bne(17, 19, 16'd2));     // taken -> 10
    put(8,  addi(12, 4));            //   delay slot
    // 9: BAD
    put(10, beq(17, 19, 16'd5));     // not taken
    put(11, addi(13, 5));            //   delay slot
    put(12, j_to(26'd16));           // j -> 16
    put(13, addi(14, 6));            //   delay slot
    // 14, 15: BAD
    put(16, jal_to(26'd24));         // jal -> 24, $ra = 16*4 + 8 = 72 (word 18)
    put(17, addi(15, 7));            //   delay slot
    put(18, addi(24, 8));            // return point
    put(19, jr(20));                 // jr $s4 -> 22
    put(20, addi(25, 9));            //   delay slot
    // 21: BAD
    put(22, beq(0, 0, 16'd6));       // taken -> 29
    put(23, addi(21, 10));           //   delay slot
    put(24, addi(22, 11));           // subroutine
    put(25, addi(23, 12));
    put(26, addi(2, 13));
    put(27, jr(31));                 // jr $ra -> 18
    put(28, addi(3, 14));            //   delay slot
    put(29, j_to(26'd34));           // j -> 34
    put(30, addi(4, 15));            //   delay slot
    put(31, addi(5, 16));            // reached by the backward branch
    put(32, j_to(26'd37));           // j -> 37
    put(33, addi(6, 17));            //   delay slot
    put(34, beq(0, 0, 16'hfffc));    // backward: 35 - 4 = 31
    put(35, addi(7, 18));            //   delay slot
    // 36: BAD
    put(37, beq(0, 0, 16'hffff));    // end: branch to itself
    put(38, NOP);                    //   delay slot

    expected_reg[8] = 1;  expected_reg[10] = 2;  expected_reg[11] = 3;  expected_reg[12] = 4;
    expected_reg[13] = 5; expected_reg[14] = 6;  expected_reg[15] = 7;  expected_reg[24] = 8;
    expected_reg[25] = 9; expected_reg[21] = 10; expected_reg[22] = 11; expected_reg[23] = 12;
    expected_reg[2] = 13; expected_reg[3] = 14;  expected_reg[4] = 15;  expected_reg[5] = 16;
    expected_reg[6] = 17; expected_reg[7] = 18;  expected_reg[31] = 72;

    step(0);  step(1);  step(4);  step(5);  step(6);  step(7);  step(8);  step(10);
    step(11); step(12); step(13); step(16); step(17); step(24); step(25); step(26);
    step(27); step(28); step(18); step(19); step(20); step(22); step(23); step(29);
    step(30); step(34); step(35); step(31); step(32); step(33);
    for (k = 0; k < 4; k = k + 1) begin step(37); step(38); end

    @(posedge clk); #1;
    reset = 0;
    for (k = 0; k < path_len; k = k + 1) begin
        @(posedge clk); #1;
        if (dut.id_valid !== 1'b1 || dut.id_pc !== 4 * path[k]) begin
            $display("FAIL  step %0d: ID has PC %h (valid %b), expected word %0d (PC %h)",
                k, dut.id_pc, dut.id_valid, path[k], 4 * path[k]);
            errors = errors + 1;
        end
    end
    repeat (4) @(posedge clk);
    #1;
    for (i = 0; i < 32; i = i + 1)
        if (dut.rf.registers[i] !== expected_reg[i]) begin
            $display("FAIL  $%0d = %h, expected %h", i, dut.rf.registers[i], expected_reg[i]);
            errors = errors + 1;
        end
    if (mem_we || mem_re) begin $display("FAIL  unexpected memory access"); errors = errors + 1; end
    $display("ok    executed path of %0d instructions, %0d registers checked", path_len, 32);

    // Reset while a taken branch is in ID: fetch restarts at 0, no redirect wins.
    @(negedge clk);
    reset = 1;
    @(posedge clk); #1;
    if (dut.fetch_pc !== 32'h0 || dut.id_valid !== 1'b0) begin
        $display("FAIL  reset during a branch: fetch_pc = %h, id_valid = %b", dut.fetch_pc, dut.id_valid);
        errors = errors + 1;
    end
    reset = 0;
    @(posedge clk); #1;
    if (dut.id_pc !== 32'h0) begin $display("FAIL  restart after reset at PC %h", dut.id_pc); errors = errors + 1; end

    if (errors == 0) $display("PASS: CPU-6 branches/jumps in ID with one delay slot");
    else $fatal(1, "CPU-6: %0d errors", errors);
    $finish;
end
initial begin #5000; $fatal(1, "CPU-6 timeout"); end
endmodule
