.data
value:      .word 25
result:     .word 0
space:      .space 16

.text
main:
    # LI with a small immediate
    li $t0, 100

    # LI with a negative immediate
    li $t1, -20

    # LI requiring LUI + ORI
    li $t2, 0x12345678

    # LA loads the address of a label
    la $s0, value

    # MOVE copies the contents of a register
    move $s1, $t0

    # NOP performs no operation
    nop

    # Check that LA points to the correct data
    lw $s2, 0($s0)

    # Calculate and store the result
    add $s3, $s2, $s1
    la $s4, result
    sw $s3, 0($s4)

end:
    j end
