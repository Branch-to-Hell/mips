`timescale 1ns/1ps
// CPU-2 integration test. Run from verif: do cpu2.do
/* The whole program is loaded into instruction memory before reset,
because the memory reads on the clock (one instruction ahead).
After each posedge, the register written by that instruction is checked
*/
module cpu2_tb;
reg clk=0, reset=1;
integer i, errors=0, n=0;

wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire mem_we, mem_re;
mips_cpu dut(
    .clk(clk), .reset(reset),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata)
);
data_memory dm(
    .clk(clk), .MemRead(mem_re), .MemWrite(mem_we), .ByteEnable(4'b1111),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(mem_rdata)
);
always #5 clk=~clk;

reg [4:0] target [0:31];
reg [31:0] expected [0:31];

task step(input [5:0] op, input [4:0] rs, rt, input [15:0] imm,
          input [4:0] tgt, input [31:0] exp);
begin
    dut.im.write_word(n, {op,rs,rt,imm});
    target[n] = tgt;
    expected[n] = exp;
    n=n+1;
end
endtask

initial begin
    #1;
    for(i=0;i<32;i=i+1) dut.rf.registers[i]=0;
    for(i=0;i<4096;i=i+1) dut.im.write_word(i, 0);
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

    @(posedge clk); #1; reset=0; // this edge loads the first instruction
    for(i=0;i<n;i=i+1) begin
        @(posedge clk); #1; // instruction i finished
        if(dut.rf.registers[target[i]] !== expected[i]) begin
            $display("FAIL instruction %0d: r%0d=%h expected=%h",i,target[i],dut.rf.registers[target[i]],expected[i]);
            errors=errors+1;
        end
    end
    if(errors) $fatal(1,"CPU-2: %0d errors",errors);
    $display("PASS: CPU-2 immediate, memory, alignment and zero-register tests");
    $finish;
end
endmodule
