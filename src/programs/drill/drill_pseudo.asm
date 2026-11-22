# drill_pseudo.asm - TC-12 practice program: one of each MARS pseudo-instruction that mars_compat.py
# rewrites, with a check after each. Expected: $s0 = 0 (no failure code), vals+8 = 7, $s3 = 1.
# It has no exit syscall: it just ends, like many MARS examples.
.data
vals: .word 100, 200, 0
.text
    li   $t0, -5
    not  $t1, $t0                 # 4
    neg  $t2, $t0                 # 5
    addi $t3, $zero, 100000       # immediate too big for addi
    andi $t4, $t3, 0x1FFFF        # immediate too big for andi
    ori  $t5, $zero, 0x12345      # immediate too big for ori
    lw   $t6, vals+4              # 200
    li   $s0, 0
    beq  $t6, 200, ok1            # branch against an immediate
    li   $s0, 99
ok1:
    blt  $t0, -2, ok2             # -5 < -2
    li   $s0, 98
ok2:
    bgt  $t3, 50000, ok3
    li   $s0, 97
ok3:
    bltz $t0, ok4
    li   $s0, 96
ok4:
    bgtz $t0, bad                 # not taken
    ble  $t1, 4, ok5              # 4 <= 4
bad:
    li   $s0, 95
ok5:
    addi $s1, $s0, 7              # 7 when every check passed
    sw   $s1, vals+8
    subi $s2, $s1, 40000          # immediate too big for subi
    bge  $t2, 100000, bad2        # 5 >= 100000: not taken (needs li + slt)
    addi $s3, $zero, 1
bad2:
