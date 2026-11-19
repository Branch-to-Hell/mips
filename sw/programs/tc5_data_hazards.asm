# tc5_data_hazards.asm - data hazards between ALU instructions (forwarding / stalls)
# TC-5: hazard / delay-slot test, self-checking. Result on the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, nn = number of the test that failed
# Written as in MARS with Delayed branching OFF: NO nops anywhere. Every dependency is
# back-to-back on purpose, so the hazard unit has to stall/forward, and the assembler's
# nop after each branch/jump must not change what the program computes.
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    addi $s0, $zero, 1            # test 1: RAW at distance 1: result used by the very next instruction
    addi $t0, $zero, 5
    add  $t1, $t0, $t0
    addi $t9, $zero, 10
    bne  $t1, $t9, fail
    addi $s0, $zero, 2            # test 2: RAW at distance 2
    addi $t0, $zero, 3
    addi $t3, $zero, 1
    add  $t1, $t0, $t0
    addi $t9, $zero, 6
    bne  $t1, $t9, fail
    addi $s0, $zero, 3            # test 3: RAW at distance 3
    addi $t0, $zero, 4
    addi $t3, $zero, 1
    addi $t4, $zero, 2
    add  $t1, $t0, $t0
    addi $t9, $zero, 8
    bne  $t1, $t9, fail
    addi $s0, $zero, 4            # test 4: chain of dependent adds: 1 -> 2 -> 4 -> 8
    addi $t0, $zero, 1
    add  $t0, $t0, $t0
    add  $t0, $t0, $t0
    add  $t0, $t0, $t0
    addi $t9, $zero, 8
    bne  $t0, $t9, fail
    addi $s0, $zero, 5            # test 5: two operands, each from one of the 2 previous instructions
    addi $t0, $zero, 6
    addi $t1, $zero, 7
    add  $t2, $t0, $t1
    addi $t9, $zero, 13
    bne  $t2, $t9, fail
    addi $s0, $zero, 6            # test 6: WAW: the later write wins
    addi $t0, $zero, 1
    addi $t0, $zero, 2
    add  $t1, $t0, $zero
    addi $t9, $zero, 2
    bne  $t1, $t9, fail
    addi $s0, $zero, 7            # test 7: sub feeding another sub
    addi $t0, $zero, 10
    addi $t1, $zero, 3
    sub  $t2, $t0, $t1
    sub  $t3, $t2, $t1
    addi $t9, $zero, 4
    bne  $t3, $t9, fail
    addi $s0, $zero, 8            # test 8: result used at distance 1 and at distance 2 by the same instruction
    addi $t0, $zero, 5
    add  $t1, $t0, $t0
    add  $t2, $t1, $t0
    addi $t9, $zero, 15
    bne  $t2, $t9, fail
    addi $s0, $zero, 9            # test 9: writing $zero never creates a dependency
    addi $zero, $zero, 5
    add  $t2, $zero, $zero
    addi $t9, $zero, 0
    bne  $t2, $t9, fail
    addi $s0, $zero, 10            # test 10: shift then or, back to back
    addi $t0, $zero, 0xF0
    sll  $t1, $t0, 4
    or   $t2, $t1, $t0
    addi $t9, $zero, 4080
    bne  $t2, $t9, fail
    addi $s0, $zero, 11            # test 11: slt feeding add
    addi $t0, $zero, 3
    addi $t1, $zero, 5
    slt  $t2, $t0, $t1
    add  $t3, $t2, $t2
    addi $t9, $zero, 2
    bne  $t3, $t9, fail
    addi $s0, $zero, 12            # test 12: lui feeding ori
    lui  $t0, 0x1234
    ori  $t1, $t0, 0x00FF
    srl  $t2, $t1, 16
    addi $t9, $zero, 4660
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
