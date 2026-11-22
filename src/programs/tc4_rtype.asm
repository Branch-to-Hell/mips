# tc4_rtype.asm - R-type: add sub and or nor slt
# TC-4: self-checking test. Result goes to the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF (all 10 LEDs on) and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, where nn = number of the test that failed
# Uses only Phase 1 instructions. No pseudo-instructions, no nops
# (MARS with Delayed branching OFF; our assembler adds the nop after branches/jumps).
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    addi $s0, $zero, 1            # test 1: add 5 + 7 = 12
    addi $t0, $zero, 5
    addi $t1, $zero, 7
    add  $t2, $t0, $t1
    addi $t9, $zero, 12
    bne  $t2, $t9, fail
    addi $s0, $zero, 2            # test 2: add with a negative: -3 + 10 = 7
    addi $t0, $zero, -3
    addi $t1, $zero, 10
    add  $t2, $t0, $t1
    addi $t9, $zero, 7
    bne  $t2, $t9, fail
    addi $s0, $zero, 3            # test 3: sub 10 - 3 = 7
    addi $t0, $zero, 10
    addi $t1, $zero, 3
    sub  $t2, $t0, $t1
    addi $t9, $zero, 7
    bne  $t2, $t9, fail
    addi $s0, $zero, 4            # test 4: sub 3 - 10 = -7
    addi $t0, $zero, 3
    addi $t1, $zero, 10
    sub  $t2, $t0, $t1
    addi $t9, $zero, -7
    bne  $t2, $t9, fail
    addi $s0, $zero, 5            # test 5: and 0x0FF0 & 0x00FF = 0x00F0
    addi $t0, $zero, 0x0FF0
    addi $t1, $zero, 0x00FF
    and  $t2, $t0, $t1
    addi $t9, $zero, 240
    bne  $t2, $t9, fail
    addi $s0, $zero, 6            # test 6: or 0x0F00 | 0x00F0 = 0x0FF0
    addi $t0, $zero, 0x0F00
    addi $t1, $zero, 0x00F0
    or   $t2, $t0, $t1
    addi $t9, $zero, 4080
    bne  $t2, $t9, fail
    addi $s0, $zero, 7            # test 7: nor 0 0 = 0xFFFFFFFF
    add  $t0, $zero, $zero
    nor  $t2, $t0, $t0
    addi $t9, $zero, -1
    bne  $t2, $t9, fail
    addi $s0, $zero, 8            # test 8: nor 0x0F0F 0x00F0 = 0xFFFFF000
    addi $t0, $zero, 0x0F0F
    addi $t1, $zero, 0x00F0
    nor  $t2, $t0, $t1
    addi $t9, $zero, -4096
    bne  $t2, $t9, fail
    addi $s0, $zero, 9            # test 9: slt 3 < 5 gives 1
    addi $t0, $zero, 3
    addi $t1, $zero, 5
    slt  $t2, $t0, $t1
    addi $t9, $zero, 1
    bne  $t2, $t9, fail
    addi $s0, $zero, 10            # test 10: slt 5 < 3 gives 0
    addi $t0, $zero, 5
    addi $t1, $zero, 3
    slt  $t2, $t0, $t1
    addi $t9, $zero, 0
    bne  $t2, $t9, fail
    addi $s0, $zero, 11            # test 11: slt is signed: -1 < 1 gives 1
    addi $t0, $zero, -1
    addi $t1, $zero, 1
    slt  $t2, $t0, $t1
    addi $t9, $zero, 1
    bne  $t2, $t9, fail
    addi $s0, $zero, 12            # test 12: slt is signed: 1 < -1 gives 0
    addi $t0, $zero, 1
    addi $t1, $zero, -1
    slt  $t2, $t0, $t1
    addi $t9, $zero, 0
    bne  $t2, $t9, fail
    addi $s0, $zero, 13            # test 13: register $zero always reads 0
    addi $zero, $zero, 5
    add  $t2, $zero, $zero
    addi $t9, $zero, 0
    bne  $t2, $t9, fail
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
