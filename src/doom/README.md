# Doom (DOOM-5)

[doomgeneric](https://github.com/ozkl/doomgeneric) (commit `e257a09`, GPL-2.0, see `doomgeneric/LICENSE`) built for our CPU and linked into the SDRAM region. Memory map, build flags and why: `docs/contracts.md`, "Doom memory" and "Tool settings".

| File | What it is |
|---|---|
| `doomgeneric/` | doomgeneric's 80 source files and its headers, without the platform backends (SDL, X11, Windows…). One change: `PACKEDATTR` is empty on MIPS (`doomtype.h`, marked with a comment) |
| `doomgeneric_mips.c` | Our platform layer (DOOM-2) and `main` |
| `link_sdram.ld` | Linker script: everything from `0x2000_0000`, heap up to the WAD at `0x2300_0000`, stack on chip (top `0x1001_3FF0`) |
| `boot.S` | Boot code for the on-chip text of `top_doom`: waits for KEY0, then `jr` to `0x2000_0000` |
| `Makefile` | Builds all of it |

## Build

In WSL, from the repo root (same tools as `src/c`):

```
make -C src/doom
```

```
build/doom/doom.elf: image 411608 bytes (0x20000000-0x200647D7), with .bss up to 0x2009F184; heap 48515 KB up to the WAD at 0x23000000
```

Output:
- `build/doom/doom.elf`, `.map`, `.lst` (disassembly). Not committed.
- `build/doom/doom.bin`: the SDRAM image (`.text .rodata .data`) from `0x2000_0000`. On the board it is loaded over JTAG at SDRAM offset 0 with `src/tools/wad_load.tcl`, like the WAD at `0x0300_0000`.
- `build/doom/doom_sdram.hex`: the same image, one word per line, for the simulation.
- `mem/doom_boot*.hex`: `boot.S` for the on-chip text (committed, Quartus reads it).

The build stops if anything doesn't fit the memory map (`elf2hex.py --sdram`) or if the code has an instruction our CPU doesn't run (`--isa`: `lwl`/`lwr`, FPU, MIPS32, traps).

Compiler flags (besides those of `src/c`): `-mmemcpy` and `PACKEDATTR` empty (no `lwl`/`lwr`), `-DCMAP256 -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200` (Doom's frame is 8-bit palette indices, the format of video mode B), `-DNORMALUNIX`, `-ffunction-sections` + `--gc-sections`. Doom's own warnings are hidden (`-w`); ours aren't.

## Sizes (Nov 22)

| Part | Size |
|---|---|
| Image (`.text` + `.rodata` + `.data`) | 402 KB (62,793 instructions) |
| `.bss` | 234 KB |
| Heap | 47 MB available; Doom's zone takes 6 MiB of it |
| WAD | from `0x2300_0000`, up to 16 MB |

Nothing comes from the cross compiler's `libgcc.a` (it is MIPS32 with an FPU): software floating point and 64-bit division are in our C library, checked bit by bit against the PC (see `src/c/README.md`).

## Platform layer

`doomgeneric_mips.c`:
- `DG_Init`: points `DG_ScreenBuffer` at framebuffer B (`0x1005_0000`) and turns on video mode B. `I_FinishUpdate` then copies Doom's frame line by line straight into it.
- `DG_DrawFrame`: writes Doom's palette to the mode B palette when it changes.
- `DG_GetTicksMs`, `DG_SleepMs`: the MMIO timer (milliseconds).
- `DG_GetKey`: no keys yet (DOOM-8).
- `main`: `doomgeneric_Create` with `-iwad doom1.wad`, then `doomgeneric_Tick` forever.

## What's next

- **DOOM-3:** register the WAD in the SDRAM as `doom1.wad` with `__mem_file_add` (our C library's files in memory) before `doomgeneric_Create`, so Doom's `fopen`/`fread` read it. Its size has to come from somewhere (the WAD header and directory, or a size word written next to it when loading).
- **DOOM-6:** run it in Verilator: an SDRAM model in the harness with `doom_sdram.hex` and the WAD, fetching through the instruction cache (PLT-12) or, until it exists, straight through the CPU's external fetch port like `mips_sim_ext`.
