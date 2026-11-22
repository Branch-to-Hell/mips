# C programs (TC-9)

C code for our CPU, compiled with GCC. Each `.c` file here is one program. The build writes the same memory images as our assembler, so the testbenches, `ref_sim.py` and Quartus (revision `program`) use them the same way.

| File | What it does |
|---|---|
| `crt0.S` | Startup at address 0: `$sp` = top of the stack region − 16 (`0x7FFF_EFF0`), zeroes `.bss`, calls `main`. When `main` returns, `$v0` has its return value and the CPU spins on a self-jump (`j` to itself at `0x40`) |
| `link.ld` | Linker script with the memory map from `docs/contracts.md`: `.text` at `0x0000_0000` (16 KB), `.rodata` + `.data` + `.bss` at `0x1001_0000` (16 KB), stack at `0x7FFF_E000` (4 KB) |
| `Makefile` | Compiles, links, writes the disassembly (`.lst`) and runs `src/tools/elf2hex.py` |
| `hello_pixels.c` | First C program: paints a gradient on framebuffer A and writes the pass code (LEDR = `0x3FF`, HEX = `0x00600D`) |

## Build

In WSL, from the repo root (needs `sudo apt install gcc-mips-linux-gnu binutils-mips-linux-gnu make python3`):

```
make -C src/c                  # every program
make -C src/c hello_pixels     # one program
```

Output:
- `build/c/<name>.elf`, `.lst` (disassembly), `.map` (where each symbol went). Not committed.
- `mem/<name>.hex` (text words), `<name>_data.hex` (data words from `0x1001_0000`), `<name>_bytes.hex` and `<name>_b0..b3.hex` (CPU-12 banks).

GCC flags: `-march=mips1 -mabi=32 -msoft-float -mno-abicalls -fno-pic -G0 -EB -O2 -ffreestanding -fno-builtin -nostdlib -mno-check-zero-division`, linked with `-nostartfiles -static -T link.ld -lgcc`.
- `-mno-abicalls -fno-pic`: bare metal, no PIC calls through `$t9`/GOT.
- `-G0`: nothing goes in `.sdata`/`.sbss`, so nothing is `$gp`-relative (`crt0` sets `$gp` = 0).
- `-EB`: big-endian, like the CPU (TC-14).
- `-mno-check-zero-division`: without it GCC puts a `break 7` trap after each `div`/`divu`, and the CPU has no exceptions. Dividing by zero just leaves HI/LO unchanged (like `ref_sim.py`).
- `-march=mips1`: GCC puts a `nop` after each load (MIPS I load delay slot). Our hazard unit already stalls, so it only costs a cycle. Branch delay slots are filled by GCC (the CPU has them).

## Memory layout

The CPU is Harvard: a `lw` can't read the instruction memory (it halts, CPU-14). So **constants (`.rodata`) go to the data region** with `.data`, not next to the code. Both images are loaded when the FPGA is configured, so `crt0` copies nothing; it only zeroes `.bss`. A reset (KEY) doesn't restore `.data`: a program that changes its initialized globals sees the changed values after a reset.

`_data_end` (from `link.ld`) is the first free byte of the data region: the heap start for `sbrk` (TC-10).

## Phase 1 CPU: `--phase1`

`mips_pipeline` only runs the phase 1 ISA until CPU-7 and CPU-8 are merged. The Makefile runs `elf2hex.py --phase1`, which fails and lists the address of each instruction outside phase 1 (`sltu`, `lbu`, `sb`, `multu`, `mfhi`, `jalr`, …). Ways around it while they're missing:
- No `/`, `%` or `*` by a non-power-of-2 (GCC uses `mult`/`multu`/`div`), use shifts and masks.
- `unsigned` comparisons (`<`) use `sltu`: prefer `!=` in loops, or `int`.
- `char`/`short` arrays use `lb`/`lbu`/`sb`: use `int`/`unsigned` arrays.
- Calls through function pointers use `jalr`.

To build anyway (for `ref_sim.py`, which runs the whole ISA): `make -C src/c ELF2HEX_FLAGS=`. Drop the flag from the Makefile once CPU-7 and CPU-8 are in.

## Run

Reference simulator (whole trace, then the halt line):
```
python src/tools/ref_sim.py mem/hello_pixels.hex --dump-mem 0x1004BFFC:1
```
`HALT: jumps to itself at 0x00000040` means `main` returned.

ModelSim, on `life_system` (the board's hardware), checks every pixel and saves `verif/tc9.ppm`:
```
cd verif
vsim -c -do "do tc9.do; quit -f"
```

Board: in `quartus/program.qsf` set the program to `hello_pixels` and compile the `program` revision.

Verilator (TC-7): not yet; the harness will take the same `mem/` images.
