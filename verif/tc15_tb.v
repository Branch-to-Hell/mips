`timescale 1ns/1ns
// TC-15 test: graded algorithm (frequency of a value) on life_system with mips_pipeline,
// the same hardware as the board. Run from verif: do tc15.do (all 3 inputs)
/* One input per run, picked with -G (see tc15.do): PROGRAM = count_value_in1..3,
N, TARGET and EXPECTED from docs/tc15_algorithm.md. The program's .data (n, target, array)
comes from <PROGRAM>_data.hex through DMEM_INIT, like on the board. Checks:
  1. the program reaches its observable end (j end, a self-jump) without a CPU halt
  2. result (0x10010008) = EXPECTED, and n and target are unchanged
  3. what the board shows: SW9 up with SW4-0 = 11 ($t3, the count) puts EXPECTED on HEX3-0
*/
module tc15_tb;
parameter PROGRAM = "count_value_in1";
parameter N = 8;
parameter TARGET = 3;
parameter EXPECTED = 4;
localparam TIMEOUT = 20_000;           // cycles; the longest input needs a few hundred

reg clk = 0, reset = 1;
reg [9:0] SW = 0;
reg [1:0] KEY = 2'b11;                 // active-low, released
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
wire [3:0] VGA_R, VGA_G, VGA_B;
wire VGA_HS, VGA_VS;

life_system #(.IMEM_INIT({"../mem/", PROGRAM}), .DMEM_INIT({"../mem/", PROGRAM, "_data.hex"}),
              .DEBOUNCE_CYCLES(50)) sys (
    .clk(clk), .reset(reset), .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

always #20 clk = ~clk;                 // 25 MHz

integer errors = 0, n, i;

// Self-jump in ID: j whose target is its own address (the program's "end: j end")
wire [31:0] id_pc = sys.cpu.id_pc, id_instr = sys.cpu.id_instruction;
wire at_end = sys.cpu.id_valid && id_instr[31:26] == 6'h02 &&
              {id_pc[31:28], id_instr[25:0], 2'b00} == id_pc;

// Expected HEX3-0 with the board's own decoder (decimal point off)
wire [6:0] e0, e1, e2, e3;
hex7seg x0(.value(EXPECTED[3:0]),   .seg(e0));
hex7seg x1(.value(EXPECTED[7:4]),   .seg(e1));
hex7seg x2(.value(EXPECTED[11:8]),  .seg(e2));
hex7seg x3(.value(EXPECTED[15:12]), .seg(e3));

task fail(input [8*56-1:0] what);
    begin
        $display("FAIL  %0s: %0s", PROGRAM, what);
        errors = errors + 1;
    end
endtask

initial begin
    for (i = 0; i < 32; i = i + 1) sys.cpu.rf.registers[i] = 0;  // like the FPGA after power-up
    repeat (4) @(posedge clk);
    @(negedge clk) reset = 0;

    // 1. Run to the self-jump
    n = 0;
    while (!at_end && !sys.halted && n < TIMEOUT) begin @(posedge clk); n = n + 1; end
    if (sys.halted)
        $fatal(1, "%0s: CPU halted, cause %0d at PC %h, address %h",
               PROGRAM, sys.halt_cause, sys.halt_pc, sys.halt_addr);
    if (!at_end) $fatal(1, "%0s: never reached the self-jump", PROGRAM);
    repeat (5) @(posedge clk);

    // 2. Result in memory, inputs untouched
    if (sys.dm.mem[2] !== EXPECTED)
        $display("FAIL  %0s: result = %0d, expected %0d", PROGRAM, sys.dm.mem[2], EXPECTED);
    if (sys.dm.mem[2] !== EXPECTED) errors = errors + 1;
    if (sys.dm.mem[0] !== N || sys.dm.mem[1] !== TARGET) fail("n or target changed (or .data not loaded)");

    // 3. The count on the board: SW9 debug view of register 11 ($t3)
    SW = 10'b10_0000_1011;
    #1;
    if ({HEX3[6:0], HEX2[6:0], HEX1[6:0], HEX0[6:0]} !== {e3, e2, e1, e0}) fail("HEX debug view of $t3");
    SW = 0;

    if (errors == 0)
        $display("PASS: %0s: n = %0d, target = %0d, result = %0d (expected %0d), self-jump after %0d cycles",
                 PROGRAM, N, TARGET, sys.dm.mem[2], EXPECTED, n);
    else
        $display("FAILED: %0s, %0d error(s)", PROGRAM, errors);
    $stop;
end

endmodule
