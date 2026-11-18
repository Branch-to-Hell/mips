# life.asm - Conway's Game of Life for MARS (LIFE-1, LIFE-2)
# Follows docs/contracts.md and docs/project-plan.md:
#   - 32x24 board, each cell is a 4x4-pixel block on the 128x96 framebuffer (0x10040000)
#   - two buffers (current / next), the 4 rules, wrap-around edges
#   - Phase 1 instructions only; Delayed branching OFF (the assembler adds the nops)
# MARS setup: Bitmap Display unit 4x4, width 512, height 384, base 0x10040000 (heap);
#             Keyboard and Display MMIO Simulator connected.
# Keys (they stand in for the board's switches/keys until the real MMIO is wired):
#   SPACE = KEY1 run/pause     r = KEY0 reset (reload the current pattern)
#   1..8  = speed (8 fastest)  s = one step (only while paused)
#   g = glider   n = random   e = empty      (pattern select)
# Starts paused with a glider.
.data
buf_a: .space 3072              # 32 x 24 words
buf_b: .space 3072

.text
main:
    lui  $s0, 0x1004            # s0 = framebuffer base 0x10040000
    lui  $s1, 0x1001            # s1 = current buffer (buf_a, 0x10010000)
    addi $s2, $s1, 3072         # s2 = next buffer (buf_b)
    lui  $s4, 0xffff            # s4 = 0xffff0000 (MARS keyboard MMIO)
    lui  $s3, 0x00FF
    ori  $s3, $s3, 0xFFFF       # s3 = 0x00FFFFFF (white = alive)
    addi $s5, $zero, 5          # s5 = speed 1..8
    addi $s6, $zero, 1          # s6 = free-running counter (random seed)
    addi $s7, $zero, 0          # s7 = 0 paused, 1 running
    addi $a0, $zero, 0          # a0 = pattern: 0 glider, 1 random, 2 empty
    jal  load_pattern
    jal  draw

main_loop:
    addi $s6, $s6, 1
    lw   $t0, 0($s4)            # keyboard control register
    andi $t0, $t0, 1            # bit 0 = a key is waiting
    beq  $t0, $zero, tick
    lw   $t1, 4($s4)            # key code (reading it clears the flag)
    addi $t2, $zero, 0x20       # SPACE
    bne  $t1, $t2, key_r
    addi $t2, $zero, 1
    sub  $s7, $t2, $s7          # toggle run/pause
    j    tick
key_r:
    addi $t2, $zero, 0x72       # 'r'
    bne  $t1, $t2, key_g
    jal  load_pattern
    jal  draw
    j    tick
key_g:
    addi $t2, $zero, 0x67       # 'g'
    bne  $t1, $t2, key_n
    addi $a0, $zero, 0
    jal  load_pattern
    jal  draw
    j    tick
key_n:
    addi $t2, $zero, 0x6e       # 'n'
    bne  $t1, $t2, key_e
    addi $a0, $zero, 1
    jal  load_pattern
    jal  draw
    j    tick
key_e:
    addi $t2, $zero, 0x65       # 'e'
    bne  $t1, $t2, key_s
    addi $a0, $zero, 2
    jal  load_pattern
    jal  draw
    j    tick
key_s:
    addi $t2, $zero, 0x73       # 's'
    bne  $t1, $t2, key_speed
    bne  $s7, $zero, tick       # single step only while paused
    jal  generation
    jal  draw
    j    tick
key_speed:
    addi $t3, $t1, -48          # '1'..'8' -> 1..8
    slti $t4, $t3, 1
    bne  $t4, $zero, tick
    slti $t4, $t3, 9
    beq  $t4, $zero, tick
    addi $s5, $t3, 0
tick:
    beq  $s7, $zero, main_loop  # paused: keep polling
    jal  generation
    jal  draw
    addi $t0, $zero, 9
    sub  $t0, $t0, $s5          # wait (9 - speed) rounds
wait_outer:
    addi $t1, $zero, 2000
wait_inner:
    addi $t1, $t1, -1
    bne  $t1, $zero, wait_inner
    addi $t0, $t0, -1
    bne  $t0, $zero, wait_outer
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
    addi $t0, $zero, 0          # row
draw_row:
    addi $t1, $zero, 0          # column
draw_col:
    sll  $t2, $t0, 5
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    add  $t2, $t2, $s1
    lw   $t3, 0($t2)            # 0 or 1
    beq  $t3, $zero, draw_blk
    addi $t3, $s3, 0            # alive: white
draw_blk:
    sll  $t4, $t0, 11           # row * 2048 (4 pixel rows of 512 bytes)
    sll  $t5, $t1, 4            # column * 16 (4 pixels of 4 bytes)
    add  $t4, $t4, $t5
    add  $t4, $t4, $s0
    sw   $t3, 0($t4)
    sw   $t3, 4($t4)
    sw   $t3, 8($t4)
    sw   $t3, 12($t4)
    sw   $t3, 512($t4)
    sw   $t3, 516($t4)
    sw   $t3, 520($t4)
    sw   $t3, 524($t4)
    sw   $t3, 1024($t4)
    sw   $t3, 1028($t4)
    sw   $t3, 1032($t4)
    sw   $t3, 1036($t4)
    sw   $t3, 1536($t4)
    sw   $t3, 1540($t4)
    sw   $t3, 1544($t4)
    sw   $t3, 1548($t4)
    addi $t1, $t1, 1
    addi $t5, $zero, 32
    bne  $t1, $t5, draw_col
    addi $t0, $t0, 1
    addi $t5, $zero, 24
    bne  $t0, $t5, draw_row
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
    jr   $ra                    # 2 = empty board
lp_glider:
    addi $t0, $zero, 1
    sw   $t0, 136($s1)          # row 1, col 2
    sw   $t0, 268($s1)          # row 2, col 3
    sw   $t0, 388($s1)          # row 3, col 1
    sw   $t0, 392($s1)          # row 3, col 2
    sw   $t0, 396($s1)          # row 3, col 3
    jr   $ra
lp_random:
    addi $t4, $s6, 12345        # seed from the polling counter
    addi $t0, $zero, 0
    addi $t1, $zero, 768
    addi $t5, $zero, 1
lp_rand_loop:
    sll  $t2, $t4, 10
    add  $t4, $t4, $t2
    addi $t4, $t4, 12345        # x = x * 1025 + 12345
    srl  $t2, $t4, 16
    andi $t2, $t2, 3
    bne  $t2, $zero, lp_rand_next   # about 1 cell in 4 is alive
    sll  $t3, $t0, 2
    add  $t3, $t3, $s1
    sw   $t5, 0($t3)
lp_rand_next:
    addi $t0, $t0, 1
    bne  $t0, $t1, lp_rand_loop
    jr   $ra
