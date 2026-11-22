# Expected: Error: line 5, instruction 'bltz': 'bltz' expects 2 operands, got 1
# python sw/assembler/assembler.py sw/programs/errors/wrong_operand_count.asm
.text
main:
    bltz $a0
