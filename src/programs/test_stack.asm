# test_stack.asm - stack region 0x7FFF_E000 - 0x7FFF_EFFF and $sp at reset (PLT-13)
# Self-checking test. Result goes to the board outputs (MMIO), like the TC-4 tests:
#   PASS: LEDR (0xFFFF0018) = 0x3FF (all 10 LEDs on) and HEX (0xFFFF001C) = 0x00600D
#   FAIL: LEDR = 0 and HEX = 0xBAD0nn, where nn = number of the test that failed
# Uses only Phase 1 instructions. No pseudo-instructions, no nops
# (MARS with Delayed branching OFF; our assembler adds the nop after branches/jumps).
# $s0 = number of the test running; the functions only use $a0, $v0, $t0-$t2 and $ra.
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)
    lui  $s1, 0x1001            # s1 = 0x10010000 (data region base)
    lui  $s2, 0x7FFF
    ori  $s2, $s2, 0xE000       # s2 = 0x7FFFE000 (stack region base, lowest word)
    lui  $s3, 0x7FFF
    ori  $s3, $s3, 0xEFFC       # s3 = 0x7FFFEFFC (top of the stack, $sp at reset)

    addi $s0, $zero, 1          # test 1: $sp starts at 0x7FFFEFFC (MARS default)
    bne  $sp, $s3, fail

    addi $s0, $zero, 2          # test 2: push two words, pop them in reverse order
    lui  $t0, 0x1234
    ori  $t0, $t0, 0x5678
    addi $t1, $zero, -7
    addi $sp, $sp, -8
    sw   $t0, 4($sp)
    sw   $t1, 0($sp)
    lw   $t2, 0($sp)
    bne  $t2, $t1, fail
    lw   $t2, 4($sp)
    bne  $t2, $t0, fail
    addi $sp, $sp, 8
    bne  $sp, $s3, fail

    addi $s0, $zero, 3          # test 3: nested calls main -> f1 -> f2 -> f3, each saves $ra
    jal  f1                     # f1 returns 100 + (10 + 3) = 113
    addi $t9, $zero, 113
    bne  $v0, $t9, fail
    addi $s0, $zero, 4          # test 4: $sp is back at the top after the calls
    bne  $sp, $s3, fail

    addi $s0, $zero, 5          # test 5: recursion, sum(20) = 20 + 19 + ... + 1 = 210
    addi $a0, $zero, 20         # 21 frames of 8 bytes on the stack
    jal  sum
    addi $t9, $zero, 210
    bne  $v0, $t9, fail
    addi $s0, $zero, 6          # test 6: $sp is back at the top after the recursion
    bne  $sp, $s3, fail

    addi $s0, $zero, 7          # test 7: lowest and highest words of the region
    addi $t0, $zero, 0x111
    addi $t1, $zero, 0x222
    sw   $t0, 0($s2)            # 0x7FFFE000
    sw   $t1, 0($s3)            # 0x7FFFEFFC
    lw   $t2, 0($s2)
    bne  $t2, $t0, fail
    lw   $t2, 0($s3)
    bne  $t2, $t1, fail

    addi $s0, $zero, 8          # test 8: stack and data are separate memories
    addi $t1, $zero, 0x333      # 0x10010000 has the same word index as 0x7FFFE000
    sw   $t1, 0($s1)
    lw   $t2, 0($s2)
    addi $t9, $zero, 0x111
    bne  $t2, $t9, fail         # the stack word didn't change
    lw   $t2, 0($s1)
    bne  $t2, $t1, fail         # and the data word holds its own value

    # Accesses just outside the stack (0x7FFFF000, 0x7FFFDFFC) used to be ignored. Since CPU-14
    # they halt the CPU, so they are checked in test_halt.asm (halt_tb) instead.
    j    pass

# f1: returns 100 + f2()
f1:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    jal  f2
    addi $v0, $v0, 100
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# f2: returns 10 + f3()
f2:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    jal  f3
    addi $v0, $v0, 10
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# f3: leaf, returns 3 (no stack frame)
f3:
    addi $v0, $zero, 3
    jr   $ra

# sum(a0): returns a0 + (a0 - 1) + ... + 1, recursive; saves $ra and a0 on the stack
sum:
    addi $sp, $sp, -8
    sw   $ra, 4($sp)
    sw   $a0, 0($sp)
    bne  $a0, $zero, sum_rec
    addi $v0, $zero, 0          # sum(0) = 0
    j    sum_ret
sum_rec:
    addi $a0, $a0, -1
    jal  sum                    # v0 = sum(a0 - 1)
    lw   $a0, 0($sp)
    add  $v0, $v0, $a0
sum_ret:
    lw   $ra, 4($sp)
    addi $sp, $sp, 8
    jr   $ra

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
