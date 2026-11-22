`timescale 1ns/1ns
// PLT-5 test: CPU + data memory + MMIO running test_timer.hex. Run from verif: do timer.do
/* 1 ms = 100 cycles here (CYCLES_PER_MS), so a simulated "second" is short.
Checks:
  1. the timer counts exactly 1 every CYCLES_PER_MS cycles from reset,
     and the program's sw to TIMER does not change it (read-only)
  2. the program reads it: HEX = TIMER, LEDR = TIMER / 1024
  3. reset sets it back to 0 and it counts again
  4. it wraps from FFFF_FFFF to 0
*/
module timer_tb;
localparam MS = 100;     // cycles per millisecond

reg clk = 0, reset = 1;
reg [9:0] SW = 0;
reg [1:0] KEY = 2'b11;
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
integer i, n, errors = 0;

wire [31:0] mem_addr, mem_wdata, mem_rdata, dm_rdata, mmio_rdata;
wire mem_we, mem_re;

mips_cpu #(.IMEM_INIT("../mem/test_timer")) dut (
    .clk(clk), .reset(reset),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata)
);
data_memory dm (
    .clk(clk), .MemRead(mem_re), .MemWrite(mem_we), .ByteEnable(4'b1111),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(dm_rdata)
);
mmio #(.DEBOUNCE_CYCLES(50), .CYCLES_PER_MS(MS)) io (
    .clk(clk), .reset(reset),
    .addr(mem_addr), .wdata(mem_wdata), .we(mem_we), .be(4'b1111), .re(mem_re), .rdata(mmio_rdata),
    .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5)
);
assign mem_rdata = dm_rdata | mmio_rdata;

always #5 clk = ~clk;

task wait_cycles(input integer k);
    repeat (k) @(posedge clk);
endtask

task fail(input [8*48-1:0] what);
    begin
        $display("FAIL  %0s", what);
        errors = errors + 1;
    end
endtask

/* After n posedges with reset low the timer must be n / MS.
Checked after every posedge for k cycles, starting at n
*/
task check_count(input integer k, input [8*40-1:0] what);
    integer before;
    begin
        before = errors;
        repeat (k) begin
            @(posedge clk); n = n + 1; #1;
            if (io.timer_ms !== n / MS && errors - before < 5) begin
                $display("FAIL  %0s: after %0d cycles timer = %0d (expected %0d)",
                         what, n, io.timer_ms, n / MS);
                errors = errors + 1;
            end
        end
        if (errors == before) $display("ok    %0s: %0d ms in %0d cycles", what, io.timer_ms, n);
    end
endtask

/* The loop takes 5 cycles, much less than 1 ms, so what the program shows
is the current value or (right after a tick) the one before
*/
task check_program(input [8*40-1:0] what);
    begin
        @(negedge clk);
        if (io.hex_reg !== io.timer_ms[23:0] && io.hex_reg !== io.timer_ms[23:0] - 1'b1) begin
            $display("FAIL  %0s: HEX = %0d, timer = %0d", what, io.hex_reg, io.timer_ms);
            errors = errors + 1;
        end else if (LEDR !== io.hex_reg[19:10]) begin
            $display("FAIL  %0s: LEDR = %0d, HEX / 1024 = %0d", what, LEDR, io.hex_reg[19:10]);
            errors = errors + 1;
        end else
            $display("ok    %0s: HEX = %0d ms, LEDR = %0d", what, io.hex_reg, LEDR);
    end
endtask

initial begin
    for (i = 0; i < 32; i = i + 1) dut.rf.registers[i] = 0;  // like the FPGA after power-up
    wait_cycles(5);
    if (io.timer_ms !== 0) fail("timer should be 0 during reset");

    // 1. Exact count from reset; the program writes 0 to TIMER right at the start
    @(negedge clk); reset = 0;
    n = 0;
    check_count(20 * MS + 37, "counts 1 per ms, write ignored");

    // 2. The program reads it (more than 1024 ms, so LEDR is not 0)
    check_program("program reads TIMER at 20 ms");
    wait_cycles(1500 * MS);
    check_program("program reads TIMER at ~1.5 s");
    if (LEDR == 0) fail("LEDR should be 1 after 1024 ms");

    // 3. Reset in the middle: back to 0, then counts again
    @(negedge clk); reset = 1;
    wait_cycles(3);
    if (io.timer_ms !== 0) fail("reset should clear the timer");
    @(negedge clk); reset = 0;
    n = 0;
    check_count(5 * MS, "counts again after reset");

    // 4. Wrap-around: right after a tick, jump to the last value
    wait (io.prescaler == 0);
    @(negedge clk);
    io.timer_ms = 32'hFFFF_FFFF;
    wait_cycles(MS + 2);
    if (io.timer_ms !== 0) fail("timer should wrap from FFFF_FFFF to 0");
    else $display("ok    wraps from FFFF_FFFF to 0");

    if (errors) $fatal(1, "PLT-5: %0d error(s)", errors);
    $display("PASS: PLT-5 timer MMIO");
    $finish;
end
endmodule
