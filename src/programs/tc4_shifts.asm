# tc4_shifts.asm - shifts: sll srl
# TC-4: self-checking test. Result goes to the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF (all 10 LEDs on) and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, where nn = number of the test that failed
# Uses only Phase 1 instructions. No pseudo-instructions, no nops
# (MARS with Delayed branching OFF; our assembler adds the nop after branches/jumps).
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    addi $s0, $zero, 1            # test 1: sll 1 << 4 = 16
    addi $t0, $zero, 1
    sll  $t2, $t0, 4
    addi $t9, $zero, 16
    bne  $t2, $t9, fail
    addi $s0, $zero, 2            # test 2: sll 1 << 31 = 0x80000000
    addi $t0, $zero, 1
    sll  $t2, $t0, 31
    lui  $t9, 0x8000
    bne  $t2, $t9, fail
    addi $s0, $zero, 3            # test 3: sll by 0 leaves the value
    addi $t0, $zero, 1234
    sll  $t2, $t0, 0
    addi $t9, $zero, 1234
    bne  $t2, $t9, fail
    addi $s0, $zero, 4            # test 4: srl 0x80 >> 4 = 8
    addi $t0, $zero, 0x80
    srl  $t2, $t0, 4
    addi $t9, $zero, 8
    bne  $t2, $t9, fail
    addi $s0, $zero, 5            # test 5: srl is logical: 0x80000000 >> 31 = 1
    lui  $t0, 0x8000
    srl  $t2, $t0, 31
    addi $t9, $zero, 1
    bne  $t2, $t9, fail
    addi $s0, $zero, 6            # test 6: srl is logical: 0xFFFFFFFF >> 28 = 0xF
    addi $t0, $zero, -1
    srl  $t2, $t0, 28
    addi $t9, $zero, 15
    bne  $t2, $t9, fail
    addi $s0, $zero, 7            # test 7: sll 16 then srl 16 keeps the low half
    addi $t0, $zero, 0x7BCD
    sll  $t1, $t0, 16
    srl  $t2, $t1, 16
    addi $t9, $zero, 31693
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
