# CPU-2: I-Type Instructions

**Author:** Victor | **Issue:** #5

I extended the existing R-type single-cycle MIPS CPU to support `addi`, `andi`, `ori`, `slti`, `lui`, `lw`, and `sw`. I updated the control unit and ALU control, added the `lui` operation, and connected the destination-register, ALU-operand, and write-back selectors. Immediate values use zero extension for `andi` and `ori`, and sign extension for arithmetic and memory offsets.

I added a 16 KB data memory at `0x10010000`–`0x10013FFF` with address/alignment checks. Ariel subsequently adapted the design for FPGA integration: instruction memory reads synchronously on `posedge` using the next PC, and data memory reads and writes synchronously on `negedge`, allowing inference of M9K memory blocks. The single-cycle register file remains implemented in logic and writes on the following `posedge`, after load data is available.

Data memory is now outside `mips_cpu`. The CPU exposes `mem_addr`, `mem_wdata`, `mem_we`, `mem_re`, and `mem_rdata` for top-level integration. A dedicated adder computes `mem_addr = DR1 + ExtendedImm`. Register and memory writes are disabled during reset. The PC still advances by four; branches, jumps, and pipelining are outside this task. The bus and timing are documented in [contracts.md](../contracts.md).

## Quartus RTL diagram

[Download the CPU-2 RTL diagram (ZIP containing the PDF)](images/cpu2_rtl.zip)

The schematic shows the PC and instruction memory, control decoding, register file, ALU, and three selectors: `WriteReg` chooses `rt` or `rd`, `ALU_B` chooses a register or immediate, and `WriteData` chooses the ALU result or `mem_rdata`. Opcode comparators select zero extension for `andi` and `ori`. The separate `Add0` adder computes `mem_addr`; `DR2` supplies `mem_wdata`. Data memory is external, so the diagram exposes its bus rather than a RAM block.

**Export discrepancy:** The PDF labels the reset input of the `PC_fetch` selector as `32'h200`. The current Verilog and contract specify `32'h00400000`; verify the Quartus sources and regenerate the export before treating it as the final schematic.
