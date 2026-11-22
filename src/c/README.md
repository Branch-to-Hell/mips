# C programs (TC-9, TC-10)

C code for our CPU, compiled with GCC and our minimal C library (`libc/`). Each `.c` file here is one program. The build writes the same memory images as our assembler, so the testbenches, `ref_sim.py` and Quartus (revision `program`) use them the same way.

| File | What it does |
|---|---|
| `crt0.S` | Startup at address 0: `$sp` = top of the stack region − 16 (`0x7FFF_EFF0`), zeroes `.bss`, calls `main`. When `main` returns, `$v0` has its return value and the CPU spins on a self-jump (`j` to itself at `0x40`) |
| `link.ld` | Linker script with the memory map from `docs/contracts.md`: `.text` at `0x0000_0000` (16 KB), `.rodata` + `.data` + `.bss` at `0x1001_0000` (16 KB), stack at `0x7FFF_E000` (4 KB) |
| `Makefile` | Builds `libc.a`, compiles, links, writes the disassembly (`.lst`) and runs `src/tools/elf2hex.py` |
| `libc/` | Our minimal C library (TC-10), see [below](#c-library-tc-10) |
| `hello_pixels.c` | First C program: paints a gradient on framebuffer A and writes the pass code (LEDR = `0x3FF`, HEX = `0x00600D`) |
| `test_bus.c` | CPU-7 byte lanes on every device: `sb`/`sh`/`lb`/`lbu`/`lh` in data, stack, MMIO and framebuffer B; at the end an `sb` to framebuffer A, which must halt (cause 3) |
| `test_libc.c` | Tests of the C library (TC-10): memory and string functions, `snprintf`/`printf`, `malloc`/`free`/`realloc`/`calloc`, `sbrk`, `sscanf`, files in memory. Same pass code; on a failure HEX = `0xBAD0nn` and `main` returns `nn`, the number of the first failed check |

## Build

In WSL, from the repo root (needs `sudo apt install gcc-mips-linux-gnu binutils-mips-linux-gnu make python3`):

```
make -C src/c                  # every program
make -C src/c hello_pixels     # one program
```

Output:
- `build/c/<name>.elf`, `.lst` (disassembly), `.map` (where each symbol went). Not committed.
- `mem/<name>.hex` (text words), `<name>_data.hex` (data words from `0x1001_0000`), `<name>_bytes.hex` and `<name>_b0..b3.hex` (CPU-12 banks).

GCC flags: `-march=mips1 -mabi=32 -msoft-float -mno-abicalls -fno-pic -G0 -EB -O2 -ffreestanding -fno-builtin -nostdlib -mno-check-zero-division -nostdinc -isystem libc/include -isystem <GCC's include>`, linked with `-nostartfiles -static -T link.ld build/c/libc.a -lgcc`.
- `-mno-abicalls -fno-pic`: bare metal, no PIC calls through `$t9`/GOT.
- `-G0`: nothing goes in `.sdata`/`.sbss`, so nothing is `$gp`-relative (`crt0` sets `$gp` = 0).
- `-EB`: big-endian, like the CPU (TC-14).
- `-mno-check-zero-division`: without it GCC puts a `break 7` trap after each `div`/`divu`, and the CPU has no exceptions. Dividing by zero just leaves HI/LO unchanged (like `ref_sim.py`).
- `-nostdinc`: the headers are ours (`libc/include`) and GCC's freestanding ones (`stddef.h`, `stdint.h`, `stdarg.h`, `stdbool.h`). Never the cross compiler's glibc headers, which would compile but not link.
- `-march=mips1`: GCC puts a `nop` after each load (MIPS I load delay slot). Our hazard unit already stalls, so it only costs a cycle. Branch delay slots are filled by GCC (the CPU has them).

## Memory layout

The CPU is Harvard: a `lw` can't read the instruction memory (it halts, CPU-14). So **constants (`.rodata`) go to the data region** with `.data`, not next to the code. Both images are loaded when the FPGA is configured, so `crt0` copies nothing; it only zeroes `.bss`. A reset (KEY) doesn't restore `.data`: a program that changes its initialized globals sees the changed values after a reset.

The heap goes from `_data_end` (the end of `.bss`) to `_heap_end` (the end of the data region, `0x1001_4000`), both from `link.ld`: about 15 KB minus the program's data. It moves to SDRAM with Doom (PLT-8).

## ISA

`mips_pipeline` runs the whole MIPS I integer set (CPU-7, CPU-8), so GCC's output runs as it is: byte and half loads/stores, `sltu`, `mult`/`div`, `jalr`, branches against zero. `lwl`/`lwr`/`swl`/`swr` are not implemented: GCC only uses them for unaligned data (packed structs), so check the `.lst` for them.

The Makefile runs `elf2hex.py --isa`: the build fails, listing addresses, if the code has any instruction our CPU doesn't run (`lwl`/`lwr`, FPU, MIPS32 such as `mul` or `clz`, traps such as `teq`). That is what keeps `libgcc.a` out (see "Software floating point and 64-bit division" below). The single-cycle `mips_cpu` stays phase 1: `make -C src/c ELF2HEX_FLAGS=--phase1` lists what it couldn't run.

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

C library and bus tests, on the CPU (Verilator) against the reference simulator:
```
make -C verif/verilator compare PROG=test_libc     # PASS: 45277 register writes, same trace
make -C verif/verilator compare PROG=test_bus      # PASS: 178 register writes, same trace
```
`test_libc` ends with `main` returning 0 (`HALT: jumps to itself at 0x00000040`). `test_bus` ends with the CPU-14 halt of its last store, `HALT: cause 3 (store) pc 0x000003AC addr 0x10040003`, the same line in both. To see a failure number in `ref_sim.py`: `--dump-regs --dump-mem 0xFFFF001C:1` (`R2` = `main`'s return value, `ref_sim.py` treats MMIO as RAM so HEX is readable there).

Verilator (TC-7), in WSL: `make -C verif/verilator compare PROG=hello_pixels` runs it and compares the trace with `ref_sim.py`; `build/verilator/mips_sim +program=mem/hello_pixels +ppm=hello.ppm` also saves the image (see `verif/verilator/README.md`).

## C library (TC-10)

Our own, small, in `libc/` (decided on Nov 22 instead of newlib/picolibc: there is no prebuilt one for MIPS in Ubuntu, their MIPS `memcpy`/`memset` use `lwl`/`lwr`/`swl`/`swr`, which our CPU doesn't have, and the text region is only 16 KB). It grows with what Doom needs. Only the functions a program calls are linked (`libc.a`).

| Header | What there is |
|---|---|
| `string.h`, `strings.h` | `memcpy memmove memset memcmp memchr strlen strnlen strcpy strncpy strcat strncat strcmp strncmp strchr strrchr strstr strdup strcasecmp strncasecmp strerror`. `memcpy`/`memmove`/`memset` copy whole words when the pointers are word aligned |
| `stdlib.h` | `malloc free calloc realloc`, `atoi atol strtol strtoul abs labs rand srand qsort getenv system`, `exit`/`abort` |
| `stdio.h` | `printf fprintf vprintf vfprintf sprintf snprintf vsprintf vsnprintf putchar puts fputc putc fputs fflush`, `sscanf vsscanf`; files in memory: `__mem_file_add fopen fclose fread fseek ftell feof`; `fwrite` (stdout/stderr), `remove rename` (always fail) |
| `unistd.h` | `sbrk` |
| `ctype.h`, `errno.h`, `assert.h`, `limits.h`, `inttypes.h` | ASCII `is*`/`toupper`/`tolower`, `errno`, `assert` (calls `abort`), the integer limits, the `PRI*` macros |
| `math.h`, `sys/stat.h`, `sys/types.h`, `fcntl.h` | `fabs fabsf`; `stat mkdir` (always fail); the types and flags Doom includes |

- **`printf` goes to nothing**: every character goes through `__putchar(int c)`, which does nothing. A program that defines its own `void __putchar(int c)` gets the output (MMIO, a buffer, …), like `test_libc.c` does.
- **Formats**: `%d %i %u %x %X %o %c %s %p %%`, flags `- 0 + space #`, width and precision (also `*`), lengths `h l z`. No `%ll` and no floating point: `%f %e %g` print `?`.
- **`malloc`**: first fit over the blocks in address order, 8-byte header and 8-byte aligned payloads, free blocks join with the free ones after them, blocks are split when the rest is big enough. It grows the heap with `sbrk`; use `malloc` or `sbrk` in a program, not both. Out of memory: `NULL` (and `errno = ENOMEM` from `sbrk`).
- **`exit(status)`** and `abort()` end like `main` returning: `$v0` = status and a self-jump (`abort` = 134).
- **Files**: there is no file system. `__mem_file_add(name, data, size)` registers a read-only block of memory under a name (up to 4), and `fopen(name, "rb")` + `fread`/`fseek`/`ftell` read it (up to 8 open at once). Doom's WAD in the SDRAM is meant to be registered this way (DOOM-3). Opening anything else, or for writing, returns `NULL`.
- **`sscanf`**: whitespace, literal characters, `%d %i %u %x %X %o`, `%s`, `%c`, `%n`, `*` to skip; no floating point.

### Software floating point and 64-bit division

`libgcc.a` of the cross compiler can't be used: it is built for a MIPS32 CPU with an FPU. Its `__subsf3` is one `sub.s` (an FPU instruction) and its `__divdi3` uses `clz` (MIPS32); our CPU would run them as `nop` and give wrong results without any error. So the helpers GCC calls live in our library, linked before `-lgcc`:
- `softfloat.c`: `__addsf3 __subsf3 __mulsf3 __divsf3 __floatsisf __fixsfsi __extendsfdf2 __ltdf2` (what Doom calls), IEEE 754 single precision, round to nearest even, subnormals, infinities and NaN, with only integer operations (the algorithms of Berkeley SoftFloat 3).
- `divdi3.c`: `__divdi3 __udivdi3 __moddi3 __umoddi3` (`long long` `/` and `%`, Doom's `FixedDiv`): one `divu` when both fit in 32 bits, binary long division otherwise.

Both are checked on the PC against its own FPU and 64-bit division, bit by bit, on millions of random values (special values, subnormals and ties included). From the repo root, in WSL:
```
gcc -O2 -o build/softfloat_test src/c/libc/test/softfloat_test.c && build/softfloat_test   # PASS: 16000000 checks
gcc -O2 -o build/divdi3_test src/c/libc/test/divdi3_test.c && build/divdi3_test           # PASS: 11962232 checks
```
If a program needs another helper (`__adddf3`, `__floatunsisf`, …), `--isa` stops the build when the `libgcc.a` one gets linked: add it to `softfloat.c` and to the test.
- **Size**: programs are compiled with `-ffunction-sections` and linked with `--gc-sections`, so only the functions a program calls are in its image (`printf` alone is ~3 KB). `test_libc` uses about 15 KB of the 16 KB text region.
- The library is compiled with `-fno-tree-loop-distribute-patterns`, so GCC doesn't turn the loop in `memset` into a call to `memset`.
