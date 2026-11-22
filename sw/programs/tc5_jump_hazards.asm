# tc5_jump_hazards.asm - jump hazards (j, jal, jr with back-to-back dependencies)
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
    addi $s0, $zero, 1            # test 1: j then use of a value computed right before the jump
    addi $t0, $zero, 4
    j    j1_tgt
j1_tgt:
    add  $t1, $t0, $t0
    addi $t9, $zero, 8
    bne  $t1, $t9, fail
    addi $s0, $zero, 2            # test 2: argument computed right before jal, used first thing in the callee
    addi $a0, $zero, 6
    jal  j2_f
    j    j2_end
j2_f:
    add  $v0, $a0, $a0
    jr   $ra
j2_end:
    addi $t9, $zero, 12
    bne  $v0, $t9, fail
    addi $s0, $zero, 3            # test 3: callee copies $ra right after jal; $ra must be the return point
    jal  j3_f
j3_ret:                           # $ra must point here: MARS links jal + 4, our CPU jal + 8 (after the delay-slot nop)
    j    j3_end
j3_f:
    addi $s2, $ra, 0
    jr   $ra
j3_end:
    la   $t9, j3_ret              # la = lui + ori, then bne uses $t9 right away
    bne  $s2, $t9, fail
    addi $s0, $zero, 4            # test 4: jr right after $ra was rebuilt by addi (ALU result into jr)
    addi $t1, $zero, 0
    jal  j4_outer
    addi $t1, $t1, 100
    j    j4_end
j4_outer:
    addi $s2, $ra, 0
    jal  j4_inner
    addi $t1, $t1, 10
    addi $ra, $s2, 0
    jr   $ra
j4_inner:
    addi $t1, $zero, 5
    jr   $ra
j4_end:
    addi $t9, $zero, 115
    bne  $t1, $t9, fail
    addi $s0, $zero, 5            # test 5: jr right after lw $ra (load-use into jr)
    addi $t1, $zero, 0
    jal  j5_outer
    addi $t1, $t1, 100
    j    j5_end
j5_outer:
    sw   $ra, 0($s1)
    jal  j5_inner
    addi $t1, $t1, 10
    lw   $ra, 0($s1)
    jr   $ra
j5_inner:
    addi $t1, $zero, 5
    jr   $ra
j5_end:
    addi $t9, $zero, 115
    bne  $t1, $t9, fail
    addi $s0, $zero, 6            # test 6: two calls back to back
    addi $t1, $zero, 0
    jal  j6_f
    jal  j6_g
    j    j6_end
j6_f:
    addi $t1, $t1, 1
    jr   $ra
j6_g:
    addi $t1, $t1, 2
    jr   $ra
j6_end:
    addi $t9, $zero, 3
    bne  $t1, $t9, fail
    addi $s0, $zero, 7            # test 7: call inside a loop: 3 calls of a function that adds 5
    addi $t1, $zero, 0
    addi $t2, $zero, 0
    addi $t3, $zero, 3
j7_loop:
    jal  j7_f
    addi $t2, $t2, 1
    bne  $t2, $t3, j7_loop
    j    j7_end
j7_f:
    addi $t1, $t1, 5
    jr   $ra
j7_end:
    addi $t9, $zero, 15
    bne  $t1, $t9, fail
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
