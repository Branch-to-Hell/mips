# test_mode_b.asm - Video mode B test for PLT-6.
# Machine code: mem/test_mode_b.hex, from src/assembler/assembler.py:
#   python src/assembler/assembler.py src/programs/test_mode_b.asm -o mem
#   python src/tools/hex2banks.py mem/test_mode_b.hex   (CPU-12 bank images, until TC-13)
# Checked in verif/video_b_tb.v.
#
# Fills the 320x200 screen with diagonal bands: pixel (x, y) = palette index (x + y) mod 256,
# then rotates the palette every 20 ms (palette cycling): the bands move across the screen
# without redrawing a single pixel, so only the palette changes.
# Palette entry i = ramp((i + offset) mod 256), ramp(k) = R k, G 2k mod 256, B 255 - k
#
# Expected on the board:
#   - 640x400 image of moving diagonal color bands, black bars above and below
#   - SW0 = 1 stops the cycling (the image stays still)
#   - KEY0 switches between mode B and mode A (mode A is black: nothing is drawn there)
#   - HEX = palette offset (0 to FF), LEDR0 = 1 in mode B
.text
main:
    lui  $s0, 0xFFFF            # $s0 = 0xFFFF0000, MMIO base
    lui  $s1, 0x1005            # $s1 = 0x10050000, framebuffer B, pixel (0, 0)
    addi $s4, $zero, 1          # $s4 = video mode, starts in B
    sw   $s4, 0x24($s0)         # VIDEO_MODE = 1
    sw   $s4, 0x18($s0)         # LEDR0 = mode

# Fill the screen, 4 pixels per sw: the left one goes in bits 31..24 (big-endian)
    add  $t3, $s1, $zero        # $t3 = address of the next 4 pixels
    addi $t1, $zero, 0          # $t1 = y
fill_row:
    addi $t2, $zero, 0          # $t2 = x
fill_word:
    add  $t4, $t2, $t1          # index of pixel x = x + y
    andi $t6, $t4, 0xFF
    sll  $t6, $t6, 24           # pixel x     -> bits 31..24
    addi $t4, $t4, 1
    andi $t5, $t4, 0xFF
    sll  $t5, $t5, 16
    or   $t6, $t6, $t5          # pixel x + 1 -> bits 23..16
    addi $t4, $t4, 1
    andi $t5, $t4, 0xFF
    sll  $t5, $t5, 8
    or   $t6, $t6, $t5          # pixel x + 2 -> bits 15..8
    addi $t4, $t4, 1
    andi $t5, $t4, 0xFF
    or   $t6, $t6, $t5          # pixel x + 3 -> bits 7..0
    sw   $t6, 0($t3)
    addi $t3, $t3, 4
    addi $t2, $t2, 4
    slti $t7, $t2, 320
    bne  $t7, $zero, fill_word
    addi $t1, $t1, 1
    slti $t7, $t1, 200
    bne  $t7, $zero, fill_row

    addi $s2, $zero, 0          # $s2 = palette offset
    addi $s3, $zero, 0          # $s3 = KEY0 the last time it was read

# Write the 256 palette entries for this offset
frame:
    ori  $t3, $s1, 0xFC00       # $t3 = 0x1005FC00, palette entry 0
    addi $t1, $zero, 0          # $t1 = i
pal_entry:
    add  $t4, $t1, $s2
    andi $t4, $t4, 0xFF         # k = (i + offset) mod 256
    sll  $t5, $t4, 16           # R = k
    sll  $t6, $t4, 1
    andi $t6, $t6, 0xFF
    sll  $t6, $t6, 8
    or   $t5, $t5, $t6          # G = 2k mod 256
    addi $t6, $zero, 255
    sub  $t6, $t6, $t4
    or   $t5, $t5, $t6          # B = 255 - k
    sw   $t5, 0($t3)
    addi $t3, $t3, 4
    addi $t1, $t1, 1
    slti $t7, $t1, 256
    bne  $t7, $zero, pal_entry

    sw   $s2, 0x1C($s0)         # HEX = offset (the testbench counts these writes)

# Wait 20 ms; meanwhile each KEY0 press switches the video mode
    lw   $t0, 0x20($s0)         # $t0 = TIMER at the start
wait:
    lw   $t1, 0x14($s0)
    andi $t1, $t1, 1            # $t1 = KEY0 (1 = pressed)
    beq  $t1, $s3, no_press     # same as last time: nothing to do
    add  $s3, $t1, $zero
    beq  $t1, $zero, no_press   # it was released
    addi $t2, $zero, 1
    sub  $s4, $t2, $s4          # mode = 1 - mode
    sw   $s4, 0x24($s0)         # VIDEO_MODE
    sw   $s4, 0x18($s0)         # LEDR0
no_press:
    lw   $t1, 0x20($s0)
    sub  $t1, $t1, $t0          # ms since the start
    slti $t1, $t1, 20
    bne  $t1, $zero, wait

    lw   $t1, 0x10($s0)
    andi $t1, $t1, 1            # SW0 = 1: keep the same offset
    bne  $t1, $zero, frame
    addi $s2, $s2, 1
    andi $s2, $s2, 0xFF         # next offset
    j    frame
