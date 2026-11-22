# Expected: Error: line 5, instruction 'bltz': 'bltz' expects 2 operands, got 1
# python src/assembler/assembler.py src/programs/errors/wrong_operand_count.asm
.text
main:
    bltz $a0
