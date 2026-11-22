# Expected: Error: line 9, instruction 'j': jump target 0x10010000 outside 256 MiB region
# j keeps the top 4 bits of PC + 4, so it cannot reach the data segment from text at 0.
# python sw/assembler/assembler.py sw/programs/errors/jump_region_edge.asm
.data
far_label: .word 0

.text
main:
    j far_label
