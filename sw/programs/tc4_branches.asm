# tc4_branches.asm - branches: beq bne
# TC-4: self-checking test. Result goes to the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF (all 10 LEDs on) and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, where nn = number of the test that failed
# Uses only Phase 1 instructions. No pseudo-instructions, no nops
# (MARS with Delayed branching OFF; our assembler adds the nop after branches/jumps).
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    addi $s0, $zero, 1            # test 1: beq taken when equal
    addi $t0, $zero, 5
    addi $t1, $zero, 5
    beq  $t0, $t1, t1_ok
    j    fail
t1_ok:
    addi $s0, $zero, 2            # test 2: beq not taken when different
    addi $t0, $zero, 5
    addi $t1, $zero, 6
    beq  $t0, $t1, fail
    addi $s0, $zero, 3            # test 3: bne taken when different
    addi $t0, $zero, 5
    addi $t1, $zero, 6
    bne  $t0, $t1, t3_ok
    j    fail
t3_ok:
    addi $s0, $zero, 4            # test 4: bne not taken when equal
    addi $t0, $zero, 5
    addi $t1, $zero, 5
    bne  $t0, $t1, fail
    addi $s0, $zero, 5            # test 5: beq with negative numbers
    addi $t0, $zero, -7
    addi $t1, $zero, -7
    beq  $t0, $t1, t5_ok
    j    fail
t5_ok:
    addi $s0, $zero, 6            # test 6: beq $zero, $zero is always taken
    beq  $zero, $zero, t6_ok
    j    fail
t6_ok:
    addi $s0, $zero, 7            # test 7: backward branch: loop adds 1+2+3+4+5 = 15
    addi $t0, $zero, 0
    addi $t1, $zero, 1
    addi $t2, $zero, 6
t7_loop:
    add  $t0, $t0, $t1
    addi $t1, $t1, 1
    bne  $t1, $t2, t7_loop
    addi $t3, $zero, 15
    bne  $t0, $t3, fail
    addi $s0, $zero, 8            # test 8: taken branch skips the instruction after it (no delay slot visible)
    addi $t5, $zero, 0
    beq  $zero, $zero, t8_skip
    addi $t5, $zero, 1
t8_skip:
    bne  $t5, $zero, fail
    addi $s0, $zero, 9            # test 9: not taken branch runs the next instruction
    addi $t5, $zero, 0
    bne  $zero, $zero, t9_skip
    addi $t5, $zero, 1
t9_skip:
    addi $t6, $zero, 1
    bne  $t5, $t6, fail
    j    pass

fail:
    lui  $t0, 0x00BA
    ori  $t0, $t0, 0xD000
    add  $t0, $t0, $s0          # 0x00BAD000 + test number
    sw   $t0, 0x1C($s6)         # HEX shows BAD0nn
    sw   $zero, 0x18($s6)       # all LEDs off
stop_fail:
    j    stop_fail
pass:
    addi $t0, $zero, 0x3FF
    sw   $t0, 0x18($s6)         # all LEDs on
    ori  $t0, $zero, 0x600D
    sw   $t0, 0x1C($s6)         # HEX shows 00600D
stop_pass:
    j    stop_pass
