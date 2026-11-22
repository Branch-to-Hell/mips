# TC-12: professor drill

The professor may bring a MARS program we have never seen and ask us to run it on our CPU. Goal: **from receiving the `.asm` to showing the result on the board in under 15 minutes.**

## The procedure

**0. Before the lab** (once): Quartus project open on revision `program`, MARS at `~/Downloads/Mars4_5.jar` (or set `MARS_JAR`), ModelSim on PATH.

**1. Save the program** as `sw/programs/drill/<name>.asm` (any name without spaces).

**2. Run the drill** from the repo root:

```
python sw/tools/drill.py sw/programs/drill/<name>.asm
```

It takes a few seconds and does everything:

| Step | What it does |
|---|---|
| 1 | `mars_compat.py` rewrites what our assembler/CPU don't have (see below) into `build/drill/<name>.asm`, and lists every change |
| 2 | Our assembler writes `hw/mem/<name>_b0..b3.hex` and `<name>_data.hex` |
| 3 | MARS runs the **original** program: the expected registers and data |
| 4 | ModelSim runs our image on `life_system` with `mips_pipeline` (the board hardware) until the program's final self-jump |
| 5 | Compares every register and the first 64 data words, and prints `PASS` or `FAIL` |

It ends with the two lines for `hw/quartus/program.qsf` and the registers to check on the board.

**3. Board:** paste the two `set_parameter` lines into `hw/quartus/program.qsf`, compile the `program` revision (about 3 minutes), program the board.

**4. Show the result:** SW9 up, SW4-0 = the register number (SW5 up = bits 31..16). The drill printed the expected value of each register. If something went wrong, HEX5 shows `E` (see "If something fails").

Practice programs, all PASS: `sw/programs/drill/drill_stats.asm` (sum, max, negatives), `drill_sort.asm` (bubble sort), `drill_pseudo.asm` (one of each rewritten pseudo-instruction). Each drill took about 2 seconds before the board step.

## What `mars_compat.py` rewrites

Only with Phase 1 instructions (the CPU in the frozen build) and `$at`, the register MARS itself uses for pseudo-instructions. Every rewrite was checked against MARS with the practice programs.

| MARS | Becomes |
|---|---|
| `blt bgt ble bge a, b, L` (register or immediate) | `slt`/`slti` into `$at` + `beq`/`bne` (`li $at` first if the immediate doesn't fit) |
| `beqz`, `bnez`, `b` | `beq`/`bne` with `$zero` |
| `beq bne a, imm, L` | `li $at, imm` + `beq`/`bne` |
| `bltz bgez blez bgtz` | `slt` into `$at` + `beq`/`bne` (they are Phase 2 on the CPU) |
| `subi`, `not`, `neg` | `addi` with `-imm`, `nor` with `$zero`, `sub` from `$zero` |
| `addi addiu slti andi ori` with a big immediate, `add rd, rs, imm` | `li $at, imm` + the R-type |
| `lw`/`sw rt, label`, `label+n`, or an address | `la`/`li $at` + `lw`/`sw n($at)` |
| `syscall` with `$v0` = 10 or 17 (exit) | a self-jump: the program stops there with its results |
| `syscall` 1, 11, 34, 36 (print) | removed; the value MARS prints is in `$a0` at that point |
| `.text` that ends without a jump | `__end: j __end` added |

`li`, `la`, `move` and `nop` are handled by our assembler, and it puts a `nop` after every branch and jump (delay slot), so the program behaves like MARS with *Delayed branching* off.

## If something fails

| What you see | Meaning | What to do |
|---|---|---|
| `ERROR ... directive .asciiz/.byte/...` | Strings and bytes are not supported | If they are only printed, delete them and their `syscall 4`. Otherwise turn them into `.word` |
| `ERROR ... syscall 5/8/12 reads input` | The program reads the keyboard | Replace the syscall with the value: `li $v0, <value>` |
| `ERROR ... mult/div/sltu/... is not in the CPU` | Phase 2 instruction; the frozen build is Phase 1 | Rewrite with Phase 1 instructions (multiply = loop of adds). After the freeze, PR #109 adds them |
| `Assembler error: line N` | Something our assembler rejects | The line number is in `build/drill/<name>.asm` |
| `CPU HALT: lw/sw at PC ..., address ...` | The address is in no region of our memory map (for example MARS's keyboard/display MMIO at 0xFFFF0000-0xFFFF000C) | Use our regions: data 0x10010000, stack, MMIO 0xFFFF0010-0xFFFF0027 (contracts.md) |
| `end timeout` | The program never reaches a self-jump | An endless loop that isn't `j itself`, or a long program: `--cycles 10000000` |
| A register says `code address` | MARS's code starts at 0x00400000, ours at 0, and our labels move by the inserted `nop`s | Expected, not an error (`$ra`, `la` of a code label) |
| `$gp` differs | MARS starts `$gp` at 0x10008000; our reset leaves it at 0 | Expected unless the program uses `$gp` |
| On the board: HEX5 = `E` | CPU halt: HEX4 = cause (1 fetch, 2 `lw`, 3 `sw`), HEX3-0 = address bits 15..0; SW8 up = PC | Same as `CPU HALT` above |
| `$at` warning | The program uses `$at` itself and the rewrites also use it | Check the rewritten lines; rename the program's register |

## Done when

The whole procedure on the board in under 15 minutes, with a program none of us wrote (issue #37). The simulation part takes seconds; most of the time is the Quartus compile.
