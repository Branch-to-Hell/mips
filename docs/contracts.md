# Technical contracts

Agreed at kickoff. Changing anything here needs the whole team's OK, because other modules depend on it.
Give this file to the AI as context when generating code.

## Board
Terasic **DE10-Lite** — MAX 10 `10M50DAF484C7G`, 64 MB SDRAM, 4-bit-per-channel VGA, 10 switches, 2 keys, 10 LEDs, 6 HEX displays.

## ISA
**Phase 1 (level 1: professor's programs + Game of Life)**
| Type | Instructions |
|---|---|
| R | `add sub and or nor slt sll srl jr` |
| I | `addi andi ori slti lui lw sw beq bne` |
| J | `j jal` |

**Phase 2 (level 2: C code and Doom)** — the full MIPS I integer set that GCC uses:
`addu subu addiu sltu sltiu xor xori sra sllv srlv srav lb lbu lh lhu sb sh bltz bgez blez bgtz jalr mult multu div divu mfhi mflo mthi mtlo`.
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

## Memory map
**Decision:** phase 1 follows MARS's **Default** memory configuration, so MARS programs and dumps match our hardware without changes.

The hardware doesn't implement the whole 4 GB. The address decoder looks at the **upper address bits** to pick the region, and the lower bits to pick the position inside that region's on-chip RAM.

| Region | Address | Size on the FPGA | Notes |
|---|---|---|---|
| Text (code) | `0x0040_0000` – `0x0040_3FFF` | 16 KB (4,096 instructions) | **PC reset value = `0x0040_0000`** |
| Data | `0x1001_0000` – `0x1001_3FFF` | 16 KB | MARS `.data` base |
| Framebuffer mode A | `0x1004_0000` – `0x1004_BFFF` | 48 KB (128×96 words) | MARS Bitmap Display base "0x10040000 (heap)" |
| Stack | `0x7FFF_E000` – `0x7FFF_EFFF` | 4 KB | `$sp` starts at `0x7FFF_EFFC` (MARS default) |
| MMIO | `0xFFFF_0010` – `0xFFFF_0027` | 6 registers | See below. `0xFFFF_0000`–`0xFFFF_000C` are left free for MARS's keyboard/display simulator |
| Framebuffer mode B (phase 2) | defined in Sprint 2 | 320×200 bytes + palette | Doom only |
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

Phase 2 adds a `mem_stall` input here (CPU-9).

### Memory timing
All memories read on a clock edge, so Quartus can place them in M9K blocks (a combinational read doesn't fit: 16 KB of flip-flops is more than the whole FPGA).
- **Instruction memory:** reads on `posedge` using the **next PC** (the same value that goes into the PC register), so the instruction is ready right after the edge.
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
| `0xFFFF_0024` | VIDEO_MODE | write | 0 = mode A, 1 = mode B |

## Video
| Mode | Used by | Format |
|---|---|---|
| **A** | Game of Life, MARS programs | 128×96, **one word per pixel** `0x00RRGGBB` (same as the MARS Bitmap Display), scaled ×5 to 640×480, top 4 bits per channel stored |
| **B** | Doom | 320×200, **8 bits per pixel** + 256-entry palette writable by the CPU, pixels doubled to 640×400 |

Both are dual-port RAMs: the CPU writes, the VGA reads.

## Clocks
- CPU and VGA at **25 MHz** (single clock domain) for phase 1.
- SDRAM clock from a PLL with phase shift (phase 2).

## Tool settings
- **MARS:** *Settings → Delayed branching* **off**; *Memory Configuration → Default*; Bitmap Display: unit 4×4, display 512 wide, base address `0x10040000 (heap)`.
- **Quartus (MAX 10):** configuration mode *"Single Uncompressed Image with Memory Initialization"* (required for `.mif` files).
- **Instruction RAM:** enable *In-System Memory Content Editor* to load programs without recompiling.
- **GCC:** `-march=mips1 -msoft-float -mno-abicalls -G0 -EL` (little-endian; confirm endianness at kickoff).
