# test_rtype.asm - R-type test for CPU-1 (single-cycle).
# Initial registers come from hw/sim/rtype_regs.bin: $t1 = 5, $t2 = 3
# (no addi yet, so the testbench preloads them).
# Machine code: hw/mem/test_rtype.hex. Expected results are checked in hw/sim/mips_cpu_tb.v.
.text
    add  $t0, $t1, $t2     # $t0 = 8
    sub  $t3, $t1, $t2     # $t3 = 2
    and  $t4, $t1, $t2     # $t4 = 1
    or   $t5, $t1, $t2     # $t5 = 7
    slt  $t6, $t2, $t1     # $t6 = 1  (3 < 5)
    sll  $t7, $t1, 2       # $t7 = 20
    srl  $s0, $t1, 1       # $s0 = 2
    nop                    # sll $zero, $zero, 0 -> $zero must stay 0
