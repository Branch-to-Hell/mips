`timescale 1ns/1ns
// PLT-13 test: life_system running test_stack.hex. Run from verif: do stack.do
/* test_stack.asm checks the stack from the program (push/pop, nested jal, recursion,
region edges, no aliasing with data) and shows PASS (LEDR = 0x3FF, HEX = 0x00600D) or
FAIL (HEX = 0xBAD0nn). This testbench checks:
  1. after reset $sp = 0x7FFF_EFFC (MARS default)
  2. the program passes
  3. the stack RAM holds what the program wrote at both ends of the region,
     and the data RAM holds its own word (separate memories)
  4. a reset in the middle of the recursion, with $sp deep in the stack,
     puts $sp back at the top, and the program passes again
*/
module stack_tb;
localparam [31:0] SP_TOP = 32'h7FFF_EFFC;
localparam TIMEOUT = 20_000;           // cycles; the program needs well under 1,000

reg clk = 0, reset = 1;
reg [9:0] SW = 0;
reg [1:0] KEY = 2'b11;                 // active-low, released
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
wire [3:0] VGA_R, VGA_G, VGA_B;
wire VGA_HS, VGA_VS;

life_system #(.IMEM_INIT("../mem/test_stack"), .DEBOUNCE_CYCLES(50)) sys (
    .clk(clk), .reset(reset), .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

always #20 clk = ~clk;                 // 25 MHz

integer errors = 0;
integer n;

wire [31:0] sp = sys.cpu.rf.registers[29];
wire passed = (LEDR == 10'h3FF) && (sys.io.hex_reg == 24'h00600D);
wire failed = (sys.io.hex_reg[23:8] == 16'hBAD0);

task fail(input [8*56-1:0] what);
    begin
        $display("FAIL  %0s", what);
        errors = errors + 1;
    end
endtask

task check_sp_at_reset;
    begin
        if (sp !== SP_TOP) fail("$sp after reset is not 0x7FFFEFFC");
        else $display("ok    $sp after reset = %h", sp);
    end
endtask

// Runs until the program shows PASS or FAIL
task wait_result;
    begin
        n = 0;
        while (!passed && !failed && n < TIMEOUT) begin
            @(posedge clk);
            n = n + 1;
        end
        if (passed) $display("ok    program PASS after %0d cycles", n);
        else if (failed) begin
            $display("FAIL  program failed test %0d (HEX = %h)", sys.io.hex_reg[7:0], sys.io.hex_reg);
            errors = errors + 1;
        end else fail("timeout: the program never finished");
    end
endtask

initial begin
    // The registers power up as 0 on the FPGA; in simulation they start as X
    // (same as cpu2_tb / cpu3_program_tb). Reset then loads $sp
    for (n = 0; n < 32; n = n + 1) sys.cpu.rf.registers[n] = 0;

    // 1-2. Reset, $sp at the top, the program passes
    repeat (4) @(posedge clk);
    #1 check_sp_at_reset;
    reset = 0;
    wait_result;

    // 3. What the program left in memory
    if (sys.stack.mem[0] !== 32'h111) fail("stack word 0x7FFFE000 is not 0x111");
    else $display("ok    stack word 0x7FFFE000 = 0x111");
    if (sys.stack.mem[1023] !== 32'h222) fail("stack word 0x7FFFEFFC is not 0x222");
    else $display("ok    stack word 0x7FFFEFFC = 0x222");
    if (sys.dm.mem[0] !== 32'h333) fail("data word 0x10010000 is not 0x333");
    else $display("ok    data word 0x10010000 = 0x333");
    if (sp !== SP_TOP) fail("$sp is not back at the top at the end");

    // 4. Reset with $sp deep in the recursion
    @(negedge clk) reset = 1;
    repeat (2) @(posedge clk);
    @(negedge clk) reset = 0;
    n = 0;
    while (sp > SP_TOP - 80 && n < TIMEOUT) begin   // at least 10 words pushed
        @(posedge clk);
        n = n + 1;
    end
    if (n >= TIMEOUT) fail("$sp never went down 80 bytes");
    else $display("ok    $sp went down to %h during the recursion", sp);
    @(negedge clk) reset = 1;
    repeat (2) @(posedge clk);
    #1 check_sp_at_reset;
    @(negedge clk) reset = 0;
    wait_result;

    if (errors == 0) $display("PASS: stack region and $sp reset");
    else             $display("FAILED: %0d error(s)", errors);
    $stop;
end

endmodule
