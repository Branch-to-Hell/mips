# Expected: Error: line 5, instruction 'j': undefined label 'missing'
# python sw/assembler/assembler.py sw/programs/errors/undefined_label.asm
.text
main:
    j missing
