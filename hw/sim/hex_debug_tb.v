`timescale 1ns/1ns
// PLT-4 test: HEX debug view on life_system. Run from hw/sim: do hex_debug.do
/* Decodes the 6 displays back to digits and checks, for all 32 registers and both halves:
  1. reset held: each register preloaded with a different value shows on HEX
     (number in decimal on HEX5-4, the chosen half on HEX3-0, decimal point of HEX4 on)
  2. the program running (life_board.hex): the view follows the live register file
  3. SW9 down: the displays show the program's HEX (MMIO) again
The switches change on negedge and the displays are checked 1 ns later,
before the next posedge can write a register
*/
module hex_debug_tb;

reg clk = 0, reset = 1;
reg [9:0] SW = 0;
reg [1:0] KEY = 2'b11;
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
wire [3:0] VGA_R, VGA_G, VGA_B;
wire VGA_HS, VGA_VS;

life_system #(.IMEM_INIT("../mem/life_board.hex"), .DEBOUNCE_CYCLES(50)) sys (
    .clk(clk), .reset(reset), .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

always #20 clk = ~clk;  // 25 MHz

integer r, h, errors = 0, checks = 0;

// Segments (active-low, gfedcba) back to a digit; 16 = not a digit
function [4:0] digit(input [6:0] seg);
    case (seg)
        7'b1000000: digit = 0;  7'b1111001: digit = 1;  7'b0100100: digit = 2;
        7'b0110000: digit = 3;  7'b0011001: digit = 4;  7'b0010010: digit = 5;
        7'b0000010: digit = 6;  7'b1111000: digit = 7;  7'b0000000: digit = 8;
        7'b0010000: digit = 9;  7'b0001000: digit = 10; 7'b0000011: digit = 11;
        7'b1000110: digit = 12; 7'b0100001: digit = 13; 7'b0000110: digit = 14;
        7'b0001110: digit = 15;
        default:    digit = 16;
    endcase
endfunction

// Show register r, half h, and compare the displays with the register file
task check_reg(input integer r, input integer h);
    reg [15:0] expected, shown;
    reg [4:0] d0, d1, d2, d3, d4, d5;
    begin
        @(negedge clk);
        SW = {1'b1, 3'b000, h[0], r[4:0]};
        #1;
        expected = h ? sys.cpu.rf.registers[r][31:16] : sys.cpu.rf.registers[r][15:0];
        d0 = digit(HEX0[6:0]); d1 = digit(HEX1[6:0]); d2 = digit(HEX2[6:0]);
        d3 = digit(HEX3[6:0]); d4 = digit(HEX4[6:0]); d5 = digit(HEX5[6:0]);
        shown = {d3[3:0], d2[3:0], d1[3:0], d0[3:0]};
        checks = checks + 1;
        if (d0[4] || d1[4] || d2[4] || d3[4] || d4[4] || d5[4]) begin
            $display("FAIL  $%0d half %0d: a display is not a digit", r, h);
            errors = errors + 1;
        end else if (d5 * 10 + d4 != r) begin
            $display("FAIL  $%0d half %0d: number shows %0d%0d", r, h, d5, d4);
            errors = errors + 1;
        end else if (shown !== expected) begin
            $display("FAIL  $%0d half %0d: shows %h (expected %h)", r, h, shown, expected);
            errors = errors + 1;
        end else if (HEX4[7] !== 1'b0 || {HEX0[7], HEX1[7], HEX2[7], HEX3[7], HEX5[7]} !== 5'b11111) begin
            $display("FAIL  $%0d half %0d: decimal points wrong", r, h);
            errors = errors + 1;
        end
    end
endtask

task check_all(input [8*40-1:0] what);
    integer before;
    begin
        before = errors;
        for (r = 0; r < 32; r = r + 1)
            for (h = 0; h < 2; h = h + 1)
                check_reg(r, h);
        if (errors == before) $display("ok    %0s: 32 registers x 2 halves", what);
    end
endtask

initial begin
    // 1. Reset held: a different value in every register (both halves differ too)
    sys.cpu.rf.registers[0] = 0;
    for (r = 1; r < 32; r = r + 1)
        sys.cpu.rf.registers[r] = (r * 32'h9E37_79B9) ^ 32'h5A5A_A5A5;
    repeat (4) @(posedge clk);
    check_all("preloaded values");

    // 2. The program runs and changes registers; the view must follow
    @(negedge clk); reset = 0;
    repeat (20_000) @(posedge clk);
    check_all("program running");
    repeat (50_000) @(posedge clk);
    check_all("program running, later");

    // 3. SW9 down: back to the program's HEX
    @(negedge clk);
    SW = 10'h01F;
    #1;
    if ({HEX5, HEX4, HEX3, HEX2, HEX1, HEX0} !== {sys.io_hex5, sys.io_hex4, sys.io_hex3,
                                                  sys.io_hex2, sys.io_hex1, sys.io_hex0}) begin
        $display("FAIL  SW9 down: HEX is not the program's");
        errors = errors + 1;
    end else
        $display("ok    SW9 down: HEX shows the program's value (%h)", sys.io.hex_reg);

    if (errors) $fatal(1, "PLT-4: %0d error(s) in %0d checks", errors, checks);
    $display("PASS: PLT-4 HEX debug view (%0d checks)", checks);
    $finish;
end
endmodule
