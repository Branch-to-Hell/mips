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
`sltu sltiu xor xori sra sllv srlv srav lb lbu lh lhu sb sh bltz bgez blez bgtz jalr mult multu div divu mfhi mflo mthi mtlo` (+ `bltzal bgezal`, which GCC uses as `bal`).
No floating point (C code is compiled with `-msoft-float`). No exceptions/interrupts: `syscall`, `break` and unknown instructions write nothing (they act as `nop`).
Not implemented: the unaligned-access instructions `lwl lwr swl swr` (GCC only emits them for packed or unaligned data).

**Phase 2 in `mips_pipeline` (CPU-7, CPU-8).** The single-cycle `mips_cpu` stays phase 1: it shares the decoder and the ALU, so phase 1 programs run exactly as before, but it has no byte lanes, branches against zero or HI/LO.
- `sltiu` sign-extends its immediate and then compares unsigned (like MIPS); `xori` zero-extends, like `andi ori`.
- `sllv srlv srav` use only `rs[4:0]` as the shift amount.
- Byte/half loads and stores: see "CPU memory bus" (`mem_be`).
- `bltzal bgezal` write `PC + 8` into `$ra` even when the branch is not taken; `jalr rd, rs` writes `PC + 8` into `rd` (`$ra` if omitted).
- **HI/LO (`mult_div.v`, in EX):** `mult/multu` take 1 cycle (33x33 signed multiplier on the DSP blocks). `div/divu` take 32 cycles in the background, like the R2000: the pipeline keeps running, and any HI/LO instruction (`mfhi mflo mthi mtlo mult div`) waits in ID until the divide is done. The quotient rounds toward zero and the remainder has the dividend's sign (C semantics). Divide by zero gives a defined but meaningless result; compile with GCC's default zero check (`break 7`, a `nop` here) or `-mno-check-zero-division`.

Pseudo-instructions handled by our assembler: `li la move nop`.

## Pipeline
- Classic 5 stages: IF, ID, EX, MEM, WB.
- **Hazard detection unit:** stalls the pipeline on data hazards (including load-use). Forwarding is optional (P1) and only adds speed.
  - `hazard_unit.v` (CPU-5). Every operand is read in ID (ALU and memory operands, the `beq/bne` compare, the `jr` address), and without forwarding the only path to ID is the WB bypass. So: **stall while ID reads a register that the instruction in EX or MEM will write**. `$zero` never stalls.
  - Sources are decoded exactly, so there are no false stalls: `rs` is read by everything except `j/jal/sll/srl/sra`; `rt` only by R-type, stores (`sb sh sw`) and `beq/bne` (in I-type ALU instructions and loads it is the destination; in `bltz/bgez/bltzal/bgezal` it selects the branch).
  - CPU-8: an instruction that uses HI/LO also stalls while a divide is running (or starting in EX).
  - During a stall, `fetch_pc` and IF/ID hold (the instruction in ID waits, and a branch/jump in ID doesn't redirect yet), ID/EX gets a bubble, and EX/MEM/WB keep going. A dependency on the previous instruction costs 2 cycles, on the one before 1 cycle (load-use included).
- **Branches and jumps resolved in ID**, with **1 branch delay slot**: the instruction right after a branch/jump always executes (real MIPS behavior, what GCC expects).
  - In ID: `beq/bne` compare the two register operands directly (no ALU), and `bltz bgez blez bgtz bltzal bgezal` look only at the sign bit of `rs` and whether it is zero; the target is `PC + 4 + (offset << 2)`, `j/jal` use `{(PC + 4)[31:28], target, 00}` and `jr/jalr` use `rs`. The fetch PC changes on the same edge that fetches the delay slot, so **nothing is flushed** (CPU-6).
  - `jal` writes **`PC + 8`** into `$ra` (the instruction after the delay slot), and so do `jalr` (into `rd`) and `bltzal/bgezal`. The single-cycle `mips_cpu` has no delay slot and writes `PC + 4`.
- An instruction in WB is visible to the instruction in ID **in the same cycle**. The register file is shared with the single-cycle CPU and writes on `posedge` (end of WB), so `mips_pipeline` adds a write-through bypass from WB to the ID read ports (never for `$zero`). It behaves like "write in the first half, read in the second".
- **LIFE-6:** `life_system` (so `top_life` and `top_video_b_test`) runs `mips_pipeline`. The single-cycle `mips_cpu` stays in the repo for its own testbenches and `top_mmio_test`; the board fallback is the single-cycle `.sof` saved before the switch.
- **Waiting for memory (CPU-9):** the pipeline freezes while a load/store isn't done, and IF waits for an instruction from the SDRAM (see "Waiting for memory").

### Delay-slot rule for assembly programs
Programs written for MARS (with *Delayed branching* **off**) assume no delay slot. **Our assembler inserts a `nop` after every branch and jump**, so those programs run unchanged. No other NOPs are needed: the hazard unit handles dependencies.
GCC-compiled code (Doom) fills its own delay slots and does not go through our assembler.

**Why we keep the delay slot** (the professor's model has none): GCC always generates MIPS I code with delay slots, so without it there is no Doom. Programs from our assembler get a `nop` in every delay slot, so they behave exactly like the professor's model: the branch/jump target is the next useful instruction that runs. The report explains this (WEB-3).

### Pipeline registers
The professor asks to document every pipeline register (CPU-4): **width, enable, reset, valid bit and when it updates**. All of them use the common clock with enables (stall = enable off, flush = valid off). IF/ID keeps the instruction word **and its PC**.

Common rules (`pipeline_register.v`, `if_id_register.v`):
- **Update:** rising edge of the CPU clock. No gated or derived clocks.
- **Priority:** synchronous reset > flush > enable > hold.
- **Reset and flush:** clear the payload and `valid`, even when `enable = 0`.
- **Enable = 1:** latch the input if it is valid. If not, load a bubble (all zeros, `valid = 0`).
- **Enable = 0 (stall):** keep the payload **and** `valid`.
- **Valid bit:** every side effect (memory read/write, register write) is gated with `valid`, so a bubble never changes state.

| Register | Width | Contents |
|---|---|---|
| IF/ID | 64 + valid = 65 | PC (32), instruction (32). The instruction memory's output register **is** the instruction field (M9K, no reset): it is masked to `nop` while `valid = 0`, and on a stall it re-reads the address in PC so the word does not change |
| ID/EX | 154 + valid = 155 | PC (32, for `halt_pc`), A or the link value PC + 8 (32), B / store data (32), immediate (32), destination (5), shamt (5), ALU control (4), ALUSrc, RegWrite, MemRead, MemWrite, MemtoReg, memory size (2), MemUnsigned, HI/LO operation (4) |
| EX/MEM | 108 + valid = 109 | PC (32, for `halt_pc`), ALU/HI/LO result or address (32), store data (32), destination (5), RegWrite, MemRead, MemWrite, MemtoReg, memory size (2), MemUnsigned |
| MEM/WB | 38 + valid = 39 | value to write (32, memory or ALU, chosen in MEM; loads already extended), destination (5), RegWrite |

HI and LO are not pipeline registers: they live in `mult_div` (EX) and are written only by an instruction that completes (valid, not dropped by a halt).

CPU-5 turns off the IF/ID enable and sends a bubble into ID/EX on a stall, CPU-6 redirects the fetch PC (no flush: the delay slot runs), and CPU-9 turns off the enables of fetch, IF/ID, ID/EX and EX/MEM while `mem_stall` = 1 (MEM/WB gets a bubble), and holds IF/ID while a fetch isn't ready (ID/EX gets a bubble). No register is flushed.

## Halt on invalid access (CPU-14)
The CPU stops in a **visible** way, and the failing instruction writes **nothing** (no register, no memory), when:
- a **fetch** is outside the text region or not aligned to 4, or
- a **load/store** goes to an address outside every region of the memory map, or is misaligned for its size: words need `addr[1:0] = 0`, halves (`lh lhu sh`) `addr[0] = 0`, bytes can be anywhere.

When halted: the PC freezes, every write is blocked, and the board shows an error code on the LEDs/HEX. Only reset leaves the halt state. The top-level address decoder decides what is valid, so new regions (SDRAM, mode B) just get added to it.

How `mips_pipeline` does it:
- **Fetch:** checked when the instruction reaches ID. Its PC must be inside the 16 KB text region and word aligned. Every fetched instruction runs (there is no flush), so the fault is real.
- **Loads/stores:** checked in MEM. It fails if `mem_fault = 1` (no region) or the address is misaligned for its size (the CPU checks this itself). `mem_re`/`mem_we` stay at 0 and the instruction goes into MEM/WB as a bubble, so no device and no register is written.
- **Precise:** older instructions finish, and the failing one and every younger one write nothing. If an older load/store fails after a younger fetch fault (for example a bad `lw` in the delay slot of a `jr` to a bad address), the load/store is the one reported. HI/LO are not touched by a dropped instruction either.

| Output | Meaning |
|---|---|
| `halted` | 1 = stopped |
| `halt_cause[1:0]` | 1 = fetch, 2 = load (`lw lh lhu lb lbu`), 3 = store (`sw sh sb`) (0 = running) |
| `halt_pc[31:0]` | PC of the failing instruction |
| `halt_addr[31:0]` | The bad address (for a fetch, the PC itself) |

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
| SDRAM | `0x2000_0000` – `0x23FF_FFFF` | 64 MB | `top_doom` only: Doom's code, data, heap and the WAD. Decoded with `mem_addr[31:26] == 6'b001000`. See "Doom memory" |

### CPU memory bus
The CPU has no memory inside except the instruction memory. Loads and stores go out through this bus, and the top level (`life_system`, PLT-3) sends each access to data, stack, framebuffer or MMIO by looking at the address. The same address decoder drives `mem_fault` (CPU-14): an address in no region of the memory map halts the CPU. While halted, `life_system` shows the error code: LEDR9 = halted, LEDR1-0 = cause, HEX = `E`, cause, bad address bits 15..0 (SW8 up: PC bits 23..0). SW9 still picks the register debug view. Checked in `verif/halt_tb.v`.

| Port | Dir | Notes |
|---|---|---|
| `mem_addr[31:0]` | out | Byte address, `rs + offset` from its own adder (not the ALU, to keep the half-cycle path short) |
| `mem_wdata[31:0]` | out | Data for stores. `sb` repeats the byte in all 4 lanes and `sh` the half in both, so a device only has to look at `mem_be` |
| `mem_be[3:0]` | out | `mips_pipeline` only (CPU-7). Byte enables, big-endian like `framebuffer_b`: `mem_be[3]` = bits 31..24 = the byte at the lowest address. `sw`/`lw` = `1111`; `sh`/`lh` = `1100` at offset 0, `0011` at offset 2; `sb`/`lb` = `1000 >> addr[1:0]` |
| `mem_we` | out | 1 = write (`sw sh sb`) |
| `mem_re` | out | 1 = read (`lw lh lhu lb lbu`) |
| `mem_rdata[31:0]` | in | The whole word, must be valid before the next `posedge`. For `lb/lh` the CPU picks the byte/half and sign- or zero-extends it |
| `mem_fault` | in | 1 = `mem_addr` isn't in any region. It must depend only on `mem_addr` (not on `mem_re`/`mem_we`). The CPU checks alignment itself and halts with no writes (CPU-14) |
| `halted`, `halt_cause[1:0]`, `halt_pc[31:0]`, `halt_addr[31:0]` | out | The CPU is stopped by a halt, why, where and which address (see "Halt on invalid access"); the top level shows the error code |

**Waiting for memory (CPU-9).** The SDRAM answers in several cycles, so the CPU can wait in two places:
- `mem_stall` (in): the load/store in MEM is not done this cycle. Fetch, IF/ID, ID/EX and EX/MEM hold, so `mem_addr`, `mem_wdata`, `mem_be`, `mem_re` and `mem_we` stay the same; MEM/WB gets a bubble (the instruction already in WB writes once). The read data is taken on the edge where `mem_stall` = 0. HI/LO don't start an operation while it is 1. On-chip devices never raise it.
- **Fetch wait** (`mips_pipeline` parameter `EXT_TEXT` = 1): a PC in the external text region (`EXT_TEXT_BASE` = `0x2000_0000`, 2^`EXT_TEXT_BITS` = 64 MB) is fetched through `ifetch_addr`/`ifetch_req` → `ifetch_data`/`ifetch_ready`, the instruction cache's port (PLT-12). IF/ID takes the word on the edge where `ifetch_ready` = 1, and it must stay valid while `ifetch_addr` doesn't change (a hit does). Until then IF and ID hold and ID/EX gets bubbles, like a hazard stall, so a branch stays in ID until its delay slot is fetched. The CPU-14 fetch check accepts both text regions: the 16 KB on chip (`TEXT_BASE`) and the external one. `RESET_PC` (default `TEXT_BASE`) is the first fetch.
  - `ifetch_next` (out, PLT-12): the address `fetch_pc` (= `ifetch_addr`) will hold after this edge (`RESET_PC` in reset). The instruction cache reads its M9K RAMs with it, so in the next cycle their outputs belong to `ifetch_addr` and a hit answers in the same cycle (one instruction per cycle). `life_system` passes it out with the other fetch ports.
- **`life_system`** with `EXT_BUS` = 1 decodes the SDRAM region (`ext_sel`, no fault) and has the ports for the external side: the CPU's bus (`bus_*`), `ext_rdata` (OR'd into the read bus, 0 unless answering), `ext_stall` (→ `mem_stall`) and the fetch port. With `EXT_BUS` = 0 (`top_life`, `top_program`) the region faults and nothing ever waits.
- Tested in Verilator with random waits: `make -C verif/verilator compare PROG=<name> STALL=<percent>` and `compare-ext` (the program runs from `0x2000_0000`, every fetch through the port, `FETCH=<max delay>`); see `verif/verilator/README.md`.

**Devices and `mem_be`** (wired in `life_system`):
- `data_memory` (data and stack): 4 byte-lane banks like the instruction memory, one write enable per byte (`ByteEnable` port). Word stores must still be aligned there (the single-cycle `mips_cpu` relies on it to ignore a misaligned `sw`).
- `framebuffer_b`: its `fb_be` input.
- MMIO: a byte or half store changes only its bytes of the register, picked by the word address (`sb` to `0xFFFF_001F` = HEX bits 7..0).
- **Framebuffer A and the palette take whole words only**: they keep 12 bits per word (4 per color), so a byte or half access there is a CPU-14 halt (cause 2 or 3), through `mem_fault`. `mem_fault` may look at `mem_be` because it depends only on the instruction in MEM, not on `mem_re`/`mem_we`. `ref_sim.py` halts the same way.
- Tops and testbenches with the single-cycle CPU tie `ByteEnable`/`be` to `4'b1111`.

### Instruction memory (CPU-12)
The professor asks for **one byte per address** and big-endian fetch: the word is `mem[PC]`, `mem[PC+1]`, `mem[PC+2]`, `mem[PC+3]`, from the most significant byte to the least.
- Built as **4 byte-lane banks** of 4,096 bytes each: bank *k* holds the bytes at addresses with `addr[1:0] = k`, indexed by `addr[13:2]`.
- All 4 banks are read in the same cycle and joined as `{bank0, bank1, bank2, bank3}`, so fetch takes one cycle, the same as before.
- **Image files** for a program `<name>` (in `mem/`), all with one byte per line, 2 hex digits, LF, no addresses:
  - `<name>_bytes.hex`: one byte per address, big-endian (the professor's loadable image).
  - `<name>_b0.hex` … `<name>_b3.hex`: bank *k* = the bytes at addresses with `addr[1:0] = k`; line *i* is the byte of instruction *i*.
  - `instruction_memory` loads the 4 bank files with `$readmemh` from the prefix in `IMEM_INIT` (e.g. `"../mem/life_board"`), in ModelSim and in Quartus.
  - The assembler writes them from the ASM (TC-13), together with the word image `<name>.hex` and the data image `<name>_data.hex` (plus its 4 lanes `<name>_data_b0..b3.hex`, see `.data` below). Everything goes to `mem/` by default (or to the folder given with `-o`), never to `src/programs/`. For a word `.hex` that does not come from our assembler (for example GNU as output), `src/tools/hex2banks.py` makes the same files.
  - **No `.mif` files** for program images: `$readmemh` with `.hex` works the same in ModelSim and Quartus.
  - **`.data` (TC-15, CPU-7):** `<name>_data.hex` has one word per line from `0x1001_0000` (what `ref_sim.py` reads). `data_memory` has one bank per byte lane, so it loads the same image split in 4 lanes, `<name>_data_b0..b3.hex` (one byte per line, lane *k* = bits `31-8k..24-8k`), from the prefix in its `INIT_FILE` parameter, as the initial content of its RAM; the rest of the region starts at 0. `life_system` passes the prefix as `DMEM_INIT` (e.g. `"../mem/count_value_in1_data"`). The assembler and `elf2hex.py` write the lanes; `hex2banks.py <name>_data.hex` makes them for any other word image. `top_program` (Quartus revision `program`) runs any assembled program with its `.data`, picked in `program.qsf`, without touching the Game of Life build. The data is loaded at configuration time only: a reset does not restore it.

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
- **SDRAM (PLT-7):** the SDRAM controller runs in the **same 25 MHz domain** as the CPU (no clock crossing). `pll_sdram` gives `c0` = 25 MHz (system) and `c1` = 25 MHz shifted **−3 ns**, which goes out on `DRAM_CLK`. `sdram_test.sdc` constrains the SDRAM pins with the chip's datasheet timing; reads have a multicycle of 2 because the controller captures the data one cycle after the SDRAM's edge.

## SDRAM (PLT-7)
- **Chip:** ISSI IS42S16320D-7, 32M × 16 = 64 MB, 4 banks, 13 row bits, 10 column bits.
- **Platform Designer system `sdram_sys`** (`quartus/sdram_sys.qsys`, rebuilt by `sdram_sys.tcl`): Intel SDRAM Controller (CAS latency 2, refresh every 7.8125 µs, 100 µs power-up) behind a **32-bit Avalon-MM bridge**. Platform Designer adds the 32 → 16 width adapter, so the master sees 64 MB of 32-bit words.
- **Interface `mem`** (what the CPU bridge, PLT-8, masters): 26-bit **byte** address (multiple of 4), `read`/`write`, `writedata`/`readdata` 32 bits, `byteenable` 4 bits, `waitrequest` (hold the command while it's 1), `readdatavalid` (read data arrives a few cycles later). One access at a time takes ~6–7 cycles.
- **Byte order:** Avalon byte lanes are little-endian (byte address A+k = bits 8k+7..8k = `byteenable[k]`). The CPU is big-endian, so the PLT-8 bridge **swaps the 4 bytes** of `writedata`/`readdata` and reverses `byteenable`. Then a file written byte by byte into SDRAM (WAD loading, PLT-10) reads back correctly with `lb`.
- **Quartus:** revision `sdram_test` (`top_sdram_test`) adds `sdram_sys.qsys` with `QSYS_FILE`, so Quartus generates its HDL during compilation. `verif/sdram.do` generates the simulation HDL (with the controller's memory model) by itself.

## WAD loading (PLT-10)
- **Hardware:** `sdram_sys` has a second master on the SDRAM, a **JTAG to Avalon Master** (`jtag`, no ports at the top level). Platform Designer arbitrates it with the CPU bridge, so the PC can read and write the SDRAM over the USB-Blaster while the design runs. Any top level with `sdram_sys` gets it (today `sdram_test`, later `top_doom`).
- **Script:** `src/tools/wad_load.tcl` (System Console) writes a file into the SDRAM, reads it back and compares it: `system-console -cli --script=src/tools/wad_load.tcl <file> [offset]` prints `PASS: the SDRAM holds the file byte-exact`. Inside System Console: `source src/tools/wad_load.tcl`, then `wad_load <file> [offset]` or `wad_verify <file> [offset]` (read back only).
- **Where:** byte *i* of the file goes to SDRAM byte offset `offset + i`. Default offset `0x0300_0000` (the top 16 MB of the SDRAM; Doom's code, data and heap use the lower 48 MB). The CPU sees it at `0x2300_0000` (SDRAM base `0x2000_0000` + offset, see "Doom memory").
- **Byte order:** the JTAG master writes Avalon byte lanes (byte address A+k = `byteenable[k]`), and the CPU bridge swaps the bytes of each word (see SDRAM above), so the CPU sees the file in order: `lb` at offset + *i* = file byte *i*, and `lw` = 4 file bytes, most significant first (big-endian, like the WAD read by `-EB` code).
- **`sdram_test`:** the smoke test writes all 64 MB after reset and on KEY0, so **SW9 = 1** (LEDR8 on) keeps it from starting; set it before loading. The file is lost on power-off, and a KEY1 reset holds the controller in reset (no refresh while the key is down), so after a reset run `wad_verify` or load again.

## Doom memory (`top_doom`, PLT-11)
Doom's code doesn't fit on chip: built with our flags it is 367 KB of code and constants, 60 KB of `.data` and 243 KB of `.bss`, and it needs a 6 MiB zone heap and the 4 MB WAD, while the whole FPGA has ~182 KB of M9K (mode B takes 64 KB). So Doom runs from the SDRAM, through an instruction cache. The level 1 regions don't change.

| Where | Address | What |
|---|---|---|
| On-chip text | `0x0000_0000` | Boot code (`src/doom/boot.S`): waits for KEY0, so the image and the WAD can be loaded over JTAG first, then `jr` to `0x2000_0000` |
| SDRAM + `0x0000_0000` | `0x2000_0000` | The Doom image: `.text`, `.rodata`, `.data` (loaded over JTAG like the WAD), then `.bss` (zeroed by Doom's `crt0`) |
| SDRAM, after `.bss` | up to `0x22FF_FFFF` | Heap (`sbrk`/`malloc`): the zone and the rest, ~47 MB. `_heap_end` = `0x2300_0000` |
| SDRAM + `0x0300_0000` | `0x2300_0000` – `0x23FF_FFFF` | The WAD (16 MB, `wad_load.tcl`'s default offset). Only the file is loaded, no size word: `main` finds its size from the WAD's own header and directory (DOOM-3, `src/doom/wad_mem.c`) and registers it as the file `doom1.wad`. If there is no valid IWAD there, all LEDs on, HEX `bAd1Ad`, and Doom doesn't start |
| On-chip data region | `0x1001_0000` – `0x1001_3FFF` | Doom's **stack**, top `0x1001_3FF0`: 1-cycle access instead of ~7. An overflow goes below `0x1001_0000`, outside every region, and halts visibly (CPU-14) |

- The SDRAM is one 256 MB region for `j`/`jal` (`PC[31:28] = 2`), so they reach any Doom function; only the boot code needs `jr`.
- **`ext_memory` (`rtl/ext_memory.v`)** is everything between `life_system`'s external side and `sdram_sys`'s `mem` port: the bridge, the instruction cache and their arbiter.
- **Instruction cache (PLT-12, `rtl/icache.v`):** direct-mapped, 8 KB (512 lines of 16 bytes = 4 words), read-only (code is never written). Address bits inside the 64 MB region: tag = `[25:13]`, index = `[12:4]`, word = `[3:2]`. Tags (valid + 13 bits, 512 × 14) and data (2048 × 32) are M9K RAMs read with `ifetch_next` (see "Waiting for memory"): a hit is one instruction per cycle. A miss reads the line's 4 words with pipelined Avalon reads (all 4 in flight), writes them as they arrive, then the tag, and waits 2 cycles (`SETTLE`) until the RAMs have been read again after the last write (Quartus infers them with old data on a read during a write). Reset walks the 512 lines and clears their valid bits (512 cycles), so after a CPU reset nothing from an older image is used. Bytes are swapped like the bridge's.
- **Bridge (PLT-8, `rtl/sdram_bridge.v`):** a load/store to the SDRAM region (`ext_sel`) raises `ext_stall` (→ `mem_stall`) until it is done, one at a time: `IDLE` → `CMD` (command held while `waitrequest` = 1) → `WAIT` (reads: until `readdatavalid`) → `DONE` (stall = 0 for one cycle; the CPU takes `ext_rdata` on that edge). A store takes ~3 cycles plus the controller's `waitrequest`, a load ~8. `DONE` always goes back to `IDLE`, because EX/MEM moves on that edge: a load/store seen in `IDLE` is always a new one. `ext_rdata` is 0 except in `DONE` after a load. Byte lanes: `writedata`/`readdata` bytes swapped and `byteenable` reversed (see "SDRAM"). No data cache.
- **Arbiter (in `ext_memory`):** the two masters share the one port, one transaction at a time. The master that starts a command keeps the port until its `busy` drops (the bridge: its read data is back; the cache: the 4 words of the line are back), so `readdatavalid` always belongs to it. When both want it, the bridge goes first (its load/store is older than the fetch). The one waiting sees `waitrequest` = 1 and holds its command. The JTAG master (PLT-10) is arbitrated by Platform Designer inside `sdram_sys`.
- **Reset:** in `top_doom`, the PLL lock resets everything; KEY1 (debounced) resets only the CPU side (`life_system` and `ext_memory`), never the SDRAM controller: resetting the controller stops the refresh and the SDRAM loses the image and the WAD. After KEY1 the CPU is back in `boot.S`, waiting for KEY0. Load `doom.bin` again before KEY0: Doom has already changed its `.data` (the WAD can stay, Doom never writes it).
- **On the board (`top_doom`, Quartus revision `top_doom`, same pins and SDRAM timing as `sdram_test`):** program the `.sof`; in System Console `wad_load build/doom/doom.bin 0` (the image at `0x2000_0000`) and `wad_load <the WAD>` (default offset `0x0300_0000` = `0x2300_0000`); then KEY0. Compiled on Nov 22: 7,893 LE (16%), 129 of 182 M9K (mode B 64 KB + caches), 8 multipliers, setup slack 5.8 ns at 25 MHz.
- **Doom's software:** linker script `src/doom/link_sdram.ld` (everything from `0x2000_0000`), its own `crt0` (`$sp` = `0x1001_3FF0`, zero `.bss`, call `main`). `elf2hex.py` writes the image as one binary from `0x2000_0000` (for `wad_load.tcl`, offset 0) and as a `.hex` for the simulation.
- **Simulation:** `mips_sim_sdram` (Verilator, `verif/verilator`) is `life_system` + `ext_memory` on a behavioural SDRAM with the same Avalon interface (`avalon_sdram.sv`: `waitrequest` and read latency at random, pipelined reads in order), preloaded with an SDRAM image (`+sdram=`) and the WAD (`+wad=`, at offset `0x0300_0000`). It starts at `0x2000_0000`, so it skips the KEY0 wait (DOOM-6 runs Doom on it). `make -C verif/verilator compare-sdram PROG=<src/c program>` links a C test like Doom and compares its trace with `ref_sim.py --sdram`. `verif/doom_mem.do` (ModelSim) runs `src/programs/test_ext.s` on `ext_memory` with the real Intel controller and its memory model.

## Reference simulator trace (TC-6)
`src/tools/ref_sim.py` runs an assembler image (`<name>.hex` + `<name>_data.hex`) and prints one line per register write, in program order. The Verilator harness (TC-7) prints **the same format**, HI/LO lines included, so the two traces compare with a plain `diff` (TC-11).

```
PC=0x00000000 R8 <= 0x00000005
PC=0x00000010 HI <= 0x00000000
PC=0x00000010 LO <= 0x0000001E
HALT: jumps to itself at 0x00000034  (steps=15)
```

- `PC` is the address of the instruction that writes, `R<n>` the register in decimal, values in 8 uppercase hex digits. Writes to `$zero` are not printed (a `nop` prints nothing).
- `mult multu div divu` print `HI` then `LO`. `mthi` and `mtlo` print one line. `div`/`divu` by zero print nothing and leave HI/LO unchanged in `ref_sim.py`; the hardware writes a meaningless value there (`mult_div.v`), so a program that divides by zero and then reads HI/LO differs (the harness prints nothing for it either).
- `bltzal`/`bgezal` write `$ra` = PC + 8 even when not taken. `syscall`, `break` and unknown instructions write nothing, like the CPU.
- Same state as `mips_pipeline` after reset: PC = text base, `$sp = 0x7FFF_EFFC`, every other register 0 (MARS also sets `$gp = 0x1000_8000`; the CPU does not).
- Delay slot as in the pipeline: `jal`/`jalr` write PC + 8 and the instruction after a jump always runs.
- Invalid fetch, load or store: the same halt as the CPU (cause 1/2/3, see "Halt on invalid access") with the memory map above, printed as `HALT: cause 2 (load) pc 0x... addr 0x...`. The failing instruction writes nothing.
- The last line always starts with `HALT:` and says why the run ended. Drop it before comparing with the CPU trace.
- **Verilator harness (TC-7):** `verif/verilator/` runs the image on `life_system` and prints this format, with the same `HALT:` line for a self-jump or a CPU-14 halt (`steps` counts the same). `make -C verif/verilator compare PROG=<name>` diffs it against `ref_sim.py`. MMIO is real there (the timer counts), so programs that read the timer differ.

## Tool settings
- **MARS:** *Settings → Delayed branching* **off**; *Memory Configuration → Default*; Bitmap Display: unit 4×4, display 512 wide, base address `0x10040000 (heap)`.
- **Quartus (MAX 10):** configuration mode *"Single Uncompressed Image with Memory Initialization"* (required to initialize on-chip memory from the `.hex` images).
- **Instruction RAM:** enable *In-System Memory Content Editor* on the 4 banks to load programs without recompiling.
- **GCC:** `mips-linux-gnu-gcc` (package `gcc-mips-linux-gnu` in WSL) with `-march=mips1 -msoft-float -mno-abicalls -G0 -EB` (**big-endian**, TC-14). Startup code, linker script and ELF → `.hex`: `src/c/` (TC-9, see its README). Constants (`.rodata`) go to the data region: the instruction memory can't be read by loads.
- **`libgcc.a`:** the cross compiler's is MIPS32 with an FPU (its `__subsf3` is `sub.s`, its `__divdi3` uses `clz`), so it is not used: software floating point and 64-bit division are in our C library (`src/c/libc/softfloat.c`, `divdi3.c`). `elf2hex.py --isa` fails the build if any instruction outside our ISA gets in.
- **Doom build:** also `-mmemcpy` and `PACKEDATTR` defined empty in `doomtype.h`. Without them GCC emits 48 `lwl`/`lwr`/`swl`/`swr` for the packed WAD structures, which our CPU doesn't have; with them, none. The structures keep the same layout (every `sizeof` and offset checked: they only hold `short`/`int`/`char` at natural offsets).
- **Assembler:** text base `0x00000000` by default; `--text-base 0x00400000` only to compare with MARS dumps.
- **GNU as test programs (CPU-7, CPU-8):** `src/programs/*.s` with `.set noreorder` (every delay slot written by hand, like GCC output). `src/tools/gas_image.sh <file.s>` (WSL) assembles one with `mips-linux-gnu-as -EB -march=mips1` and writes the word image `mem/<name>.hex`. The real assembler is also an independent check of our encodings. Use `div $zero, rs, rt` (3 operands): the 2-operand `div` is a GNU as macro with a zero check.
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
