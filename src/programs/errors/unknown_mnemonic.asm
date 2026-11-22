# Expected: Error: line 5, instruction 'foo': unknown instruction 'foo'
# python sw/assembler/assembler.py sw/programs/errors/unknown_mnemonic.asm
.text
main:
    foo $t0, $t1, $t2
