# Expected: Error: line 5, instruction 'add': invalid register '$fake'
# python src/assembler/assembler.py src/programs/errors/invalid_register.asm
.text
main:
    add $t0, $fake, $t1
