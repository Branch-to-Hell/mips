# Pipelined MIPS on the DE10-Lite

A 5-stage pipelined MIPS processor in Verilog for the DE10-Lite (MAX 10), with our own assembler, Conway's Game of Life on VGA and, as the team goal, Doom.
Start with [`docs/project-plan.md`](docs/project-plan.md), then [`docs/workflow.md`](docs/workflow.md) and [`docs/contracts.md`](docs/contracts.md).

## Folders

The four folders the professor asks for:

| Folder | What it holds |
|---|---|
| [`rtl/`](rtl/) | All the Verilog: the CPU (`mips_pipeline.v` and its modules, the single-cycle `mips_cpu.v`), memories, MMIO, VGA and the board top-levels (`top_*.v`) |
| [`verif/`](verif/) | Testbenches (`*_tb.v`) and their ModelSim scripts (`*.do`). [`verif/traces/`](verif/traces/): the annotated R, I and J traces (TC-16). [`verif/results/`](verif/results/): expected vs observed results |
| [`docs/`](docs/) | Plan, workflow, technical contracts, test coverage (`tc16/`), the graded algorithm (`tc15_algorithm.md`), lab checklists and [`docs/evidence/`](docs/evidence/) (board photos and videos, individual sheets) |
| [`src/`](src/) | Everything that is not Verilog: [`src/assembler/`](src/assembler/) (our assembler), [`src/programs/`](src/programs/) (assembly programs), [`src/tools/`](src/tools/) (reference simulator, professor drill, converters), `src/doom/` |

Three extra folders that don't fit those four:

| Folder | What it holds |
|---|---|
| [`quartus/`](quartus/) | The Quartus project `mips.qpf`. One revision per board image: `top_life`, `program`, `mmio_test`, `video_test`, `video_b_test`, `sdram_test` (`.qsf` + `.sdc`) |
| [`mem/`](mem/) | Memory images written by the assembler (`<name>.hex`, `_bytes.hex`, `_b0`–`_b3.hex`, `_data.hex`), read by the testbenches and by Quartus |
| [`web/`](web/) | The report website (Astro Starlight, deployed on Vercel) |

`rtl/`, `verif/`, `quartus/` and `mem/` are side by side, so the testbenches and the `.qsf` files use relative paths (`../rtl/…`, `../mem/…`).

## Quick start

Assemble a program (writes `mem/<name>*.hex`), from the repo root:

```
python src/assembler/assembler.py src/programs/<name>.asm
```

Run a testbench, from `verif/` in ModelSim:

```
cd verif
vsim -c -do "do tc4.do; quit -f"
```

Build a board image: open `quartus/mips.qpf`, pick the revision and compile. For any program on the pipelined CPU use the `program` revision (see `quartus/program.qsf`).

Run an unseen MARS program on our CPU (assembler, MARS and ModelSim, compared): `python src/tools/drill.py <program.asm>` (see [`docs/tc12_drill.md`](docs/tc12_drill.md)).

More: [`src/assembler/README.md`](src/assembler/README.md) (assembler), [`docs/tc16/README.md`](docs/tc16/README.md) (how to reproduce every test).
