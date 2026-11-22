`timescale 1ns/1ns
// PLT-3 / LIFE-5 / LIFE-3 / LIFE-4 test: life_system running life_board.hex. Run from verif: do life.do
/* Reads the 32x24 board back from the framebuffer (every 4x4 block must be all white
or all black) and compares each generation with a Game of Life model written here.
Short debounce (50 cycles) so the key presses are fast. Checks:
  1. starts paused with a glider, LEDR0 off, HEX 0
  2. KEY1 runs: 8 generations match the model (the glider moves), LEDR0 on, HEX counts
  3. KEY1 again pauses: no new generations, board unchanged
  4. while running, KEY0 loads the pattern from SW5-4: empty, R-pentomino, random
  5. random board: 3 generations match the model (lots of wrap-around)
  6. edit mode (LIFE-3): paused on an empty board, SW9-5/SW4-0 move a red cursor,
     KEY0 toggles cells (a glider is drawn, one cell is toggled on and off again),
     the cursor leaves no trace, and the drawn glider evolves like the model
  LIFE-4: the live-cell bar on LEDR9-1 (one LED per 32 live cells, rounded up, at most 9)
     matches the board after loading, while paused, after each toggle and every generation
While paused the cursor is hidden with SW9-5 = 11000 (row 24) so read_board only sees
black and white cells.
The end of a generation is when addi $k0, $k0, 1 reaches EX (found by its
instruction), right after generation + draw.
Key presses last 200,000 cycles (8 ms), shorter than a real click (~100 ms):
the program must see them even while it computes a generation (~6 ms).
*/
module life_tb;
localparam DB = 50;                    // debounce cycles
localparam [31:0] GEN_DONE_INSTR = 32'h275A0001;  // addi $k0, $k0, 1 (professor's addi = opcode 0x09)
localparam PRESS = 200_000;            // cycles a key is held, and then released
localparam TIMEOUT = 1_000_000;        // cycles per generation, much more than needed

reg clk = 0, reset = 1;
reg [9:0] SW = 10'h300;                // row 24: no cursor
reg [1:0] KEY = 2'b11;                 // active-low, released
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
wire [3:0] VGA_R, VGA_G, VGA_B;
wire VGA_HS, VGA_VS;

life_system #(.IMEM_INIT("../mem/life_board"), .DEBOUNCE_CYCLES(DB)) sys (
    .clk(clk), .reset(reset), .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

always #20 clk = ~clk;                 // 25 MHz

integer i, r, c, dr, dc, n, g, errors = 0, alive;
integer gens = 0;                      // generations finished (PC reached wait_outer)
reg [31:0] done_addr;
reg board [0:767], prev [0:767], model [0:767];

always @(posedge clk)
    // Each instruction enters EX exactly once (stalls send bubbles), so this counts once per generation
    if (!reset && sys.cpu.ex_valid && sys.cpu.ex_pc == done_addr) gens = gens + 1;

task wait_cycles(input integer k);
    repeat (k) @(posedge clk);
endtask

task fail(input [8*48-1:0] what);
    begin
        $display("FAIL  %0s", what);
        errors = errors + 1;
    end
endtask

// One clean press and release (bounces are tested in mmio_tb)
task press(input integer k);
    begin
        KEY[k] = 0; wait_cycles(PRESS);
        KEY[k] = 1; wait_cycles(PRESS);
    end
endtask

// Read the board from the framebuffer; every pixel of a cell must agree
task read_board;
    integer p, x, y;
    reg [11:0] first;
    begin
        alive = 0;
        for (r = 0; r < 24; r = r + 1)
            for (c = 0; c < 32; c = c + 1) begin
                first = sys.video.fb.mem[(r * 4) * 128 + c * 4];
                if (first !== 12'h000 && first !== 12'hFFF) begin
                    $display("FAIL  cell (%0d,%0d) color %h", r, c, first);
                    errors = errors + 1;
                end
                for (y = 0; y < 4; y = y + 1)
                    for (x = 0; x < 4; x = x + 1) begin
                        p = (r * 4 + y) * 128 + c * 4 + x;
                        if (sys.video.fb.mem[p] !== first) begin
                            $display("FAIL  cell (%0d,%0d) pixel (%0d,%0d) differs", r, c, x, y);
                            errors = errors + 1;
                        end
                    end
                board[r * 32 + c] = (first === 12'hFFF);
                alive = alive + board[r * 32 + c];
            end
    end
endtask

// Next generation of prev into model: 4 rules, edges wrap around
task step_model;
    begin
        for (r = 0; r < 24; r = r + 1)
            for (c = 0; c < 32; c = c + 1) begin
                n = 0;
                for (dr = -1; dr <= 1; dr = dr + 1)
                    for (dc = -1; dc <= 1; dc = dc + 1)
                        if (dr != 0 || dc != 0)
                            n = n + prev[((r + dr + 24) % 24) * 32 + ((c + dc + 32) % 32)];
                model[r * 32 + c] = (n == 3) || (prev[r * 32 + c] && n == 2);
            end
    end
endtask

task save_prev;
    for (i = 0; i < 768; i = i + 1) prev[i] = board[i];
endtask

task check_same_as(input integer use_model, input [8*48-1:0] what);
    integer bad;
    begin
        bad = 0;
        for (i = 0; i < 768; i = i + 1)
            if (board[i] !== (use_model ? model[i] : prev[i])) bad = bad + 1;
        if (bad) begin
            $display("FAIL  %0s: %0d cell(s) differ", what, bad);
            errors = errors + 1;
        end else
            $display("ok    %0s (%0d alive)", what, alive);
    end
endtask

// Wait until the program finishes a generation (generation + draw), then read the board
task wait_generation(input integer k);
    integer start, t;
    begin
        start = gens;
        t = 0;
        while (gens == start && t < TIMEOUT) begin @(posedge clk); t = t + 1; end
        if (gens == start) begin
            $display("FAIL  generation %0d never finished", k);
            errors = errors + 1;
        end
        read_board;
    end
endtask

/* Run one generation and compare it with the model.
The board read at the end of the previous generation is the starting point:
reading it at any other moment could catch draw halfway through
*/
task check_generation(input integer k);
    integer prev_alive;
    begin
        save_prev;
        prev_alive = alive;
        wait_generation(k);
        // The main loop wrote LEDR after the previous generation's update_leds, before this one ran
        check_bar(prev_alive, "live-cell bar of the previous generation");
        step_model;
        check_same_as(1, "generation matches the model");
    end
endtask

// LIFE-4: LEDR9-1 = ceil(count / 32) LEDs from LEDR1 up, at most 9
function [8:0] bar(input integer count);
    integer lit;
    begin
        lit = (count + 31) / 32;
        if (lit > 9) lit = 9;
        bar = (9'h1 << lit) - 1;
    end
endfunction

task check_bar(input integer count, input [8*48-1:0] what);
    if (LEDR[9:1] !== bar(count)) begin
        $display("FAIL  %0s: LEDR9-1 = %b for %0d alive (expected %b)", what, LEDR[9:1], count, bar(count));
        errors = errors + 1;
    end
endtask

task check_cells(input integer count, input [8*48-1:0] what);
    if (alive != count) begin
        $display("FAIL  %0s: %0d alive (expected %0d)", what, alive, count);
        errors = errors + 1;
    end else
        $display("ok    %0s", what);
endtask

// Color of the top-left pixel of a cell (12 bits, RGB)
function [11:0] cell_color(input integer row, input integer col);
    cell_color = sys.video.fb.mem[(row * 4) * 128 + col * 4];
endfunction

/* Edit mode: move the cursor with the switches, press KEY0 and check the cell now
shows its new state (the program shows it for a full blink period, ~6M cycles).
When the cursor moves to a new cell it must show red right away; on the same cell
it is still showing the real color from the previous toggle
*/
task toggle_cell(input integer row, input integer col, input expect_alive);
    reg moved;
    begin
        moved = (SW !== {row[4:0], col[4:0]});
        SW = {row[4:0], col[4:0]};
        wait_cycles(2_000);
        if (moved && cell_color(row, col) !== 12'hF00) begin
            $display("FAIL  cursor at (%0d,%0d) is %h, expected red", row, col, cell_color(row, col));
            errors = errors + 1;
        end
        press(0);
        if (cell_color(row, col) !== (expect_alive ? 12'hFFF : 12'h000)) begin
            $display("FAIL  cell (%0d,%0d) after KEY0 is %h", row, col, cell_color(row, col));
            errors = errors + 1;
        end else
            $display("ok    cell (%0d,%0d) toggled %0s", row, col, expect_alive ? "on" : "off");
    end
endtask

initial begin
    for (i = 0; i < 32; i = i + 1) sys.cpu.rf.registers[i] = 0;  // like the FPGA after power-up
    done_addr = 32'hFFFF_FFFF;
    for (i = 0; i < 4096; i = i + 1)
        if (sys.cpu.if_id.im.read_word(i) === GEN_DONE_INSTR) done_addr = 32'h0000_0000 + 4 * i;
    if (done_addr == 32'hFFFF_FFFF) $fatal(1, "addi $k0, $k0, 1 not found in the program");
    $display("generation done at %h", done_addr);

    wait_cycles(2);
    @(negedge clk); reset = 0;

    // 1. Paused with a glider at rows 1-3, columns 1-3
    wait_cycles(60_000);
    read_board;
    check_cells(5, "glider loaded");
    if (!(board[1*32+2] && board[2*32+3] && board[3*32+1] && board[3*32+2] && board[3*32+3]))
        fail("glider cells");
    if (LEDR[0] !== 1'b0) fail("LEDR0 should be off while paused");
    wait_cycles(20_000);                // update_leds runs after draw (~10,000 cycles)
    check_bar(alive, "live-cell bar at start");
    if (sys.io.hex_reg !== 0) fail("HEX should be 0 at start");
    if (gens != 0) fail("ran a generation while paused");

    // 2. KEY1 runs; 8 generations (2 full glider cycles)
    SW = 10'h30F;                       // fastest, cursor hidden
    press(1);
    wait_generation(0);                 // start from a fully drawn board
    for (g = 1; g <= 8; g = g + 1) begin
        check_generation(g);
        check_cells(5, "glider still has 5 cells");
    end
    wait_cycles(400);
    if (LEDR[0] !== 1'b1) fail("LEDR0 should be on while running");
    if (sys.io.hex_reg < 8) fail("HEX should count the generations");
    else $display("ok    HEX = %0d after 8+ generations", sys.io.hex_reg);

    // 3. KEY1 pauses
    press(1);
    wait_cycles(10_000);
    read_board; save_prev;
    g = gens;
    wait_cycles(600_000);
    read_board;
    if (gens != g) fail("generations while paused");
    check_same_as(0, "paused: board unchanged");
    if (LEDR[0] !== 1'b0) fail("LEDR0 should be off after pausing");

    /* 4. While running, KEY0 loads the pattern from SW5-4.
    Speed 0: after a load the program waits ~5M cycles before the next generation,
    so the freshly loaded pattern can be read
    */
    press(1);                           // run
    SW = 10'h320;                       // 10 = empty, speed 0
    press(0);
    wait_cycles(60_000);
    read_board;
    check_cells(0, "empty pattern");
    check_bar(alive, "live-cell bar, empty pattern");
    if (sys.io.hex_reg !== 0) fail("HEX should go back to 0 after loading");

    SW = 10'h330;                       // 11 = R-pentomino
    press(0);
    wait_cycles(60_000);
    read_board;
    check_cells(5, "R-pentomino loaded");
    check_bar(alive, "live-cell bar, R-pentomino");
    if (!(board[10*32+15] && board[10*32+16] && board[11*32+14] && board[11*32+15] && board[12*32+15]))
        fail("R-pentomino cells");

    SW = 10'h310;                       // 01 = random
    press(0);
    wait_cycles(60_000);
    read_board;
    if (alive < 100 || alive > 300) fail("random pattern density");
    else $display("ok    random pattern (%0d alive, about 1 in 4)", alive);
    check_bar(alive, "live-cell bar, random pattern");
    if (LEDR[9:1] == 9'h1FF || LEDR[9:1] == 9'h001) fail("random pattern: the bar should be in between");
    else $display("ok    live-cell bar: LEDR9-1 = %b for %0d alive", LEDR[9:1], alive);

    // 5. A new random board at full speed matches the model
    SW = 10'h31F;                       // 01 = random, fastest
    press(0);
    wait_generation(0);
    for (g = 1; g <= 3; g = g + 1)
        check_generation(g);

    // 6. Edit mode (LIFE-3): empty board, pause, draw a glider with the cursor
    SW = 10'h32F;                       // 10 = empty, fastest
    press(0);
    SW = 10'h300;                       // cursor hidden
    press(1);                           // pause
    wait_cycles(10_000);
    read_board;
    check_cells(0, "edit mode: empty board");
    if (LEDR[0] !== 1'b0) fail("LEDR0 should be off in edit mode");
    g = gens;

    toggle_cell(0, 0, 1);               // on and off again: toggling works both ways
    check_bar(1, "live-cell bar follows a toggle on");
    toggle_cell(0, 0, 0);
    check_bar(0, "live-cell bar follows a toggle off");
    toggle_cell(5, 11, 1);              // glider:  .X. / ..X / XXX  at rows 5-7, columns 10-12
    toggle_cell(6, 12, 1);
    toggle_cell(7, 10, 1);
    toggle_cell(7, 11, 1);
    toggle_cell(7, 12, 1);
    toggle_cell(23, 31, 1);             // last cell: row 23 = SW9-5 10111, column 31 = SW4-0 11111
    toggle_cell(23, 31, 0);

    SW = 10'h300;                       // hide the cursor: its cell goes back to its real color
    wait_cycles(2_000);
    read_board;                         // also fails on any red pixel left behind
    check_cells(5, "edit mode: drawn glider");
    check_bar(alive, "live-cell bar after drawing");
    if (!(board[5*32+11] && board[6*32+12] && board[7*32+10] && board[7*32+11] && board[7*32+12]))
        fail("drawn glider cells");
    if (gens != g) fail("generations while editing");

    // The drawn glider evolves: the first generation comes right after KEY1
    SW = 10'h30F;                       // fastest, cursor hidden
    save_prev;
    KEY[1] = 0;                         // hold KEY1 while the first generation runs
    wait_generation(1);
    KEY[1] = 1;
    step_model;
    check_same_as(1, "drawn glider: generation 1 matches the model");
    for (g = 2; g <= 4; g = g + 1) begin
        check_generation(g);
        check_cells(5, "drawn glider still has 5 cells");
    end

    if (errors) $fatal(1, "LIFE-5/LIFE-3/LIFE-4: %0d error(s)", errors);
    $display("PASS: PLT-3/LIFE-5/LIFE-3/LIFE-4 Game of Life on life_system (15 generations checked, live-cell bar)");
    $finish;
end
endmodule
