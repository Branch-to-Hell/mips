# cpu8_muldiv.s - CPU-8: HI/LO, mult multu div divu mfhi mflo mthi mtlo
# Self-checking, same protocol as TC-4 (see cpu7_isa.s). Expected values were computed
# with Python (C semantics: the quotient rounds toward zero, the remainder takes the
# dividend's sign). No nops between HI/LO instructions: the hazard unit waits for the
# divider (32 cycles) and GCC-style code may read HI/LO right away.
    .set noreorder
    .set noat
    .text
    .globl main
main:
    lui   $s6, 0xFFFF              # MMIO base

# --- multiply ----------------------------------------------------------------------
    addiu $s0, $zero, 1            # 1: mult 7 * 6 = 42, HI = 0
    addiu $t0, $zero, 7
    addiu $t1, $zero, 6
    mult  $t0, $t1
    mflo  $t2
    addiu $t9, $zero, 42
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    bne   $t2, $zero, fail
    nop
    addiu $s0, $zero, 2            # 2: mult -3 * 5 = -15: HI = 0xFFFFFFFF, LO = 0xFFFFFFF1
    addiu $t0, $zero, -3
    addiu $t1, $zero, 5
    mult  $t0, $t1
    mfhi  $t2
    addiu $t9, $zero, -1
    bne   $t2, $t9, fail
    nop
    mflo  $t2
    addiu $t9, $zero, -15
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 3            # 3: multu 0xFFFFFFFF^2 = 0xFFFFFFFE_00000001
    addiu $t0, $zero, -1
    multu $t0, $t0
    mfhi  $t2
    addiu $t9, $zero, -2
    bne   $t2, $t9, fail
    nop
    mflo  $t2
    addiu $t9, $zero, 1
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 4            # 4: mult -1 * -1 = 1 (signed): HI = 0
    mult  $t0, $t0
    mfhi  $t2
    bne   $t2, $zero, fail
    nop
    mflo  $t2
    addiu $t9, $zero, 1
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 5            # 5: mult 0x12345678 * 0x9ABCDEF0 = 0xF8CC93D6_242D2080
    lui   $t0, 0x1234
    ori   $t0, $t0, 0x5678
    lui   $t1, 0x9ABC
    ori   $t1, $t1, 0xDEF0
    mult  $t0, $t1
    mfhi  $t2
    lui   $t9, 0xF8CC
    ori   $t9, $t9, 0x93D6
    bne   $t2, $t9, fail
    nop
    mflo  $t2
    lui   $t9, 0x242D
    ori   $t9, $t9, 0x2080
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 6            # 6: multu of the same = 0x0B00EA4E_242D2080
    multu $t0, $t1
    mfhi  $t2
    lui   $t9, 0x0B00
    ori   $t9, $t9, 0xEA4E
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 7            # 7: mult 0x80000000^2 = 0x40000000_00000000
    lui   $t0, 0x8000
    mult  $t0, $t0
    mfhi  $t2
    lui   $t9, 0x4000
    bne   $t2, $t9, fail
    nop
    mflo  $t2
    bne   $t2, $zero, fail
    nop
    addiu $s0, $zero, 8            # 8: operands produced right before mult (GPR hazard)
    addiu $t0, $zero, 9
    addiu $t1, $zero, 11
    mult  $t0, $t1
    mflo  $t2
    addiu $t2, $t2, 1              # uses mflo's result right away
    addiu $t9, $zero, 100
    bne   $t2, $t9, fail
    nop

# --- divide ------------------------------------------------------------------------
    addiu $s0, $zero, 9            # 9: div 100 / 7: LO = 14, HI = 2 (mflo right after div waits)
    addiu $t0, $zero, 100
    addiu $t1, $zero, 7
    div   $zero, $t0, $t1
    mflo  $t2
    addiu $t9, $zero, 14
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    addiu $t9, $zero, 2
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 10           # 10: div -100 / 7: LO = -14, HI = -2
    addiu $t0, $zero, -100
    div   $zero, $t0, $t1
    mflo  $t2
    addiu $t9, $zero, -14
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    addiu $t9, $zero, -2
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 11           # 11: div 100 / -7: LO = -14, HI = 2
    addiu $t0, $zero, 100
    addiu $t1, $zero, -7
    div   $zero, $t0, $t1
    mflo  $t2
    addiu $t9, $zero, -14
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    addiu $t9, $zero, 2
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 12           # 12: div -100 / -7: LO = 14, HI = -2
    addiu $t0, $zero, -100
    div   $zero, $t0, $t1
    mflo  $t2
    addiu $t9, $zero, 14
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    addiu $t9, $zero, -2
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 13           # 13: divu 0xFFFFFFFF / 16: LO = 0x0FFFFFFF, HI = 15
    addiu $t0, $zero, -1
    addiu $t1, $zero, 16
    divu  $zero, $t0, $t1
    mflo  $t2
    lui   $t9, 0x0FFF
    ori   $t9, $t9, 0xFFFF
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    addiu $t9, $zero, 15
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 14           # 14: div 0x80000000 / -1: LO = 0x80000000, HI = 0
    lui   $t0, 0x8000
    addiu $t1, $zero, -1
    div   $zero, $t0, $t1
    mflo  $t2
    bne   $t2, $t0, fail
    nop
    mfhi  $t2
    bne   $t2, $zero, fail
    nop
    addiu $s0, $zero, 15           # 15: divu 0x9ABCDEF0 / 0x1234: LO = 0x88028, HI = 0x6D0
    lui   $t0, 0x9ABC
    ori   $t0, $t0, 0xDEF0
    ori   $t1, $zero, 0x1234
    divu  $zero, $t0, $t1
    mflo  $t2
    lui   $t9, 0x0008
    ori   $t9, $t9, 0x8028
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    ori   $t9, $zero, 0x06D0
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 16           # 16: div of the same (signed): LO = 0xFFFA6FE6, HI = 0xFFFFF838
    div   $zero, $t0, $t1
    mflo  $t2
    lui   $t9, 0xFFFA
    ori   $t9, $t9, 0x6FE6
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    addiu $t9, $zero, -1992        # 0xFFFFF838
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 17           # 17: independent instructions keep running during a divide
    addiu $t0, $zero, 1000
    addiu $t1, $zero, 10
    div   $zero, $t0, $t1
    addiu $t3, $zero, 1            # these do not touch HI/LO: no wait
    addiu $t3, $t3, 2
    addiu $t3, $t3, 3
    mflo  $t2                      # waits here for the quotient
    addiu $t9, $zero, 100
    bne   $t2, $t9, fail
    nop
    addiu $t9, $zero, 6
    bne   $t3, $t9, fail
    nop

# --- mthi / mtlo and ordering --------------------------------------------------------
    addiu $s0, $zero, 18           # 18: mthi/mtlo then mfhi/mflo
    lui   $t0, 0xDEAD
    ori   $t0, $t0, 0xBEEF
    lui   $t1, 0x0123
    ori   $t1, $t1, 0x4567
    mthi  $t0
    mtlo  $t1
    mfhi  $t2
    bne   $t2, $t0, fail
    nop
    mflo  $t2
    bne   $t2, $t1, fail
    nop
    addiu $s0, $zero, 19           # 19: mthi right after div waits for it, then overwrites HI only
    addiu $t0, $zero, 50
    addiu $t1, $zero, 8
    div   $zero, $t0, $t1          # LO = 6, HI = 2
    addiu $t3, $zero, 77
    mthi  $t3
    mfhi  $t2
    addiu $t9, $zero, 77
    bne   $t2, $t9, fail
    nop
    mflo  $t2
    addiu $t9, $zero, 6
    bne   $t2, $t9, fail
    nop
    addiu $s0, $zero, 20           # 20: mult right after div waits, and its result wins
    div   $zero, $t0, $t1
    mult  $t1, $t1                 # 64
    mflo  $t2
    addiu $t9, $zero, 64
    bne   $t2, $t9, fail
    nop
    mfhi  $t2
    bne   $t2, $zero, fail
    nop
    addiu $s0, $zero, 21           # 21: mfhi into $zero is ignored
    mfhi  $zero
    bne   $zero, $zero, fail
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
