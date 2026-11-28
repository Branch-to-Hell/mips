---
title: How to reproduce
description: Everything needed to regenerate the images, run the tests and program the board, from a fresh clone.
---

Every command runs from the repository root unless it says otherwise. The repository's [README](https://github.com/Branch-to-Hell/mips#readme) has the same steps with more detail.

## Tools

| Tool | For |
|---|---|
| Python 3.10+ (no extra packages) | The assembler and the tools in `src/tools/` |
| ModelSim – Intel FPGA Starter Edition 20.1 (`vsim` on the PATH) | The testbenches in `verif/` |
| Quartus Prime Lite 20.1 with MAX 10 support + USB-Blaster driver | Building and programming the board |
| MARS 4.5 | Only to compare with MARS (`drill.py`) |
| WSL (Ubuntu) with `gcc-mips-linux-gnu`, `make`, `verilator` | Only for C programs, Doom and Verilator |

## Repository layout

| Folder | What it holds |
|---|---|
| `rtl/` | All the Verilog: the CPU, memories, MMIO, video and the board top levels (`top_*.v`) |
| `verif/` | Testbenches and their ModelSim scripts (`*.do`), the traces (`verif/traces/`) and results |
| `docs/` | Plan, workflow, technical contracts, test coverage, lab checklists and evidence |
| `src/` | Everything that isn't Verilog: the assembler, the assembly programs, C programs, tools, Doom |
| `quartus/` | The Quartus project `mips.qpf`, one revision per board image |
| `mem/` | Memory images written by the assembler, read by ModelSim and Quartus |
| `web/` | This website |

## An assembly program on the board

1. **Write it** in `src/programs/<name>.asm`, like in MARS with *delayed branching* off.
2. **Assemble it:** `python src/assembler/assembler.py src/programs/<name>.asm`. It writes `mem/<name>*.hex` and prints two `set_parameter` lines.
3. **(Optional) check it** against MARS: `python src/tools/drill.py src/programs/<name>.asm` must end with `PASS`.
4. **Build:** paste the two lines into `quartus/program.qsf`, open `quartus/mips.qpf`, pick the revision **`program`** and compile (~3 minutes).
5. **Program:** *Tools → Programmer*, USB-Blaster, add `quartus/output_files/program.sof`, *Start*. The program runs at once (PC = 0).
6. **Read the result:** LEDs and HEX show what the program writes. SW9 up shows a register on the HEX (SW4–0 = its number). A halt shows `E` on HEX5.

The graded algorithm, step by step: [Algorithm → On the board](/algorithm/#on-the-board).

## The Game of Life

1. `python src/assembler/assembler.py src/programs/life_board.asm`
2. Quartus: revision **`top_life`**, compile, program `top_life.sof`.
3. It starts paused with a glider: KEY1 to run ([controls](/game-of-life/#switches-keys-leds-and-displays)).

## The tests

[Tests → How to reproduce everything](/tests/#how-to-reproduce-everything): assemble the test programs, then run the ModelSim scripts from `verif/`. Each prints `PASS` or `FAIL`.

## Doom

In WSL:

```
make -C src/doom                 # builds build/doom/doom.bin and mem/doom_boot*.hex
make -C verif/verilator doom-check   # optional: Doom in Verilator, compared with the PC
```

The WAD is the shareware `DOOM1.WAD` v1.9 (never committed): keep it at `build/wad/doom1.wad` and check its SHA-1 (`src/doom/README.md`).

On the board:

1. Quartus: revision **`top_doom`**, compile, program `top_doom.sof`.
2. System Console (Quartus → *Tools → System Debugging Tools*), from the repo root:
   ```
   source src/tools/wad_load.tcl
   wad_load build/doom/doom.bin 0
   wad_load build/wad/doom1.wad
   ```
3. Press **KEY0**.

The lab checklist with every step and the fallback is `docs/doom-lab-checklist.md`.

## This website

```powershell
cd web
npm install
npm run dev      # http://localhost:4321
npm run build    # must pass before a PR
```
