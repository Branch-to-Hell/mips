# CPU-3: single-cycle branches and jumps

## Scope and behavior

Implements issue #6: `beq`, `bne`, `j`, `jal`, and `jr` on the current
single-cycle CPU. As with MARS with delayed branching disabled and the current
TC-4 tests, transfers take effect immediately: there is **no delay slot**.
`jal` writes `PC + 4` to register 31 (`$ra`).

This is the S1 implementation, not the final pipeline behavior. CPU-6 owns
branch/jump resolution in ID with one delay slot; that change must also update
`jal` to link to `PC + 8` and update the corresponding tests. The pipeline
agreement in `docs/contracts.md` remains unchanged.

| Instruction | Next PC | Register write |
|---|---|---|
| `beq rs, rt, offset` | `PC + 4 + (sign_extend(offset) << 2)` when equal; otherwise `PC + 4` | None |
| `bne rs, rt, offset` | Same target when unequal; otherwise `PC + 4` | None |
| `j target` | `{(PC + 4)[31:28], target[25:0], 2'b00}` | None |
| `jal target` | Same as `j` | `$ra = PC + 4` |
| `jr rs` | Value of register `rs` | None |

The branch comparison uses the ALU's subtraction/Zero result. The control
unit decodes `funct` to prevent `jr` from enabling an arithmetic register write.
The PC and synchronous instruction memory receive the same selected address,
so the instruction fetched at the edge matches the new PC. Reset still takes
priority and suppresses register and memory writes. Memory bus ports and CPU-2
load/store timing are unchanged.

## Run on macOS

Requires Python 3 and Icarus Verilog (`iverilog` and `vvp` on PATH).
From the repository root:

```sh
python3 hw/sim/run_cpu3.py
```

The runner uses a temporary directory for compiled simulations and generated
HEX/MIF files, and removes it afterwards. It uses the team's assembler and
existing `tc4_branches.asm` / `tc4_jumps.asm` programs without modifications.
No FPGA vendor simulation libraries are needed.

## Verification performed

Passed on macOS with Icarus Verilog 13.0:

- Existing CPU-1 R-type regression.
- Existing CPU-2 immediate and memory regression.
- 15 directed CPU-3 transfers: taken/not-taken branches, negative operands,
  backward/zero/extreme offsets, J-format upper address bits including a
  `PC + 4` boundary crossing, `jal` link value, `jr $ra`, and `jr` through
  another register. Every transfer checks synchronous fetch alignment and
  absence of unintended register or memory writes.
- Reset during `jal`: reset PC/fetch wins and `$ra` is not overwritten.
- TC-4 branch program: LEDR `0x3FF` and HEX `0x00600D`.
- TC-4 jump program: same pass protocol, including nested function calls.

The directed fixture intentionally seeds PC/register state to isolate boundary
cases, including addresses outside physical instruction RAM. The TC-4 tests
instead execute complete assembled programs from reset. They model the output
register writes to validate the programs; they do not validate physical MMIO.

Short HEX images can produce a `$readmemh` warning about fewer than 4096 words.
This is expected: the programs occupy only part of instruction RAM. The new
program testbench initializes the remaining words to zero.

ModelSim and physical FPGA verification were not performed. The user requested
macOS verification instead of ModelSim for this work. These results do not
establish FPGA timing closure or replace the team's PR review.

## Review notes

AI assisted with the control/datapath changes, testbenches, runner, and this
note. Verification used the simulations above. A PR for this change should
reference `Closes #6` and include the runner output as evidence.
