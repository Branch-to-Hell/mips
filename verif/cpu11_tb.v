`timescale 1ns/1ps
// CPU-11: the professor's encodings add = funct 0x21, sub = funct 0x23, addi = opcode 0x09
// (the codes of addu subu addiu), and the old 0x20 0x22 0x08 still work.
// Runs the same program on the single-cycle mips_cpu and on mips_pipeline.
// Every instruction only reads preset registers, so the pipeline needs no hazard unit.
// Run from verif in ModelSim: do cpu11.do
module cpu11_tb;
reg clk = 0, reset = 1;
integer i, n = 0, errors = 0;
reg [4:0] dest [0:31];
reg [31:0] expected [0:31];
reg [8*16-1:0] name [0:31];

wire [31:0] sc_addr, sc_wdata, pl_addr, pl_wdata;
wire sc_we, sc_re, pl_we, pl_re;
mips_cpu sc(.clk(clk), .reset(reset), .mem_addr(sc_addr), .mem_wdata(sc_wdata),
    .mem_we(sc_we), .mem_re(sc_re), .mem_rdata(32'd0), .dbg_sel(5'd0), .dbg_value());
mips_pipeline pl(.clk(clk), .reset(reset), .mem_addr(pl_addr), .mem_wdata(pl_wdata),
    .mem_we(pl_we), .mem_re(pl_re), .mem_rdata(32'd0), .mem_fault(1'b0), .mem_stall(1'b0), .ifetch_addr(), .ifetch_req(), .ifetch_data(32'd0), .ifetch_ready(1'b0), .dbg_sel(5'd0), .dbg_value());
always #5 clk = ~clk;

// R-type: rs, rt, rd, funct. I-type: opcode, rs, rt, imm.
function [31:0] r_type(input [4:0] rs, rt, rd, input [5:0] funct);
    r_type = {6'h00, rs, rt, rd, 5'd0, funct};
endfunction
function [31:0] i_type(input [5:0] op, input [4:0] rs, rt, input [15:0] imm);
    i_type = {op, rs, rt, imm};
endfunction

task emit(input [8*16-1:0] label, input [31:0] insn, input [4:0] rd, input [31:0] value);
begin
    sc.im.write_word(n, insn);
    pl.if_id.im.write_word(n, insn);
    name[n] = label; dest[n] = rd; expected[n] = value;
    n = n + 1;
end
endtask

task check(input [8*8-1:0] cpu, input [31:0] got, input integer k);
begin
    if (got !== expected[k]) begin
        $display("FAIL  %0s %0s -> $%0d = %h (expected %h)", cpu, name[k], dest[k], got, expected[k]);
        errors = errors + 1;
    end else
        $display("ok    %0s %0s -> $%0d = %h", cpu, name[k], dest[k], got);
end
endtask

initial begin
    #1;
    for (i = 0; i < 4096; i = i + 1) begin sc.im.write_word(i, 0); pl.if_id.im.write_word(i, 0); end
    for (i = 0; i < 32; i = i + 1) begin sc.rf.registers[i] = 0; pl.rf.registers[i] = 0; end
    // $s1 = 10, $s2 = 3, $s4 = 0x7fffffff (overflow without an exception)
    sc.rf.registers[17] = 10;            pl.rf.registers[17] = 10;
    sc.rf.registers[18] = 3;             pl.rf.registers[18] = 3;
    sc.rf.registers[20] = 32'h7fffffff;  pl.rf.registers[20] = 32'h7fffffff;

    emit("add  0x20",  r_type(17, 18,  8, 6'h20),  8, 13);
    emit("add  0x21",  r_type(17, 18,  9, 6'h21),  9, 13);
    emit("sub  0x22",  r_type(17, 18, 10, 6'h22), 10, 7);
    emit("sub  0x23",  r_type(17, 18, 11, 6'h23), 11, 7);
    emit("addi 0x08",  i_type(6'h08, 17, 12, 16'hfffe), 12, 8);
    emit("addi 0x09",  i_type(6'h09, 17, 13, 16'hfffe), 13, 8);
    emit("add  0x21 ovf", r_type(20, 18, 14, 6'h21), 14, 32'h80000002);
    emit("sub  0x23 neg", r_type(18, 17, 15, 6'h23), 15, 32'hfffffff9);
    emit("addi 0x09 ovf", i_type(6'h09, 20, 24, 16'h0001), 24, 32'h80000000);
    emit("addi 0x09 $0",  i_type(6'h09, 18,  0, 16'h0005),  0, 0);

    @(posedge clk); #1;
    reset = 0;
    repeat (n + 8) @(posedge clk);
    #1;
    for (i = 0; i < n; i = i + 1) begin
        check("single", sc.rf.registers[dest[i]], i);
        check("pipeline", pl.rf.registers[dest[i]], i);
    end
    if (sc_we || pl_we) begin
        $display("FAIL  unexpected memory write");
        errors = errors + 1;
    end
    if (errors == 0) $display("PASS: CPU-11 professor's encodings (0x21 0x23 0x09) and old codes, %0d checks", 2 * n);
    else $fatal(1, "CPU-11: %0d errors", errors);
    $finish;
end
initial begin #5000; $fatal(1, "CPU-11 timeout"); end
endmodule
