# Expected: Error: line 5, instruction 'j': misaligned target 0x00000006 (must be a multiple of 4)
# python src/assembler/assembler.py src/programs/errors/misaligned.asm
.text
main:
    j 0x00000006
