---
title: References
description: Books, manuals and external code used in the project, with their licenses.
---

## Technical references

- David A. Patterson and John L. Hennessy, *Computer Organization and Design: The Hardware/Software Interface*, 5th edition, chapter 4 (the datapath, control and pipeline).
- MIPS Technologies, *MIPS32 Architecture for Programmers, Volume II: The MIPS32 Instruction Set* (encodings and behavior of every instruction).
- *MIPS 101*, Nanyang Technological University (course reference from the spec).
- *Proyecto final de Arquitectura de Computadoras*, the course's project specification.
- Terasic, *DE10-Lite User Manual* (pins, VGA, SDRAM, switches and keys).
- ISSI, *IS42S16320D* SDRAM datasheet (the board's 64 MB SDRAM).
- Intel, *Embedded Peripherals IP User Guide*: SDRAM Controller and JTAG to Avalon Master Bridge.

## Tools

- MARS 4.5 (Missouri State University): MIPS simulator used to write and check the assembly programs.
- Intel Quartus Prime Lite 20.1 and ModelSim – Intel FPGA Starter Edition 20.1.
- Verilator, GCC (`mips-linux-gnu-gcc`), GNU binutils.
- Astro Starlight (this website), deployed on Vercel.

## External code and data

| What | Where | License |
|---|---|---|
| [doomgeneric](https://github.com/ozkl/doomgeneric), commit `e257a09` | `src/doom/doomgeneric/` | GPL-2.0 (`src/doom/doomgeneric/LICENSE`) |
| Intel SDRAM Controller and JTAG to Avalon Master (Platform Designer IP) | Generated from `quartus/sdram_sys.qsys` | Intel FPGA IP license (Quartus Lite) |
| Shareware `DOOM1.WAD` v1.9 | Not in the repository: loaded at run time | Freely distributable shareware |

Everything else (CPU, platform, assembler, tools, C library, test programs, the Game of Life) was written for this project.
