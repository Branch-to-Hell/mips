# tc4_jumps.asm - jumps: j jal jr
# TC-4: self-checking test. Result goes to the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF (all 10 LEDs on) and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, where nn = number of the test that failed
# Uses only Phase 1 instructions. No pseudo-instructions, no nops
# (MARS with Delayed branching OFF; our assembler adds the nop after branches/jumps).
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    addi $s0, $zero, 1            # test 1: j skips the instruction after it
    addi $t0, $zero, 0
    j    t1_skip
    addi $t0, $zero, 1
t1_skip:
    bne  $t0, $zero, fail
    addi $s0, $zero, 2            # test 2: jal calls and jr $ra returns
    addi $t1, $zero, 0
    addi $t2, $zero, 0
    jal  func_a
    addi $t2, $zero, 7
    j    t2_check
func_a:
    addi $t1, $zero, 42
    jr   $ra
t2_check:
    addi $t9, $zero, 42
    bne  $t1, $t9, fail
    addi $t9, $zero, 7
    bne  $t2, $t9, fail
    addi $s0, $zero, 3            # test 3: nested call: a function saves $ra, calls another, restores it
    addi $t1, $zero, 0
    addi $t2, $zero, 0
    jal  func_outer
    addi $t2, $t2, 100
    j    t3_check
func_outer:
    addi $s2, $ra, 0
    jal  func_inner
    addi $t1, $t1, 10
    addi $ra, $s2, 0
    jr   $ra
func_inner:
    addi $t1, $zero, 5
    jr   $ra
t3_check:
    addi $t9, $zero, 15
    bne  $t1, $t9, fail
    addi $t9, $zero, 100
    bne  $t2, $t9, fail
    addi $s0, $zero, 4            # test 4: loop built with j: count to 3
    addi $t0, $zero, 0
    addi $t1, $zero, 3
t4_loop:
    beq  $t0, $t1, t4_done
    addi $t0, $t0, 1
    j    t4_loop
t4_done:
    bne  $t0, $t1, fail
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
