.data

value:
    .word 1234

.text

main:

    move $t0, $zero

    li $t1, 25

    li $t2, 0x12345678

    la $t3, value

    beq $t0, $zero, target

    li $s0, 9999  

target:

    j end

    li $s1, 8888 

end:

    nop