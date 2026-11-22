# Expected: Error: line 5, instruction 'add': invalid register '$fake'
# python sw/assembler/assembler.py sw/programs/errors/invalid_register.asm
.text
main:
    add $t0, $fake, $t1
