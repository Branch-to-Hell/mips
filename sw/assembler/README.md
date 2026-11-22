# Assembler (v3, TC-13)

Two-pass MIPS assembler in Python. It turns a `.asm` file into the memory images the CPU loads. Python 3 only, no extra packages.

## Regenerate an image

From the repository root:

```
python sw/assembler/assembler.py sw/programs/<name>.asm
```

Example: `python sw/assembler/assembler.py sw/programs/life_board.asm` rewrites `hw/mem/life_board*.hex`.

| Option               | Meaning                                                                                                                                                   |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-o <folder>`        | Write the files to `<folder>` instead of `hw/mem/` (created if missing).                                                                                  |
| `--list`             | Print the listing (address, 32-bit word, instruction text) and the labels.                                                                                |
| `--text-base <addr>` | Address of the first instruction. Default `0` (the professor's initial PC). `0x00400000` is only for comparing with a MARS dump. Must be a multiple of 4. |

## Output files

Files go to `hw/mem/` by default, or to the `-o` folder. Nothing is written to `sw/programs/`. Every file has one value per line in lowercase hex, with no address and no header (read with `$readmemh`).

| File                              | Content                                                                                                                                                      |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `<name>.hex`                      | Word image: one 32-bit instruction per line.                                            |
| `<name>_bytes.hex`                | One byte per address, big-endian: line _n_ is the byte at `text_base + n`. This is the professor's loadable image.                                                                                   |
| `<name>_b0.hex` … `<name>_b3.hex` | The 4 instruction memory banks (CPU-12). Bank _k_ holds the bytes with `addr[1:0] = k`, so line _i_ is one byte of instruction _i_. `_b0` holds bits 31..24. |
| `<name>_data.hex`                 | `.data` segment, one word per line, starting at `0x10010000`. Only written if the program has `.data`.                                                       |

Files are written only if assembling succeeds. The text image is limited to 4096 instructions, and the data image to 4096 words. Nothing is written if either limit is exceeded.

## Supported syntax

**Instructions**

- Arithmetic and logic (R-type): `add addu sub subu and or nor xor slt sltu sll srl sra sllv srlv srav`
- Arithmetic and logic (I-type): `addi addiu slti sltiu andi ori xori lui`
- Multiply and divide: `mul` (SPECIAL2), `mult multu div divu mfhi mflo mthi mtlo`
- Memory: `lw sw lb lbu lh lhu sb sh`
- Jumps and branches: `j jal jr jalr beq bne blez bgtz bltz bgez`

Encodings: `add` and `addu` emit funct `0x21`; `sub` and `subu` emit `0x23`; `addi` and `addiu` emit opcode `0x09`. These are the codes the professor asks for. The hardware accepts both codes (see `docs/contracts.md`).

**Pseudo-instructions**

- `nop`
- `move rd, rs` becomes `add rd, rs, $zero`.
- `li rt, imm` becomes one `addi` if the value fits in 16 signed bits, otherwise `lui` + `ori`.
- `la rt, label` always becomes `lui` + `ori`.

**Directives**

- `.text`, `.data`
- `.word v1, v2, ...`
- `.space n` (rounded up to whole words)
- `.globl` and `.align` are accepted and ignored.

**Operands**

- Immediates: decimal, `0x` hex, or negative.
- Registers: `$t0` style or `$8` style.
- Memory operands: `offset($reg)`. The offset can be omitted: `($t0)`.
- Branch and jump targets: a label, or a literal address (`j 0x00000010`).
- Comments start with `#`.

## Instruction table

The table `isa` is at the top of `assembler.py`. It holds each instruction's fixed bits (opcode, funct, shift amount, and the fixed `rt` for REGIMM branches). There is no separate decoder file.

To add an instruction: add a row to `isa` in `assembler.py`, then add its operand form in `encode()` in the same file. Check the encoding against MARS (see _Tests_ below).

## Delay slot

The pipelined CPU has one branch delay slot. The assembler inserts a `nop` after every `beq`, `bne`, `blez`, `bgtz`, `bltz`, `bgez`, `j`, `jal`, `jr` and `jalr`. The `nop` fills the delay slot, so a program that does not put anything there gives the same result as in MARS with delayed branching off. Programs are not reordered. The listing shows the inserted `nop`s.

## Byte order

Data memory is big-endian: the byte at the lowest address is the most significant, as the contracts specify. This matters for `lb`, `lbu`, `lh`, `lhu`, `sb` and `sh`. MARS is little-endian by default.

## Tests

All programs are in `sw/programs/`. The two self-checking ISA tests are documented in this section. The other programs (`t1`–`t3`, `tc4_*`, `life*`, `test_mmio`, `test_stack`, and so on) are CPU programs used by the testbenches and the hardware images.

Each self-checking test stores its results in data memory and has its expected values written below. Run it in MARS or on the CPU and compare the final data memory with the table.

| Program                        | What it checks                                                                                                                                                         |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `test_pseudoinstrucciones.asm` | `li`, `la`, `move`, `nop`, `lw`, `sw`. Expected: the word `result` = `125` (`0x0000007D`).                                                                             |
| `test_new_instruction.asm`     | Every instruction of phase 2 that is not already in phase 1, including the branches and jumps. Each result has its own word in `results`, starting at `results + 4*i`. |

### Expected values of `test_new_instruction.asm`

`results` starts at the label `results`. Word _i_ is at offset `4*i` from it.

| Word  | Offset | Expected value (hex) | Checks                                                |
| ----- | ------ | -------------------- | ----------------------------------------------------- |
| r[0]  | 0      | `00000019`           | `addu` (20 + 5 = 25)                                  |
| r[1]  | 4      | `0000000F`           | `subu` (20 − 5 = 15)                                  |
| r[2]  | 8      | `0000000F`           | `addiu` (20 + (−5) = 15)                              |
| r[3]  | 12     | `00000001`           | `sltu` (5 < 20)                                       |
| r[4]  | 16     | `00000001`           | `sltiu` (5 < 10)                                      |
| r[5]  | 20     | `0000000C`           | `xor` (0xF ^ 0x3)                                     |
| r[6]  | 24     | `000000FF`           | `xori` (0xF ^ 0xF0)                                   |
| r[7]  | 28     | `FFFFFFFC`           | `sra` (−16 >> 2)                                      |
| r[8]  | 32     | `FFFFFFC0`           | `sllv` (−16 << 2)                                     |
| r[9]  | 36     | `3FFFFFFC`           | `srlv` (0xFFFFFFF0 >> 2, logical)                     |
| r[10] | 40     | `FFFFFFFC`           | `srav` (−16 >> 2, arithmetic)                         |
| r[11] | 44     | `FFFFFF80`           | `lb` of byte 0x80 (sign-extended)                     |
| r[12] | 48     | `000000FF`           | `lbu` of byte 0xFF (zero-extended)                    |
| r[13] | 52     | `FFFF80FF`           | `lh` of halfword 0x80FF (sign-extended)               |
| r[14] | 56     | `00007F01`           | `lhu` of halfword 0x7F01 (zero-extended)              |
| r[15] | 60     | `55001234`           | `sb` at byte 0 and `sh` at bytes 2..3, read with `lw` |
| r[16] | 64     | `0000001E`           | `mult` low (10 × 3 = 30)                              |
| r[17] | 68     | `00000000`           | `mult` high                                           |
| r[18] | 72     | `0000001E`           | `multu` low                                           |
| r[19] | 76     | `00000000`           | `multu` high                                          |
| r[20] | 80     | `0000001E`           | `mul` (30)                                            |
| r[21] | 84     | `00000006`           | `div` quotient (20 / 3)                               |
| r[22] | 88     | `00000002`           | `div` remainder                                       |
| r[23] | 92     | `00000006`           | `divu` quotient                                       |
| r[24] | 96     | `00000002`           | `divu` remainder                                      |
| r[25] | 100    | `00000064`           | `mthi` then `mfhi` (100)                              |
| r[26] | 104    | `000000C8`           | `mtlo` then `mflo` (200)                              |
| r[27] | 108    | `00000001`           | `bltz` taken (−1 < 0)                                 |
| r[28] | 112    | `00000002`           | `bltz` not taken (1)                                  |
| r[29] | 116    | `00000001`           | `bgez` taken (1 ≥ 0)                                  |
| r[30] | 120    | `00000002`           | `bgez` not taken (−1)                                 |
| r[31] | 124    | `00000001`           | `blez` taken (0 ≤ 0)                                  |
| r[32] | 128    | `00000002`           | `blez` not taken (5)                                  |
| r[33] | 132    | `00000001`           | `bgtz` taken (5 > 0)                                  |
| r[34] | 136    | `00000002`           | `bgtz` not taken (0)                                  |
| r[35] | 140    | `00000001`           | `j` skips the store of 99                             |
| r[36] | 144    | `00000005`           | `jalr` calls `function`, which sets 5, then returns   |

A branch check works like this: the good value (1 or 2) is set before the branch, and the wrong path writes 99. If the branch goes the wrong way, the word holds 99 and the check fails. Each check has its own word, so no result is overwritten.

The program then loops in `end:` (`j end`).

To compare the code with MARS, dump `.text` from MARS with the Default memory configuration (_Settings → Memory Configuration → Default_, _Delayed branching_ off):

```
java -jar Mars4_5.jar nc a dump .text HexText mars_<name>.hex sw/programs/<name>.asm
python sw/assembler/assembler.py sw/programs/<name>.asm -o out --text-base 0x00400000
```

Then compare the two `.hex` files (`fc.exe` on Windows, `diff` elsewhere). The differences listed under _Known differences with MARS_ are expected.

## Known differences with MARS

These differences are expected. They do not change the result of the program.

- `li` with a large value and `la` expand to `lui` + `ori` using the destination register. MARS uses `$at` as the intermediate register.
- `move rd, rs` becomes `add rd, rs, $zero`. MARS uses `addu rd, $zero, rs`.
- `add`, `sub` and `addi` use the professor's codes (`0x21`, `0x23`, `0x09`). MARS uses `0x20`, `0x22` and `0x08`. So for these three, a word-by-word comparison with a MARS dump never matches.
- The assembler inserts one `nop` after every jump and branch (the delay slot). MARS does not insert it.
- Labels and addresses that come after an inserted `nop` have different values than in MARS.

## Diagnostics

Errors stop the assembler with the line number and exit code 1. Each one has an example in `sw/programs/errors/`. The first line of each `errors/*.asm` file is `# Expected:` followed by the exact message the assembler must print.

|Error|Example|
|---|---|
|Unknown mnemonic|`unknown_mnemonic.asm`|
|Unknown register|`invalid_register.asm`|
|Duplicate label|`duplicate_label.asm`|
|Undefined label|`undefined_label.asm`|
|Operand out of range (immediate, offset, shift, branch distance)|`out_of_range.asm`|
|Wrong number of operands|(e.g. `bltz $a0` without a target)|
|`j`/`jal` target outside the 256 MiB region of `PC + 4`|`jump_region_edge.asm`|
|Branch or jump target not a multiple of 4|`misaligned.asm`|

Example:

```
python sw/assembler/assembler.py sw/programs/errors/misaligned.asm
Error: line 5, instruction 'j': misaligned target 0x00000006 (must be a multiple of 4)
```
