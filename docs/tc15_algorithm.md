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
| # | File | n | target | array | Expected result | Observed |
|---|---|---|---|---|---|---|
| 1 | count_value_in1.asm | 8 | 3 | 3, -1, 3, 3, -1, 0, 3, 5 | 4 | **4** (MARS, Value +8 = 0x00000004) |
| 2 | count_value_in2.asm | 4 | 7 | 7, 7, 7, 7 | 4 | **4** (MARS, Value +8 = 0x00000004) |
| 3 | count_value_in3.asm (edge: empty array) | 0 | 5 | (none) | 0 | **0** (MARS, Value +8 = 0x00000000) |

## How to reproduce (MARS)
1. Open the file, Assemble (F3), Run, wait 2 seconds, Stop.
2. In the Data Segment open `0x10010000 (.data)`: the third word (`+8`) is the result.
