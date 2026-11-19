# Technical contracts

Agreed at kickoff. Changing anything here needs the whole team's OK, because other modules depend on it.
Give this file to the AI as context when generating code.

> **Updated Nov 18** to follow the professor's spec (*Proyecto final de Arquitectura de Computadoras*). What changed and why is in [Changes from the professor's spec](#changes-from-the-professors-spec) at the end.

## Board
Terasic **DE10-Lite** — MAX 10 `10M50DAF484C7G`, 64 MB SDRAM, 4-bit-per-channel VGA, 10 switches, 2 keys, 10 LEDs, 6 HEX displays.

## ISA
**Phase 1 (level 1: professor's programs + Game of Life)**
| Type | Instructions |
|---|---|
| R | `add sub and or nor slt sll srl jr` (+ `addu subu`) |
| I | `addi andi ori slti lui lw sw beq bne` (+ `addiu`) |
| J | `j jal` |

**Professor's encodings (CPU-11, TC-13).** The professor's table gives `add` = funct `0x21`, `sub` = funct `0x23` and `addi` = opcode `0x09`, which are the codes of `addu subu addiu`. With no overflow exceptions both codes do the same thing, so:
- **Hardware** accepts both codes: `0x20`/`0x21`, `0x22`/`0x23`, `0x08`/`0x09`.
- **Assembler** emits the professor's codes (`0x21 0x23 0x09`) for `add sub addi`, and also accepts the mnemonics `addu subu addiu`.

**Phase 2 (level 2: C code and Doom)** — the rest of the MIPS I integer set that GCC uses:
`sltu sltiu xor xori sra sllv srlv srav lb lbu lh lhu sb sh bltz bgez blez bgtz jalr mult multu div divu mfhi mflo mthi mtlo`.
No floating point (C code is compiled with `-msoft-float`). No exceptions/interrupts.

Pseudo-instructions handled by our assembler: `li la move nop`.

## Pipeline
- Classic 5 stages: IF, ID, EX, MEM, WB.
- **Hazard detection unit:** stalls the pipeline on data hazards (including load-use). Forwarding is optional (P1) and only adds speed.
- **Branches and jumps resolved in ID**, with **1 branch delay slot**: the instruction right after a branch/jump always executes (real MIPS behavior, what GCC expects).
- Register file writes on `negedge`, reads afterwards in the same cycle. (The single-cycle CPU writes it on `posedge` instead, see "Memory timing".)
- **Memory stall input:** the whole pipeline freezes while a memory access isn't ready (needed for SDRAM).

### Delay-slot rule for assembly programs
Programs written for MARS (with *Delayed branching* **off**) assume no delay slot. **Our assembler inserts a `nop` after every branch and jump**, so those programs run unchanged. No other NOPs are needed: the hazard unit handles dependencies.
GCC-compiled code (Doom) fills its own delay slots and does not go through our assembler.

**Why we keep the delay slot** (the professor's model has none): GCC always generates MIPS I code with delay slots, so without it there is no Doom. Programs from our assembler get a `nop` in every delay slot, so they behave exactly like the professor's model: the branch/jump target is the next useful instruction that runs. The report explains this (WEB-3).

### Pipeline registers
The professor asks to document every pipeline register (CPU-4): **width, enable, reset, valid bit and when it updates**. All of them use the common clock with enables (stall = enable off, flush = valid off). IF/ID keeps the instruction word **and its PC**.

## Halt on invalid access (CPU-14)
The CPU stops in a **visible** way, and the failing instruction writes **nothing** (no register, no memory), when:
- a **fetch** is outside the text region or not aligned to 4, or
- an **`lw`/`sw`** goes to an address outside every region of the memory map, or not aligned to 4 (byte/half loads and stores in phase 2 check their own alignment).

When halted: the PC freezes, every write is blocked, and the board shows an error code on the LEDs/HEX. Only reset leaves the halt state. The top-level address decoder decides what is valid, so new regions (SDRAM, mode B) just get added to it.

## Memory map
**Decision:** data, framebuffer, stack and MMIO follow MARS's **Default** memory configuration, so MARS programs run without changes. **Text starts at `0x0000_0000`** because the professor asks for "initial PC = 0" (CPU-13). To compare with a MARS dump (text at `0x0040_0000`), assemble with `--text-base 0x00400000`.

**Byte order: big-endian everywhere** (the professor's spec): the byte at the lowest address is the most significant one (bits 31..24) of the word. This applies to the instruction memory, the data memory byte lanes (`sb`/`lb` in phase 2), the assembler image and the Doom build (`-EB`).

The hardware doesn't implement the whole 4 GB. The address decoder looks at the **upper address bits** to pick the region, and the lower bits to pick the position inside that region's on-chip RAM.

| Region | Address | Size on the FPGA | Notes |
|---|---|---|---|
| Text (code) | `0x0000_0000` – `0x0000_3FFF` | 16 KB (4,096 instructions) | **PC reset value = `0x0000_0000`**. One byte per address (see "Instruction memory") |
| Data | `0x1001_0000` – `0x1001_3FFF` | 16 KB | MARS `.data` base |
| Framebuffer mode A | `0x1004_0000` – `0x1004_BFFF` | 48 KB (128×96 words) | MARS Bitmap Display base "0x10040000 (heap)" |
| Stack | `0x7FFF_E000` – `0x7FFF_EFFF` | 4 KB | `$sp` starts at `0x7FFF_EFFC` (MARS default) |
| MMIO | `0xFFFF_0010` – `0xFFFF_0027` | 6 registers | See below. `0xFFFF_0000`–`0xFFFF_000C` are left free for MARS's keyboard/display simulator |
| Framebuffer mode B | `0x1005_0000` – `0x1005_F9FF` | 62.5 KB (320×200 bytes) | Doom only (PLT-6). One byte per pixel, 4 pixels per word, big-endian |
| Palette mode B | `0x1005_FC00` – `0x1005_FFFF` | 256 words | Entry *i* at `0x1005_FC00 + 4i`, `0x00RRGGBB` (PLT-6) |
| SDRAM (phase 2) | defined in Sprint 2 | 64 MB | Doom code, data, heap and WAD |

### CPU memory bus
`mips_cpu` has no memory inside except the instruction memory. Loads and stores go out through this bus, and the top level (`top_life`, PLT-3) sends each access to data, stack, framebuffer or MMIO by looking at the address.

| Port | Dir | Notes |
|---|---|---|
| `mem_addr[31:0]` | out | Byte address, `rs + offset` from its own adder (not the ALU, to keep the half-cycle path short) |
| `mem_wdata[31:0]` | out | Data for `sw` |
| `mem_we` | out | 1 = write (`sw`) |
| `mem_re` | out | 1 = read (`lw`) |
| `mem_rdata[31:0]` | in | Data for `lw`, must be valid before the next `posedge` |
| `mem_fault` | in | 1 = the address isn't in any region or isn't aligned. The CPU halts with no writes (CPU-14) |
| `halted` | out | 1 = the CPU is stopped by a halt; the top level shows the error code |

Phase 2 adds a `mem_stall` input here (CPU-9).

### Instruction memory (CPU-12)
The professor asks for **one byte per address** and big-endian fetch: the word is `mem[PC]`, `mem[PC+1]`, `mem[PC+2]`, `mem[PC+3]`, from the most significant byte to the least.
- Built as **4 byte-lane banks** of 4,096 bytes each: bank *k* holds the bytes at addresses with `addr[1:0] = k`, indexed by `addr[13:2]`.
- All 4 banks are read in the same cycle and joined as `{bank0, bank1, bank2, bank3}`, so fetch takes one cycle, the same as before.
- The assembler writes a **byte-per-address image** and, from it, the 4 bank `.mif` files that Quartus loads (TC-13).

### Memory timing
All memories read on a clock edge, so Quartus can place them in M9K blocks (a combinational read doesn't fit: 16 KB of flip-flops is more than the whole FPGA).
- **Instruction memory:** the 4 banks read on `posedge` using the **next PC** (the same value that goes into the PC register), so the instruction is ready right after the edge.
- **Data memory, stack, framebuffer port A and MMIO:** read and write on `negedge`. The ALU has the first half of the cycle to compute the address; the read data is ready for the second half.
- **Register file (single-cycle):** writes on `posedge`, at the end of the cycle, after the `negedge` read. If it wrote on `negedge`, a `lw` would store the old data.

### MMIO registers
| Address | Register | Access | Notes |
|---|---|---|---|
| `0xFFFF_0010` | SW | read | Bits 9..0 = switches |
| `0xFFFF_0014` | KEY | read | Bits 1..0 = keys, **1 = pressed** (hardware inverts and debounces the active-low keys); software detects the press edge |
| `0xFFFF_0018` | LEDR | write | Bits 9..0 = LEDs |
| `0xFFFF_001C` | HEX | write | Value shown in hexadecimal on the 6 displays (bits 23..0) |
| `0xFFFF_0020` | TIMER | read | Milliseconds since reset |
| `0xFFFF_0024` | VIDEO_MODE | write | Bit 0: 0 = mode A, 1 = mode B (also readable). Reset = mode A |

## Video
| Mode | Used by | Format |
|---|---|---|
| **A** | Game of Life, MARS programs | 128×96, **one word per pixel** `0x00RRGGBB` (same as the MARS Bitmap Display), scaled ×5 to 640×480, top 4 bits per channel stored |
| **B** | Doom | 320×200, **8 bits per pixel** + 256-entry palette writable by the CPU, pixels doubled to 640×400 |

Both are dual-port RAMs: the CPU writes, the VGA reads.

**Mode B in detail (PLT-6):**
- Pixel (x, y) is the byte at `0x1005_0000 + y*320 + x`, a palette index. Big-endian: one `sw` writes 4 pixels, the left one in bits 31..24. The memory is 4 byte-lane banks with byte enables, so `sb` works as soon as the bus carries byte enables (CPU-7).
- Palette entry *i* is written as `0x00RRGGBB`; only the top 4 bits of each color are kept (the VGA has 4 bits per channel), and reads return them repeated (`0xF0` → `0xFF`). After power-up the palette is RGB 3-3-2 (index bits `RRRGGGBB`).
- The 640×400 image is centered on the 640×480 screen, with 40 black lines above and below.
- Both modes run all the time; VIDEO_MODE only picks which one reaches the VGA pins. Mode B is built only where it's needed (`life_system` parameter `MODE_B = 1`: `top_video_b_test` now, `top_doom` later), so `top_life` doesn't spend the 64 M9K blocks on it.

## Clocks
- CPU and VGA at **25 MHz** (single clock domain) for phase 1.
- SDRAM clock from a PLL with phase shift (phase 2).

## Tool settings
- **MARS:** *Settings → Delayed branching* **off**; *Memory Configuration → Default*; Bitmap Display: unit 4×4, display 512 wide, base address `0x10040000 (heap)`.
- **Quartus (MAX 10):** configuration mode *"Single Uncompressed Image with Memory Initialization"* (required for `.mif` files).
- **Instruction RAM:** enable *In-System Memory Content Editor* on the 4 banks to load programs without recompiling.
- **GCC:** `mips-linux-gnu-gcc` (package `gcc-mips-linux-gnu` in WSL) with `-march=mips1 -msoft-float -mno-abicalls -G0 -EB` (**big-endian**, TC-14).
- **Assembler:** text base `0x00000000` by default; `--text-base 0x00400000` only to compare with MARS dumps.
- **Website:** [Astro Starlight](https://starlight.astro.build) in `web/`. One Markdown page per topic in `web/src/content/docs/`; the sidebar is set in `web/astro.config.mjs`. Run `npm run build` from `web/` before opening a PR (it must pass). Vercel deploys with **Root Directory = `web`**: production from `main`, a preview URL for each PR.

## Changes from the professor's spec
Decided on Nov 18 after reviewing the professor's document. Each line says what changed and why.

| What | Before | Now | Why | Task |
|---|---|---|---|---|
| `add sub addi` encoding | `0x20 0x22 0x08` | Hardware accepts both; assembler emits `0x21 0x23 0x09` | Professor's instruction table | CPU-11, TC-13 |
| PC reset / text base | `0x0040_0000` | `0x0000_0000` | "Initial PC = 0" | CPU-13 |
| Instruction memory | One 32-bit word per position | One byte per address, 4 byte-lane banks, big-endian | "Each position holds one byte", big-endian fetch | CPU-12 |
| Endianness | `-EL` "to confirm" | Big-endian everywhere, GCC `-EB` | Big-endian image and fetch | TC-14 |
| Invalid access | Ignored (an invalid `lw` wrote 0) | Visible halt, no writes | "Stop invalid accesses visibly" | CPU-14 |
| Pipeline registers | Not documented | Width, enable, reset, valid, update documented | "Document the intermediate registers" | CPU-4 |

**What we keep, and why** (explained in the report): the branch delay slot (needed by GCC/Doom; our assembler's `nop` makes programs behave like the professor's model), the pipeline (allowed, and it gives the intermediate registers the spec asks for), the word-organized data memory (allowed: "index with address / 4 after validating") and the MARS memory map for data, framebuffer, stack and MMIO (the spec doesn't fix those addresses).
