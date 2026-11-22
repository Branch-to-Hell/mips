`timescale 1ns/1ns
// PLT-2 test: CPU + data memory + MMIO running test_mmio.hex. Run from hw/sim: do mmio.do
/* Short debounce (50 cycles) so the test is fast.
The program loops with j (CPU-3); without CPU-3 it runs again when the PC wraps,
every 4,096 cycles. The waits use that worst case (one "pass"), so both work
Checks:
  1. debounce ignores bounces shorter than the debounce time
  2. LEDR mirrors SW through lw/sw
  3. one bouncy KEY0 press = +1 on HEX, holding it doesn't count again
  4. HEX0 shows the right segments
*/
module mmio_tb;
localparam DB = 50;      // debounce cycles
localparam PASS = 4096;  // cycles per pass of the program

reg clk = 0, reset = 1;
reg [9:0] SW = 0;
reg [1:0] KEY = 2'b11;   // active-low, released
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
integer i, errors = 0;

wire [31:0] mem_addr, mem_wdata, mem_rdata, dm_rdata, mmio_rdata;
wire mem_we, mem_re;

mips_cpu #(.IMEM_INIT("../mem/test_mmio")) dut (
    .clk(clk), .reset(reset),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata)
);
data_memory dm (
    .clk(clk), .MemRead(mem_re), .MemWrite(mem_we),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(dm_rdata)
);
mmio #(.DEBOUNCE_CYCLES(DB)) io (
    .clk(clk), .reset(reset),
    .addr(mem_addr), .wdata(mem_wdata), .we(mem_we), .re(mem_re), .rdata(mmio_rdata),
    .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5)
);
assign mem_rdata = dm_rdata | mmio_rdata;

always #5 clk = ~clk;

task wait_cycles(input integer n);
    repeat (n) @(posedge clk);
endtask

task check(input [31:0] got, input [31:0] want, input [8*24-1:0] what);
    begin
        if (got !== want) begin
            $display("FAIL  %0s = %h (expected %h)", what, got, want);
            errors = errors + 1;
        end else
            $display("ok    %0s = %h", what, got);
    end
endtask

// KEY0 bounces: short pulses, each shorter than the debounce time
task bounce_key0(input final_level);
    begin
        repeat (4) begin
            KEY[0] = ~KEY[0]; wait_cycles(DB / 5);
        end
        KEY[0] = final_level;
    end
endtask

initial begin
    // Registers start at 0, like the flip-flops on the FPGA after power-up
    for (i = 0; i < 32; i = i + 1) dut.rf.registers[i] = 0;
    wait_cycles(2);
    @(negedge clk); reset = 0;

    // 1. Bounces alone must not register as a press
    KEY[0] = 0; wait_cycles(DB / 2); KEY[0] = 1; wait_cycles(DB / 2);
    KEY[0] = 0; wait_cycles(DB / 2); KEY[0] = 1;
    wait_cycles(DB * 2);
    check(io.key_pressed, 2'b00, "KEY after glitches");

    // 2. Switches mirror onto LEDs
    SW = 10'h2A5;
    wait_cycles(PASS + 10);
    check(LEDR, 10'h2A5, "LEDR (SW = 2A5)");
    SW = 10'h15A;
    wait_cycles(PASS + 10);
    check(LEDR, 10'h15A, "LEDR (SW = 15A)");

    // 3. One bouncy press, held for several passes, counts once
    check(io.hex_reg, 0, "HEX before presses");
    KEY[0] = 0; bounce_key0(0);   // press
    wait_cycles(3 * PASS);         // held
    check(io.key_pressed, 2'b01, "KEY while KEY0 held");
    check(io.hex_reg, 1, "HEX after 1 press");
    bounce_key0(1);                // release
    wait_cycles(2 * PASS);
    check(io.hex_reg, 1, "HEX after release");

    KEY[0] = 0; bounce_key0(0);   // second press
    wait_cycles(2 * PASS);
    bounce_key0(1);
    wait_cycles(2 * PASS);
    check(io.hex_reg, 2, "HEX after 2 presses");

    // KEY1 doesn't count
    KEY[1] = 0; wait_cycles(2 * PASS);
    check(io.key_pressed, 2'b10, "KEY while KEY1 held");
    KEY[1] = 1; wait_cycles(2 * PASS);
    check(io.hex_reg, 2, "HEX after KEY1 press");

    // 4. Segments: HEX0 shows "2", the rest "0", decimal points off
    check(HEX0, 8'b1_0100100, "HEX0 segments ('2')");
    check(HEX1, 8'b1_1000000, "HEX1 segments ('0')");

    if (errors) $fatal(1, "PLT-2: %0d error(s)", errors);
    $display("PASS: PLT-2 MMIO switches, LEDs, debounced keys and HEX");
    $finish;
end
endmodule
