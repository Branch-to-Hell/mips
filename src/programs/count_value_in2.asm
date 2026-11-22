# count_value_in2.asm - TC-15: graded algorithm "frequency of a value"
# Counts how many times TARGET appears in an array of N words and stores the count.
# Input 2: all equal: n=4, target=7, array 7 7 7 7 -> expected 4
# Instructions: the 12 required ones (add, beq, j, lw, sw, addi, slt) + lui, only to build
# the data address 0x10010000. Loop + decision + lw/sw. Ends in a self-jump (observable end).
#
# Data map (byte offset from 0x10010000):
#   +0  n       number of elements
#   +4  target  value to count
#   +8  result  the count (written by the program)
#   +12 array   n words
# Register map:
#   $s0 data base   $t0 n   $t1 target   $t2 pointer to the current element
#   $t3 count       $t4 i   $t5 array[i] $t6 guard (1 when 0 < n)
.data
n:      .word 4
target: .word 7
result: .word 0
array:  .word 7, 7, 7, 7

.text
main:
    lui  $s0, 0x1001            # s0 = 0x10010000 (data base)
    lw   $t0, 0($s0)            # t0 = n
    lw   $t1, 4($s0)            # t1 = target
    addi $t2, $s0, 12           # t2 = address of array[0]
    add  $t3, $zero, $zero      # count = 0
    add  $t4, $zero, $zero      # i = 0
    slt  $t6, $zero, $t0        # t6 = 1 if 0 < n
    beq  $t6, $zero, done       # n <= 0: nothing to count (edge case)
loop:
    beq  $t4, $t0, done         # i == n: finished
    lw   $t5, 0($t2)            # t5 = array[i]
    beq  $t5, $t1, hit          # decision: element equals target?
    j    next
hit:
    addi $t3, $t3, 1            # count = count + 1
next:
    addi $t2, $t2, 4            # next element
    addi $t4, $t4, 1            # i = i + 1
    j    loop
done:
    sw   $t3, 8($s0)            # result = count
end:
    j    end                    # observable end point: self-jump, result already stored
