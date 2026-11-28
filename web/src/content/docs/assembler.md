---
title: Assembler
description: Our two-pass MIPS assembler - how to run it, the listing, the loadable images, the delay-slot nop and the diagnostics.
---

:::tip[In 30 seconds]
- `src/assembler/assembler.py` turns a `.asm` file into the numbers the CPU runs: **one line of assembly → one 32-bit word**.
- **Two passes:** the first finds the address of every label, the second encodes every instruction (so labels work forwards and backwards).
- It writes the **listing**, the **byte-per-address image** the spec asks for, the 4 bank files Quartus loads, and stops with the **line number** on any error.
:::

## Running it

From the repository root (Python 3, no extra packages):

```
python src/assembler/assembler.py src/programs/count_value_in1.asm
```

```
OK: 24 instructions, 11 data words
Files generated in: C:\...\mips\mem
To run it on the board, put these lines in quartus/program.qsf and compile the 'program' revision:
    set_parameter -name PROGRAM "count_value_in1"
    set_parameter -name WITH_DATA 1
```

| Option | Meaning |
|---|---|
| `--list` | Print the listing: address, word, instruction text, and the labels |
| `-o <folder>` | Write the files there instead of `mem/` |
| `--text-base <addr>` | Address of the first instruction. Default `0` (the spec's initial PC); `0x00400000` only to compare with a MARS dump |

## Listing

`--list` on the graded algorithm (the `nop`s are the delay slots the assembler inserts):

```
0x00000000  3C101001 lui  $s0, 0x1001
0x00000004  8E080000 lw   $t0, 0($s0)
0x00000008  8E090004 lw   $t1, 4($s0)
0x0000000C  260A000C addi $t2, $s0, 12
0x00000010  00005821 add  $t3, $zero, $zero
0x00000014  00006021 add  $t4, $zero, $zero
0x00000018  0008702A slt  $t6, $zero, $t0
0x0000001C  11C0000D beq  $t6, $zero, done
0x00000020  00000000 nop
0x00000024  1188000B beq  $t4, $t0, done
0x00000028  00000000 nop
0x0000002C  8D4D0000 lw   $t5, 0($t2)
0x00000030  11A90003 beq  $t5, $t1, hit
0x00000034  00000000 nop
0x00000038  08000011 j    next
0x0000003C  00000000 nop
0x00000040  256B0001 addi $t3, $t3, 1
0x00000044  254A0004 addi $t2, $t2, 4
0x00000048  258C0001 addi $t4, $t4, 1
0x0000004C  08000009 j    loop
0x00000050  00000000 nop
0x00000054  AE0B0008 sw   $t3, 8($s0)
0x00000058  08000016 j    end
0x0000005C  00000000 nop

Labels:
n = 0x10010000        main = 0x0
target = 0x10010004   loop = 0x24
result = 0x10010008   hit = 0x40
array = 0x1001000C    next = 0x44
                      done = 0x54
                      end = 0x58
```

Two checks you can do by hand:

- `beq $t5, $t1, hit` at `0x30` → immediate = (`0x40` − `0x34`) / 4 = **3** → `0x11A90003`.
- `j loop` at `0x4C` → index = `0x24` / 4 = **9** → `0x08000009`. The `j` is checked to stay in the same 256 MB region as PC + 4.

## Output files

Everything goes to `mem/` (never next to the source). One value per line, hex, no addresses, read by ModelSim and Quartus with `$readmemh`.

| File | Content |
|---|---|
| `<name>_bytes.hex` | **One byte per address, big-endian**: line *n* is the byte at address *n*. The spec's loadable image |
| `<name>_b0.hex` … `_b3.hex` | The 4 instruction memory banks (bank *k* = bytes with `addr[1:0] = k`). This is what the hardware loads |
| `<name>.hex` | One 32-bit word per line (for the reference simulator) |
| `<name>_data.hex` (+ `_data_b0..b3`) | The `.data` segment from `0x1001_0000` |

To regenerate an image: run the same command again. Quartus picks it up on the next compilation (the program goes into the on-chip memory at compile time).

## What it accepts

- **Instructions:** the 12 required, the Game of Life's, and the MIPS I integer set ([Instruction set](/isa/)).
- **Registers:** names (`$t0`) or numbers (`$8`).
- **Pseudo-instructions:** `nop`, `move`, `li` (one `addi`, or `lui` + `ori` for large values), `la` (`lui` + `ori`).
- **Directives:** `.text`, `.data`, `.word`, `.space` (`.globl` and `.align` are ignored).
- **Immediates:** decimal, `0x` hex or negative; memory operands as `offset($reg)`.

`add`, `sub` and `addi` are emitted with the professor's codes `0x21`, `0x23`, `0x09`.

### The delay-slot `nop`

The CPU has one [branch delay slot](/pipeline/#the-branch-delay-slot). The assembler inserts a `nop` after every `beq bne blez bgtz bltz bgez j jal jr jalr`, so a program written for MARS with *delayed branching* off gives the same result on our CPU. Programs are never reordered. `drill.py` proves it: it runs a program in MARS and on our CPU in ModelSim and compares every register and the data ([Tests](/tests/)).

## Diagnostics

Any error stops the assembler with the line number and exit code 1, and **no file is written**. Each error has an example in `src/programs/errors/`; `python src/tools/check_asm_errors.py` runs all 8 and checks the message.

| Error | Example file |
|---|---|
| Unknown mnemonic | `unknown_mnemonic.asm` |
| Unknown register | `invalid_register.asm` |
| Duplicate label | `duplicate_label.asm` |
| Undefined label | `undefined_label.asm` |
| Operand out of range (immediate, offset, shift, branch distance) | `out_of_range.asm` |
| Wrong number of operands | `wrong_operand_count.asm` |
| `j`/`jal` target outside the 256 MiB region of PC + 4 | `jump_region_edge.asm` |
| Branch or jump target not a multiple of 4 | `misaligned.asm` |

Ranges checked: `addi`, `lw`, `sw` immediates from −32768 to 32767; `ori` from 0 to 65535; branch distances must fit in 16 signed bits.

```
> python src/assembler/assembler.py src/programs/errors/duplicate_label.asm
Error: line 7: duplicate label 'loop'

> python src/assembler/assembler.py src/programs/errors/misaligned.asm
Error: line 5, instruction 'j': misaligned target 0x00000006 (must be a multiple of 4)
```

## Differences with MARS

None of these change a program's result:

- `add sub addi` use the professor's codes (MARS: `0x20 0x22 0x08`).
- A `nop` after every branch and jump, so labels after it move by 4.
- `li`/`la` with large values use the destination register as the intermediate (MARS uses `$at`).

This one does: MARS is little-endian and our CPU big-endian, so `lb lbu lh lhu sb sh` see different bytes. The graded programs and the Game of Life only use words.
