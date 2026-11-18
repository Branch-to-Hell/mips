.text
main:
  addi $t0, $zero, 0
  addi $t1, $zero, 5
loop:
  beq  $t0, $t1, done
  addi $t0, $t0, 1
  j    loop
done: jal func
  bne  $v0, $zero, end
  addi $v0, $zero, 99
func:
  addi $v0, $zero, 7
  jr   $ra
end:
  j end
