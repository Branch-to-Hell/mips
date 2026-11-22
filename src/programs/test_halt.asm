# test_halt.asm - life_system address decoder and visible halt (CPU-14, LIFE-6)
# Checked in verif/halt_tb.v (do halt.do).
# 1. Touches the first and last word of every region of the memory map (data, framebuffer
#    mode A, stack, MMIO): none of them may halt the CPU.
# 2. LEDR = 0x155: every valid access went through.
# 3. sw to 0x7FFFF000, the word just above the stack: the CPU halts (cause 3 = sw),
#    the word is not written and nothing younger runs.
# Expected on the board: LEDR9 and LEDR1-0 = 1 1 (cause 3), HEX = E3F000; SW8 up = PC of the sw.
.text
main:
    lui  $s6, 0xFFFF            # s6 = 0xFFFF0000 (MMIO base)

    lui  $t0, 0x1001            # data: 0x10010000 - 0x10013FFC
    sw   $zero, 0($t0)
    ori  $t1, $t0, 0x3FFC
    sw   $zero, 0($t1)

    lui  $t0, 0x1004            # framebuffer mode A: 0x10040000 - 0x1004BFFC
    lw   $t2, 0($t0)
    ori  $t1, $t0, 0xBFFC
    lw   $t2, 0($t1)

    lui  $t0, 0x7FFF            # stack: 0x7FFFE000 - 0x7FFFEFFC
    ori  $t1, $t0, 0xE000
    lw   $t2, 0($t1)
    ori  $t1, $t0, 0xEFFC
    lw   $t2, 0($t1)

    lw   $t2, 0x10($s6)         # MMIO: first register (SW) and last one (VIDEO_MODE)
    lw   $t2, 0x24($s6)

    addi $t0, $zero, 0x155
    sw   $t0, 0x18($s6)         # LEDR = 0x155

    lui  $t0, 0x7FFF
    ori  $t0, $t0, 0xF000       # 0x7FFFF000: no region
    addi $t3, $zero, 0x444
    sw   $t3, 0($t0)            # halts here: cause 3
    addi $t4, $zero, 1          # never runs ($t4 stays 0)
stop:
    j    stop
