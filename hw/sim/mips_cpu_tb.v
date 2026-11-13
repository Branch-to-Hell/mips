`timescale 1ns/1ns
// Self-checking R-type test for CPU-1. Run from hw/sim/: do mips_cpu.do
module mips_cpu_tb();

reg clk, reset;
integer errors = 0;

mips_cpu #(
    .IMEM_INIT("../mem/test_rtype.hex"),
    .REGS_INIT("rtype_regs.bin")
) dut(.clk(clk), .reset(reset));

initial clk = 0;
always #5 clk = ~clk;

task check(input [4:0] r, input [31:0] expected);
    begin
        if (dut.rf.registers[r] !== expected) begin
            $display("FAIL  $%0d = %0d (expected %0d)", r, dut.rf.registers[r], expected);
            errors = errors + 1;
        end else
            $display("ok    $%0d = %0d", r, expected);
    end
endtask

initial begin
    reset = 1;
    #10;
    if (dut.PC_out !== 32'h0040_0000) begin
        $display("FAIL  PC after reset = %h (expected 00400000)", dut.PC_out);
        errors = errors + 1;
    end
    reset = 0;
    #80;   // 8 instructions x 10 ns
    check(8,  8);   // add  $t0
    check(11, 2);   // sub  $t3
    check(12, 1);   // and  $t4
    check(13, 7);   // or   $t5
    check(14, 1);   // slt  $t6
    check(15, 20);  // sll  $t7
    check(16, 2);   // srl  $s0
    check(0,  0);   // nop must not change $zero
    if (errors == 0) $display("PASS: all R-type tests");
    else             $display("FAILED: %0d error(s)", errors);
    $stop;
end
endmodule
