`timescale 1ns/1ps
// CPU-5: hazard detection unit on mips_pipeline. Back-to-back dependencies with NO nops
// (only the delay slots hold a nop): RAW at distance 1 and 2, chains, store data, load-use,
// load -> store, load -> base address, branch after lw and after an ALU result, jr right
// after its address is computed. Also checks that there are no false stalls ($zero, the rt
// destination of I-type instructions, independent instructions).
// Checks the final registers and memory, and the exact number of stall cycles (21).
// Run from hw/sim in ModelSim: do cpu5.do
module cpu5_tb;
reg clk = 0, reset = 1;
wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire mem_we, mem_re;
integer i, errors = 0, stalls = 0, cycles = 0;
reg [31:0] expected_reg [0:31];
localparam EXPECTED_STALLS = 21;

mips_pipeline dut(.clk(clk), .reset(reset), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata), .dbg_sel(5'd0), .dbg_value());
data_memory dm(.clk(clk), .MemRead(mem_re), .MemWrite(mem_we), .Address(mem_addr),
    .WriteData(mem_wdata), .ReadData(mem_rdata));
always #5 clk = ~clk;

function [31:0] r(input [4:0] rs, rt, rd, input [5:0] funct); r = {6'h00, rs, rt, rd, 5'd0, funct}; endfunction
function [31:0] i_t(input [5:0] op, input [4:0] rs, rt, input [15:0] imm); i_t = {op, rs, rt, imm}; endfunction
localparam [5:0] ADD = 6'h20, ADDI = 6'h08, LW = 6'h23, SW = 6'h2b, BEQ = 6'h04, BNE = 6'h05, JR = 6'h08;
localparam [31:0] NOP = 32'h0000_0000;
localparam [31:0] BAD = {ADDI, 5'd0, 5'd25, 16'h0bad};   // addi $t9, $zero, 0xbad: skipped
task put(input integer index, input [31:0] word); dut.if_id.im.write_word(index, word); endtask

initial begin
    #1;
    for (i = 0; i < 4096; i = i + 1) begin put(i, BAD); dm.mem[i] = 0; end
    for (i = 0; i < 32; i = i + 1) begin dut.rf.registers[i] = 0; expected_reg[i] = 0; end
    dut.rf.registers[17] = 32'h1001_0000;     // $s1 = data base
    expected_reg[17] = 32'h1001_0000;
    expected_reg[29] = 32'h7fff_effc;         // $sp after reset

    //                                                   stalls
    put(0,  i_t(ADDI, 0, 8, 16'd5));        // t0 = 5       0
    put(1,  r(8, 8, 9, ADD));               // t1 = 10      2  RAW distance 1
    put(2,  i_t(ADDI, 0, 10, 16'd3));       // t2 = 3       0
    put(3,  i_t(ADDI, 0, 11, 16'd1));       // t3 = 1       0
    put(4,  r(10, 10, 12, ADD));            // t4 = 6       1  RAW distance 2
    put(5,  r(8, 8, 8, ADD));               // t0 = 10      0
    put(6,  r(8, 8, 8, ADD));               // t0 = 20      2  chain
    put(7,  r(8, 8, 8, ADD));               // t0 = 40      2  chain
    put(8,  i_t(SW, 17, 8, 16'd0));         // mem[0] = 40  2  store data (rt)
    put(9,  i_t(LW, 17, 14, 16'd0));        // t6 = 40      0
    put(10, r(14, 14, 15, ADD));            // t7 = 80      2  load-use
    put(11, i_t(LW, 17, 18, 16'd0));        // s2 = 40      0
    put(12, i_t(SW, 17, 18, 16'd4));        // mem[1] = 40  2  load -> store data
    put(13, i_t(ADDI, 17, 19, 16'd4));      // s3 = s1 + 4  0
    put(14, i_t(LW, 19, 20, 16'd0));        // s4 = 40      2  base address just computed
    put(15, i_t(BEQ, 20, 14, 16'd2));       // taken -> 18  2  branch right after lw
    put(16, NOP);                           //   delay slot
    // 17: BAD
    put(18, i_t(ADDI, 0, 4, 16'd88));       // a0 = 88      0
    put(19, r(4, 0, 0, JR));                // jr a0 -> 22  2  jr right after its address
    put(20, NOP);                           //   delay slot
    // 21: BAD
    put(22, i_t(ADDI, 0, 21, 16'd7));       // s5 = 7       0
    put(23, i_t(BNE, 21, 0, 16'd2));        // taken -> 26  2  branch right after ALU
    put(24, NOP);                           //   delay slot
    // 25: BAD
    put(26, i_t(ADDI, 0, 0, 16'd5));        // $zero stays  0
    put(27, r(0, 0, 23, ADD));              // s7 = 0       0  reads $zero: no stall
    put(28, i_t(ADDI, 0, 24, 16'd9));       // t8 = 9       0
    put(29, i_t(ADDI, 0, 24, 16'd10));      // t8 = 10      0  rt is a destination: no stall
    put(30, i_t(BEQ, 0, 0, 16'hffff));      // end: loop    0
    put(31, NOP);

    expected_reg[8] = 40;  expected_reg[9] = 10;  expected_reg[10] = 3;  expected_reg[11] = 1;
    expected_reg[12] = 6;  expected_reg[14] = 40; expected_reg[15] = 80; expected_reg[18] = 40;
    expected_reg[19] = 32'h1001_0004; expected_reg[20] = 40; expected_reg[4] = 88;
    expected_reg[21] = 7;  expected_reg[24] = 10;

    @(posedge clk); #1;
    reset = 0;
    // Run until the end loop is in ID, counting stall cycles on the way.
    while (!(dut.id_valid && dut.id_pc == 4 * 30) && cycles < 200) begin
        if (dut.stall) stalls = stalls + 1;
        @(posedge clk); #1;
        cycles = cycles + 1;
    end
    repeat (6) @(posedge clk);
    #1;
    if (cycles >= 200) begin $display("FAIL  never reached the end loop"); errors = errors + 1; end
    for (i = 0; i < 32; i = i + 1)
        if (dut.rf.registers[i] !== expected_reg[i]) begin
            $display("FAIL  $%0d = %h, expected %h", i, dut.rf.registers[i], expected_reg[i]);
            errors = errors + 1;
        end
    if (dm.mem[0] !== 40 || dm.mem[1] !== 40) begin
        $display("FAIL  memory: mem[0] = %0d, mem[1] = %0d, expected 40 40", dm.mem[0], dm.mem[1]);
        errors = errors + 1;
    end
    if (stalls !== EXPECTED_STALLS) begin
        $display("FAIL  %0d stall cycles, expected %0d", stalls, EXPECTED_STALLS);
        errors = errors + 1;
    end
    $display("ok    end loop reached after %0d cycles, %0d of them stalls", cycles, stalls);
    if (errors == 0) $display("PASS: CPU-5 hazard unit, no nops needed for data, load-use, branch and jr hazards");
    else $fatal(1, "CPU-5: %0d errors", errors);
    $finish;
end
initial begin #10000; $fatal(1, "CPU-5 timeout"); end
endmodule
