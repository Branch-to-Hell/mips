# Pipelined MIPS on the DE10-Lite

A 5-stage pipelined MIPS processor in Verilog for the DE10-Lite (MAX 10), with our own assembler, Conway's Game of Life on VGA and, as the team goal, Doom.
Start with [`docs/project-plan.md`](docs/project-plan.md), then [`docs/workflow.md`](docs/workflow.md) and [`docs/contracts.md`](docs/contracts.md).

## Folders

The four folders the professor asks for:

| Folder | What it holds |
|---|---|
| [`rtl/`](rtl/) | All the Verilog: the CPU (`mips_pipeline.v` and its modules, the single-cycle `mips_cpu.v`), memories, MMIO, VGA and the board top-levels (`top_*.v`) |
| [`verif/`](verif/) | Testbenches (`*_tb.v`) and their ModelSim scripts (`*.do`). [`verif/traces/`](verif/traces/): the annotated R, I and J traces (TC-16). [`verif/results/`](verif/results/): expected vs observed results |
| [`docs/`](docs/) | Plan, workflow, technical contracts, test coverage (`tc16/`), the graded algorithm (`tc15_algorithm.md`), lab checklists and [`docs/evidence/`](docs/evidence/) (board photos and videos, individual sheets) |
| [`src/`](src/) | Everything that is not Verilog: [`src/assembler/`](src/assembler/) (our assembler), [`src/programs/`](src/programs/) (assembly programs), [`src/c/`](src/c/) (C programs: GCC setup, `crt0.S`, linker script), [`src/tools/`](src/tools/) (reference simulator, professor drill, converters), `src/doom/` |

Three extra folders that don't fit those four:

| Folder | What it holds |
|---|---|
| [`quartus/`](quartus/) | The Quartus project `mips.qpf`. One revision per board image: `top_life`, `program`, `mmio_test`, `video_test`, `video_b_test`, `sdram_test` (`.qsf` + `.sdc`) |
| [`mem/`](mem/) | Memory images written by the assembler (`<name>.hex`, `_bytes.hex`, `_b0`–`_b3.hex`, `_data.hex`), read by the testbenches and by Quartus |
| [`web/`](web/) | The report website (Astro Starlight, deployed on Vercel) |

`rtl/`, `verif/`, `quartus/` and `mem/` are side by side, so the testbenches and the `.qsf` files use relative paths (`../rtl/…`, `../mem/…`).

## What you need

| Tool | For |
|---|---|
| Python 3 (no extra packages) | The assembler and the tools in `src/tools/` |
| ModelSim - Intel FPGA Starter Edition 20.1 (`vsim` on the PATH) | The testbenches in `verif/` |
| Quartus Prime Lite 20.1 + the DE10-Lite USB-Blaster driver | Building and loading board images |
| MARS 4.5 (`Mars4_5.jar`) | Only for `drill.py`, which compares with MARS |
| WSL (Ubuntu) with `gcc-mips-linux-gnu`, `make`, `verilator` | Only for C programs and Verilator |

## From an assembly program to the board (TC-3)

**1. The program.** Put it in `src/programs/<name>.asm`. Write it like in MARS with *Delayed branching* off: our assembler puts a `nop` after every branch and jump, so the program behaves the same. It accepts the pseudo-instructions `li`, `la`, `move` and `nop`, and `.text`, `.data`, `.word`, `.space` (all the syntax: [`src/assembler/README.md`](src/assembler/README.md)). Data starts at `0x10010000` and the stack at `0x7FFFEFFC`, like MARS; LEDs, HEX displays, switches and keys are memory-mapped at `0xFFFF0010`–`0xFFFF0027` ([`docs/contracts.md`](docs/contracts.md), "MMIO registers"). A MARS program with other pseudo-instructions or with `syscall`: use `drill.py` (step 3), which rewrites them.

**2. Generate the image**, from the repo root:

```
python src/assembler/assembler.py src/programs/<name>.asm
```

```
OK: 24 instructions, 11 data words
Files generated in: C:\...\mips\mem
To run it on the board, put these lines in quartus/program.qsf and compile the 'program' revision:
    set_parameter -name PROGRAM "count_value_in1"
    set_parameter -name WITH_DATA 1
```

It writes `mem/<name>.hex` (one instruction per line), `<name>_bytes.hex` (one byte per address, big-endian: the professor's image), `<name>_b0`–`_b3.hex` (the 4 instruction memory banks) and `<name>_data.hex` (`.data`). An error prints the line and the reason and writes nothing (`Error: line 5, instruction 'j': misaligned target ...`). `--list` prints the listing; `--help` shows every option.

**3. Check it in simulation** (optional, seconds). `drill.py` runs the original program in MARS and our image on the board's hardware in ModelSim, and compares every register and the data:

```
python src/tools/drill.py src/programs/<name>.asm
```

It must end with `PASS`. Details and what to do if it fails: [`docs/tc12_drill.md`](docs/tc12_drill.md). Without MARS: `python src/tools/ref_sim.py mem/<name>.hex --dump-regs` runs it on the reference simulator.

**4. Load it on the board.**
1. Paste the two `set_parameter` lines from step 2 into `quartus/program.qsf` (they replace the ones there).
2. Open `quartus/mips.qpf` in Quartus, pick the revision `program` (*Project → Revisions*, or the drop-down in the toolbar) and compile (*Processing → Start Compilation*, about 3 minutes). The program goes into the on-chip memory at compile time.
3. *Tools → Programmer*: *Hardware Setup* = USB-Blaster, add `quartus/output_files/program.sof`, *Start*.

**5. Run it and read the result.** The program starts as soon as the board is programmed (PC = 0).
- What the program writes to LEDR and HEX shows on the LEDs and displays.
- **Registers:** SW9 up shows a register: SW4–SW0 = its number (HEX5–HEX4 show it in decimal, like `$0`–`$31` in MARS), HEX3–HEX0 = its value, bits 15..0 with SW5 down and bits 31..16 with SW5 up.
- **Halt:** if the program reads or writes an address outside the memory map, or a misaligned one, the CPU stops: LEDR9 on, HEX5 = `E`, HEX4 = cause (1 fetch, 2 load, 3 store), HEX3–HEX0 = the address (SW8 up: the PC).
- To run it again from the start, program the board again: that also restores `.data`.

## Reproduce the tests

From `verif/` (ModelSim): `vsim -c -do "do <script>.do; quit -f"`. Each one prints `PASS` or `FAIL` with the reason. Assemble first if the program changed (step 2).

| Script | What it checks |
|---|---|
| `tc4.do` | The 6 self-checking programs, one per instruction group (`src/programs/tc4_*.asm`) |
| `tc5.do` | Data, load-use, branch and jump hazards (`tc5_*.asm`) |
| `trace.do` | The R, I and J traces through the 5 stages, written to `verif/traces/` (TC-16) |
| `tc15.do` | The graded algorithm with its 3 inputs (`count_value_in1..3.asm`) |
| `cpu11.do`, `cpu6.do`, `cpu5.do` | Professor's encodings, delay slot, hazard unit |
| `cpu14.do`, `halt.do` | Invalid and misaligned accesses: the visible halt and how the board shows it |
| `instruction_memory.do` | One byte per address, big-endian fetch |
| `life.do` | The Game of Life on the board's hardware (a few minutes) |
| `mmio.do`, `timer.do`, `stack.do`, `hex_debug.do` | Switches, keys, LEDs, HEX, timer, stack region, register view |

From the repo root:

| Command | What it checks |
|---|---|
| `python src/tools/check_asm_errors.py` | The assembler's 8 error examples (`src/programs/errors/`): message and exit code |
| `python src/tools/drill.py src/programs/drill/drill_sort.asm` | A MARS program on our CPU, compared with MARS (also `drill_stats`, `drill_pseudo`) |
| `make -C verif/verilator compare PROG=<name>` (WSL) | Our CPU in Verilator gives the same trace as the reference simulator ([`verif/verilator/README.md`](verif/verilator/README.md)) |

Which test covers each instruction and case, and the results: [`docs/tc16/README.md`](docs/tc16/README.md). Expected vs observed results: [`verif/results/`](verif/results/).

## C programs

`make -C src/c` (WSL) builds every C program in `src/c/` with GCC and our minimal C library, and writes the same `mem/<name>*.hex` images, so steps 4 and 5 are the same. See [`src/c/README.md`](src/c/README.md).
