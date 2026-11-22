`timescale 1ns/1ns
// LIFE-6 / CPU-14 test: life_system address decoder and visible halt. Run from verif: do halt.do
/* Runs test_halt.hex (src/programs/test_halt.asm) on life_system with mips_pipeline. Checks:
  1. the first and last word of every region (data, mode A, stack, MMIO) don't halt: the
     program reaches LEDR = 0x155, and the CPU halts at the sw to 0x7FFFF000
     (cause 3, halt_addr 0x7FFFF000, halt_pc = that sw)
  2. nothing was written by the failing sw or younger instructions ($t4 = 0)
  3. what the board shows: LEDR = 0x203 (LEDR9 + cause), HEX = E3F000,
     SW8 up = PC bits 23:0, SW9 up = the register debug view still works
  4. the address decoder alone (mem_addr forced while halted, so nothing is written):
     region edges inside are valid, the words right outside are faults
*/
module halt_tb;
localparam TIMEOUT = 5_000;            // cycles; the program needs well under 100
localparam [31:0] BAD_SW = 32'hAD0B0000;   // sw $t3, 0($t0)

reg clk = 0, reset = 1;
reg [9:0] SW = 0;
reg [1:0] KEY = 2'b11;                 // active-low, released
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
wire [3:0] VGA_R, VGA_G, VGA_B;
wire VGA_HS, VGA_VS;

life_system #(.IMEM_INIT("../mem/test_halt"), .DEBOUNCE_CYCLES(50)) sys (
    .clk(clk), .reset(reset), .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

always #20 clk = ~clk;                 // 25 MHz

integer errors = 0, n, i;
reg [31:0] bad_pc;

// Expected HEX digits, with the same decoder the board uses (decimal point off)
reg [23:0] expect_hex;
wire [6:0] e0, e1, e2, e3, e4, e5;
hex7seg x0(.value(expect_hex[3:0]),   .seg(e0));
hex7seg x1(.value(expect_hex[7:4]),   .seg(e1));
hex7seg x2(.value(expect_hex[11:8]),  .seg(e2));
hex7seg x3(.value(expect_hex[15:12]), .seg(e3));
hex7seg x4(.value(expect_hex[19:16]), .seg(e4));
hex7seg x5(.value(expect_hex[23:20]), .seg(e5));

task fail(input [8*56-1:0] what);
    begin
        $display("FAIL  %0s", what);
        errors = errors + 1;
    end
endtask

task check_hex(input [23:0] value, input [8*56-1:0] what);
    begin
        expect_hex = value;
        #1;
        if ({HEX5, HEX4, HEX3, HEX2, HEX1, HEX0} !== {1'b1, e5, 1'b1, e4, 1'b1, e3, 1'b1, e2, 1'b1, e1, 1'b1, e0})
            fail(what);
        else $display("ok    %0s (%h)", what, value);
    end
endtask

task check_fault(input [31:0] addr, input expected);
    begin
        force sys.mem_addr = addr;
        #1;
        if (sys.mem_fault !== expected) begin
            $display("FAIL  mem_fault(%h) = %b, expected %b", addr, sys.mem_fault, expected);
            errors = errors + 1;
        end
    end
endtask

initial begin
    for (n = 0; n < 32; n = n + 1) sys.cpu.rf.registers[n] = 0;  // like the FPGA after power-up
    bad_pc = 32'hFFFF_FFFF;
    for (i = 0; i < 4096; i = i + 1)
        if (sys.cpu.if_id.im.read_word(i) === BAD_SW) bad_pc = 4 * i;
    if (bad_pc == 32'hFFFF_FFFF) $fatal(1, "sw $t3, 0($t0) not found in the program");

    repeat (4) @(posedge clk);
    @(negedge clk) reset = 0;

    // 1. Run until the halt
    n = 0;
    while (!sys.halted && n < TIMEOUT) begin @(posedge clk); n = n + 1; end
    if (!sys.halted) $fatal(1, "the CPU never halted");
    if (sys.io_ledr !== 10'h155) fail("1. a valid region edge halted the CPU (LEDR != 0x155)");
    else $display("ok    every region edge accepted (LEDR = 0x155)");
    if (sys.halt_cause !== 2'd3 || sys.halt_addr !== 32'h7FFF_F000 || sys.halt_pc !== bad_pc) begin
        $display("FAIL  1. halt cause %0d at PC %h, address %h (expected 3, %h, 7ffff000)",
                 sys.halt_cause, sys.halt_pc, sys.halt_addr, bad_pc);
        errors = errors + 1;
    end else $display("ok    halted after %0d cycles: cause 3 at PC %h, address 7ffff000", n, bad_pc);

    // 2. No writes from the failing sw or younger instructions
    repeat (10) @(posedge clk);
    if (sys.stack.word(0) === 32'h444) fail("2. the failing sw wrote the stack");
    if (sys.cpu.rf.registers[12] !== 32'd0) fail("2. an instruction after the sw ran ($t4)");
    else $display("ok    nothing written after the halt");

    // 3. What the board shows
    #1;
    if (LEDR !== 10'h203) fail("3. LEDR = 0x203 (LEDR9 + cause 3)");
    else $display("ok    LEDR = 203");
    check_hex(24'hE3_F000, "3. HEX = E, cause, address bits 15:0");
    SW[8] = 1;
    check_hex(bad_pc[23:0], "3. SW8 up: HEX = PC bits 23:0");
    SW = 10'b10_0000_1100;             // SW9 up, register 12
    #1;
    if (HEX4[7] !== 1'b0) fail("3. SW9 up shows the debug view");
    else $display("ok    SW9 up still shows the debug view");
    SW = 0;

    // 4. The decoder alone (halted: mem_we/mem_re are 0, so forcing the address writes nothing)
    check_fault(32'h1001_0000, 0); check_fault(32'h1001_3FFC, 0);   // data
    check_fault(32'h1000_FFFC, 1); check_fault(32'h1001_4000, 1);
    check_fault(32'h1004_0000, 0); check_fault(32'h1004_BFFC, 0);   // framebuffer mode A
    check_fault(32'h1003_FFFC, 1); check_fault(32'h1004_C000, 1);
    check_fault(32'h7FFF_E000, 0); check_fault(32'h7FFF_EFFC, 0);   // stack
    check_fault(32'h7FFF_DFFC, 1); check_fault(32'h7FFF_F000, 1);
    check_fault(32'hFFFF_0010, 0); check_fault(32'hFFFF_0024, 0);   // MMIO
    check_fault(32'hFFFF_000C, 1); check_fault(32'hFFFF_0028, 1);
    check_fault(32'h1005_0000, 1); check_fault(32'h1005_FC00, 1);   // mode B: not in top_life
    check_fault(32'h0000_0000, 1);                                   // text is not data
    release sys.mem_addr;
    $display("ok    address decoder: 19 addresses checked");

    if (errors == 0) $display("PASS: LIFE-6 address decoder and visible halt");
    else             $display("FAILED: %0d error(s)", errors);
    $stop;
end

endmodule
