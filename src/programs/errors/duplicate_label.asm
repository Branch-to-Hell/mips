# Expected: Error: line 7: duplicate label 'loop'
# python sw/assembler/assembler.py sw/programs/errors/duplicate_label.asm
.text
loop:
    nop

loop:
    nop
