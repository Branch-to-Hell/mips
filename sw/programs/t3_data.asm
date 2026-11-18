.data
a:   .word 5, 10, -1
b:   .word 0x7FFFFFFF
buf: .space 8
.text
main:
  ori  $t0, $zero, 0x2000
  lw   $t1, 0($t0)
  lw   $t2, 4($t0)
  add  $t3, $t1, $t2
  sw   $t3, 16($t0)
  sw   $t3, -4($t0)
  beq  $t3, $zero, main
end: j end
