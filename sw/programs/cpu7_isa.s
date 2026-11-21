# cpu7_isa.s - CPU-7: the rest of the MIPS I integer set (contracts.md "ISA", phase 2)
#   sltu sltiu xor xori sra sllv srlv srav lb lbu lh lhu sb sh
#   bltz bgez blez bgtz bltzal bgezal jalr
# Self-checking, same protocol as TC-4 (pipeline_program_tb / cpu7_tb):
#   PASS: LEDR (0xFFFF0018) = 0x3FF, then HEX (0xFFFF001C) = 0x00600D
#   FAIL: HEX = 0xBAD0nn (nn = test number in $s0), then LEDR = 0
# GNU as syntax (assembled by the real toolchain with sw/tools/gas_image.sh, which is
# also an independent check of our encodings). .set noreorder: every delay slot is
# written explicitly, as GCC does; the CPU always runs it (CPU-6).
    .set noreorder
    .set noat
    .text
    .globl main
main:
    lui   $s6, 0xFFFF              # MMIO base
    lui   $s1, 0x1001              # data region base

# --- sltu / sltiu -------------------------------------------------------------
    addiu $s0, $zero, 1            # 1: sltu 1 < 0xFFFFFFFF (unsigned) = 1
    addiu $t0, $zero, 1
    addiu $t1, $zero, -1
    sltu  $t2, $t0, $t1
    addiu $t9, $zero, 1
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 2            # 2: slt 1 < -1 (signed) = 0, same operands
    slt   $t2, $t0, $t1
    bne   $t2, $zero, fail
    nop
    addiu $s0, $zero, 3            # 3: sltu 0xFFFFFFFF < 1 = 0
    sltu  $t2, $t1, $t0
    bne   $t2, $zero, fail
    nop
    addiu $s0, $zero, 4            # 4: sltiu sign-extends 0xFFFF then compares unsigned: 5 < 0xFFFFFFFF
    addiu $t0, $zero, 5
    sltiu $t2, $t0, -1
    addiu $t9, $zero, 1
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 5            # 5: sltiu 0xFFFFFFFF < 1 = 0
    sltiu $t2, $t1, 1
    bne   $t2, $zero, fail
    nop

# --- xor / xori -----------------------------------------------------------------
    addiu $s0, $zero, 6            # 6: 0xF0F0F0F0 ^ 0xFF00FF00 = 0x0FF00FF0
    lui   $t0, 0xF0F0
    ori   $t0, $t0, 0xF0F0
    lui   $t1, 0xFF00
    ori   $t1, $t1, 0xFF00
    xor   $t2, $t0, $t1
    lui   $t9, 0x0FF0
    ori   $t9, $t9, 0x0FF0
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 7            # 7: xori zero-extends: 0xFFFF0000 ^ 0x8001 = 0xFFFF8001
    lui   $t0, 0xFFFF
    xori  $t2, $t0, 0x8001
    lui   $t9, 0xFFFF
    ori   $t9, $t9, 0x8001
    bne   $t2, $t9, fail
    nop

# --- shifts ---------------------------------------------------------------------
    addiu $s0, $zero, 8            # 8: sra keeps the sign: 0x80000010 >> 4 = 0xF8000001
    lui   $t0, 0x8000
    ori   $t0, $t0, 0x0010
    sra   $t2, $t0, 4
    lui   $t9, 0xF800
    ori   $t9, $t9, 0x0001
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 9            # 9: sra of a positive value: 0x40000000 >> 30 = 1
    lui   $t0, 0x4000
    sra   $t2, $t0, 30
    addiu $t9, $zero, 1
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 10           # 10: sllv uses rs[4:0] only: 1 << 33 = 1 << 1 = 2
    addiu $t0, $zero, 1
    addiu $t1, $zero, 33
    sllv  $t2, $t0, $t1
    addiu $t9, $zero, 2
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 11           # 11: srlv is logical: 0x80000000 >> 31 = 1
    lui   $t0, 0x8000
    addiu $t1, $zero, 31
    srlv  $t2, $t0, $t1
    addiu $t9, $zero, 1
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 12           # 12: srav is arithmetic: 0x80000000 >> 31 = 0xFFFFFFFF
    srav  $t2, $t0, $t1
    addiu $t9, $zero, -1
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 13           # 13: srav by 32 = by 0: value unchanged
    addiu $t1, $zero, 32
    srav  $t2, $t0, $t1
    bne   $t2, $t0, fail
    nop

# --- byte and half loads/stores (big-endian: offset 0 = bits 31..24) -------------
    addiu $s0, $zero, 14           # 14: sb at offset 1 changes only that byte: 0x11AB3344
    lui   $t0, 0x1122
    ori   $t0, $t0, 0x3344
    sw    $t0, 0($s1)
    addiu $t1, $zero, 0xAB
    sb    $t1, 1($s1)
    lw    $t2, 0($s1)
    lui   $t9, 0x11AB
    ori   $t9, $t9, 0x3344
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 15           # 15: lb sign-extends: 0xAB -> 0xFFFFFFAB
    lb    $t2, 1($s1)
    addiu $t9, $zero, -85          # 0xFFFFFFAB
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 16           # 16: lbu zero-extends: 0xAB
    lbu   $t2, 1($s1)
    addiu $t9, $zero, 0xAB
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 17           # 17: lb of offsets 0 and 3 (0x11, 0x44)
    lb    $t2, 0($s1)
    addiu $t9, $zero, 0x11
    bne   $t2, $t9, fail
    nop
    lb    $t2, 3($s1)
    addiu $t9, $zero, 0x44
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 18           # 18: sh at offset 2 changes only the low half: 0x11AB8001
    ori   $t1, $zero, 0x8001
    sh    $t1, 2($s1)
    lw    $t2, 0($s1)
    lui   $t9, 0x11AB
    ori   $t9, $t9, 0x8001
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 19           # 19: lh sign-extends: 0x8001 -> 0xFFFF8001
    lh    $t2, 2($s1)
    lui   $t9, 0xFFFF
    ori   $t9, $t9, 0x8001
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 20           # 20: lhu zero-extends: 0x00008001
    lhu   $t2, 2($s1)
    ori   $t9, $zero, 0x8001
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 21           # 21: lh at offset 0 = 0x11AB
    lh    $t2, 0($s1)
    ori   $t9, $zero, 0x11AB
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 22           # 22: sh at offset 0 = 0xCAFE8001, neighbour word untouched
    lui   $t0, 0x5555
    ori   $t0, $t0, 0x5555
    sw    $t0, 4($s1)
    ori   $t1, $zero, 0xCAFE
    sh    $t1, 0($s1)
    lw    $t2, 0($s1)
    lui   $t9, 0xCAFE
    ori   $t9, $t9, 0x8001
    bne   $t2, $t9, fail
    nop
    lw    $t2, 4($s1)
    bne   $t2, $t0, fail
    nop
    addiu $s0, $zero, 23           # 23: four sb build 0x01020304 (only the low byte of rt is stored)
    addiu $t0, $s1, 8
    addiu $t1, $zero, 0x701        # low byte 0x01
    sb    $t1, 0($t0)
    addiu $t1, $zero, 0x02
    sb    $t1, 1($t0)
    addiu $t1, $zero, 0x03
    sb    $t1, 2($t0)
    addiu $t1, $zero, 0x04
    sb    $t1, 3($t0)
    lw    $t2, 0($t0)
    lui   $t9, 0x0102
    ori   $t9, $t9, 0x0304
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 24           # 24: load-use with lbu, no nops: the hazard unit waits
    lbu   $t2, 9($s1)              # 0x02
    addu  $t2, $t2, $t2            # 0x04
    addiu $t9, $zero, 4
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 25           # 25: lb into $zero is ignored
    lb    $zero, 1($s1)
    bne   $zero, $zero, fail
    nop

# --- branches against zero (each with a delay slot that must run) -----------------
    addiu $s0, $zero, 26           # 26: bltz taken on a negative value, delay slot runs
    addiu $t0, $zero, -5
    addiu $t3, $zero, 0
    bltz  $t0, 1f
    addiu $t3, $t3, 1              # delay slot
    b     fail                     # skipped
    nop
1:  addiu $t9, $zero, 1
    bne   $t3, $t9, fail
    nop
    addiu $s0, $zero, 27           # 27: bltz not taken on zero
    bltz  $zero, fail
    nop
    addiu $s0, $zero, 28           # 28: bgez taken on zero
    bgez  $zero, 1f
    nop
    b     fail
    nop
1:  addiu $s0, $zero, 29           # 29: bgez not taken on a negative value
    bgez  $t0, fail
    nop
    addiu $s0, $zero, 30           # 30: blez taken on zero and on a negative value
    blez  $zero, 1f
    nop
    b     fail
    nop
1:  blez  $t0, 1f
    nop
    b     fail
    nop
1:  addiu $s0, $zero, 31           # 31: blez not taken on a positive value
    addiu $t1, $zero, 7
    blez  $t1, fail
    nop
    addiu $s0, $zero, 32           # 32: bgtz taken on a positive value, not on zero or negative
    bgtz  $zero, fail
    nop
    bgtz  $t0, fail
    nop
    bgtz  $t1, 1f
    nop
    b     fail
    nop
1:  addiu $s0, $zero, 33           # 33: bgtz on 0x80000000 (most negative) not taken
    lui   $t2, 0x8000
    bgtz  $t2, fail
    nop
    addiu $s0, $zero, 34           # 34: branch on a value produced just before (hazard), backward loop
    addiu $t0, $zero, 3            # counts 3, 2, 1, 0
    addiu $t3, $zero, 0
2:  addiu $t0, $t0, -1
    bgtz  $t0, 2b
    addiu $t3, $t3, 1              # delay slot: runs on every pass, 3 times
    addiu $t9, $zero, 3
    bne   $t3, $t9, fail
    nop

# --- links: bgezal, bltzal, jalr --------------------------------------------------
    addiu $s0, $zero, 35           # 35: bgezal $zero (bal) jumps and $ra = its PC + 8
    bgezal $zero, 1f
    nop
ret35:
    b     fail
    nop
1:  la    $t9, ret35
    bne   $ra, $t9, fail
    nop
    addiu $s0, $zero, 36           # 36: bltzal not taken still writes $ra = PC + 8
    addiu $ra, $zero, 0
    bltzal $zero, fail
    nop
ret36:
    la    $t9, ret36
    bne   $ra, $t9, fail
    nop
    addiu $s0, $zero, 37           # 37: jalr rs: jumps, delay slot runs, $ra = PC + 8
    la    $t0, sub37
    addiu $t3, $zero, 0
    jalr  $t0
    addiu $t3, $t3, 1              # delay slot
ret37:
    b     fail                     # sub37 returns past this
    nop
sub37:
    la    $t9, ret37
    bne   $ra, $t9, fail
    nop
    addiu $t9, $zero, 1
    bne   $t3, $t9, fail
    nop
    addiu $s0, $zero, 38           # 38: jalr rd, rs writes rd (not $ra); return with jr rd
    addiu $ra, $zero, 0x55
    la    $t0, sub38
    jalr  $t8, $t0
    nop
ret38:
    addiu $t9, $zero, 0x55         # back here: $ra untouched
    bne   $ra, $t9, fail
    nop
    b     39f
    nop
sub38:
    la    $t9, ret38
    bne   $t8, $t9, fail
    nop
    jr    $t8
    nop
39:
# --- unknown R-type funct (break) writes nothing ----------------------------------
    addiu $s0, $zero, 39           # 39: a break word with rd = $ra in its code field is a nop
    addiu $ra, $zero, 0x1234
    .word 0x0000F80D               # break, bits 15..11 = 31
    addiu $t9, $zero, 0x1234
    bne   $ra, $t9, fail
    nop
    b     pass
    nop

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
