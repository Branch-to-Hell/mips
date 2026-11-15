`timescale 1ns/1ps
// CPU-2 integration test. Run from hw/sim: do cpu2.do
// Instruction/register RAM is initialized here to isolate CPU execution.
module cpu2_tb;
reg clk=0, reset=1;
integer i, errors=0, n=0;
mips_cpu dut(.clk(clk), .reset(reset));
always #5 clk=~clk;

task step(input [5:0] op, input [4:0] rs, rt, input [15:0] imm,
          input [4:0] target, input [31:0] expected);
begin
    dut.im.mem[n] = {op,rs,rt,imm};
    @(negedge clk); #1;
    if(dut.rf.registers[target] !== expected) begin
        $display("FAIL instruction %0d: r%0d=%h expected=%h",n,target,dut.rf.registers[target],expected);
        errors=errors+1;
    end
    n=n+1;
    @(posedge clk); #1;
end
endtask

initial begin
    #1;
    for(i=0;i<32;i=i+1) dut.rf.registers[i]=0;
    for(i=0;i<4096;i=i+1) dut.im.mem[i]=0;
    @(posedge clk); #1; reset=0;
    step(6'h08,0,8,16'hffff,8,32'hffffffff); // addi -1
    step(6'h0c,8,9,16'hffff,9,32'h0000ffff); // andi zero extension
    step(6'h0d,0,10,16'h8000,10,32'h00008000); // ori zero extension
    step(6'h0a,8,11,0,11,1); // signed slti
    step(6'h0a,8,11,16'hffff,11,0); // equality
    step(6'h0f,0,12,16'h8000,12,32'h80000000); // lui
    step(6'h0f,0,16,16'h1001,16,32'h10010000); // data base
    step(6'h2b,16,8,0,8,32'hffffffff); // sw preserves source
    step(6'h23,16,13,0,13,32'hffffffff); // lw
    step(6'h08,16,17,4,17,32'h10010004);
    step(6'h2b,17,10,0,10,32'h8000);
    step(6'h23,17,14,16'hfffc,14,32'hffffffff); // negative offset
    step(6'h23,16,15,4,15,32'h8000); // separate word
    step(6'h08,0,0,123,0,0); // zero register protection
    // Invalid region and unaligned writes must not alias valid RAM.
    step(6'h2b,0,10,0,10,32'h8000);
    step(6'h2b,16,10,1,10,32'h8000);
    step(6'h23,16,13,0,13,32'hffffffff);
    if(errors) $fatal(1,"CPU-2: %0d errors",errors);
    $display("PASS: CPU-2 immediate, memory, alignment and zero-register tests");
    $finish;
end
endmodule
