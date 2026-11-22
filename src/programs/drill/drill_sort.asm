# drill_sort.asm - TC-12 practice program: bubble sort, MARS style.
# Expected: arr = 1 2 3 4 6 7 8 9
.data
arr: .word 9, 4, 7, 1, 8, 2, 6, 3
.text
main:
    la   $s0, arr
    li   $s1, 8
outer:
    subi $s1, $s1, 1
    blez $s1, done
    li   $t0, 0              # j
    li   $t6, 0              # swapped
inner:
    bge  $t0, $s1, end_inner
    sll  $t1, $t0, 2
    add  $t1, $t1, $s0
    lw   $t2, 0($t1)
    lw   $t3, 4($t1)
    ble  $t2, $t3, no_swap
    sw   $t3, 0($t1)
    sw   $t2, 4($t1)
    li   $t6, 1
no_swap:
    addi $t0, $t0, 1
    j    inner
end_inner:
    bnez $t6, outer
done:
    li   $v0, 10
    syscall
