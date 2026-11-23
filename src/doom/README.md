# Doom (DOOM-1, DOOM-3, DOOM-5)

[doomgeneric](https://github.com/ozkl/doomgeneric) (commit `e257a09`, GPL-2.0, see `doomgeneric/LICENSE`) built for our CPU and linked into the SDRAM region. Memory map, build flags and why: `docs/contracts.md`, "Doom memory" and "Tool settings".

| File | What it is |
|---|---|
| `doomgeneric/` | doomgeneric's 80 source files and its headers, without the platform backends (SDL, X11, Windows…). One change: `PACKEDATTR` is empty on MIPS (`doomtype.h`, marked with a comment) |
| `doomgeneric_mips.c` | Our platform layer (DOOM-2) and `main`, which registers the WAD in the SDRAM as a file (DOOM-3) |
| `wad_mem.c`, `.h` | `wad_size()`: the size of a WAD in memory, from its header and directory (DOOM-3) |
| `host/` | The same Doom on the PC without a window, the reference frames (DOOM-1) |
| `link_sdram.ld` | Linker script: everything from `0x2000_0000`, heap up to the WAD at `0x2300_0000`, stack on chip (top `0x1001_3FF0`) |
| `boot.S` | Boot code for the on-chip text of `top_doom`: waits for KEY0, then `jr` to `0x2000_0000` |
| `Makefile` | Builds all of it |

## Build

In WSL, from the repo root (same tools as `src/c`):

```
make -C src/doom
```

```
build/doom/doom.elf: image 412136 bytes (0x20000000-0x200649E7), with .bss up to 0x2009F394; heap 48515 KB up to the WAD at 0x23000000
```

Output:
- `build/doom/doom.elf`, `.map`, `.lst` (disassembly). Not committed.
- `build/doom/doom.bin`: the SDRAM image (`.text .rodata .data`) from `0x2000_0000`. On the board it is loaded over JTAG at SDRAM offset 0 with `src/tools/wad_load.tcl`, like the WAD at `0x0300_0000`.
- `build/doom/doom_sdram.hex`: the same image, one word per line, for the simulation.
- `mem/doom_boot*.hex`: `boot.S` for the on-chip text (committed, Quartus reads it).

The build stops if anything doesn't fit the memory map (`elf2hex.py --sdram`) or if the code has an instruction our CPU doesn't run (`--isa`: `lwl`/`lwr`, FPU, MIPS32, traps).

Compiler flags (besides those of `src/c`): `-mmemcpy` and `PACKEDATTR` empty (no `lwl`/`lwr`), `-DCMAP256 -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200` (Doom's frame is 8-bit palette indices, the format of video mode B), `-DNORMALUNIX`, `-ffunction-sections` + `--gc-sections`. Doom's own warnings are hidden (`-w`); ours aren't.

## The WAD (DOOM-3)

We use the **shareware `DOOM1.WAD` v1.9** (freely distributable, episode 1 only): 4,196,020 bytes, SHA-1 `5b2e249b9c5133ec987b3ea77596381dc0d6bc1d`. It is never committed: keep it at `build/wad/doom1.wad` (ignored by git), e.g. from <https://raw.githubusercontent.com/Akbar30Bill/DOOM_wads/master/doom1.wad>, and check the SHA-1.

- **On the board:** `wad_load.tcl` writes it at SDRAM offset `0x0300_0000`, so the CPU sees it at `0x2300_0000` (see `docs/contracts.md`, "WAD loading" and "Doom memory").
- **In `main`:** `wad_size()` reads the WAD's header (`IWAD`, lump count, directory offset) and directory, all little-endian, byte by byte, and returns where the file ends: the end of the directory or of the last lump, whichever is further. Nothing is stored next to the WAD: the file describes itself. Then `__mem_file_add("doom1.wad", 0x23000000, size)`, so Doom's `fopen`/`fread` read it from the SDRAM (our C library's files in memory, `src/c/libc/stdio.c`).
- **No WAD there** (not loaded, or a reset that lost the SDRAM): `wad_size()` returns -1, `main` turns on all the LEDs, shows **`bAd1Ad`** on HEX and stops. Load the WAD again and press KEY1.

## On the PC (DOOM-1)

The same doomgeneric sources, defines and platform rules built with the PC's `gcc`, without a window. It is the reference for the Verilator run (DOOM-6) and the board (DOOM-7): what the first frames must look like.

```
make -C src/doom host-run                # WAD=build/wad/doom1.wad FRAMES=40 by default
```

`host/doomgeneric_host.c`:
- Reads the WAD into RAM and checks that `wad_size()` gives exactly the file's size (DOOM-3's check on a real file).
- Doom's `fopen` (redirected by `host/host_files.h`, forced into every doomgeneric file) opens only `doom1.wad`, read only, from that RAM. Every other file fails, as with our C library (no config file, no saves).
- Time only moves in `DG_SleepMs`, so every run gives the same frames.
- `DG_DrawFrame` saves `build/doom/host/frame_NNN.ppm` (320x200, Doom's palette applied) and prints the time and the page shown; it stops after `FRAMES` frames.

Result (Nov 22): Doom prints its whole start-up (`Z_Init` … `ST_Init`, `I_InitGraphics: ... 320 x 200`) and **the very first frame (`frame_000.ppm`) is the title screen** (`TITLEPIC`); frames 1–59 are the same image (the title stays for 170 tics, ~5 s, before the demo). So for DOOM-6 and DOOM-7, the first `DG_DrawFrame` is the goal: everything before it is start-up.

## Sizes (Nov 22)

| Part | Size |
|---|---|
| Image (`.text` + `.rodata` + `.data`) | 402 KB (62,927 instructions) |
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

- **DOOM-6:** run it in Verilator: an SDRAM model in the harness with `doom_sdram.hex` and the WAD, fetching through the instruction cache (PLT-12) or, until it exists, straight through the CPU's external fetch port like `mips_sim_ext`.
