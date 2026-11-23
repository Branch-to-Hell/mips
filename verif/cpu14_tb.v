`timescale 1ns/1ps
// CPU-14: visible halt on mips_pipeline (contracts.md "Halt on invalid access").
// Seven programs, each one ends in a halt:
//   1 fetch outside the text region   2 misaligned fetch
//   3 lw to no region                 4 misaligned lw
//   5 sw to no region                 6 misaligned sw
//   7 an older bad lw (delay slot) reaches MEM after a younger bad fetch: the lw is reported
//   8 misaligned lh   9 misaligned sh   10 lb at an odd address is legal (CPU-7)
// For each: halted/halt_cause/halt_pc/halt_addr, the failing and younger instructions
// write nothing, older ones finish, the bus never touches a bad address, the PC and
// every register stay frozen while halted, and reset clears the halt.
// Run from verif in ModelSim: do cpu14.do
module cpu14_tb;
reg clk = 0, reset = 1;
wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire mem_we, mem_re;
wire [3:0] mem_be;
wire halted;
wire [1:0] halt_cause;
wire [31:0] halt_pc, halt_addr;
integer i, errors = 0, checks = 0;
reg [31:0] snapshot [0:31];
reg [31:0] frozen_pc;

// Testbench address decoder: only the data region exists (0x1001_0000 - 0x1001_3FFF).
wire in_data = (mem_addr[31:14] == 18'h0400_4);   // 0x1001_0000 >> 14
wire mem_fault = !in_data;

mips_pipeline dut(.clk(clk), .reset(reset), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_be(mem_be), .mem_rdata(mem_rdata), .dbg_sel(5'd0), .dbg_value(),
    .mem_fault(mem_fault), .mem_stall(1'b0), .ifetch_addr(), .ifetch_req(), .ifetch_data(32'd0), .ifetch_ready(1'b0), .halted(halted), .halt_cause(halt_cause),
    .halt_pc(halt_pc), .halt_addr(halt_addr));
data_memory dm(.clk(clk), .MemRead(mem_re), .MemWrite(mem_we), .ByteEnable(mem_be), .Address(mem_addr),
    .WriteData(mem_wdata), .ReadData(mem_rdata));
always #5 clk = ~clk;

// The bus must never reach a bad address: no region, or misaligned for the access size
// (word: be = 1111, half: 1100/0011, byte: one lane; CPU-7).
wire bus_misaligned = (mem_be == 4'b1111) ? (mem_addr[1:0] != 2'b00) :
                      (mem_be == 4'b1100 || mem_be == 4'b0011) ? mem_addr[0] : 1'b0;
always @(negedge clk)
    if ((mem_we || mem_re) && (mem_fault || bus_misaligned)) begin
        $display("FAIL  bus access to bad address %h (we=%b re=%b)", mem_addr, mem_we, mem_re);
        errors = errors + 1;
    end

function [31:0] r(input [4:0] rs, rt, rd, input [5:0] funct); r = {6'h00, rs, rt, rd, 5'd0, funct}; endfunction
function [31:0] i_t(input [5:0] op, input [4:0] rs, rt, input [15:0] imm); i_t = {op, rs, rt, imm}; endfunction
localparam [5:0] ADDI = 6'h08, LW = 6'h23, SW = 6'h2b, LB = 6'h20, LH = 6'h21, SH = 6'h29;
localparam [31:0] BAD = {ADDI, 5'd0, 5'd25, 16'h0bad};   // addi $t9, $zero, 0xbad: never runs
localparam [4:0] T0 = 8, T1 = 9, T2 = 10, T3 = 11, T4 = 12, T5 = 13, T6 = 14, T9 = 25, S1 = 17, S2 = 18;
task put(input integer index, input [31:0] word); dut.if_id.im.write_word(index, word); endtask
function [31:0] jr(input [4:0] rs); jr = {6'h00, rs, 15'd0, 6'h08}; endfunction

// Clear memory, preset registers, hold reset for two edges.
task start;
begin
    reset = 1;
    for (i = 0; i < 4096; i = i + 1) begin put(i, BAD); dm.write_word(i, 0); end
    @(posedge clk); #1;
    for (i = 0; i < 32; i = i + 1) dut.rf.registers[i] = 0;
    dut.rf.registers[S1] = 32'h1001_0000;   // data base
    dut.rf.registers[S2] = 32'h2000_0000;   // in no region
    dut.rf.registers[T2] = 32'h5555;        // a bad lw must not overwrite it
    dm.write_word(0, 32'h1234);
end
endtask

task expect_reg(input [4:0] n, input [31:0] value);
begin
    checks = checks + 1;
    if (dut.rf.registers[n] !== value) begin
        $display("FAIL  $%0d = %h, expected %h", n, dut.rf.registers[n], value);
        errors = errors + 1;
    end
end
endtask

// Release reset, wait for the halt, check the report, then check that nothing moves.
task run_and_check(input [8*24-1:0] name, input [1:0] cause, input [31:0] pc, input [31:0] addr);
    integer c;
begin
    @(posedge clk); #1;
    if (halted !== 1'b0 || halt_cause !== 2'd0) begin
        $display("FAIL  %0s: reset did not clear the halt", name); errors = errors + 1;
    end
    reset = 0;
    c = 0;
    while (halted !== 1'b1 && c < 100) begin @(posedge clk); #1; c = c + 1; end
    // A younger fetch fault may be replaced by an older access fault while draining.
    repeat (3) @(posedge clk);
    #1;
    checks = checks + 1;
    if (halted !== 1'b1 || halt_cause !== cause || halt_pc !== pc || halt_addr !== addr) begin
        $display("FAIL  %0s: halted=%b cause=%0d pc=%h addr=%h, expected cause=%0d pc=%h addr=%h",
            name, halted, halt_cause, halt_pc, halt_addr, cause, pc, addr);
        errors = errors + 1;
    end
    // Frozen: same fetch PC and registers for 20 more cycles.
    frozen_pc = dut.fetch_pc;
    for (i = 0; i < 32; i = i + 1) snapshot[i] = dut.rf.registers[i];
    repeat (20) @(posedge clk);
    #1;
    checks = checks + 1;
    if (dut.fetch_pc !== frozen_pc || halted !== 1'b1) begin
        $display("FAIL  %0s: PC moved while halted (%h -> %h)", name, frozen_pc, dut.fetch_pc);
        errors = errors + 1;
    end
    for (i = 0; i < 32; i = i + 1)
        if (dut.rf.registers[i] !== snapshot[i]) begin
            $display("FAIL  %0s: $%0d changed while halted", name, i); errors = errors + 1;
        end
    expect_reg(T9, 0);   // no BAD instruction ever ran
    $display("ok    %0s: cause %0d at PC %h, address %h", name, halt_cause, halt_pc, halt_addr);
end
endtask

initial begin
    #1;
    // 1: jr to 0x4050, outside the 16 KB text region (word 20 would alias to a BAD).
    start;
    put(0, i_t(ADDI, 0, T0, 16'h4050));
    put(1, jr(T0));
    put(2, i_t(ADDI, 0, T1, 16'd1));          // delay slot: older, runs
    run_and_check("fetch outside text", 2'd1, 32'h4050, 32'h4050);
    expect_reg(T1, 1);

    // 2: jr to a misaligned address.
    start;
    put(0, i_t(ADDI, 0, T0, 16'h0042));
    put(1, jr(T0));
    put(2, i_t(ADDI, 0, T1, 16'd1));
    run_and_check("misaligned fetch", 2'd1, 32'h0042, 32'h0042);
    expect_reg(T1, 1);

    // 3: lw from an address in no region.
    start;
    put(0, i_t(ADDI, 0, T5, 16'd7));          // older: runs
    put(1, i_t(LW, S2, T2, 16'd0));           // fails
    put(2, i_t(ADDI, 0, T4, 16'd9));          // younger (in EX): dropped
    put(3, i_t(ADDI, 0, T6, 16'd9));          // younger (in ID): dropped
    run_and_check("lw to no region", 2'd2, 32'h4, 32'h2000_0000);
    expect_reg(T5, 7); expect_reg(T2, 32'h5555); expect_reg(T4, 0); expect_reg(T6, 0);

    // 4: misaligned lw inside the data region (the decoder says valid, the CPU checks alignment).
    start;
    put(0, i_t(LW, S1, T2, 16'd2));
    put(1, i_t(ADDI, 0, T4, 16'd9));
    run_and_check("misaligned lw", 2'd2, 32'h0, 32'h1001_0002);
    expect_reg(T2, 32'h5555); expect_reg(T4, 0);

    // 5: sw to an address in no region (its data comes from the instruction before: a stall).
    start;
    put(0, i_t(ADDI, 0, T5, 16'd7));
    put(1, i_t(SW, S2, T5, 16'd0));
    put(2, i_t(ADDI, 0, T4, 16'd9));
    run_and_check("sw to no region", 2'd3, 32'h4, 32'h2000_0000);
    expect_reg(T5, 7); expect_reg(T4, 0);

    // 6: misaligned sw inside the data region: memory unchanged.
    start;
    put(0, i_t(ADDI, 0, T5, 16'd7));
    put(1, i_t(SW, S1, T5, 16'd1));
    put(2, i_t(ADDI, 0, T4, 16'd9));
    run_and_check("misaligned sw", 2'd3, 32'h4, 32'h1001_0001);
    checks = checks + 1;
    if (dm.word(0) !== 32'h1234) begin $display("FAIL  misaligned sw changed memory"); errors = errors + 1; end
    expect_reg(T4, 0);

    // 7: jr to a bad address with a bad lw in its delay slot. The bad fetch reaches ID while
    //    the lw is in EX (halt, cause 1), then the lw reaches MEM: it is older, so it wins.
    start;
    put(0, i_t(ADDI, 0, T0, 16'h4050));
    put(1, i_t(ADDI, 0, T3, 16'd0));
    put(2, jr(T0));
    put(3, i_t(LW, S2, T2, 16'd0));
    run_and_check("older lw beats fetch", 2'd2, 32'hC, 32'h2000_0000);
    expect_reg(T2, 32'h5555);

    // 8: misaligned lh (CPU-7: halves need addr[0] = 0).
    start;
    put(0, i_t(LH, S1, T2, 16'd1));
    put(1, i_t(ADDI, 0, T4, 16'd9));
    run_and_check("misaligned lh", 2'd2, 32'h0, 32'h1001_0001);
    expect_reg(T2, 32'h5555); expect_reg(T4, 0);

    // 9: misaligned sh: memory unchanged.
    start;
    put(0, i_t(ADDI, 0, T5, 16'd7));
    put(1, i_t(SH, S1, T5, 16'd3));
    put(2, i_t(ADDI, 0, T4, 16'd9));
    run_and_check("misaligned sh", 2'd3, 32'h4, 32'h1001_0003);
    checks = checks + 1;
    if (dm.word(0) !== 32'h1234) begin $display("FAIL  misaligned sh changed memory"); errors = errors + 1; end
    expect_reg(T4, 0);

    // 10: lb at an odd address does not halt; the lw after it to no region does.
    start;
    put(0, i_t(LB, S1, T3, 16'd3));
    put(1, i_t(LW, S2, T2, 16'd0));
    run_and_check("lb at odd address is ok", 2'd2, 32'h4, 32'h2000_0000);

    if (errors == 0) $display("PASS: CPU-14 visible halt, 10 cases, %0d checks", checks);
    else $fatal(1, "CPU-14: %0d errors", errors);
    $finish;
end
initial begin #100000; $fatal(1, "CPU-14 timeout"); end
endmodule
