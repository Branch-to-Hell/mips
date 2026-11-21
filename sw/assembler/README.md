# Assembler (v3, TC-13)

Two-pass MIPS assembler in Python. It turns a `.asm` file into the memory images the CPU loads.
No dependencies beyond Python 3.

## Regenerate an image

From the repository root:

```
python sw/assembler/assembler.py sw/programs/<name>.asm
```

Example: `python sw/assembler/assembler.py sw/programs/life_board.asm` rewrites `hw/mem/life_board*.hex`.

| Option | Meaning |
| --- | --- |
| `-o <folder>` | Write the files to `<folder>` instead of `hw/mem/` (created if missing). |
| `--list` | Print the listing: address, 32-bit word and instruction text, then the labels. |
| `--text-base <addr>` | Address of the first instruction. Default `0` (the professor's initial PC). Use `0x00400000` only to compare with a MARS dump. Must be a multiple of 4. |

## Output files

All files go to `hw/mem/` by default, or to the `-o` folder. Nothing is written to `sw/programs/`.
Every file has one value per line in lowercase hex, with no address and no header (read with `$readmemh`).

| File | Content |
| --- | --- |
| `<name>.hex` | Word image: one 32-bit instruction per line. |
| `<name>_bytes.hex` | One byte per address, big-endian (the professor's loadable image). |
| `<name>_b0.hex` … `<name>_b3.hex` | The 4 instruction memory banks (CPU-12): bank *k* holds the bytes at addresses with `addr[1:0] = k`, so line *i* is one byte of instruction *i*. `_b0` = bits 31..24. |
| `<name>_data.hex` | `.data` segment, one word per line, starting at `0x10010000`. Only written when the program has `.data`. |

Files are written only when assembling succeeds. The text image is limited to 4096 instructions and the data image to 4096 words.

## Supported syntax

- **Instructions:** `add addu sub subu and or nor slt sll srl jr addi addiu andi ori slti lui lw sw beq bne j jal`.
- **Professor's encodings:** `add`, `sub` and `addi` emit funct `0x21`, funct `0x23` and opcode `0x09` (the same codes as `addu subu addiu`). The hardware accepts both codes (see `docs/contracts.md`).
- **Pseudo-instructions:** `nop`; `move rd, rs` → `add rd, rs, $zero`; `li rt, imm` → one `addi` if the value fits in 16 signed bits, otherwise `lui` + `ori`; `la rt, label` → always `lui` + `ori`.
- **Directives:** `.text`, `.data`, `.word v1, v2, ...`, `.space n` (rounded up to whole words). `.globl` and `.align` are accepted and ignored.
- **Operands:** immediates in decimal, `0x` hex or negative; registers as `$t0` or `$8`; branch and jump targets as a label or a literal address (`j 0x00000010`).
- **Comments** start with `#`.

## Delay slot

The pipelined CPU has one branch delay slot. The assembler inserts a `nop` after every `beq`, `bne`, `j`, `jal` and `jr`, so programs written for MARS (delayed branching off) run unchanged. Programs are not reordered. The listing shows the inserted `nop`s.

## Diagnostics

Errors stop the assembler with the line number and exit code 1. Each one has an example in `sw/programs/errors/` (the first line of the file is the expected message):

| Error | Example |
| --- | --- |
| Unknown mnemonic | `unknown_mnemonic.asm` |
| Unknown register | `invalid_register.asm` |
| Duplicate label | `duplicate_label.asm` |
| Undefined label | `undefined_label.asm` |
| Operand out of range (immediate, offset, shift, branch distance) | `out_of_range.asm` |
| `j`/`jal` target outside the 256 MiB region of `PC + 4` | `jump_region_edge.asm` |
| Branch or jump target not a multiple of 4 | `misaligned.asm` |

```
python sw/assembler/assembler.py sw/programs/errors/misaligned.asm
Error: line 5, instruction 'j': misaligned target 0x00000006 (must be a multiple of 4)
```
