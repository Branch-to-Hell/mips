# Expected: Error: line 5, instruction 'j': undefined label 'missing'
# python src/assembler/assembler.py src/programs/errors/undefined_label.asm
.text
main:
    j missing
