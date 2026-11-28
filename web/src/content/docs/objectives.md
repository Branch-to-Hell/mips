---
title: Objectives and scope
description: What the professor asks for, what we built on top of it, and every place where we differ from the spec.
---

:::tip[In 30 seconds]
- The assignment: a **32-bit MIPS** on the **DE10-Lite** that runs an assembled program and shows how the bits of an instruction become control signals (Modality A, FPGA).
- We built that as a **5-stage pipeline** with our **own assembler**, and used the same CPU for two extra levels: the **Game of Life** and **Doom**.
- Where the design doesn't follow the spec to the letter (the delay slot, mainly), the last section says why and shows it doesn't change the graded programs.
:::

## The assignment

From *Proyecto final de Arquitectura de Computadoras*, Modality A (processor on the FPGA):

- Implement the datapath and control in HDL for the DE10-Lite, with a reproducible Quartus project, pin assignments, memory images and a testbench.
- Implement the **12 required instructions** (R, I and J formats) with their MIPS encodings.
- Write an **assembler** that resolves labels, prints a listing and exports a loadable image with one byte per address.
- Run an **algorithm** with a loop, a decision, `lw` and `sw`, with three inputs (one edge case) and an observable end point.
- Test every instruction and the integration cases, with one trace per format (R, I, J).
- Publish a report (this site) and demonstrate the program on the board.

## Our objectives

| Level | Objective | Where |
|---|---|---|
| **1. Required** | A MIPS that runs any assembly program assembled by our assembler, including the graded algorithm, with every test the spec lists | [Datapath](/datapath/), [Assembler](/assembler/), [Algorithm](/algorithm/), [Tests](/tests/) |
| **2. Game of Life** | A real interactive program on the board: VGA, switches, keys, LEDs and HEX, all through memory-mapped I/O | [Game of Life](/game-of-life/) |
| **3. Doom** | The original game, compiled with GCC, on the same CPU: SDRAM, caches, a palette video mode and a boot loader | [Doom](/doom/) |

Level 1 always had priority: Doom work was never allowed to break the Game of Life build.

## What the spec asks for, and what we did

| The spec | What we built |
|---|---|
| Single-cycle or multicycle; a pipeline is allowed if the pipeline registers are documented | **5-stage pipeline** with a hazard unit (stalls) and one branch delay slot. Every pipeline register is documented ([Pipeline](/pipeline/)) |
| 12 instructions | The 12, plus `nor sll srl jr andi slti lui bne jal` for the Game of Life, plus the rest of the **MIPS I integer set** for GCC ([Instruction set](/isa/)) |
| Assembler with labels, listing, byte image and diagnostics | Two-pass assembler in Python with all of that, pseudo-instructions and 8 diagnostic examples ([Assembler](/assembler/)) |
| An observable result on the board | HEX displays and LEDs, a **register view** on the HEX (SW9), a visible **halt** with an error code, and VGA |
| Initial PC = 0, big-endian, one byte per address | Done: text at `0x0000_0000`, 4 byte-lane banks, big-endian everywhere (also the Doom build, `-EB`) |

## Where we differ from the spec

Most of the spec is met exactly as written (the table above, and the [tests](/tests/)). These are the points where our design **does not follow the spec to the letter**, because another part of the project (mostly Doom) needed something else. For each one: what the spec asks, what we do, why, and what it means for the programs the spec grades.

| The spec asks | What we do | Why | Effect on the graded programs |
|---|---|---|---|
| **No delay slot:** "the jumps are applied without a delay slot; the target is the next instruction that runs" | The CPU has **one branch delay slot**: the instruction right after a branch or jump always runs | GCC generates MIPS code with delay slots and fills them with useful instructions: without it there is no Doom | **None.** Our assembler puts a `nop` in every delay slot, so the target is the next *useful* instruction that runs, as the spec says ([example](/pipeline/#the-branch-delay-slot)) |
| With overlapped instructions, test "the discarding of the wrong path" | **Nothing is ever discarded.** Branches are resolved in ID, and the only instruction already fetched is the delay slot, which must run | The same reason: discarding the delay slot would break GCC's code | **None visible:** that instruction is the assembler's `nop`. `cpu6.do` tests that it always runs |
| 32 registers "initialized to zero on reset" | All 0 after the board is programmed, **except `$sp` = `0x7FFF_EFFC`** | MARS starts `$sp` there, so programs that use the stack run unchanged on our CPU | **None:** the graded programs don't use `$sp` |
| Stop visibly "any fetch outside the program" | The CPU halts on a fetch **outside the 16 KB text region** or misaligned. Past the end of a program but inside the region, it reads zeros, which are `nop`s | The hardware knows the size of the text region, not of each program | **None:** every program ends in a self-jump (`j end`), so it never runs past its end. `cpu14.do` tests the halt |
