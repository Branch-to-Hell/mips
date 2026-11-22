# Expected: Error: line 5, instruction 'j': misaligned target 0x00000006 (must be a multiple of 4)
# python sw/assembler/assembler.py sw/programs/errors/misaligned.asm
.text
main:
    j 0x00000006
