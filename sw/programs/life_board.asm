# life_board.asm - Conway's Game of Life on the DE10-Lite (LIFE-5, LIFE-3)
# Same game as life.asm (LIFE-1, LIFE-2); only the input and the delay change:
# life.asm reads MARS's keyboard simulator, this one reads our MMIO (docs/contracts.md).
#   - 32x24 board, each cell is a 4x4-pixel block on the 128x96 framebuffer (0x10040000)
#   - two buffers (current / next), the 4 rules, wrap-around edges
#   - Phase 1 instructions only
# The main loop reads the keys on every pass (~20 cycles) and counts passes to
# pace the generations and the cursor blink, so a quick click is never missed.
# Machine code: hw/mem/life_board.hex, runs on top_life (PLT-3):
#   python sw/assembler/assembler.py sw/programs/life_board.asm -o hw/mem
#
# Controls (KEY = 1 when pressed; the program reacts on the press edge):
#   KEY1    = run/pause (running starts with a generation right away)
#   Running:
#     KEY0  = load the pattern chosen with SW5-4:
#             00 glider, 01 random, 10 empty, 11 R-pentomino
#             (the new pattern stays on screen for one full wait before it evolves)
#     SW3-0 = speed, 0 slowest (~0.2 s per generation) to 15 fastest (~20 ms)
#   Paused = edit mode (LIFE-3):
#     SW4-0 = cursor column (0-31), SW9-5 = cursor row (0-23; 24-31 hide the cursor)
#     the cursor cell blinks between red and its real color (~0.25 s each)
#     KEY0  = toggle the cell under the cursor (alive <-> dead)
#   LEDR0   = on while running
#   LEDR9-1 = live-cell bar (LIFE-4): one LED per 16 live cells, rounded up, at most 9
#   HEX     = generation number (0 after loading a pattern)
# Starts paused with a glider. To draw from scratch: run, load "empty" (SW5-4 = 10),
# pause, draw with the switches and KEY0, then run.
.data
buf_a: .space 3072              # 32 x 24 words
buf_b: .space 3072

.text
main:
    lui  $s0, 0x1004            # s0 = framebuffer base 0x10040000
    lui  $s1, 0x1001            # s1 = current buffer (buf_a, 0x10010000)
    addi $s2, $s1, 3072         # s2 = next buffer (buf_b)
    lui  $s4, 0xffff            # s4 = 0xffff0000 (MMIO base: SW +0x10, KEY +0x14, LEDR +0x18, HEX +0x1C)
    lui  $s3, 0x00FF
    ori  $s3, $s3, 0xFFFF       # s3 = 0x00FFFFFF (white = alive)
    addi $s5, $zero, 0          # s5 = speed 0..15 (SW3-0)
    addi $s6, $zero, 1          # s6 = free-running counter (random seed)
    addi $s7, $zero, 0          # s7 = 0 paused, 1 running
    addi $fp, $zero, 0          # fp = KEY value in the previous pass (for the press edge)
    addi $k0, $zero, 0          # k0 = generation number
    addi $v1, $zero, 1          # v1 = passes left until the next generation
    addi $a0, $zero, 0          # a0 = pattern: 0 glider, 1 random, 2 empty, 3 R-pentomino
    addi $a1, $zero, -1         # a1 = cursor cell (row*32 + column), -1 = no cursor
    addi $a2, $zero, 1          # a2 = passes left until the cursor blinks
    addi $a3, $zero, 0          # a3 = blink phase: 1 = red, 0 = the cell's real color
    addi $gp, $zero, 0          # gp = live-cell bar for LEDR9-1 (LIFE-4), v0 = live cells
    jal  load_pattern
    jal  draw
    jal  update_leds

main_loop:
    addi $s6, $s6, 1
    or   $t3, $gp, $s7          # LEDR0 = running, LEDR9-1 = live-cell bar
    sw   $t3, 0x18($s4)         # LEDR
    sw   $k0, 0x1C($s4)         # HEX = generation
    lw   $t0, 0x10($s4)         # t0 = SW
    andi $s5, $t0, 15           # SW3-0 = speed
    lw   $t1, 0x14($s4)         # t1 = KEY (1 = pressed)
    nor  $t2, $fp, $zero
    and  $t2, $t1, $t2          # t2 = keys pressed since the previous pass
    addi $fp, $t1, 0
    andi $t3, $t2, 2            # KEY1: run/pause
    beq  $t3, $zero, cursor
    addi $t3, $zero, 1
    sub  $s7, $t3, $s7          # toggle run/pause
    addi $v1, $zero, 1          # running: first generation on the next pass
    addi $a3, $zero, 0
    jal  cursor_paint           # cursor cell back to its real color
    addi $a1, $zero, -1         # no cursor (if paused, the next lines place it again)

# ---- edit mode (paused): the switches move the cursor ----
cursor:
    bne  $s7, $zero, key0       # running: no cursor
    srl  $t4, $t0, 5            # t4 = row (SW9-5)
    andi $t5, $t0, 31           # t5 = column (SW4-0)
    addi $t7, $zero, -1         # t7 = new cursor cell
    slti $t6, $t4, 24
    beq  $t6, $zero, cur_moved  # rows 24-31 don't exist: no cursor
    sll  $t7, $t4, 5
    add  $t7, $t7, $t5
cur_moved:
    beq  $t7, $a1, key0         # same cell as before
    addi $a3, $zero, 0
    jal  cursor_paint           # old cell back to its real color
    addi $a1, $t7, 0
    addi $a2, $zero, 1          # show the cursor at the end of this pass

key0:
    andi $t3, $t2, 1            # KEY0: toggle (paused) or load a pattern (running)
    beq  $t3, $zero, tick
    beq  $s7, $zero, toggle
    srl  $a0, $t0, 4            # running: load the pattern from SW5-4
    andi $a0, $a0, 3
    addi $k0, $zero, 0
    jal  load_pattern
    jal  draw
    jal  update_leds            # live-cell bar for the new pattern
    j    wait                   # full wait before the new pattern evolves
toggle:
    slt  $t3, $a1, $zero
    bne  $t3, $zero, tick       # no cursor: nothing to toggle
    sll  $t3, $a1, 2
    add  $t3, $t3, $s1          # address of the cell in the current buffer
    lw   $t4, 0($t3)
    addi $t5, $zero, 1
    sub  $t4, $t5, $t4          # 0 <-> 1
    sw   $t4, 0($t3)
    jal  update_leds            # live-cell bar follows the toggle
    addi $a3, $zero, 0
    jal  cursor_paint           # show the new state right away...
    lui  $a2, 4                 # ...for a full blink period

tick:
    bne  $s7, $zero, run
    addi $a2, $a2, -1           # paused: count passes until the cursor blinks
    bne  $a2, $zero, main_loop
    lui  $a2, 4                 # 4 x 65,536 passes (~24 cycles each, ~0.25 s)
    addi $t3, $zero, 1
    sub  $a3, $t3, $a3          # toggle the blink phase
    jal  cursor_paint
    j    main_loop
run:
    addi $v1, $v1, -1           # running: count passes until the next generation
    bne  $v1, $zero, main_loop
    jal  generation
    jal  draw
    addi $k0, $k0, 1            # generation done (hw/sim/life_tb.v looks for this instruction)
    jal  update_leds            # live-cell bar for the new generation
wait:
    addi $t0, $zero, 16
    sub  $t0, $t0, $s5
    sll  $v1, $t0, 14           # wait (16 - speed) x 16,384 passes (~20 cycles each, ~13 ms)
    j    main_loop

# ---- generation: next generation from the current buffer, then swap buffers ----
generation:
    addi $t0, $zero, 0          # t0 = row r
gen_row:
    addi $t1, $zero, 0          # t1 = column c
gen_col:
    addi $t2, $zero, 0          # t2 = live neighbours
    addi $t3, $zero, -1         # t3 = dr
gen_dr:
    addi $t4, $zero, -1         # t4 = dc
gen_dc:
    or   $t5, $t3, $t4
    beq  $t5, $zero, gen_skip   # the cell itself
    add  $t5, $t0, $t3          # neighbour row
    addi $t6, $zero, -1
    bne  $t5, $t6, gen_r24
    addi $t5, $zero, 23         # row -1 wraps to 23
gen_r24:
    addi $t6, $zero, 24
    bne  $t5, $t6, gen_rok
    addi $t5, $zero, 0          # row 24 wraps to 0
gen_rok:
    add  $t6, $t1, $t4          # neighbour column
    andi $t6, $t6, 31           # wraps (32 columns)
    sll  $t5, $t5, 5
    add  $t5, $t5, $t6
    sll  $t5, $t5, 2
    add  $t5, $t5, $s1
    lw   $t6, 0($t5)            # 0 or 1
    add  $t2, $t2, $t6
gen_skip:
    addi $t4, $t4, 1
    addi $t5, $zero, 2
    bne  $t4, $t5, gen_dc
    addi $t3, $t3, 1
    bne  $t3, $t5, gen_dr

    sll  $t5, $t0, 5            # offset of this cell: (r*32 + c) * 4
    add  $t5, $t5, $t1
    sll  $t5, $t5, 2
    add  $t6, $t5, $s1
    lw   $t7, 0($t6)            # current state
    add  $t8, $t5, $s2          # address in the next buffer
    addi $t9, $zero, 3
    beq  $t2, $t9, gen_live     # 3 neighbours: alive
    beq  $t7, $zero, gen_dead   # dead without 3: stays dead
    addi $t9, $zero, 2
    beq  $t2, $t9, gen_live     # alive with 2: survives
gen_dead:
    sw   $zero, 0($t8)
    j    gen_next
gen_live:
    addi $t9, $zero, 1
    sw   $t9, 0($t8)
gen_next:
    addi $t1, $t1, 1
    addi $t5, $zero, 32
    bne  $t1, $t5, gen_col
    addi $t0, $t0, 1
    addi $t5, $zero, 24
    bne  $t0, $t5, gen_row

    addi $t0, $s1, 0            # swap current and next
    addi $s1, $s2, 0
    addi $s2, $t0, 0
    jr   $ra

# ---- draw: paint every cell as a 4x4 block on the framebuffer ----
draw:
    addi $k1, $ra, 0            # paint_cell overwrites $ra
    addi $t8, $zero, 0          # t8 = cell 0..767 (row*32 + column)
draw_loop:
    sll  $t2, $t8, 2
    add  $t2, $t2, $s1
    lw   $t3, 0($t2)            # 0 or 1
    addi $t9, $zero, 0          # dead: black
    beq  $t3, $zero, draw_paint
    addi $t9, $s3, 0            # alive: white
draw_paint:
    jal  paint_cell
    addi $t8, $t8, 1
    addi $t5, $zero, 768
    bne  $t8, $t5, draw_loop
    jr   $k1

# ---- cursor_paint: paint the cursor cell (a1) red if a3 = 1, else its real color ----
# Does nothing when there is no cursor (a1 = -1). Uses t4-t6, t8, t9.
cursor_paint:
    slt  $t6, $a1, $zero
    bne  $t6, $zero, cp_none
    sll  $t6, $a1, 2
    add  $t6, $t6, $s1
    lw   $t6, 0($t6)            # 0 or 1
    addi $t9, $zero, 0          # dead: black
    beq  $t6, $zero, cp_blink
    addi $t9, $s3, 0            # alive: white
cp_blink:
    beq  $a3, $zero, cp_paint
    lui  $t9, 0x00FF            # cursor: red 0x00FF0000
cp_paint:
    addi $t8, $a1, 0
    j    paint_cell             # paint_cell returns straight to our caller
cp_none:
    jr   $ra

# ---- paint_cell: fill cell t8 (row*32 + column) with color t9. Uses t4, t5 ----
paint_cell:
    srl  $t4, $t8, 5
    sll  $t4, $t4, 11           # row * 2048 (4 pixel rows of 512 bytes)
    andi $t5, $t8, 31
    sll  $t5, $t5, 4            # column * 16 (4 pixels of 4 bytes)
    add  $t4, $t4, $t5
    add  $t4, $t4, $s0
    sw   $t9, 0($t4)
    sw   $t9, 4($t4)
    sw   $t9, 8($t4)
    sw   $t9, 12($t4)
    sw   $t9, 512($t4)
    sw   $t9, 516($t4)
    sw   $t9, 520($t4)
    sw   $t9, 524($t4)
    sw   $t9, 1024($t4)
    sw   $t9, 1028($t4)
    sw   $t9, 1032($t4)
    sw   $t9, 1036($t4)
    sw   $t9, 1536($t4)
    sw   $t9, 1540($t4)
    sw   $t9, 1544($t4)
    sw   $t9, 1548($t4)
    jr   $ra

# ---- update_leds: count the live cells (v0) and build the bar for LEDR9-1 (gp) ----
# One LED per 16 live cells, rounded up, at most 9. LEDR0 stays "running".
# The main loop writes LEDR = gp | running. Uses t0-t2.
update_leds:
    addi $v0, $zero, 0          # v0 = live cells
    addi $t0, $zero, 0          # t0 = cell 0..767
ul_count:
    sll  $t1, $t0, 2
    add  $t1, $t1, $s1
    lw   $t1, 0($t1)            # 0 or 1
    add  $v0, $v0, $t1
    addi $t0, $t0, 1
    addi $t2, $zero, 768
    bne  $t0, $t2, ul_count
    addi $t0, $v0, 15
    srl  $t0, $t0, 4            # LEDs lit = ceil(live / 16)
    slti $t1, $t0, 10
    bne  $t1, $zero, ul_cap_ok
    addi $t0, $zero, 9          # at most 9 LEDs (LEDR9-1)
ul_cap_ok:
    addi $gp, $zero, 0          # gp = bar: bits 1..lit set
ul_bar:
    beq  $t0, $zero, ul_done
    sll  $gp, $gp, 1
    ori  $gp, $gp, 2
    addi $t0, $t0, -1
    j    ul_bar
ul_done:
    jr   $ra

# ---- load_pattern: clear both buffers, then fill the current one (a0 = pattern) ----
load_pattern:
    addi $t0, $zero, 0
    addi $t1, $zero, 768
lp_clear:
    sll  $t2, $t0, 2
    add  $t3, $t2, $s1
    sw   $zero, 0($t3)
    add  $t3, $t2, $s2
    sw   $zero, 0($t3)
    addi $t0, $t0, 1
    bne  $t0, $t1, lp_clear
    beq  $a0, $zero, lp_glider
    addi $t0, $zero, 1
    beq  $a0, $t0, lp_random
    addi $t0, $zero, 3
    beq  $a0, $t0, lp_rpent
    jr   $ra                    # 2 = empty board
lp_glider:
    addi $t0, $zero, 1
    sw   $t0, 136($s1)          # row 1, col 2
    sw   $t0, 268($s1)          # row 2, col 3
    sw   $t0, 388($s1)          # row 3, col 1
    sw   $t0, 392($s1)          # row 3, col 2
    sw   $t0, 396($s1)          # row 3, col 3
    jr   $ra
lp_rpent:                       # R-pentomino in the centre:  .XX / XX. / .X.
    addi $t0, $zero, 1          # (a Gosper gun is 36 columns wide and doesn't fit in 32)
    sw   $t0, 1340($s1)         # row 10, col 15
    sw   $t0, 1344($s1)         # row 10, col 16
    sw   $t0, 1464($s1)         # row 11, col 14
    sw   $t0, 1468($s1)         # row 11, col 15
    sw   $t0, 1596($s1)         # row 12, col 15
    jr   $ra
lp_random:
    andi $t4, $s6, 0xFFFF       # seed from the polling counter, kept below 2^16
    addi $t0, $zero, 0
    addi $t1, $zero, 768
    addi $t5, $zero, 1
lp_rand_loop:
    sll  $t2, $t4, 10
    add  $t4, $t4, $t2
    addi $t4, $t4, 12345        # x = x * 1025 + 12345 (x < 2^16, so add can't overflow)
    andi $t4, $t4, 0xFFFF       # x = x mod 2^16
    srl  $t2, $t4, 14           # top 2 bits of x
    andi $t2, $t2, 3
    bne  $t2, $zero, lp_rand_next   # about 1 cell in 4 is alive
    sll  $t3, $t0, 2
    add  $t3, $t3, $s1
    sw   $t5, 0($t3)
lp_rand_next:
    addi $t0, $t0, 1
    bne  $t0, $t1, lp_rand_loop
    jr   $ra
