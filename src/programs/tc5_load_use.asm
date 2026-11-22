# tc5_load_use.asm - load-use hazards (lw followed by an instruction that uses its result)
# TC-5: hazard / delay-slot test, self-checking. Result on the board outputs (MMIO):
#   PASS: LEDR (0xFFFF0018) = 0x3FF and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, nn = number of the test that failed
# Written as in MARS with Delayed branching OFF: NO nops anywhere. Every dependency is
# back-to-back on purpose, so the hazard unit has to stall/forward, and the assembler's
# nop after each branch/jump must not change what the program computes.
# Run on mips_pipeline: from verif, `do tc5.do` (assemble first: python src/assembler/assembler.py src/programs/<name>.asm).
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    lui  $s1, 0x1001            # s1 = 0x10010000 (data region base)
    addi $s0, $zero, 1            # test 1: sw then lw of the same address, back to back
    addi $t0, $zero, 99
    sw   $t0, 16($s1)
    lw   $t1, 16($s1)
    addi $t9, $zero, 99
    bne  $t1, $t9, fail
    addi $s0, $zero, 2            # test 2: load-use at distance 1: lw then add
    addi $t0, $zero, 21
    sw   $t0, 0($s1)
    lw   $t0, 0($s1)
    add  $t1, $t0, $t0
    addi $t9, $zero, 42
    bne  $t1, $t9, fail
    addi $s0, $zero, 3            # test 3: load-use at distance 2
    lw   $t0, 0($s1)
    addi $t3, $zero, 1
    add  $t1, $t0, $t0
    addi $t9, $zero, 42
    bne  $t1, $t9, fail
    addi $s0, $zero, 4            # test 4: loaded value as the second operand
    addi $t3, $zero, 8
    lw   $t0, 0($s1)
    add  $t1, $t3, $t0
    addi $t9, $zero, 29
    bne  $t1, $t9, fail
    addi $s0, $zero, 5            # test 5: pointer chase: lw whose result is the base of the next lw
    addi $t0, $s1, 8
    sw   $t0, 4($s1)
    addi $t2, $zero, 77
    sw   $t2, 8($s1)
    lw   $t1, 4($s1)
    lw   $t3, 0($t1)
    addi $t9, $zero, 77
    bne  $t3, $t9, fail
    addi $s0, $zero, 6            # test 6: load-use into the data of a sw
    lw   $t0, 0($s1)
    sw   $t0, 12($s1)
    lw   $t1, 12($s1)
    addi $t9, $zero, 21
    bne  $t1, $t9, fail
    addi $s0, $zero, 7            # test 7: two loads back to back, then add
    addi $t0, $zero, 10
    sw   $t0, 20($s1)
    addi $t0, $zero, 32
    sw   $t0, 24($s1)
    lw   $t1, 20($s1)
    lw   $t2, 24($s1)
    add  $t3, $t1, $t2
    addi $t9, $zero, 42
    bne  $t3, $t9, fail
    addi $s0, $zero, 8            # test 8: lw into $zero is ignored even if used right away
    lw   $zero, 0($s1)
    add  $t2, $zero, $zero
    addi $t9, $zero, 0
    bne  $t2, $t9, fail
    addi $s0, $zero, 9            # test 9: a later ALU write must beat an earlier load to the same register
    lw   $t0, 0($s1)
    addi $t0, $zero, 5
    add  $t1, $t0, $t0
    addi $t9, $zero, 10
    bne  $t1, $t9, fail
    addi $s0, $zero, 10           # test 10: store then load of different addresses keeps both
    addi $t0, $zero, 1
    addi $t1, $zero, 2
    sw   $t0, 28($s1)
    sw   $t1, 32($s1)
    lw   $t2, 28($s1)
    lw   $t3, 32($s1)
    add  $t4, $t2, $t3
    addi $t9, $zero, 3
    bne  $t4, $t9, fail
    addi $s0, $zero, 11           # test 11: ALU result used right away as the base address of sw and lw
    addi $t0, $zero, 55
    addi $t5, $s1, 36
    sw   $t0, 0($t5)
    addi $t6, $s1, 36
    lw   $t7, 0($t6)
    addi $t9, $zero, 55
    bne  $t7, $t9, fail
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
