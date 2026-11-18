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
