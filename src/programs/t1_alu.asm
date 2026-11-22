.text
main:
  addi $t0, $zero, 5
  addi $t1, $zero, -3
  add  $t2, $t0, $t1
  sub  $t3, $t0, $t1
  and  $t4, $t0, $t1
  or   $t5, $t0, $t1
  nor  $t6, $t0, $t1
  slt  $t7, $t1, $t0
  sll  $s0, $t0, 4
  srl  $s1, $s0, 2
  add $t0,$t1,$t2
  andi $s3, $t0, 0xFF
  ori  $s4, $zero, 0x1234
  slti $s5, $t0, 10
  lui  $s6, 0x1001
  nop
