`timescale 1ns/1ps
// TC-16: one trace per format (R, I, J) on mips_pipeline. Run from verif: do trace.do
/* Runs src/programs/tc16_trace.asm (data from its _data.hex) and follows three instructions
through IF, ID, EX, MEM and WB, one line block per cycle:
    R: add $t2, $t0, $t1     I: lw $t3, 4($s1)     J: j j_target
For each one it writes verif/traces/trace_<R|I|J>.txt with:
  - state before (registers and memory it uses) and after (once its write is done)
  - IF: PC and the 4 bytes mem[PC]..mem[PC+3] (big-endian banks) joined into the word
  - ID: fields, immediate, control signals, ALU control, operands read, stall, redirect
  - EX: ID/EX register (A, B, immediate, destination, shamt, control) and the ALU result
  - MEM: EX/MEM register, the memory bus (address, read/write, read data)
  - WB: MEM/WB register and the register file write
Each line is the state during that cycle (sampled at the rising edge that ends it).
It also checks the results: $t2 = 12, $t3 = 0xCAFE1234, $t4 = 0 (the j skipped its write),
and that every traced instruction went through the 5 stages in 5 consecutive cycles.
*/
module trace_tb;
localparam [31:0] ADD_WORD = 32'h0109_5021;   // add $t2, $t0, $t1 (funct 0x21)
localparam [31:0] LW_WORD  = 32'h8E2B_0004;   // lw $t3, 4($s1)

reg clk = 0, reset = 1;
wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire mem_we, mem_re;
mips_pipeline #(.IMEM_INIT("../mem/tc16_trace")) dut(.clk(clk), .reset(reset),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_we(mem_we), .mem_re(mem_re),
    .mem_rdata(mem_rdata), .mem_fault(1'b0), .dbg_sel(5'd0), .dbg_value(),
    .halted(), .halt_cause(), .halt_pc(), .halt_addr());
data_memory #(.INIT_FILE("../mem/tc16_trace_data.hex")) dm(.clk(clk), .MemRead(mem_re),
    .MemWrite(mem_we), .Address(mem_addr), .WriteData(mem_wdata), .ReadData(mem_rdata));
always #5 clk = ~clk;

integer i, k, cycle = 0, errors = 0;
reg [31:0] pc [0:2];                 // traced PCs: 0 = R, 1 = I, 2 = J
integer f [0:2];
integer first [0:2], seen [0:2];     // cycle of IF, stages seen (bit per stage)
integer wb_cycle [0:2];
reg [8*12-1:0] name [0:2];

function [8*6-1:0] rname(input [4:0] r);
    case (r)
        0: rname = "$zero"; 1: rname = "$at"; 2: rname = "$v0"; 3: rname = "$v1";
        4: rname = "$a0"; 5: rname = "$a1"; 6: rname = "$a2"; 7: rname = "$a3";
        8: rname = "$t0"; 9: rname = "$t1"; 10: rname = "$t2"; 11: rname = "$t3";
        12: rname = "$t4"; 13: rname = "$t5"; 14: rname = "$t6"; 15: rname = "$t7";
        16: rname = "$s0"; 17: rname = "$s1"; 18: rname = "$s2"; 19: rname = "$s3";
        20: rname = "$s4"; 21: rname = "$s5"; 22: rname = "$s6"; 23: rname = "$s7";
        24: rname = "$t8"; 25: rname = "$t9"; 26: rname = "$k0"; 27: rname = "$k1";
        28: rname = "$gp"; 29: rname = "$sp"; 30: rname = "$fp"; 31: rname = "$ra";
    endcase
endfunction

function [31:0] reg_value(input [4:0] r);
    reg_value = dut.rf.registers[r];
endfunction

// Registers and memory each instruction uses, before and after
task state(input integer t, input [8*6-1:0] when);
    begin
        case (t)
        0: $fdisplay(f[t], "%0s: $t0 = %h  $t1 = %h  $t2 = %h", when,
                     reg_value(8), reg_value(9), reg_value(10));
        1: $fdisplay(f[t], "%0s: $s1 = %h  $t3 = %h  mem[0x10010004] = %h", when,
                     reg_value(17), reg_value(11), dm.mem[1]);
        2: $fdisplay(f[t], "%0s: $t4 = %h  (j_target skips addi $t4, $zero, 1)", when, reg_value(12));
        endcase
    end
endtask

task header(input integer t);
    reg [31:0] w;
    begin
        w = dut.if_id.im.read_word(pc[t][13:2]);
        $fdisplay(f[t], "TC-16 trace, %0s: PC %h, word %h", name[t], pc[t], w);
        $fdisplay(f[t], "Program src/programs/tc16_trace.asm on mips_pipeline (verif/trace_tb.v, do trace.do).");
        $fdisplay(f[t], "Each block is one clock cycle; values are the state during the cycle (sampled at the edge that ends it).");
        $fdisplay(f[t], "");
    end
endtask

// One cycle of the traced instruction t, in the stage(s) where it is
task log_cycle(input integer t);
    reg [31:0] w;
    begin
        // IF: fetch_pc = this PC and the fetch is not stalled; the 4 banks give the 4 bytes
        if (dut.fetch_pc == pc[t] && dut.if_id_enable) begin
            if (seen[t] == 0) begin first[t] = cycle; state(t, "Before"); $fdisplay(f[t], ""); end
            seen[t] = seen[t] | 1;
            $fdisplay(f[t], "Cycle %0d  IF   PC = %h -> bytes mem[PC..PC+3] = %h %h %h %h -> word %h (loaded into IF/ID at the end of the cycle)",
                cycle - first[t] + 1, pc[t],
                dut.if_id.im.bank0[pc[t][13:2]], dut.if_id.im.bank1[pc[t][13:2]],
                dut.if_id.im.bank2[pc[t][13:2]], dut.if_id.im.bank3[pc[t][13:2]],
                dut.if_id.im.read_word(pc[t][13:2]));
        end
        // ID: IF/ID holds it
        if (dut.id_valid && dut.id_pc == pc[t]) begin
            w = dut.id_instruction;
            seen[t] = seen[t] | 2;
            $fdisplay(f[t], "Cycle %0d  ID   IF/ID: valid = 1, PC = %h, instruction = %h", cycle - first[t] + 1, dut.id_pc, w);
            if (w[31:26] == 6'h00)
                $fdisplay(f[t], "               fields R: opcode = %b, rs = %0d (%0s), rt = %0d (%0s), rd = %0d (%0s), shamt = %0d, funct = %b (0x%h)",
                    w[31:26], w[25:21], rname(w[25:21]), w[20:16], rname(w[20:16]), w[15:11], rname(w[15:11]), w[10:6], w[5:0], w[5:0]);
            else if (w[31:26] == 6'h02 || w[31:26] == 6'h03)
                $fdisplay(f[t], "               fields J: opcode = %b, target = %h -> {(PC + 4)[31:28], target, 00} = %h",
                    w[31:26], w[25:0], dut.jump_target);
            else
                $fdisplay(f[t], "               fields I: opcode = %b, rs = %0d (%0s), rt = %0d (%0s), immediate = %h -> extended %h",
                    w[31:26], w[25:21], rname(w[25:21]), w[20:16], rname(w[20:16]), w[15:0], dut.id_imm);
            $fdisplay(f[t], "               control: RegDst = %b, ALUSrc = %b, MemtoReg = %b, RegWrite = %b, MemRead = %b, MemWrite = %b,",
                dut.reg_dst, dut.alu_src, dut.mem_to_reg, dut.reg_write, dut.mem_read, dut.mem_write);
            $fdisplay(f[t], "                        Branch = %b, BranchNE = %b, Jump = %b, JumpReg = %b, Link = %b, ALUOp = %b, ALU control = %b",
                dut.branch, dut.branch_ne, dut.jump, dut.jump_reg, dut.link, dut.alu_op, dut.id_alu_ctl);
            $fdisplay(f[t], "               register file: A = R[rs] = %h, B = R[rt] = %h, destination = %0d (%0s)",
                dut.id_a, dut.id_b, dut.ex_dest_in, rname(dut.ex_dest_in));
            $fdisplay(f[t], "               hazard unit: stall = %b; redirect = %b%0s",
                dut.stall, dut.redirect, dut.redirect ? " (jump/branch taken in ID)" : "");
            $fdisplay(f[t], "               fetch: IF fetches %h this cycle%0s, then %h",
                dut.fetch_pc, dut.redirect ? " (the delay slot, it always runs)" : "", dut.next_fetch_pc);
        end
        // EX: ID/EX holds it
        if (dut.ex_valid && dut.ex_pc == pc[t]) begin
            seen[t] = seen[t] | 4;
            $fdisplay(f[t], "Cycle %0d  EX   ID/EX: valid = 1, PC = %h, A = %h, B = %h, immediate = %h, destination = %0d (%0s), shamt = %0d,",
                cycle - first[t] + 1, dut.ex_pc, dut.ex_a, dut.ex_b, dut.ex_imm, dut.ex_dest, rname(dut.ex_dest), dut.ex_shamt);
            $fdisplay(f[t], "                      ALU control = %b, ALUSrc = %b, RegWrite = %b, MemRead = %b, MemWrite = %b, MemtoReg = %b",
                dut.ex_alu_ctl, dut.ex_alu_src, dut.ex_reg_write, dut.ex_mem_read, dut.ex_mem_write, dut.ex_mem_to_reg);
            $fdisplay(f[t], "               ALU: %h op %h = %h; address adder A + immediate = %h; value to EX/MEM = %h",
                dut.ex_a, dut.ex_alu_src ? dut.ex_imm : dut.ex_b, dut.ex_result, dut.ex_address, dut.ex_value);
        end
        // MEM: EX/MEM holds it
        if (dut.mem_valid && dut.mem_pc == pc[t]) begin
            seen[t] = seen[t] | 8;
            wb_cycle[t] = cycle + 1;
            $fdisplay(f[t], "Cycle %0d  MEM  EX/MEM: valid = 1, PC = %h, value = %h, store data = %h, destination = %0d (%0s),",
                cycle - first[t] + 1, dut.mem_pc, dut.mem_value, dut.mem_store_data, dut.mem_dest, rname(dut.mem_dest));
            $fdisplay(f[t], "                       RegWrite = %b, MemRead = %b, MemWrite = %b, MemtoReg = %b",
                dut.mem_reg_write, dut.mem_read_ctl, dut.mem_write_ctl, dut.mem_to_reg_ctl);
            $fdisplay(f[t], "               memory bus: address = %h, read = %b, write = %b, read data = %h -> value to MEM/WB = %h",
                mem_addr, mem_re, mem_we, mem_rdata, dut.mem_to_reg_ctl ? mem_rdata : dut.mem_value);
        end
        // WB: MEM/WB holds it (the cycle after MEM)
        if (cycle == wb_cycle[t] && dut.wb_valid) begin
            seen[t] = seen[t] | 16;
            $fdisplay(f[t], "Cycle %0d  WB   MEM/WB: valid = 1, value = %h, destination = %0d (%0s), RegWrite = %b",
                cycle - first[t] + 1, dut.wb_data, dut.wb_dest, rname(dut.wb_dest), dut.wb_reg_write);
            if (dut.wb_write)
                $fdisplay(f[t], "               register file: %0s <= %h at the end of the cycle (bypassed to ID during it)",
                    rname(dut.wb_dest), dut.wb_data);
            else
                $fdisplay(f[t], "               register file: no write (RegWrite = 0 or destination $zero)");
        end
    end
endtask

// Every rising edge: log the cycle that just ended (signals still hold its values)
always @(posedge clk) if (!reset) begin
    cycle = cycle + 1;
    for (k = 0; k < 3; k = k + 1) log_cycle(k);
end

initial begin
    name[0] = "R add"; name[1] = "I lw"; name[2] = "J j";
    for (i = 0; i < 32; i = i + 1) dut.rf.registers[i] = 0;
    for (i = 0; i < 3; i = i + 1) begin pc[i] = 32'hFFFF_FFFF; seen[i] = 0; wb_cycle[i] = -1; end
    #1;
    for (i = 0; i < 4096; i = i + 1) begin
        if (dut.if_id.im.read_word(i) === ADD_WORD && pc[0] === 32'hFFFF_FFFF) pc[0] = 4 * i;
        if (dut.if_id.im.read_word(i) === LW_WORD  && pc[1] === 32'hFFFF_FFFF) pc[1] = 4 * i;
    end
    if (pc[0] === 32'hFFFF_FFFF || pc[1] === 32'hFFFF_FFFF) $fatal(1, "traced instructions not found");
    pc[2] = pc[1] + 4;                                        // j right after the lw
    if (dut.if_id.im.read_word(pc[2][13:2]) >> 26 !== 6'h02) $fatal(1, "no j after the lw");

    f[0] = $fopen("traces/trace_R.txt", "w");
    f[1] = $fopen("traces/trace_I.txt", "w");
    f[2] = $fopen("traces/trace_J.txt", "w");
    for (i = 0; i < 3; i = i + 1) begin
        if (f[i] == 0) $fatal(1, "cannot write verif/traces/ (run from verif/)");
        header(i);
    end

    @(posedge clk); @(negedge clk) reset = 0;
    repeat (60) @(posedge clk);
    #1;

    for (i = 0; i < 3; i = i + 1) begin
        $fdisplay(f[i], "");
        state(i, "After ");
        if (seen[i] != 5'b11111) begin
            $display("FAIL  %0s: stages seen %b (expected all 5)", name[i], seen[i][4:0]);
            errors = errors + 1;
        end
        $fclose(f[i]);
    end
    if (dut.rf.registers[10] !== 32'd12) begin $display("FAIL  $t2 = %h, expected 0000000c", dut.rf.registers[10]); errors = errors + 1; end
    if (dut.rf.registers[11] !== 32'hCAFE_1234) begin $display("FAIL  $t3 = %h, expected cafe1234", dut.rf.registers[11]); errors = errors + 1; end
    if (dut.rf.registers[12] !== 32'd0) begin $display("FAIL  $t4 = %h, the j did not skip", dut.rf.registers[12]); errors = errors + 1; end

    if (errors) $fatal(1, "TC-16 trace: %0d error(s)", errors);
    $display("PASS: TC-16 traces R (PC %h), I (PC %h), J (PC %h) written to verif/traces/", pc[0], pc[1], pc[2]);
    $finish;
end
endmodule
