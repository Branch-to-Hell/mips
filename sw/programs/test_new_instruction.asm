# Self-checking test for the phase 2 ISA.
# Every result is stored in its own word of results[] (word index r[i] is at
# offset 4*i from $s7). Nothing is overwritten. Expected values: see README.md.
# Branch checks: the good value is set before the branch; a wrong path
# writes 99 (taken when it should not be, or not taken when it should).

.data
data:       .word 0x80FF7F01
memory:     .word 0, 0
results:    .space 148          # 37 words, r[0] .. r[36]

.text
main:
    la $s7, results             # $s7 = base of results[]
    la $s0, data                # $s0 = base of data
    la $s5, memory              # $s5 = base of memory

    # ---------------------------------
    # ADDU, SUBU and ADDIU -> r[0..2]
    # ---------------------------------
    li $t0, 20
    li $t1, 5

    addu  $t2, $t0, $t1         # 25
    sw    $t2, 0($s7)
    subu  $t3, $t0, $t1         # 15
    sw    $t3, 4($s7)
    addiu $t4, $t0, -5          # 15
    sw    $t4, 8($s7)

    # ---------------------------------
    # SLTU and SLTIU -> r[3..4]
    # ---------------------------------
    sltu  $t5, $t1, $t0         # 5 < 20 -> 1
    sw    $t5, 12($s7)
    sltiu $t6, $t1, 10          # 5 < 10 -> 1
    sw    $t6, 16($s7)

    # ---------------------------------
    # XOR and XORI -> r[5..6]
    # ---------------------------------
    li $t0, 0x0000000F
    li $t1, 0x00000003

    xor  $t2, $t0, $t1          # 0xF ^ 0x3 = 0x0000000C
    sw   $t2, 20($s7)
    xori $t3, $t0, 0x00F0       # 0xF ^ 0x00F0 = 0x000000FF
    sw   $t3, 24($s7)

    # ---------------------------------
    # SRA, SLLV, SRLV and SRAV -> r[7..10]
    # ---------------------------------
    li $t0, -16                 # 0xFFFFFFF0
    li $t1, 2

    sra  $t2, $t0, 2            # 0xFFFFFFFC
    sw   $t2, 28($s7)
    sllv $t3, $t0, $t1          # 0xFFFFFFC0
    sw   $t3, 32($s7)
    srlv $t4, $t0, $t1          # 0x3FFFFFFC
    sw   $t4, 36($s7)
    srav $t5, $t0, $t1          # 0xFFFFFFFC
    sw   $t5, 40($s7)

    # ---------------------------------
    # LB, LBU, LH and LHU -> r[11..14]
    # Data: 0x80FF7F01, big-endian
    # ---------------------------------
    lb  $t2, 0($s0)             # 0xFFFFFF80
    sw  $t2, 44($s7)
    lbu $t3, 1($s0)             # 0x000000FF
    sw  $t3, 48($s7)
    lh  $t4, 0($s0)             # 0xFFFF80FF
    sw  $t4, 52($s7)
    lhu $t5, 2($s0)             # 0x00007F01
    sw  $t5, 56($s7)

    # ---------------------------------
    # SB and SH -> r[15]
    # sb 0x55 at byte 0, sh 0x1234 at bytes 2..3 of word 0
    # ---------------------------------
    li $t0, 0x00000055
    sb $t0, 0($s5)
    li $t1, 0x00001234
    sh $t1, 2($s5)
    lw $t2, 0($s5)              # 0x55001234
    sw $t2, 60($s7)

    # ---------------------------------
    # MULT, MULTU, MUL, MFHI and MFLO -> r[16..20]
    # ---------------------------------
    li $t0, 10
    li $t1, 3

    mult  $t0, $t1
    mflo  $t2                   # 30
    sw    $t2, 64($s7)
    mfhi  $t3                   # 0
    sw    $t3, 68($s7)
    multu $t0, $t1
    mflo  $t4                   # 30
    sw    $t4, 72($s7)
    mfhi  $t5                   # 0
    sw    $t5, 76($s7)
    mul   $t6, $t0, $t1         # 30
    sw    $t6, 80($s7)

    # ---------------------------------
    # DIV and DIVU -> r[21..24]
    # ---------------------------------
    li $t0, 20
    li $t1, 3

    div  $t0, $t1
    mflo $t2                    # 6
    sw   $t2, 84($s7)
    mfhi $t3                    # 2
    sw   $t3, 88($s7)
    divu $t0, $t1
    mflo $t4                    # 6
    sw   $t4, 92($s7)
    mfhi $t5                    # 2
    sw   $t5, 96($s7)

    # ---------------------------------
    # MTHI and MTLO -> r[25..26]
    # ---------------------------------
    li $t0, 100
    li $t1, 200

    mthi $t0
    mtlo $t1
    mfhi $t2                    # 100
    sw   $t2, 100($s7)
    mflo $t3                    # 200
    sw   $t3, 104($s7)

    # ---------------------------------
    # BLTZ taken (t0 = -1): r[27] = 1
    # ---------------------------------
    li $t8, 1
    li $t0, -1
    bltz $t0, bltz_taken
    li $t8, 99                  # must be skipped
bltz_taken:
    sw $t8, 108($s7)

    # BLTZ not taken (t0 = 1): r[28] = 2
    li $t8, 99
    li $t0, 1
    bltz $t0, bltz_nt
    li $t8, 2                   # runs because the branch is not taken
bltz_nt:
    sw $t8, 112($s7)

    # ---------------------------------
    # BGEZ taken (t0 = 1): r[29] = 1
    # ---------------------------------
    li $t8, 1
    li $t0, 1
    bgez $t0, bgez_taken
    li $t8, 99                  # must be skipped
bgez_taken:
    sw $t8, 116($s7)

    # BGEZ not taken (t0 = -1): r[30] = 2
    li $t8, 99
    li $t0, -1
    bgez $t0, bgez_nt
    li $t8, 2
bgez_nt:
    sw $t8, 120($s7)

    # ---------------------------------
    # BLEZ taken (t0 = 0): r[31] = 1
    # ---------------------------------
    li $t8, 1
    li $t0, 0
    blez $t0, blez_taken
    li $t8, 99                  # must be skipped
blez_taken:
    sw $t8, 124($s7)

    # BLEZ not taken (t0 = 5): r[32] = 2
    li $t8, 99
    li $t0, 5
    blez $t0, blez_nt
    li $t8, 2
blez_nt:
    sw $t8, 128($s7)

    # ---------------------------------
    # BGTZ taken (t0 = 5): r[33] = 1
    # ---------------------------------
    li $t8, 1
    li $t0, 5
    bgtz $t0, bgtz_taken
    li $t8, 99                  # must be skipped
bgtz_taken:
    sw $t8, 132($s7)

    # BGTZ not taken (t0 = 0): r[34] = 2
    li $t8, 99
    li $t0, 0
    bgtz $t0, bgtz_nt
    li $t8, 2
bgtz_nt:
    sw $t8, 136($s7)

    # ---------------------------------
    # J: the jump must skip the store of 99. r[35] = 1
    # ---------------------------------
    li $t8, 1
    j j_ok
    li $t8, 99                  # must be skipped
j_ok:
    sw $t8, 140($s7)

    # ---------------------------------
    # JALR: the function sets $t8 = 5 and returns. r[36] = 5
    # ---------------------------------
    la   $t9, function
    jalr $ra, $t9
    sw   $t8, 144($s7)

end:
    j end

function:
    li $t8, 5
    jr $ra
