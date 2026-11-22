# Verilator harness (TC-7)

Runs a program on `life_system` (the same hardware as the board: `mips_pipeline`, the CPU-14 address decoder, data, stack, MMIO, video modes A and B) and prints **the same trace as `src/tools/ref_sim.py`** (`docs/contracts.md`, "Reference simulator trace"), so the two compare with a plain `diff`.

| File | What it does |
|---|---|
| `harness_top.sv` | Wraps `life_system`, loads the program from `+program=`, prints one line per register write in WB and decides when the run ends |
| `sim_main.cpp` | Clock (25 MHz) and reset (4 cycles), until `harness_top` sets `done` |
| `Makefile` | Builds the simulator (default target), `run` and `compare` |

## Install and build

In WSL (Ubuntu 24.04 has Verilator 5.020): `sudo apt install verilator`. From the repo root:

```
make -C verif/verilator                           # builds build/verilator/mips_sim (a few seconds, once)
```

The program is loaded at run time, so the same build runs every program. Rebuild only when the RTL changes (`make` notices).

## Run

```
build/verilator/mips_sim +program=mem/<name> [+max-cycles=N] [+ppm=file.ppm]
make -C verif/verilator run PROG=<name>
make -C verif/verilator compare PROG=<name>       # diff against ref_sim.py, prints PASS or the diff
```

- `+program=mem/<name>`: the images from our assembler or from `make -C src/c` (`<name>_b0..b3.hex`, and `<name>_data.hex` if it exists).
- `+max-cycles=N`: stop after N clock cycles (default 10,000,000).
- `+ppm=file.ppm`: save framebuffer A (128×96) at the end.

stdout is only the trace; the cycle count goes to stderr (`mips_sim: 124970 cycles, 87028 instructions`).

## Trace

```
PC=0x00000000 R29 <= 0x80000000
PC=0x00000004 R29 <= 0x7FFFEFF0
...
HALT: jumps to itself at 0x00000040  (steps=87028)
```

- A line is printed when the register file writes, at the end of WB, so the lines are in program order. The PC is the instruction's own PC: MEM/WB has no PC field, but it is always enabled, so the harness takes the PC that was in EX/MEM one cycle before.
- The run ends like in `ref_sim.py`, and the `HALT:` line has the same text:
  - **Self-jump** (`end: j end`, or any branch to itself that is taken): after its delay slot finishes.
  - **CPU-14 halt**: `HALT: cause C (fetch|load|store) pc ... addr ...`, after the older instructions finish.
  - **`+max-cycles`**: `HALT: reached +max-cycles N at PC=...` (`ref_sim.py` counts instructions, so this line differs).
- `steps` = instructions that finished (nops too, stall bubbles not): the same number `ref_sim.py` prints.
- **HI/LO (CPU-8):** `mult multu div divu` print `HI` then `LO`, `mthi`/`mtlo` one line, in the instruction's place (when it reaches WB). A divide finishes 32 cycles later while the pipeline keeps going, so its lines, and every line after them, wait in a queue until the divider is done. Divide by zero prints nothing, like `ref_sim.py`.

## What is checked (Nov 22)

`compare` passes for every program in `mem/` that ends: the TC-4, TC-5, TC-15 and TC-16 programs, the drills, `test_*`, the C programs `hello_pixels` (62,332 writes), `test_libc` (43,191, HI/LO included) and `test_bus`, and the GNU as ISA tests `cpu7_isa` and `cpu8_muldiv` (CPU-7, CPU-8). `test_halt` and `test_bus` end with the same CPU-14 halt line.

Programs that never end (`life_board`, `test_mmio`, `test_mode_b`, `test_timer`) give the same trace as far as both run, except where they read the timer: `ref_sim.py` treats MMIO as RAM, while the hardware timer counts. Switches and keys read 0 (released) in both.
