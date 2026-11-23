`timescale 1ns/1ns
// TC-9: the first C program (src/c/hello_pixels.c, built with GCC) on life_system with
// mips_pipeline, the same hardware as the board. Run from verif: do tc9.do
/* The program comes from GCC + src/c/crt0.S + src/c/link.ld + src/tools/elf2hex.py:
   make -C src/c (in WSL). Checks:
  1. it reaches crt0's self-jump (main returned) without a CPU halt
  2. every pixel of framebuffer A is the gradient main() paints: stripes of 8 rows in
     red, green, blue, white (the .rodata table in the data image), shade = 2x per column
  3. .bss was zeroed by crt0 (main checks it) and main's increment is in memory: frames = 1
  4. the pass protocol on the board: LEDR = 0x3FF and HEX = 0x00600D
Saves verif/tc9.ppm (128x96, the framebuffer as the monitor shows it, scaled down 5x).
Verilator (TC-7) runs the same image: make -C verif/verilator compare PROG=hello_pixels
*/
module tc9_tb;
parameter PROGRAM = "hello_pixels";
localparam [31:0] END_PC = 32'h0000_0040;  // crt0.S: "3: j 3b" after jal main
localparam [31:0] FRAMES_WORD = 4;         // frames (.bss) at 0x1001_0010, see build/c/hello_pixels.map
localparam TIMEOUT = 1_000_000;            // cycles; the program takes ~87k instructions

reg clk = 0, reset = 1;
reg [9:0] SW = 0;
reg [1:0] KEY = 2'b11;
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
wire [3:0] VGA_R, VGA_G, VGA_B;
wire VGA_HS, VGA_VS;

life_system #(.IMEM_INIT({"../mem/", PROGRAM}), .DMEM_INIT({"../mem/", PROGRAM, "_data"}),
              .DEBOUNCE_CYCLES(50)) sys (
    .clk(clk), .reset(reset), .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

always #20 clk = ~clk;                     // 25 MHz

wire [31:0] id_pc = sys.cpu.id_pc, id_instr = sys.cpu.id_instruction;
wire at_end = sys.cpu.id_valid && id_pc == END_PC && id_instr[31:26] == 6'h02 &&
              {id_pc[31:28], id_instr[25:0], 2'b00} == id_pc;

// What main() writes at pixel (x, y), as the framebuffer stores it (top 4 bits per color)
function [11:0] expected_pixel(input integer x, input integer y);
    reg [31:0] band, shade, value;
    begin
        case ((y >> 3) & 3)
            0: band = 32'h00FF0000;
            1: band = 32'h0000FF00;
            2: band = 32'h000000FF;
            default: band = 32'h00FFFFFF;
        endcase
        shade = x << 1;
        value = band & (shade << 16 | shade << 8 | shade);
        expected_pixel = {value[23:20], value[15:12], value[7:4]};
    end
endfunction

integer errors = 0, n, x, y, f;
reg [11:0] got;

initial begin
    for (n = 0; n < 32; n = n + 1) sys.cpu.rf.registers[n] = 0;  // like the FPGA after power-up
    repeat (4) @(posedge clk);
    @(negedge clk) reset = 0;

    // 1. Run until main returns
    n = 0;
    while (!at_end && !sys.halted && n < TIMEOUT) begin @(posedge clk); n = n + 1; end
    if (sys.halted)
        $fatal(1, "%0s: CPU halted, cause %0d at PC %h, address %h",
               PROGRAM, sys.halt_cause, sys.halt_pc, sys.halt_addr);
    if (!at_end) $fatal(1, "%0s: main never returned (timeout)", PROGRAM);
    repeat (5) @(posedge clk);

    // 2. Every pixel, and the image for a quick look
    f = $fopen("tc9.ppm", "w");
    $fwrite(f, "P3\n128 96\n15\n");
    for (y = 0; y < 96; y = y + 1)
        for (x = 0; x < 128; x = x + 1) begin
            got = sys.video.fb.mem[y * 128 + x];
            $fwrite(f, "%0d %0d %0d\n", got[11:8], got[7:4], got[3:0]);
            if (got !== expected_pixel(x, y)) begin
                if (errors < 10)
                    $display("FAIL  pixel (%0d, %0d) = %h, expected %h", x, y, got, expected_pixel(x, y));
                errors = errors + 1;
            end
        end
    $fclose(f);

    // 3. .bss
    if (sys.dm.word(FRAMES_WORD) !== 32'd1) begin
        $display("FAIL  frames (.bss) = %h, expected 1", sys.dm.word(FRAMES_WORD));
        errors = errors + 1;
    end

    // 4. Pass protocol (HEX = BAD055 means .bss was not zero at the start of main)
    if (sys.io.ledr_reg !== 10'h3FF || sys.io.hex_reg !== 24'h00600D) begin
        $display("FAIL  LEDR = %h, HEX = %h, expected 3ff and 00600d", sys.io.ledr_reg, sys.io.hex_reg);
        errors = errors + 1;
    end

    if (errors == 0)
        $display("PASS: %0s (C, GCC): 12288 pixels, .bss, LEDR/HEX ok; main returned after %0d cycles; tc9.ppm saved",
                 PROGRAM, n);
    else
        $display("FAILED: %0s, %0d error(s)", PROGRAM, errors);
    $stop;
end

endmodule
