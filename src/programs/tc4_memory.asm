# tc4_memory.asm - memory: lw sw
# TC-4: self-checking test. Result goes to the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF (all 10 LEDs on) and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, where nn = number of the test that failed
# Uses only Phase 1 instructions. No pseudo-instructions, no nops
# (MARS with Delayed branching OFF; our assembler adds the nop after branches/jumps).
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    lui  $s1, 0x1001            # s1 = 0x10010000 (data region base)
    addi $s0, $zero, 1            # test 1: sw then lw returns 0x12345678
    lui  $t0, 0x1234
    ori  $t0, $t0, 0x5678
    sw   $t0, 0($s1)
    lw   $t2, 0($s1)
    lui  $t9, 0x1234
    ori  $t9, $t9, 0x5678
    bne  $t2, $t9, fail
    addi $s0, $zero, 2            # test 2: three words at offsets 0 / 4 / 8: first
    addi $t0, $zero, 11
    addi $t1, $zero, 22
    addi $t3, $zero, 33
    sw   $t0, 0($s1)
    sw   $t1, 4($s1)
    sw   $t3, 8($s1)
    lw   $t2, 0($s1)
    addi $t9, $zero, 11
    bne  $t2, $t9, fail
    addi $s0, $zero, 3            # test 3: three words at offsets 0 / 4 / 8: second
    lw   $t2, 4($s1)
    addi $t9, $zero, 22
    bne  $t2, $t9, fail
    addi $s0, $zero, 4            # test 4: three words at offsets 0 / 4 / 8: third
    lw   $t2, 8($s1)
    addi $t9, $zero, 33
    bne  $t2, $t9, fail
    addi $s0, $zero, 5            # test 5: negative offset: lw -4(base+8) reads the word at +4
    addi $t0, $s1, 8
    lw   $t2, -4($t0)
    addi $t9, $zero, 22
    bne  $t2, $t9, fail
    addi $s0, $zero, 6            # test 6: overwrite offset 4 with 99
    addi $t0, $zero, 99
    sw   $t0, 4($s1)
    lw   $t2, 4($s1)
    addi $t9, $zero, 99
    bne  $t2, $t9, fail
    addi $s0, $zero, 7            # test 7: neighbour at offset 0 is unchanged
    lw   $t2, 0($s1)
    addi $t9, $zero, 11
    bne  $t2, $t9, fail
    addi $s0, $zero, 8            # test 8: neighbour at offset 8 is unchanged
    lw   $t2, 8($s1)
    addi $t9, $zero, 33
    bne  $t2, $t9, fail
    addi $s0, $zero, 9            # test 9: a word with the top bit set survives
    lui  $t0, 0x8000
    sw   $t0, 12($s1)
    lw   $t2, 12($s1)
    lui  $t9, 0x8000
    bne  $t2, $t9, fail
    addi $s0, $zero, 10            # test 10: lw into $zero is ignored
    addi $t0, $zero, 77
    sw   $t0, 16($s1)
    lw   $zero, 16($s1)
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
