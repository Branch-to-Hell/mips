# test_timer.asm - Timer MMIO test for PLT-5.
# Machine code: hw/mem/test_timer.hex, from sw/assembler/assembler.py:
#   python sw/assembler/assembler.py sw/programs/test_timer.asm -o hw/mem
# Checked in hw/sim/timer_tb.v.
#
# Expected on the board:
#   - HEX = milliseconds since reset, in hexadecimal (0x3E8 = 1 second)
#   - LEDR = TIMER / 1024, about one count per second
.text
main:
    lui  $s0, 0xFFFF            # $s0 = 0xFFFF0000, MMIO base
    sw   $zero, 0x20($s0)       # TIMER is read-only: this write must be ignored
loop:
    lw   $t0, 0x20($s0)         # $t0 = TIMER (ms since reset)
    sw   $t0, 0x1C($s0)         # HEX = ms
    srl  $t1, $t0, 10           # $t1 = ms / 1024, about seconds
    sw   $t1, 0x18($s0)         # LEDR = seconds
    j    loop
