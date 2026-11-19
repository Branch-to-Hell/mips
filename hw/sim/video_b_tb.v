`timescale 1ns/1ps
// PLT-6 test: life_system with MODE_B = 1 running test_mode_b.hex. Run from hw/sim: do video_b.do
/* The CPU fills the screen and changes the palette (PLT-6 "done when"). Timer at
100 cycles per ms and debounce of 50 cycles, so the program's 20 ms wait is short.
The end of each palette update is when the CPU runs sw $s2, 0x1C($s0) (HEX = offset).
Checks:
  1. after the first palette update (SW0 = 1, cycling stopped): VIDEO_MODE = 1, LEDR0 = 1,
     all 64,000 pixels are (x + y) mod 256, all 256 palette entries are ramp(i)
  2. one full frame on the VGA pins matches palette[pixel] (black bars outside the
     640x400 image); saved in video_b.ppm, the image the board should show
  3. SW0 = 0: the offset moves on and every palette entry is ramp(i + offset)
     (HEX = offset); the pixels are not touched
  4. KEY0 press: VIDEO_MODE = 0, LEDR0 = 0, the VGA pins show mode A; another press: mode B
*/
module video_b_tb;
localparam [31:0] PAL_DONE_INSTR = 32'hAE12001C;   // sw $s2, 0x1C($s0)

reg clk = 0, reset = 1;
reg [9:0] SW = 10'b1;                  // SW0 = 1: cycling stopped
reg [1:0] KEY = 2'b11;                 // active-low, released
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
wire [3:0] VGA_R, VGA_G, VGA_B;
wire VGA_HS, VGA_VS;

life_system #(.IMEM_INIT("../mem/test_mode_b"), .DEBOUNCE_CYCLES(50),
              .CYCLES_PER_MS(100), .MODE_B(1)) sys (
    .clk(clk), .reset(reset), .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

always #20 clk = ~clk;                 // 25 MHz

`define VB sys.mode_b.video_b
integer errors = 0, updates = 0, i, x, y, n, bad, f, pixels;
reg [7:0] p;
reg [31:0] offset;

always @(posedge clk)
    if (!reset && sys.cpu.Instruction == PAL_DONE_INSTR) updates = updates + 1;

task fail(input [8*48-1:0] what);
    begin
        $display("FAIL %0s", what);
        errors = errors + 1;
    end
endtask

// ramp(k) as stored (top 4 bits): R = k, G = 2k mod 256, B = 255 - k
function [11:0] ramp(input [7:0] k);
    reg [7:0] g2, bl;
    begin
        g2 = k << 1;
        bl = 8'd255 - k;
        ramp = {k[7:4], g2[7:4], bl[7:4]};
    end
endfunction

function [7:0] pixel(input integer px, input integer py);
    integer o;
    begin
        o = py * 320 + px;
        case (o % 4)
            0: pixel = `VB.fb.bank0[o / 4];
            1: pixel = `VB.fb.bank1[o / 4];
            2: pixel = `VB.fb.bank2[o / 4];
            3: pixel = `VB.fb.bank3[o / 4];
        endcase
    end
endfunction

task wait_updates(input integer k);   // k more palette updates
    begin
        n = updates + k;
        while (updates < n) @(posedge clk);
        @(posedge clk);                // the sw to HEX happened on the negedge in between
    end
endtask

task check_palette(input [7:0] off, input [8*48-1:0] what);
    begin
        bad = 0;
        for (i = 0; i < 256; i = i + 1)
            if (`VB.pal.mem[i] !== ramp(i + off)) bad = bad + 1;
        if (bad != 0) begin
            $display("  %0d palette entries wrong for offset %0d", bad, off);
            fail(what);
        end
    end
endtask

task check_pixels(input [8*48-1:0] what);
    begin
        bad = 0;
        for (y = 0; y < 200; y = y + 1)
            for (x = 0; x < 320; x = x + 1)
                if (pixel(x, y) !== ((x + y) % 256)) bad = bad + 1;
        if (bad != 0) begin
            $display("  %0d pixels wrong", bad);
            fail(what);
        end
    end
endtask

// One frame from the VGA pins; the color leaves 2 cycles after the sync counters
reg [9:0] h1, v1, h2, v2;
always @(posedge clk) begin
    h1 <= `VB.h; v1 <= `VB.v;
    h2 <= h1;    v2 <= v1;
end

task check_frame;
    reg [11:0] expected;
    begin
        f = $fopen("video_b.ppm", "w");
        $fwrite(f, "P3\n640 480\n15\n");
        pixels = 0; bad = 0;
        wait (h2 == 799 && v2 == 524);
        @(posedge clk);
        forever begin
            #1;
            if (h2 < 640 && v2 >= 40 && v2 < 440)
                expected = ramp(pixel(h2 / 2, (v2 - 40) / 2));   // offset 0
            else
                expected = 12'h000;
            if ({VGA_R, VGA_G, VGA_B} !== expected) begin
                if (bad < 5) $display("  pixel h=%0d v=%0d: %h, expected %h", h2, v2, {VGA_R, VGA_G, VGA_B}, expected);
                bad = bad + 1;
            end
            if (h2 < 640 && v2 < 480) begin
                $fwrite(f, "%0d %0d %0d\n", VGA_R, VGA_G, VGA_B);
                pixels = pixels + 1;
            end
            if (h2 == 799 && v2 == 524) disable check_frame;
            @(posedge clk);
        end
    end
endtask

task press_key0;
    begin
        @(negedge clk) KEY[0] = 0;
        repeat (2000) @(posedge clk);  // longer than one pass of the program's wait loop
        @(negedge clk) KEY[0] = 1;
        repeat (2000) @(posedge clk);
    end
endtask

initial begin
    for (i = 0; i < 32; i = i + 1) sys.cpu.rf.registers[i] = 0;  // like the FPGA after power-up
    repeat (5) @(negedge clk);
    reset = 0;

    // 1. Screen filled and first palette written
    wait_updates(1);
    if (sys.io.video_mode_reg !== 1'b1) fail("1. VIDEO_MODE = 1");
    if (LEDR[0] !== 1'b1) fail("1. LEDR0 = 1");
    if (sys.io.hex_reg !== 24'd0) fail("1. HEX = offset 0");
    check_pixels("1. pixels (x + y) mod 256");
    check_palette(8'd0, "1. palette offset 0");
    $display("screen filled and palette written after %0d cycles", $time / 40);

    // 2. What the monitor shows (the program keeps rewriting the same palette, SW0 = 1)
    check_frame;
    $fclose(f);
    if (bad != 0) begin
        $display("  %0d pixels wrong on the VGA pins", bad);
        fail("2. VGA frame");
    end
    $display("%0d pixels checked on the VGA pins, video_b.ppm saved", pixels);
    if (sys.io.hex_reg !== 24'd0) fail("2. SW0 = 1 keeps offset 0");

    // 3. Palette cycling
    SW[0] = 0;
    wait_updates(3);
    offset = sys.io.hex_reg;
    if (offset == 0) fail("3. offset moves on");
    check_palette(offset[7:0], "3. palette = ramp(i + offset)");
    check_pixels("3. pixels unchanged");
    wait_updates(2);
    if (sys.io.hex_reg !== offset + 2) fail("3. offset +1 per update");
    check_palette(offset[7:0] + 8'd2, "3. palette after 2 more updates");
    $display("palette cycling: offset %0d -> %0d", offset, sys.io.hex_reg);

    // 4. KEY0 switches the mode
    press_key0;
    if (sys.io.video_mode_reg !== 1'b0) fail("4. KEY0 -> VIDEO_MODE = 0");
    if (LEDR[0] !== 1'b0) fail("4. LEDR0 = 0");
    bad = 0;
    for (i = 0; i < 20000; i = i + 1) begin
        @(posedge clk); #1;
        if ({VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS} !== {sys.a_r, sys.a_g, sys.a_b, sys.a_hs, sys.a_vs})
            bad = bad + 1;
    end
    if (bad != 0) fail("4. VGA pins show mode A");
    press_key0;
    if (sys.io.video_mode_reg !== 1'b1) fail("4. KEY0 again -> VIDEO_MODE = 1");
    bad = 0;
    for (i = 0; i < 20000; i = i + 1) begin
        @(posedge clk); #1;
        if ({VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS} !== {sys.b_r, sys.b_g, sys.b_b, sys.b_hs, sys.b_vs})
            bad = bad + 1;
    end
    if (bad != 0) fail("4. VGA pins show mode B");

    if (errors == 0) $display("PASS: video_b_tb, all checks");
    else $display("FAIL: video_b_tb, %0d checks failed", errors);
    $stop;
end

initial begin
    #200_000_000;                      // 200 ms: something is stuck
    $display("FAIL: timeout");
    $stop;
end

endmodule
