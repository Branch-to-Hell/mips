# drill_stats.asm - TC-12 practice program, written the way MARS users write (pseudo-instructions,
# lw/sw with labels, syscalls). Sum, maximum and number of negatives of an array.
# Expected: sum = 32, max = 20, negatives = 3 (also printed by syscall 1 in MARS)
.data
arr: .word 5, -3, 12, 0, -8, 7, 20, -1
n:   .word 8
sum: .word 0
max: .word 0
neg: .word 0
.text
main:
    la   $s0, arr
    lw   $s1, n
    li   $t0, 0              # i
    li   $t1, 0              # sum
    lw   $t2, 0($s0)         # max = arr[0]
    li   $t3, 0              # negatives
loop:
    bge  $t0, $s1, done
    sll  $t4, $t0, 2
    add  $t4, $t4, $s0
    lw   $t5, 0($t4)
    add  $t1, $t1, $t5
    ble  $t5, $t2, no_max
    move $t2, $t5
no_max:
    bgez $t5, not_neg
    addi $t3, $t3, 1
not_neg:
    addi $t0, $t0, 1
    b    loop
done:
    sw   $t1, sum
    sw   $t2, max
    sw   $t3, neg
    move $a0, $t1
    li   $v0, 1              # print the sum
    syscall
    li   $v0, 10             # exit
    syscall
