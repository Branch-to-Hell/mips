  

The image regenerates from the ASM

command for the assembler V3 to created .hex with the .asm

```
repository root: python sw/assembler/assembler.py sw/programs/<file>.asm
```

Example:
```
repository root: python sw/assembler/assembler.py sw/programs/life_board.asm
```

for the creation of a folder to save the .hex is is with the command

```
repository root: python sw/assembler/assembler.py sw/programs/<file>.asm -o <name of the folder>
```

The files will be create afther that.

| File           | Root    |
| -------------- | ------- |
| file.hex       | -o root |
| file_data.hex  | -o root |
| file_bytes.hex | -o root |
| file_b0.hex    | -o root |
| file_b1.hex    | -o root |
| file_b2.hex    | -o root |
| file_b3.hex    | -o root |
The default folder the files will be save is `hw/mem/`.

for print the list is with the command
```
repository root: python sw/assembler/assembler.py sw/programs/<file>.asm --list
```

For compared with mars is 
```
repository root: python sw/assembler/assembler.py sw/programs/<file>.asm --text-base 0x00400000
```

Address of the first instruction. Default 0. Use 0x00400000 only to compare with a MARS dump. Must be a multiple of 4.

## Supported syntax

- Instructions: `add addu sub subu and or nor slt mul sll srl jr addi addiu andi ori slti lui lw sw beq bne j jal`
- Pseudo-instructions: `nop`, `move rd, rs` (becomes `add rd, rs, $zero`), `li rt, imm` (one `addi`, or `lui` + `ori` if the value does not fit in 16 signed bits), `la rt, label` (always `lui` + `ori`).
- Directives: `.text`, `.data`, `.word v1, v2, ...`, `.space n`. `.globl` and `.align` are accepted and ignored.
- Immediates: decimal, `0x` hexadecimal, negative values. Registers: `$t0` style or `$8` style.
- Jump and branch targets: a label, or a literal address (`j 0x00400010`).

## Delay slot
The CPU has one branch delay slot. The assembler inserts a `nop` after every`beq`, `bne`, `j`, `jal` and `jr`. Programs are not reordered.

