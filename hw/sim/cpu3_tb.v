`timescale 1ns/1ps
// Directed control-flow checks, including fetch alignment and side effects.
module cpu3_tb;
reg clk = 0, reset = 1;
wire [31:0] mem_addr, mem_wdata;
wire mem_we, mem_re;
integer i, checks = 0;
reg [31:0] saved [0:31];
mips_cpu dut(.clk(clk), .reset(reset), .mem_addr(mem_addr),
    .mem_wdata(mem_wdata), .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(32'd0));
always #5 clk = ~clk;

// Set up one instruction between edges; the next edge must retire it and
// synchronously fetch the instruction at the expected PC. This fixture also
// permits testing upper PC bits beyond the physical instruction RAM region.
task check_transfer;
    input [31:0] instruction, pc_value, rs_value, rt_value, next_pc;
    input link;
    begin
        @(negedge clk); #1;
        reset = 0;
        for (i = 0; i < 32; i = i + 1) dut.rf.registers[i] = 32'h12340000 + i;
        dut.rf.registers[0] = 0;
        dut.rf.registers[instruction[25:21]] = rs_value;
        dut.rf.registers[instruction[20:16]] = rt_value;
        dut.rf.registers[0] = 0;
        for (i = 0; i < 32; i = i + 1) saved[i] = dut.rf.registers[i];
        dut.pc_reg.PC_out = pc_value;
        dut.im.Instruction = instruction;
        // A recognizable fetched instruction, not executed in this fixture.
        dut.im.mem[next_pc[13:2]] = 32'h2015002a;
        #1;
        if (mem_we !== 0 || mem_re !== 0 || dut.RegWrite !== link)
            $fatal(1, "Unexpected side effect for instruction %h", instruction);
        @(posedge clk); #1;
        if (dut.PC_out !== next_pc || dut.Instruction !== 32'h2015002a)
            $fatal(1, "PC/fetch mismatch: instruction=%h PC=%h expected=%h fetched=%h",
                instruction, dut.PC_out, next_pc, dut.Instruction);
        for (i = 0; i < 32; i = i + 1) begin
            if (link && i == 31) begin
                if (dut.rf.registers[i] !== pc_value + 32'd4)
                    $fatal(1, "jal must write PC+4 into ra");
            end else if (dut.rf.registers[i] !== saved[i])
                $fatal(1, "Unexpected write to register %0d", i);
        end
        checks = checks + 1;
    end
endtask

initial begin
    #1;
    for (i = 0; i < 4096; i = i + 1) dut.im.mem[i] = 0;
    // beq/bne: taken and not taken, negative values, backward/zero/extreme offsets.
    check_transfer({6'h04,5'd8,5'd9,16'd2},32'h00400020,7,7,32'h0040002c,0);
    check_transfer({6'h04,5'd8,5'd9,16'd2},32'h00400020,7,8,32'h00400024,0);
    check_transfer({6'h05,5'd8,5'd9,16'd2},32'h00400020,7,8,32'h0040002c,0);
    check_transfer({6'h05,5'd8,5'd9,16'd2},32'h00400020,7,7,32'h00400024,0);
    check_transfer({6'h04,5'd8,5'd9,16'hfffe},32'h00400020,32'hfffffff9,32'hfffffff9,32'h0040001c,0);
    check_transfer({6'h05,5'd8,5'd9,16'hfffe},32'h00400020,32'hffffffff,0,32'h0040001c,0);
    check_transfer({6'h04,5'd8,5'd9,16'd0},32'h00400020,7,7,32'h00400024,0);
    check_transfer({6'h04,5'd8,5'd9,16'h8000},32'h00420000,7,7,32'h00400004,0);
    check_transfer({6'h04,5'd8,5'd9,16'h7fff},32'h00400000,7,7,32'h00420000,0);
    // J-format: target is shifted by two, upper nibble comes from PC+4.
    check_transfer({6'h02,26'h0100020},32'h00400000,0,0,32'h00400080,0);
    check_transfer({6'h03,26'h0100020},32'h00400000,0,0,32'h00400080,1);
    check_transfer({6'h02,26'h0000010},32'h0ffffffc,0,0,32'h10000040,0);
    check_transfer({6'h03,26'h0000010},32'h0ffffffc,0,0,32'h10000040,1);
    // jr uses rs (not just ra); it never links or writes memory.
    check_transfer({6'h00,5'd31,5'd0,5'd0,5'd0,6'h08},32'h00400020,32'h00400004,0,32'h00400004,0);
    check_transfer({6'h00,5'd8,5'd0,5'd0,5'd0,6'h08},32'h00400020,32'h00400100,0,32'h00400100,0);
    // Reset wins over a pending jal and suppresses its register write.
    @(negedge clk); #1;
    dut.im.Instruction = {6'h03,26'h0100020};
    dut.rf.registers[31] = 32'hcafebabe;
    dut.im.mem[0] = 32'h2015002a;
    reset = 1;
    @(posedge clk); #1;
    if (dut.PC_out !== 32'h00400000 || dut.Instruction !== 32'h2015002a ||
        dut.rf.registers[31] !== 32'hcafebabe || mem_we !== 0 || mem_re !== 0)
        $fatal(1, "Reset failed to override control flow");
    $display("PASS: CPU-3 %0d directed transfers plus reset", checks);
    $finish;
end
initial begin #10000; $fatal(1, "CPU-3 timeout"); end
endmodule
