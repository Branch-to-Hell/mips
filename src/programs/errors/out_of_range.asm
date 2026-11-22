# Expected: Error: line 5, instruction 'addi': immediate 50000 out of range [-32768, 32767]
# python src/assembler/assembler.py src/programs/errors/out_of_range.asm
.text
main:
    addi $t0, $zero, 50000
