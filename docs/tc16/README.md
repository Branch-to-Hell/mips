# TC-16: test coverage and traces

Every case the professor asks for, the test that covers it and how to reproduce it. All the CPU tests run on **`mips_pipeline`**, the CPU that goes to the board. Each test checks itself and prints `PASS` or `FAIL`.

## How to run everything

From the repo root (PowerShell), assemble the programs once:

```
foreach ($p in "tc4_rtype","tc4_itype","tc4_shifts","tc4_memory","tc4_branches","tc4_jumps","tc5_data_hazards","tc5_load_use","tc5_branch_hazards","tc5_jump_hazards","tc16_trace","test_halt") { python sw/assembler/assembler.py sw/programs/$p.asm }
```

Then run the testbenches from `hw/sim` (ModelSim):

```
cd hw/sim
foreach ($t in "tc4","tc5","trace","instruction_memory","cpu11","cpu14","halt","cpu6") { vsim -c -do "do $t.do; quit -f" | Select-String "PASS|FAIL" }
cd ../..
python sw/tools/check_asm_errors.py
```

Results on Nov 21 (all PASS):

| Testbench | What it runs | Result |
|---|---|---|
| `tc4.do` | the 6 `tc4_*.asm` programs, one per instruction group | 6/6 PASS (86 to 152 cycles each) |
| `tc5.do` | the 4 `tc5_*.asm` hazard programs | 4/4 PASS |
| `trace.do` | `tc16_trace.asm`: writes the 3 traces below | PASS |
| `instruction_memory.do` | CPU-12: every fetch of `life_board` (323 instructions) at text base 0 and 0x00400000 | PASS, 647 fetches |
| `cpu11.do` | professor's encodings `0x21 0x23 0x09` and the standard ones | PASS, 20 checks |
| `cpu14.do`, `halt.do` | CPU-14 invalid accesses, and how the board shows them | PASS (7 cases, 34 checks; decoder 19 addresses) |
| `cpu6.do` | delay slot: the instruction after a branch/jump always runs | PASS |
| `check_asm_errors.py` | the 8 `sw/programs/errors/*.asm` examples | 8/8 PASS |

## 1. One case per instruction

Covers the whole Phase 1 set (20 instructions plus `addu subu addiu`), so the professor's minimum set of 12 is included whatever its exact list.

| Instruction | Format | Test (program: test numbers) | Also in |
|---|---|---|---|
| `add` | R | `tc4_rtype`: 1, 2 | trace R, `cpu11` (funct 0x21 and 0x20) |
| `sub` | R | `tc4_rtype`: 3, 4 | `cpu11` (funct 0x23 and 0x22) |
| `and` | R | `tc4_rtype`: 5 | |
| `or` | R | `tc4_rtype`: 6 | |
| `nor` | R | `tc4_rtype`: 7, 8 | |
| `slt` | R | `tc4_rtype`: 9 to 12 (signed) | |
| `sll` | R | `tc4_shifts`: 1, 2, 3, 7 | |
| `srl` | R | `tc4_shifts`: 4, 5, 6, 7 (logical) | |
| `jr` | R | `tc4_jumps`: 2, 3 | `tc5_jump_hazards`: 4, 5 |
| `addi` | I | `tc4_itype`: 1, 2 | `cpu11` (opcode 0x09 and 0x08) |
| `andi` | I | `tc4_itype`: 3, 4 | |
| `ori` | I | `tc4_itype`: 5, 6, 12 | |
| `slti` | I | `tc4_itype`: 7 to 10 | |
| `lui` | I | `tc4_itype`: 11, 12 | |
| `lw` | I | `tc4_memory`: 1 to 10 | trace I |
| `sw` | I | `tc4_memory`: 1 to 9 | |
| `beq` | I | `tc4_branches`: 1, 2, 5, 6, 8 | |
| `bne` | I | `tc4_branches`: 3, 4, 7, 9 | |
| `j` | J | `tc4_jumps`: 1, 4 | trace J |
| `jal` | J | `tc4_jumps`: 2, 3 | `tc5_jump_hazards`: 2 to 7 |
| `addu subu addiu` | R, R, I | `cpu11` | |

## 2. Integration

| Case | Test |
|---|---|
| The 4 fetch bytes | `instruction_memory.do`: for every instruction, `mem[PC]..mem[PC+3]` from the byte image, the 4 banks and the joined big-endian word. Every trace shows them in its IF line |
| Writes to `$zero` | `tc4_rtype` 13 (`addi $zero`), `tc4_memory` 10 (`lw $zero`), `tc5_data_hazards` 9, `tc5_load_use` 8, `cpu11` (`addi $0`) |
| Sign and zero extension | Sign: `tc4_itype` 1, 2, 9, 10 (`addi`, `slti` with negatives), `tc4_memory` 5 (negative offset). Zero: `tc4_itype` 4, 6 (`andi`, `ori` with 0xFFFF). Trace I shows the extended immediate |
| `lw` / `sw` | `tc4_memory` 1 to 10, `tc5_load_use` 1 to 11, trace I |
| Branch taken and not taken | `tc4_branches` 1 and 3 (taken), 2, 4 and 9 (not taken), `tc5_branch_hazards` 3, 8 |
| A backward branch | `tc4_branches` 7 (loop 1+2+3+4+5 = 15), `tc5_branch_hazards` 5 |
| A `j` that skips an instruction with a visible effect | `tc4_jumps` 1 (`$t0` stays 0), trace J (`$t4` stays 0: `addi $t4, $zero, 1` never runs) |

## 3. Errors

| Case | Test |
|---|---|
| Assembler errors | `python sw/tools/check_asm_errors.py`: the 8 examples in `sw/programs/errors/` (unknown mnemonic, invalid register, duplicate label, undefined label, out of range, wrong number of operands, `j` outside its 256 MiB region, misaligned target). Each file starts with its expected message; the script checks the message and exit code 1 |
| Invalid data access (CPU-14) | `cpu14.do`: 7 cases (fetch outside text, misaligned fetch, `lw`/`sw` with no region and misaligned, precise order), nothing is written. `halt.do`: on `life_system` (the board hardware), `sw` to 0x7FFFF000 halts with LEDR = 0x203 and HEX = `E3F000` |

## 4. Traces (R, I, J)

`trace.do` runs `sw/programs/tc16_trace.asm` and follows one instruction of each format through the 5 stages, one block per clock cycle:

| Trace | Instruction | PC | Result |
|---|---|---|---|
| [`trace_R.txt`](trace_R.txt) | `add $t2, $t0, $t1` | 0x1C | `$t2` = 5 + 7 = 0x0000000C |
| [`trace_I.txt`](trace_I.txt) | `lw $t3, 4($s1)` | 0x20 | `$t3` = mem[0x10010004] = 0xCAFE1234 |
| [`trace_J.txt`](trace_J.txt) | `j j_target` | 0x24 | IF fetches the delay slot (0x28), then 0x30; `$t4` stays 0 |

Each trace has: state before; **IF** (PC, the 4 bytes, the word); **ID** (IF/ID register, fields, extended immediate, every control signal, operands read, stall and redirect); **EX** (ID/EX register, ALU inputs and result); **MEM** (EX/MEM register, memory bus); **WB** (MEM/WB register, register file write); state after. The testbench also checks the results and that each instruction took 5 consecutive cycles.

The traces are generated files: run `do trace.do` again after any CPU change.
