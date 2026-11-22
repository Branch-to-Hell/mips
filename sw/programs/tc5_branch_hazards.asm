# tc5_branch_hazards.asm - branch hazards (beq / bne right after their operands, after a lw, back to back)
# TC-5: hazard / delay-slot test, self-checking. Result on the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, nn = number of the test that failed
# Written as in MARS with Delayed branching OFF: NO nops anywhere. Every dependency is
# back-to-back on purpose, so the hazard unit has to stall/forward, and the assembler's
# nop after each branch/jump must not change what the program computes.
# Run on mips_pipeline: from hw/sim, `do tc5.do` (assemble first: python sw/assembler/assembler.py sw/programs/<name>.asm).
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    lui  $s1, 0x1001            # s1 = 0x10010000 (data region base)
    addi $s0, $zero, 1            # test 1: beq right after the instruction that computes its operand (taken)
    addi $t0, $zero, 5
    addi $t1, $zero, 5
    beq  $t0, $t1, b1_ok
    j    fail
b1_ok:
    addi $s0, $zero, 2            # test 2: bne right after its operand is computed (taken)
    addi $t0, $zero, 1
    addi $t1, $zero, 2
    bne  $t0, $t1, b2_ok
    j    fail
b2_ok:
    addi $s0, $zero, 3            # test 3: beq not taken, operand just computed
    addi $t0, $zero, 1
    addi $t1, $zero, 2
    beq  $t0, $t1, fail
    addi $s0, $zero, 4            # test 4: branch right after a lw (load-use into the branch)
    addi $t0, $zero, 7
    sw   $t0, 0($s1)
    addi $t1, $zero, 7
    lw   $t2, 0($s1)
    beq  $t2, $t1, b4_ok
    j    fail
b4_ok:
    addi $s0, $zero, 5            # test 5: loop whose counter is computed right before bne: 1+2+3+4+5
    addi $t0, $zero, 0
    addi $t1, $zero, 1
    addi $t2, $zero, 6
b5_loop:
    add  $t0, $t0, $t1
    addi $t1, $t1, 1
    bne  $t1, $t2, b5_loop
    addi $t9, $zero, 15
    bne  $t0, $t9, fail
    addi $s0, $zero, 6            # test 6: taken branch skips the next source line (the delay slot only holds the assembler's nop)
    addi $t5, $zero, 0
    addi $t0, $zero, 1
    beq  $t0, $t0, b6_skip
    addi $t5, $zero, 1
b6_skip:
    bne  $t5, $zero, fail
    addi $s0, $zero, 7            # test 7: value computed right before a taken branch is used right at the target
    addi $t0, $zero, 9
    beq  $zero, $zero, b7_tgt
b7_tgt:
    add  $t1, $t0, $t0
    addi $t9, $zero, 18
    bne  $t1, $t9, fail
    addi $s0, $zero, 8            # test 8: not taken branch, then use of a value computed before it
    addi $t0, $zero, 3
    bne  $zero, $zero, fail
    add  $t1, $t0, $t0
    addi $t9, $zero, 6
    bne  $t1, $t9, fail
    addi $s0, $zero, 9            # test 9: two taken branches back to back
    addi $t0, $zero, 1
    beq  $t0, $t0, b9_a
    j    fail
b9_a:
    beq  $t0, $t0, b9_b
    j    fail
b9_b:
    addi $s0, $zero, 10           # test 10: taken branch skips an instruction that would write a register used later
    addi $t3, $zero, 4
    beq  $zero, $zero, b10_t
    addi $t3, $zero, 99
b10_t:
    add  $t4, $t3, $t3
    addi $t9, $zero, 8
    bne  $t4, $t9, fail
    j    pass

# The result code must be right even when the hazard unit is broken, so fail and pass
# keep every dependency 3 instructions apart with nops (no stall needed).
fail:
    lui  $t0, 0x00BA
    nop
    nop
    ori  $t0, $t0, 0xD000
    nop
    nop
    add  $t0, $t0, $s0          # 0x00BAD000 + test number
    nop
    nop
    sw   $t0, 0x1C($s6)         # HEX shows BAD0nn
    sw   $zero, 0x18($s6)       # all LEDs off
stop_fail:
    j    stop_fail
pass:
    addi $t0, $zero, 0x3FF
    ori  $t1, $zero, 0x600D
    nop
    sw   $t0, 0x18($s6)         # all LEDs on
    sw   $t1, 0x1C($s6)         # HEX shows 00600D
stop_pass:
    j    stop_pass
