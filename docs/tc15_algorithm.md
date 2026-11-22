# TC-15: graded algorithm - frequency of a value

**What it does:** counts how many times a value (`target`) appears in an array of `n` words and stores the count.
Chosen from the options in the project statement (frequency of values). Not Fibonacci or factorial.

## Pseudocode
```
count = 0
i = 0
if n <= 0: go to done          # edge case: empty array
while i != n:
    x = array[i]               # lw
    if x == target:            # decision (beq)
        count = count + 1
    i = i + 1
done:
result = count                 # sw
loop forever                   # observable end point (self-jump)
```

## Data map (byte offset from 0x10010000)
| Offset | Name | Meaning |
|---|---|---|
| +0 | n | number of elements |
| +4 | target | value to count |
| +8 | result | the count, written by the program |
| +12 | array | n words |

## Register map
| Register | Use |
|---|---|
| $s0 | data base 0x10010000 |
| $t0 | n |
| $t1 | target |
| $t2 | pointer to the current element |
| $t3 | count |
| $t4 | i |
| $t5 | array[i] |
| $t6 | guard: 1 when 0 < n |

## Instructions used
`add`, `slt` (R) - `addi`, `lw`, `sw`, `beq` (I) - `j` (J): all from the 12 required.
Plus `lui` (extension, documented) only to build the data address 0x10010000.

## Three inputs
Programs in `sw/programs/`. "Observed" is our pipelined CPU (`life_system`, the same hardware as the board), from `hw/sim/tc15.do`; MARS gives the same values.

| # | File | n | target | array | Expected result | Observed (our CPU) |
|---|---|---|---|---|---|---|
| 1 | `count_value_in1.asm` | 8 | 3 | 3, -1, 3, 3, -1, 0, 3, 5 | 4 | **4** (self-jump after 118 cycles) |
| 2 | `count_value_in2.asm` | 4 | 7 | 7, 7, 7, 7 | 4 | **4** (self-jump after 66 cycles) |
| 3 | `count_value_in3.asm` (edge: empty array) | 0 | 5 | (none) | 0 | **0** (self-jump after 16 cycles) |

## How to reproduce
**Assemble** (from the repo root), for k = 1, 2, 3:
```
python sw/assembler/assembler.py sw/programs/count_value_in<k>.asm
```
This writes `hw/mem/count_value_in<k>_b0..b3.hex` (code) and `hw/mem/count_value_in<k>_data.hex` (`.data`: n, target, result, array).

**Simulation (ModelSim):** from `hw/sim`, `do tc15.do`. It runs the 3 inputs on `life_system` and checks the result word, that n and target are unchanged, the self-jump, and the count on the HEX debug view.

**Board:** Quartus revision `program` (`hw/rtl/top_program.v`). In `hw/quartus/program.qsf` set `set_parameter -name PROGRAM "count_value_in<k>"` (and `WITH_DATA 1`), compile, program the board. The program ends in `j end` with the result stored. To see it: SW9 up and SW4-0 = 01011 (register 11, `$t3` = count), HEX3-0 = the count. A CPU halt would show `E` on HEX5 and LEDR9 on.

**MARS:** open the file, Assemble (F3), Run, wait 2 seconds, Stop. In the Data Segment (`0x10010000 (.data)`), the third word (`+8`) is the result.
