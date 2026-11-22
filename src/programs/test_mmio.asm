# test_mmio.asm - MMIO test for PLT-2 (switches, keys, LEDs, HEX).
# Machine code: mem/test_mmio.hex, from src/assembler/assembler.py:
#   python src/assembler/assembler.py src/programs/test_mmio.asm -o mem
# Checked in verif/mmio_tb.v and on the board with top_mmio_test.
#
# With CPU-3 the program loops with j. Before CPU-3, j does nothing: the rest of
# the instruction memory is 0 (nop) and the PC wraps around the 16 KB text region,
# so the code runs again every 4,096 cycles anyway. Both work on the board.
# $s1 and $s2 start at 0 (registers are 0 after power-up).
#
# Expected on the board:
#   - LEDR mirrors SW
#   - HEX counts KEY0 presses: one click = +1 (needs the debounce)
.text
main:
    lui  $s0, 0xFFFF            # $s0 = 0xFFFF0000, MMIO base
loop:
    lw   $t0, 0x10($s0)         # $t0 = SW
    sw   $t0, 0x18($s0)         # LEDR = SW
    lw   $t1, 0x14($s0)         # $t1 = KEY (1 = pressed)
    andi $t1, $t1, 1            # keep KEY0
    nor  $t2, $s1, $zero        # $t2 = ~previous KEY0
    and  $t2, $t1, $t2          # $t2 = 1 only on the press edge
    add  $s2, $s2, $t2          # count += edge
    or   $s1, $t1, $zero        # previous = KEY0
    sw   $s2, 0x1C($s0)         # HEX = count
    j    loop
