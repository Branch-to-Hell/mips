# Verilator harness (TC-7)

Runs a program on `life_system` (the same hardware as the board: `mips_pipeline`, the CPU-14 address decoder, data, stack, MMIO, video modes A and B) and prints **the same trace as `src/tools/ref_sim.py`** (`docs/contracts.md`, "Reference simulator trace"), so the two compare with a plain `diff`.

| File | What it does |
|---|---|
| `harness_top.sv` | Wraps `life_system`, loads the program from `+program=`, prints one line per register write in WB and decides when the run ends |
| `sim_main.cpp` | Clock (25 MHz) and reset (4 cycles), until `harness_top` sets `done` |
| `mips_sim_ext` | The same harness built with `EXT_START=1`: it starts at `0x2000_0000` and fetches through the external port (CPU-9) |
| `mips_sim_sdram` | Built with `EXT_START=2`: the real external side, `rtl/ext_memory.v` (SDRAM bridge PLT-8 + instruction cache PLT-12), on `avalon_sdram.sv`, starting at `0x2000_0000` like `top_doom` after `boot.S` |
| `avalon_sdram.sv` | Behavioural SDRAM (64 MB) behind `sdram_sys`'s Avalon interface: random `waitrequest` and read latency, pipelined reads in order, little-endian byte lanes |
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

stdout is only the trace; the cycle count goes to stderr (`mips_sim: 124952 cycles, 87016 instructions`).

## Trace

```
PC=0x00000000 R29 <= 0x80000000
PC=0x00000004 R29 <= 0x7FFFEFF0
...
HALT: jumps to itself at 0x00000040  (steps=87016)
```

- A line is printed when the register file writes, at the end of WB, so the lines are in program order. The PC is the instruction's own PC: MEM/WB has no PC field, but it is always enabled, so the harness takes the PC that was in EX/MEM one cycle before.
- The run ends like in `ref_sim.py`, and the `HALT:` line has the same text:
  - **Self-jump** (`end: j end`, or any branch to itself that is taken): after its delay slot finishes.
  - **CPU-14 halt**: `HALT: cause C (fetch|load|store) pc ... addr ...`, after the older instructions finish.
  - **`+max-cycles`**: `HALT: reached +max-cycles N at PC=...` (`ref_sim.py` counts instructions, so this line differs).
- `steps` = instructions that finished (nops too, stall bubbles not): the same number `ref_sim.py` prints.
- **HI/LO (CPU-8):** `mult multu div divu` print `HI` then `LO`, `mthi`/`mtlo` one line, in the instruction's place (when it reaches WB). A divide finishes 32 cycles later while the pipeline keeps going, so its lines, and every line after them, wait in a queue until the divider is done. Divide by zero prints nothing, like `ref_sim.py`.

## CPU-9: random waits

The trace must not change when the CPU waits for memory, so the same comparisons run with random waits:

```
make -C verif/verilator compare PROG=test_libc STALL=30 SEED=7       # mem_stall in 30% of the cycles
make -C verif/verilator compare-ext PROG=tc4_rtype FETCH=6 STALL=20  # fetch every instruction from 0x2000_0000
```

- `STALL=<P>` raises `mem_stall` in P% of the cycles at random, with or without a load/store in MEM (`+stall=P`).
- `compare-ext` assembles `src/programs/<PROG>.asm` with `--text-base 0x20000000` into `build/verilator/ext/` and runs it on `mips_sim_ext`, which starts at `0x2000_0000`: every instruction comes through the CPU's external fetch port from a memory in the harness, each new address after 1 to `FETCH`+1 cycles (`+fetch_delay=N`). `ref_sim.py` runs the same image with `--text-base 0x20000000`.
- `SEED=<S>` makes a run repeatable (`+seed=S`).

Checked on Nov 22: `compare` with STALL 10/30/60 for `tc4_rtype tc4_memory tc5_load_use tc5_branch_hazards tc5_jump_hazards count_value_in1 test_stack test_halt hello_pixels test_libc test_bus`, and `compare-ext` with FETCH 0/3/6 (and STALL 30) for every `tc4_*`, `tc5_*`, `count_value_in1/2`, `test_stack`, `test_pseudo`, `test_halt`: all the same trace. `test_libc` takes 128k cycles without waits and 315k with STALL=60, for the same 83,050 instructions.

## PLT-8 / PLT-12: the SDRAM side

```
make -C verif/verilator compare-sdram PROG=test_libc WAIT=30 EXTRA=4      # src/c/<PROG>.c linked like Doom
make -C verif/verilator compare-sdram-asm PROG=tc4_rtype WAIT=40 EXTRA=6  # an .asm run from the SDRAM
build/verilator/mips_sim_sdram +sdram=<image>_sdram.hex [+wad=<file>] [+sdram_wait=P] [+sdram_extra=N]
```

- `compare-sdram` links `src/c/<PROG>.c` with `src/doom/link_sdram.ld` (code, data, `.bss` and heap in the SDRAM, stack on chip), writes `build/verilator/sdram/<PROG>_sdram.hex` with `elf2hex.py --sdram`, runs it on `mips_sim_sdram` and compares with `ref_sim.py --sdram`.
- `WAIT=<P>`: `waitrequest` = 1 in P% of the cycles (`+sdram_wait`). `EXTRA=<N>`: read latency 5 to 5+N cycles (`+sdram_extra`). `STALL` still adds random `mem_stall` on top.
- `+wad=<file>` loads a binary file at SDRAM offset `0x0300_0000` (`0x2300_0000`), like `wad_load.tcl`.
- At the end, stderr also says what the SDRAM cost: `ext_memory: <n> cache misses, <n> SDRAM loads, <n> stores; cycles waiting: <n> fetch, <n> data`.

Checked on Nov 22: `compare-sdram` for `test_libc`, `test_bus` and `hello_pixels` with (WAIT, EXTRA, STALL) = (0, 0, 0), (30, 4, 0) and (60, 8, 30), and `compare-sdram-asm` with WAIT 0 and 40 for every `tc4_*`, `tc5_*`, `count_value_in1/2/3`, `tc16_trace`, `test_pseudo`, `test_rtype`, `test_stack`: all the same trace. A swapped `byteenable` in the bridge makes `test_bus` fail. `test_libc` from the SDRAM: 527k instructions in 1.45M cycles, 1,089 cache misses; most of the waiting is the ~8 cycles of each SDRAM load (83k loads).
Doom (with DOOM-3's WAD in memory) on `mips_sim_sdram`, Nov 22: by 200M cycles (8 s of the board at 25 MHz) it is already past the title screen and playing the E1M1 demo, at ~1.6M simulated cycles per second with `+notrace`:

```
build/verilator/mips_sim_sdram +sdram=build/doom/doom_sdram.hex +wad=build/wad/doom1.wad \
    +notrace +max-cycles=400000000 +ppm_b=build/doom6/frame_b.ppm +ppm_b_every=50000000
```

- `+ppm_b=<file>` saves framebuffer B (320×200) through the mode B palette at the end, and every `+ppm_b_every` cycles. `+notrace` drops the trace lines (only `HALT:`), for long runs.

The same hardware on the real Intel SDRAM controller: `verif/doom_mem.do` in ModelSim (`src/programs/test_ext.s`, PASS with 9 cache misses, the expected number).

## What is checked (Nov 22)

`compare` passes for every program in `mem/` that ends: the TC-4, TC-5, TC-15 and TC-16 programs, the drills, `test_*`, the C programs `hello_pixels` (62,329 writes), `test_libc` (45,277, HI/LO included) and `test_bus`, and the GNU as ISA tests `cpu7_isa` and `cpu8_muldiv` (CPU-7, CPU-8). `test_halt` and `test_bus` end with the same CPU-14 halt line.

Programs that never end (`life_board`, `test_mmio`, `test_mode_b`, `test_timer`) give the same trace as far as both run, except where they read the timer: `ref_sim.py` treats MMIO as RAM, while the hardware timer counts. Switches and keys read 0 (released) in both.
