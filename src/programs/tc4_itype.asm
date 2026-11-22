# tc4_itype.asm - I-type: addi andi ori slti lui
# TC-4: self-checking test. Result goes to the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF (all 10 LEDs on) and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, where nn = number of the test that failed
# Uses only Phase 1 instructions. No pseudo-instructions, no nops
# (MARS with Delayed branching OFF; our assembler adds the nop after branches/jumps).
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    addi $s0, $zero, 1            # test 1: addi 100 + (-1) = 99
    addi $t0, $zero, 100
    addi $t2, $t0, -1
    addi $t9, $zero, 99
    bne  $t2, $t9, fail
    addi $s0, $zero, 2            # test 2: addi 5 + (-10) = -5
    addi $t0, $zero, 5
    addi $t2, $t0, -10
    addi $t9, $zero, -5
    bne  $t2, $t9, fail
    addi $s0, $zero, 3            # test 3: andi 0x0F0F & 0x00FF = 0x000F
    addi $t0, $zero, 0x0F0F
    andi $t2, $t0, 0x00FF
    addi $t9, $zero, 15
    bne  $t2, $t9, fail
    addi $s0, $zero, 4            # test 4: andi zero-extends the immediate: 0xFFFFFFFF & 0xFFFF = 0xFFFF
    addi $t0, $zero, -1
    andi $t2, $t0, 0xFFFF
    lui  $t9, 0x0000
    ori  $t9, $t9, 0xFFFF
    bne  $t2, $t9, fail
    addi $s0, $zero, 5            # test 5: ori 0x1200 | 0x0034 = 0x1234
    addi $t0, $zero, 0x1200
    ori  $t2, $t0, 0x0034
    addi $t9, $zero, 4660
    bne  $t2, $t9, fail
    addi $s0, $zero, 6            # test 6: ori zero-extends the immediate: 0 | 0xFFFF = 0x0000FFFF
    add  $t0, $zero, $zero
    ori  $t2, $t0, 0xFFFF
    lui  $t9, 0x0000
    ori  $t9, $t9, 0xFFFF
    bne  $t2, $t9, fail
    addi $s0, $zero, 7            # test 7: slti 3 < 5 gives 1
    addi $t0, $zero, 3
    slti $t2, $t0, 5
    addi $t9, $zero, 1
    bne  $t2, $t9, fail
    addi $s0, $zero, 8            # test 8: slti 5 < 3 gives 0
    addi $t0, $zero, 5
    slti $t2, $t0, 3
    addi $t9, $zero, 0
    bne  $t2, $t9, fail
    addi $s0, $zero, 9            # test 9: slti with negatives: -2 < -1 gives 1
    addi $t0, $zero, -2
    slti $t2, $t0, -1
    addi $t9, $zero, 1
    bne  $t2, $t9, fail
    addi $s0, $zero, 10            # test 10: slti with negatives: -1 < -2 gives 0
    addi $t0, $zero, -1
    slti $t2, $t0, -2
    addi $t9, $zero, 0
    bne  $t2, $t9, fail
    addi $s0, $zero, 11            # test 11: lui 0x1234 = 0x12340000
    lui  $t2, 0x1234
    lui  $t9, 0x1234
    bne  $t2, $t9, fail
    addi $s0, $zero, 12            # test 12: lui + ori = 0x1234FFFF
    lui  $t2, 0x1234
    ori  $t2, $t2, 0xFFFF
    lui  $t9, 0x1234
    ori  $t9, $t9, 0xFFFF
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
