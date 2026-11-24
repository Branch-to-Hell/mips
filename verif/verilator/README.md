# Verilator harness (TC-7)

Runs a program on `life_system` (the same hardware as the board: `mips_pipeline`, the CPU-14 address decoder, data, stack, MMIO, video modes A and B) and prints **the same trace as `src/tools/ref_sim.py`** (`docs/contracts.md`, "Reference simulator trace"), so the two compare with a plain `diff`.

| File | What it does |
|---|---|
| `harness_top.sv` | Wraps `life_system`, loads the program from `+program=`, prints one line per register write in WB and decides when the run ends |
| `sim_main.cpp` | Clock (25 MHz) and reset (4 cycles), until `harness_top` sets `done` |
| `mips_sim_ext` | The same harness built with `EXT_START=1`: it starts at `0x2000_0000` and fetches through the external port (CPU-9) |
| `mips_sim_sdram` | Built with `EXT_START=2`: the real external side, `rtl/ext_memory.v` (SDRAM bridge PLT-8 + instruction cache PLT-12), on `avalon_sdram.sv`, starting at `0x2000_0000` like `top_doom` after `boot.S` |
| `mips_sim_boot` | Built with `EXT_START=3`: like `mips_sim_sdram` but it starts at `0x0` with the on-chip boot code, like `top_doom` (DOOM-7 rehearsal) |
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
The same hardware on the real Intel SDRAM controller: `verif/doom_mem.do` in ModelSim (`src/programs/test_ext.s`, PASS with 9 cache misses, the expected number).

## DOOM-6 / DOOM-7: Doom

Needs the WAD at `build/wad/doom1.wad` (or `WAD=<path>`), see `src/doom/README.md`.

```
make -C verif/verilator doom [FRAMES=3]   # build Doom, run it on mips_sim_sdram, save its first frames
make -C verif/verilator doom-check        # also frame 0 against the PC reference (host build, DOOM-1)
make -C verif/verilator doom-boot         # like the board: boot.S on chip, KEY0, then Doom (mips_sim_boot)
```

- Frames go to `build/verilator/doom/frame_NNN.ppm` (and `frame_000.png`): one each time `doomgeneric_Tick` starts (`+snap_pc`), when the previous Tick has drawn its frame and written its palette. Frame 0 is the title screen.
- `doom-check` runs `make -C src/doom host-run` and compares frame 0 with the PC's frame 0 at 4 bits per color (what mode B's palette keeps): `src/tools/frame_compare.py`.
- `doom-boot` uses `mips_sim_boot` (`EXT_START=3`): the same hardware, starting at `0x0` with `mem/doom_boot` (`boot.S`) like `top_doom`; `doom_boot_inputs.txt` presses KEY0 at cycle 20,000.
- Harness options for this: `+snap_pc=<hex> +snap_skip=K +snap_max=N +snap_prefix=<path>`, `+inputs=<file>` (lines `<cycle> <SW hex> <KEY0> <KEY1>`), `+ppm_b=<file>` / `+ppm_b_every=N`, `+notrace` (no trace lines: ~1.6M simulated cycles per second). See the header of `harness_top.sv`.

Checked on Nov 23, without the data cache (the numbers with it are below):

| What | Result |
|---|---|
| `doom-check` | `MATCH`: frame 0 (TITLEPIC) is the PC's title screen, pixel by pixel at 4 bits per color. Reached at 42.1M cycles (16.1M instructions) = **1.7 s after KEY0** on the board at 25 MHz |
| `doom-boot` | `MATCH` too: `boot.S` waits, KEY0, `jr` to `0x2000_0000`, the same title screen 42.1M cycles later |
| Title frames | 1.3M cycles each (~19 per second at 25 MHz) |
| Demo (attract mode, E1M1), from 162M cycles | **~4.2 frames per second** at 25 MHz: 6.0M cycles per frame on average (5.0M to 8.2M), 65 frames measured. The game runs at the right speed (the timer is real), the picture is choppy |

Where the 600M cycles of that run go (stderr): 30% instructions (177M), **52% waiting for SDRAM loads/stores** (35.5M loads, 13.3M stores), 3% waiting for the instruction cache (1.7M misses), ~15% hazard and multiply/divide bubbles. So a data cache in `ext_memory` is the biggest speed-up left; forwarding (CPU-10) is second (see issue #13).

### The data cache (Nov 23)

`mips_sim_sdram` and `mips_sim_boot` are built with ext_memory's data cache: `DCACHE=<n>` = `DCACHE_LINES_LOG2` (0 = none, the bridge; 9 = 8 KB; **10 = 16 KB, the default and `top_doom`'s**; 11 = 32 KB). Changing it rebuilds them (`build/verilator/dcache_<n>.stamp`), e.g. `make -C verif/verilator doom DCACHE=0`.

The same 600M-cycle Doom run with each size (`doom-check` passes with all of them: frame 0 is still the PC's title screen):

| Data cache | Title screen after KEY0 | Demo, frames per second at 25 MHz | Loads that go to the SDRAM | M9K in `top_doom` |
|---|---|---|---|---|
| none (bridge) | 42.1M cycles = 1.7 s | 4.17 | 100% | 129 |
| 8 KB | 29.4M = 1.18 s | 7.68 | 7.9% | ~138 |
| **16 KB** | **28.6M = 1.15 s** | **7.81** | **7.1%** | **147** |
| 32 KB | 28.5M = 1.14 s | 7.94 | 6.2% | ~165 |

With 16 KB the 600M cycles go: 51% instructions (306M), 16% waiting for data (98M, mostly the ~3 cycles of each write-through store: 23.6M stores), 6% waiting for the instruction cache, ~27% hazard and multiply/divide bubbles. Now forwarding (CPU-10, after the DEMO-1 freeze) and posting stores without waiting (a write buffer) are the next speed-ups.
`doom-boot` with the 16 KB cache: `MATCH`, title at 28.7M cycles.
The title screen and frame 150 of the demo: `docs/evidence/2026-11-23_doom6_title_verilator.png`, `docs/evidence/2026-11-23_doom6_demo_verilator.png`.

## What is checked (Nov 22)

`compare` passes for every program in `mem/` that ends: the TC-4, TC-5, TC-15 and TC-16 programs, the drills, `test_*`, the C programs `hello_pixels` (62,329 writes), `test_libc` (45,277, HI/LO included) and `test_bus`, and the GNU as ISA tests `cpu7_isa` and `cpu8_muldiv` (CPU-7, CPU-8). `test_halt` and `test_bus` end with the same CPU-14 halt line.

Programs that never end (`life_board`, `test_mmio`, `test_mode_b`, `test_timer`) give the same trace as far as both run, except where they read the timer: `ref_sim.py` treats MMIO as RAM, while the hardware timer counts. Switches and keys read 0 (released) in both.
