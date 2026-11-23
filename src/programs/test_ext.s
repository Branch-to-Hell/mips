# test_ext.s - PLT-8 + PLT-12: the SDRAM through ext_memory (bridge + instruction cache).
# Runs from the on-chip text at 0x0 (like boot.S in top_doom) and uses the SDRAM region:
#   1-16  words written and read back (also across a 16-byte cache line and a 2 KB row)
#   17-24 byte/half stores and loads, big-endian (sb sh lb lbu lh lhu), as on the data region
#   25-26 a routine copied into the SDRAM and called twice (jalr): the first call fills the
#         instruction cache from the SDRAM, the second one runs from the cache; both must
#         return the sum of the 16 words of test 1
#   27    a second routine at an address with the same cache index (8 KB further), so it
#         replaces the first line; then the first one again (a miss again, same sum)
# Self-checking, same protocol as TC-4 / cpu7_isa:
#   PASS: LEDR (0xFFFF0018) = 0x3FF, then HEX (0xFFFF001C) = 0x00600D
#   FAIL: HEX = 0xBAD0nn (nn = test number in $s0), then LEDR = 0
# Assemble with src/tools/gas_image.sh (GNU as), then src/tools/hex2banks.py mem/test_ext.hex.
# Simulations: verif/doom_mem.do (ModelSim: the real Intel SDRAM controller and its memory
# model) and the Verilator harness.
    .set noreorder
    .set noat
    .text
    .globl main
main:
    lui   $s6, 0xFFFF              # MMIO base
    lui   $s7, 0x2000              # SDRAM base

# --- 1-16: 16 words at 0x2000_0000, value i * 0x00010001 + 0x1234, read back ----------
    addiu $t0, $zero, 0            # i
    addiu $s1, $zero, 0            # expected sum
    move  $t2, $s7                 # address
fill:
    sll   $t3, $t0, 16
    addu  $t3, $t3, $t0
    addiu $t3, $t3, 0x1234         # value
    sw    $t3, 0($t2)
    addu  $s1, $s1, $t3
    addiu $t0, $t0, 1
    slti  $t4, $t0, 16
    bne   $t4, $zero, fill
    addiu $t2, $t2, 4              # delay slot

    addiu $t0, $zero, 0
    move  $t2, $s7
check:
    addiu $s0, $t0, 1              # test number 1..16
    sll   $t3, $t0, 16
    addu  $t3, $t3, $t0
    addiu $t3, $t3, 0x1234
    lw    $t5, 0($t2)
    bne   $t5, $t3, fail
    nop
    addiu $t0, $t0, 1
    slti  $t4, $t0, 16
    bne   $t4, $zero, check
    addiu $t2, $t2, 4

# --- 17-24: byte and half lanes at 0x2000_0800 (another SDRAM row) -------------------
    addiu $t2, $s7, 0x800
    lui   $t3, 0x1122
    ori   $t3, $t3, 0x3344
    sw    $t3, 0($t2)
    addiu $t3, $zero, 0xAA
    sb    $t3, 0($t2)              # bits 31..24
    lw    $t5, 0($t2)
    lui   $t6, 0xAA22
    ori   $t6, $t6, 0x3344
    addiu $s0, $zero, 17
    bne   $t5, $t6, fail
    nop
    addiu $t3, $zero, 0x5566
    sh    $t3, 2($t2)              # bits 15..0
    lw    $t5, 0($t2)
    lui   $t6, 0xAA22
    ori   $t6, $t6, 0x5566
    addiu $s0, $zero, 18
    bne   $t5, $t6, fail
    nop
    addiu $t3, $zero, 0xDD
    sb    $t3, 3($t2)              # bits 7..0
    lw    $t5, 0($t2)
    lui   $t6, 0xAA22
    ori   $t6, $t6, 0x55DD
    addiu $s0, $zero, 19
    bne   $t5, $t6, fail
    nop
    lbu   $t5, 1($t2)
    addiu $t6, $zero, 0x22
    addiu $s0, $zero, 20
    bne   $t5, $t6, fail
    nop
    lb    $t5, 0($t2)              # 0xAA sign-extended
    addiu $t6, $zero, -86
    addiu $s0, $zero, 21
    bne   $t5, $t6, fail
    nop
    lbu   $t5, 0($t2)
    addiu $t6, $zero, 0xAA
    addiu $s0, $zero, 22
    bne   $t5, $t6, fail
    nop
    lh    $t5, 2($t2)              # 0x55DD
    addiu $t6, $zero, 0x55DD
    addiu $s0, $zero, 23
    bne   $t5, $t6, fail
    nop
    addiu $t3, $zero, -2           # 0xFFFE
    sh    $t3, 0($t2)
    lhu   $t5, 0($t2)
    ori   $t6, $zero, 0xFFFE
    addiu $s0, $zero, 24
    bne   $t5, $t6, fail
    nop

# --- 25-26: copy sum16 to 0x2000_0100 and call it twice -----------------------------------
    addiu $a0, $s7, 0x100
    jal   copy_sum16
    nop
    addiu $s0, $zero, 25
    jalr  $a0                      # first call: cache misses
    nop
    bne   $v0, $s1, fail
    nop
    addiu $s0, $zero, 26
    jalr  $a0                      # second call: hits
    nop
    bne   $v0, $s1, fail
    nop

# --- 27: the same routine 8 KB further (same cache index), then the first one again -------
    lui   $a0, 0x2000
    ori   $a0, $a0, 0x2100
    jal   copy_sum16
    nop
    addiu $s0, $zero, 27
    jalr  $a0
    nop
    bne   $v0, $s1, fail
    nop
    addiu $a0, $s7, 0x100
    jalr  $a0                      # the line was replaced: a miss again
    nop
    bne   $v0, $s1, fail
    nop
    b     pass
    nop

# copy_sum16($a0): writes this routine at $a0 (10 words), keeps $a0. The routine returns
# in $v0 the sum of the 16 words at 0x2000_0000:
#       addiu $v0, $zero, 0      24020000
#       lui   $t0, 0x2000        3C082000
#       addiu $t1, $zero, 16     24090010
#   1:  lw    $t2, 0($t0)        8D0A0000
#       addiu $t1, $t1, -1       2529FFFF
#       addu  $v0, $v0, $t2      004A1021
#       bne   $t1, $zero, 1b     1520FFFC
#       addiu $t0, $t0, 4        25080004
#       jr    $ra                03E00008
#       nop                      00000000
copy_sum16:
    lui   $t1, 0x2402
    sw    $t1, 0($a0)
    lui   $t1, 0x3C08
    ori   $t1, $t1, 0x2000
    sw    $t1, 4($a0)
    lui   $t1, 0x2409
    ori   $t1, $t1, 0x0010
    sw    $t1, 8($a0)
    lui   $t1, 0x8D0A
    sw    $t1, 12($a0)
    lui   $t1, 0x2529
    ori   $t1, $t1, 0xFFFF
    sw    $t1, 16($a0)
    lui   $t1, 0x004A
    ori   $t1, $t1, 0x1021
    sw    $t1, 20($a0)
    lui   $t1, 0x1520
    ori   $t1, $t1, 0xFFFC
    sw    $t1, 24($a0)
    lui   $t1, 0x2508
    ori   $t1, $t1, 0x0004
    sw    $t1, 28($a0)
    lui   $t1, 0x03E0
    ori   $t1, $t1, 0x0008
    sw    $t1, 32($a0)
    jr    $ra
    sw    $zero, 36($a0)           # delay slot

fail:
    lui   $t0, 0x00BA
    ori   $t0, $t0, 0xD000
    addu  $t0, $t0, $s0            # 0x00BAD000 + test number
    sw    $t0, 0x1C($s6)           # HEX shows BAD0nn
    sw    $zero, 0x18($s6)         # all LEDs off
stop_fail:
    b     stop_fail
    nop
pass:
    addiu $t0, $zero, 0x3FF
    sw    $t0, 0x18($s6)           # all LEDs on
    ori   $t0, $zero, 0x600D
    sw    $t0, 0x1C($s6)           # HEX shows 00600D
stop_pass:
    b     stop_pass
    nop
