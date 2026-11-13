# Project plan

> **Read this first.** It explains what we're building, who does what, and where each piece lives in the repo.
> Then read [`workflow.md`](workflow.md) (how we work) and [`contracts.md`](contracts.md) (technical agreements).

## 1. What we're building
A **pipelined MIPS processor in Verilog** on the **DE10-Lite**, with two levels:

| Level | Goal | Priority |
|---|---|---|
| **1. Minimum deliverable** | Our pipelined MIPS runs **any MIPS assembly program** (the professor's included), assembled with **our own assembler**, and runs **Conway's Game of Life** on VGA, controlled with the switches and keys | **P0 — this has to be ready, no matter what** |
| **2. Team goal** | **Real Doom** (the original game, via doomgeneric) running on our MIPS on the DE10-Lite | **P1 — where most of our time goes** |

We also deliver a **report website** on Vercel.
**Presentation: Monday, November 30.**

**Why this split:** the Game of Life is small (about 100–150 lines of assembly), uses only the basic instructions, and needs no new hardware beyond the VGA framebuffer and the switches. That makes the minimum deliverable safe early, so the team can put most of its time into Doom.

**Priority rule:** P0 always goes first. Once the Game of Life runs on the board (target: **Wed Nov 18**), the team's focus shifts to Doom. If a Doom task ever blocks a P0 task, P0 wins.

### Why one CPU serves both levels
Real Doom is C code compiled with GCC, and GCC expects a "real" MIPS: hazards handled by the hardware and one **branch delay slot**. So our pipeline has a **hazard detection unit (stalls)** and resolves branches in **ID with 1 delay slot** (see `contracts.md`). The same CPU runs the professor's programs, the Game of Life and Doom. Our assembler only has to fill each delay slot with a `nop`.

The Game of Life also runs on the **single-cycle CPU**, so the minimum deliverable can be on the board before the pipeline is finished.

### How the pieces fit together
```
 Level 1 (assembly)                           Level 2 (C / Doom)
 sw/programs/*.asm ─► sw/assembler/           sw/doom/ (doomgeneric + our platform layer)
                        │                        │  mipsel-linux-gnu-gcc + linker script + crt0
                        ▼                        ▼
                  hw/mem/*.mif              ELF ─► .hex / WAD loaded into SDRAM
                        │                        │
                        ▼                        ▼
 Switches/keys ─► MMIO ─► hw/rtl/ MIPS CPU (pipeline + hazard unit) ─► Framebuffer ─► VGA
                               │
                    On-chip RAM (level 1)  /  SDRAM 64 MB (level 2)
```
Programs are written and checked in **MARS** (assembly) or on the PC (C) first, so **software never waits for hardware**.

## 2. How we use AI
We use it **wherever it saves time**: writing Verilog, testbenches, the assembler, the reference simulator, C code, scripts and documentation.

What stays human:
- **Verifying.** AI-generated code isn't done until a test proves it works (simulation, trace comparison, or the board).
- **Integrating.** Making pieces from different people work together.
- **Understanding.** Everyone can explain their own module in 2 minutes without notes (part of our Definition of Done).

Practical rules:
- Ask the AI for **the test along with the module**, not just the module.
- Give it our `contracts.md` as context, so every piece follows the same addresses and rules.
- In each PR, say briefly what the AI generated and how you verified it.

## 3. Who does what (and where)
| Person | Focus | Works mainly in |
|---|---|---|
| **Ariel** | **FPGA platform lead.** Everything around the CPU on the board: top-levels, VGA modes, MMIO, timer, SDRAM, WAD loading, lab sessions, Vercel deploy. Leads Doom on the hardware side | `hw/rtl/` (platform), `hw/quartus/`, `hw/mem/` |
| **Victor** | **CPU core lead.** Datapath, control, pipeline, hazard unit, delay slot, full MIPS I instruction set, Verilator harness | `hw/rtl/` (CPU), `hw/sim/` |
| **Uriel** | **Toolchain lead.** Our assembler, the reference simulator, trace comparison, GCC toolchain, cross-compiling Doom | `sw/assembler/`, `sw/tools/`, `sw/doom/` (build) |
| **Yocelyn** | **Software and website lead.** Game of Life, test programs, Doom's platform layer in C, website, report and slides | `sw/programs/`, `sw/doom/`, `web/`, `docs/` |

**Pairs:** Ariel + Victor (hardware), Uriel + Yocelyn (software). Pairs review each other's PRs; Ariel gives the final approval.

### Who depends on whom
| Needs | From | What |
|---|---|---|
| Victor | Uriel | Assembled test programs and the reference simulator, to check the CPU |
| Ariel | Victor | The CPU module with the agreed ports (including a memory-stall input) |
| Yocelyn | Ariel | MMIO addresses (switches, keys, LEDs, HEX, timer) and the framebuffer formats |
| Uriel | Ariel | The memory map, to write the linker script |
| Everyone | Everyone | One paragraph per finished task for the report |

## 4. Timeline and checkpoints
| Sprint | Dates | Goal |
|---|---|---|
| **S1** | Wed Nov 11 – Tue Nov 17 | Single-cycle CPU complete in simulation · framebuffer and MMIO on the board · assembler v1 · **Game of Life with controls in MARS** · all tools installed · doomgeneric running on a PC |
| **S2** | Wed Nov 18 – Tue Nov 24 | **Game of Life on the board** (single-cycle first, then pipelined) · pipeline + hazard unit · full MIPS I instruction set · C programs on our CPU in simulation · SDRAM on the board · Doom platform layer |
| **S3** | Wed Nov 25 – Sun Nov 29 | Doom in simulation and on the board · website finished · validations · rehearsal |
| **Demo** | Mon Nov 30 | Presentation |

**Checkpoints:**

| Date | Checkpoint | Level | If we miss it |
|---|---|---|---|
| **Wed Nov 18** | Game of Life runs on the board (single-cycle CPU) | 1 | Everyone helps until it does |
| **Wed Nov 18** | Pipeline + hazard unit passes the instruction tests in simulation | 1–2 | Victor + Ariel focus on it before anything else |
| **Fri Nov 20** | A C program compiled with GCC passes the trace comparison in Verilator | 2 | Keep going; this is the key Doom milestone |
| **Tue Nov 24** | Game of Life runs on the **pipelined** CPU on the board | 1 | Everyone helps until it does |
| **Tue Nov 24** | SDRAM read/write test passes on the board | 2 | Doom continues in simulation |
| **Wed Nov 25** | Doom title screen in Verilator | 2 | Debug with trace comparison |
| **Fri Nov 27** | Doom title screen on the board | 2 | We present Doom running in simulation + the Game of Life |

**Feature freeze for level 1: Wed Nov 25 at night.** Doom can keep going after that, but it must not touch the Game of Life build. **Final validations on the board: Thu Nov 26 and Fri Nov 27**, the last two lab days before the demo (see section 6).

## 5. Backlog
Priority: **P0** = level 1 (minimum deliverable, must have), **P1** = level 2 (Doom).

### Prerequisites (already established, not tasks)
Everyone has this ready before picking up a task. Details of each tool's configuration are in `contracts.md` (tool settings) and `workflow.md`.

| What | Who | Notes |
|---|---|---|
| Quartus Prime Lite 20.1 (with MAX 10 support) + USB-Blaster driver | Everyone who goes to the lab | Device `10M50DAF484C7G` |
| ModelSim – Intel FPGA Starter Edition 20.1 | Everyone | Same version as Quartus |
| Java + MARS 4.5 | Everyone | Memory Configuration **Default**, Delayed branching **off** |
| Git + access to `Branch-to-Hell/mips` | Everyone | Git is used from Windows only |
| Node.js (LTS) | Everyone | Runs our assembler and the website |
| WSL (Ubuntu) + Verilator + `gcc-mipsel-linux-gnu` | Everyone | Used only for Verilator and GCC, from the repo folder (`wsl --cd .`) |
| Memory map and MMIO registers | — | Decided in `contracts.md` |
| GitHub Project board, labels and sprint milestones | — | Created by the backlog script |

### CPU core
| ID | Task | Owner | Pri | Sprint | Done when |
|---|---|---|---|---|---|
| CPU-1 | Bring the R-type single-cycle into `hw/rtl/` with our naming | Victor + Ariel | P0 | S1 | Passes its R-type tests in the new repo |
| CPU-2 | I-type: `addi andi ori slti lui lw sw` | Victor | P0 | S1 | Each instruction verified in ModelSim |
| CPU-3 | Branches and jumps: `beq bne j jal jr` | Victor | P0 | S1 | Verified in ModelSim |
| CPU-4 | Pipeline registers IF/ID, ID/EX, EX/MEM, MEM/WB | Victor | P0 | S2 | Programs with no dependencies run correctly |
| CPU-5 | Hazard detection unit (stalls for data and load-use hazards) | Victor | P0 | S2 | Hazard test suite passes with no NOPs in the code |
| CPU-6 | Branch/jump resolution in ID + 1 delay slot | Victor | P0 | S2 | Delay-slot tests pass |
| CPU-7 | Full MIPS I integer set: `addu subu addiu sltu sltiu xor xori sra sllv srlv srav lb lbu lh lhu sb sh bltz bgez blez bgtz jalr` | Victor + Ariel | P1 | S2 | Each instruction matches the reference simulator |
| CPU-8 | `mult multu div divu mfhi mflo mthi mtlo` | Victor | P1 | S2 | Matches the reference simulator |
| CPU-9 | Memory-stall input (freeze the pipeline while memory isn't ready) | Victor + Ariel | P1 | S2 | CPU runs correctly with a memory that answers in random delays |
| CPU-10 | Forwarding unit (fewer stalls, faster Doom) | Victor | P1 | S3 | Same tests pass, fewer cycles |

### Platform
| ID | Task | Owner | Pri | Sprint | Done when |
|---|---|---|---|---|---|
| PLT-1 | Quartus project with DE10-Lite pins + video mode A: 128×96 framebuffer, one word per pixel (MARS-compatible), ×5 scaler | Ariel | P0 | S1 | A `.mif` image shows on the monitor |
| PLT-2 | MMIO: SW, KEY (debounced, 1 = pressed), LEDR, HEX | Ariel | P0 | S1 | Switches mirror onto LEDs through the bus; one click = one press |
| PLT-3 | `top_life`: CPU + on-chip RAM + MMIO + framebuffer | Ariel | P0 | S1–S2 | CPU draws a test pattern on the monitor |
| PLT-4 | HEX debug view: switches select a register, value on HEX | Ariel | P0 | S2 | Any register readable on the board |
| PLT-5 | Timer MMIO (millisecond counter) | Ariel | P1 | S2 | A program reads elapsed time |
| PLT-6 | Video mode B: 320×200, 8 bits per pixel + 256-color palette writable by the CPU (reuse `VGA_Frame`) | Ariel | P1 | S2 | CPU fills the screen and changes the palette |
| PLT-7 | SDRAM: Intel SDRAM Controller IP (Platform Designer) + PLL with phase shift | Ariel | P1 | S2 | Controller instantiated, timing met |
| PLT-8 | CPU ↔ SDRAM bridge (waitrequest → CPU memory stall) | Ariel + Victor | P1 | S2 | CPU reads and writes SDRAM in simulation |
| PLT-9 | SDRAM memory test on the board (**checkpoint Nov 24**) | Ariel | P1 | S2 | Whole 64 MB written and read back without errors |
| PLT-10 | WAD loading into SDRAM (JTAG to Avalon Master + System Console script) | Ariel | P1 | S3 | A file from the PC appears byte-exact in SDRAM |
| PLT-11 | `top_doom`: CPU + SDRAM + mode B + timer + inputs (separate Quartus revision) | Ariel | P1 | S3 | Boots a C program from SDRAM |
| PLT-12 | Instruction cache | Ariel + Victor | P1 | S3 | Doom runs noticeably faster |

### Toolchain and verification
| ID | Task | Owner | Pri | Sprint | Done when |
|---|---|---|---|---|---|
| TC-1 | Assembler v1: labels, R/I/J encoding, `.data`, `.mif`/`.hex` output | Uriel | P0 | S1 | Output matches MARS dumps on 3 programs |
| TC-2 | Assembler v2: pseudo-instructions `li la move nop` + fills every delay slot with `nop` | Uriel | P0 | S2 | MARS programs (delayed branching off) run unchanged on our CPU |
| TC-3 | Assembler CLI + README | Uriel | P0 | S2 | A teammate uses it without asking |
| TC-4 | Self-checking test programs per instruction type (result on LEDs) | Yocelyn | P0 | S1 | One program per instruction group |
| TC-5 | Hazard and delay-slot test suite | Victor + Yocelyn | P0 | S2 | Covers data, load-use and branch cases |
| TC-6 | Reference simulator (Python): runs our binaries, prints a trace of every register write | Uriel | P1 | S1–S2 | Matches MARS on the test programs |
| TC-7 | Verilator harness for the CPU, same trace format | Victor | P1 | S2 | Runs a program and prints its trace |
| TC-8 | Trace comparison script: reports the first instruction where CPU and reference disagree | Uriel | P1 | S2 | Points to an injected bug correctly |
| TC-9 | GCC setup: flags (`-march=mips1 -msoft-float -mno-abicalls -G0`), linker script, `crt0.S` (stack + zero the BSS), ELF → `.hex` | Uriel + Ariel | P1 | S1–S2 | A C "hello pixels" runs in Verilator |
| TC-10 | Minimal C library (newlib or picolibc) + `sbrk`/heap | Uriel | P1 | S2 | `malloc`, `memcpy`, `printf`-to-nothing work |
| TC-11 | C programs pass the trace comparison (**checkpoint Nov 20**) | Uriel + Victor | P1 | S2 | 3 C programs match with zero differences |
| TC-12 | Professor drill: unseen MARS program → assemble → load → verify | Uriel + Victor | P0 | S3 | Done in under 15 minutes |

### Game of Life (minimum deliverable)
| ID | Task | Owner | Pri | Sprint | Done when |
|---|---|---|---|---|---|
| LIFE-1 | v0 in MARS: 32×24 board (4×4-pixel cells on 128×96), two buffers, the 4 rules, wrap-around edges | Yocelyn | P0 | S1 | Gliders move correctly in MARS's Bitmap Display |
| LIFE-2 | Run mode: KEY1 run/pause, SW0–3 speed, SW4–5 pattern (gliders, gun, random, empty), KEY0 reset | Yocelyn | P0 | S1 | Works in MARS with the keyboard/MMIO simulator |
| LIFE-3 | Edit mode (paused): SW0–4 column, SW5–9 row, blinking cursor, KEY0 toggles the cell | Yocelyn | P0 | S2 | Draw a pattern in pause and watch it evolve |
| LIFE-4 | Outputs: generation number on HEX, live-cell bar on LEDs | Yocelyn | P0 | S2 | Values update every generation |
| LIFE-5 | Game of Life on the board with the **single-cycle** CPU (**checkpoint Nov 18**) | Ariel + Yocelyn | P0 | S2 | Runs on the monitor, controls respond |
| LIFE-6 | Game of Life on the board with the **pipelined** CPU (**checkpoint Nov 24**) | Ariel + Victor | P0 | S2 | Same behavior as LIFE-5 |

### Doom
| ID | Task | Owner | Pri | Sprint | Done when |
|---|---|---|---|---|---|
| DOOM-1 | Get doomgeneric + a WAD (shareware `DOOM1.WAD` or Freedoom) and run it on a PC | Yocelyn | P1 | S1 | Runs natively on a laptop |
| DOOM-2 | Our platform layer: `DG_Init`, `DG_DrawFrame` (8-bit frame + palette), `DG_SleepMs`, `DG_GetTicksMs` (timer), `DG_GetKey` (switches/keys) | Yocelyn + Ariel | P1 | S2 | Compiles against our MMIO header |
| DOOM-3 | Read the WAD from memory instead of a file | Yocelyn | P1 | S2 | Runs on the PC with the WAD loaded in RAM |
| DOOM-4 | Reduced WAD (E1M1 only) for faster loading | Yocelyn | P1 | S2 | Smaller WAD still works on the PC |
| DOOM-5 | Cross-compile Doom for our MIPS and link it into the SDRAM region | Uriel | P1 | S2–S3 | ELF builds and fits the memory map |
| DOOM-6 | Doom in Verilator until the first frame is saved as an image (**checkpoint Nov 25**) | Victor + Uriel | P1 | S3 | Title screen image from simulation |
| DOOM-7 | Doom on the board: load the WAD, see the title screen (**checkpoint Nov 27**) | Ariel | P1 | S3 | Title screen on the monitor |
| DOOM-8 | Controls on switches/keys | Ariel + Yocelyn | P1 | S3 | Can walk and shoot |

### Website, report and demo
| ID | Task | Owner | Pri | Sprint | Done when |
|---|---|---|---|---|---|
| WEB-1 | Site skeleton + first Vercel deploy | Yocelyn / Ariel | P0 | S1 | Live URL |
| WEB-2 | Assembler page | Uriel (content) + Yocelyn | P0 | S2 | Explains usage and encoding |
| WEB-3 | CPU page: ISA table, datapath and pipeline diagrams, hazard unit | Victor (content) + Yocelyn | P0 | S3 | Published |
| WEB-4 | Game of Life and Doom pages, with screenshots | Yocelyn | P0 | S3 | Published |
| WEB-5 | Report draft of your own section | Everyone | P0 | S2–S3 | In `docs/report/` |
| DEMO-1 | Freeze the demo build: tag the commit and keep the `.sof` + `.mif` files used in the validations (GitHub Release + USB) | Ariel | P0 | S3 (Wed Nov 25) | The exact files we'll use on Nov 30 are tagged and backed up |
| DEMO-2 | 5-minute slides and script | Yocelyn | P0 | S3 | Reviewed by the team |
| DEMO-3 | Full rehearsal | Everyone | P0 | S3 (Fri Nov 27) | Done once end to end |
| DEMO-4 | Validation 1 on the board: full demo run with the frozen build, following `docs/demo-checklist.md` | Ariel + Victor | P0 | S3 (Thu Nov 26) | Every item on the checklist passes |
| DEMO-5 | Validation 2 on the board: repeat the full run; only fixes from validation 1 allowed | Everyone | P0 | S3 (Fri Nov 27) | Every item passes twice in a row |

## 6. Lab plan
| Date | Goal |
|---|---|
| Thu 12 / Fri 13 | Mode A framebuffer showing a `.mif` image; switches → LEDs; keys debounced |
| Mon 16 | No lab (holiday) |
| Tue 17 / **Wed 18** | Single-cycle CPU on the board: test pattern, HEX debug view, **Game of Life running** |
| Thu 19 / Fri 20 | Pipelined CPU on the board; SDRAM controller first tests |
| Mon 23 / Tue 24 | **Game of Life on the pipelined CPU**; SDRAM memory test; first C program from SDRAM |
| **Wed 25** | Buffer for fixes · Doom attempts · **freeze the demo build at night** |
| **Thu 26** | **Validation 1** with the frozen build + professor drill · Doom attempts afterwards |
| **Fri 27** | **Validation 2**: same checklist again + rehearsal · Doom attempts afterwards |
| **Mon 30** | Checklist right before class · Presentation |

**Lab sessions are Monday to Friday only.** We work every day, but weekends are for what doesn't need the board: simulation (ModelSim/Verilator), MARS, the assembler, C code, the website and slides. Doom attempts on the board never use the demo build.

Most Doom work happens **at home in simulation** (Verilator + trace comparison). The lab is for confirming what simulation can't: VGA, switches and real SDRAM timing.

## 7. Risks
| Risk | What we do |
|---|---|
| The pipeline runs late | The Game of Life already runs on the single-cycle CPU from Nov 18; the pipeline only has to catch up |
| Generated code "almost works" | Trace comparison against the reference simulator finds the exact failing instruction |
| SDRAM works "almost right" (random bad bytes) | Memory test on the board before running any C code; check the PLL phase shift |
| Doom finds bugs no test found | Run it in Verilator first, where every cycle is visible |
| Limited lab time | Simulation first, checklists, anyone can go with a checklist |
| The board fails on demo day | Two full validations on the last two lab days (Thu 26, Fri 27) with a frozen and backed-up build; a checklist to run before presenting |

## 8. Kickoff agenda
1. Present the two levels and the priority rule
2. Review `contracts.md`: hazard unit + delay slot, memory map and MMIO registers
3. Agree on the AI rules
4. Sprint 1 planning: everyone picks their cards on the board
