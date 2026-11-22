# Expected: Error: line 7: duplicate label 'loop'
# python src/assembler/assembler.py src/programs/errors/duplicate_label.asm
.text
loop:
    nop

loop:
    nop
