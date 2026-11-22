`timescale 1ns/1ps
// PLT-7 test: sdram_smoke + the real Platform Designer system (bridge + Intel SDRAM
// controller) + the controller's own SDRAM memory model. Run from verif: do sdram.do
/* The model has no I/O delays, so this checks the logic (commands, CAS latency, the
32 -> 16 width adapter, byte enables), not the board timing: that is TimeQuest's job.
Checks:
  1. after the controller's power-up sequence, the smoke test writes and reads back
     WORDS words with no errors
  2. data really reaches the memory: word at byte address A = halfwords A/2 (bits 15..0)
     and A/2+1 (bits 31..16) of the model. Avalon byte lanes are little-endian: byte
     address A+k is bits 8k+7..8k (byteenable[k]). The CPU is big-endian (contracts.md),
     so the CPU bridge (PLT-8) has to swap the bytes
  3. a corrupted word in memory is detected: errors = 1 and first_bad = its address
  4. byte enables: writing 1 byte or 1 halfword only changes those byte lanes
*/
module sdram_tb;
localparam WORDS = 256;

reg clk = 0, reset = 1, start = 0;
always #20 clk = ~clk;                   // 25 MHz

integer errors_tb = 0;

// ---- Avalon bus: the smoke test drives it, except in check 4 (the testbench drives it) ----
reg tb_owns = 0;
reg [25:0] tb_address = 0;
reg tb_read = 0, tb_write = 0;
reg [31:0] tb_writedata = 0;
reg [3:0] tb_byteenable = 0;

wire [25:0] st_address;
wire st_read, st_write;
wire [31:0] st_writedata;
wire [3:0] st_byteenable;

wire [25:0] address = tb_owns ? tb_address : st_address;
wire read = tb_owns ? tb_read : st_read;
wire write = tb_owns ? tb_write : st_write;
wire [31:0] writedata = tb_owns ? tb_writedata : st_writedata;
wire [3:0] byteenable = tb_owns ? tb_byteenable : st_byteenable;
wire [31:0] readdata;
wire readdatavalid, waitrequest;

wire busy, done;
wire [23:0] errors;
wire [25:0] first_bad;

sdram_smoke #(.WORDS(WORDS)) test (
    .clk(clk), .reset(reset), .start(start),
    .address(st_address), .read(st_read), .write(st_write),
    .writedata(st_writedata), .byteenable(st_byteenable),
    .readdata(readdata), .readdatavalid(readdatavalid), .waitrequest(waitrequest),
    .busy(busy), .done(done), .errors(errors), .first_bad(first_bad)
);

// ---- SDRAM system and memory model ----
wire [12:0] DRAM_ADDR;
wire [1:0] DRAM_BA, DRAM_DQM;
wire DRAM_CAS_N, DRAM_RAS_N, DRAM_WE_N, DRAM_CS_N, DRAM_CKE;
wire [15:0] DRAM_DQ;

sdram_sys dut (
    .clk_clk(clk), .reset_reset_n(!reset),
    .mem_address(address), .mem_read(read), .mem_write(write),
    .mem_writedata(writedata), .mem_byteenable(byteenable),
    .mem_burstcount(1'b1), .mem_debugaccess(1'b0),
    .mem_readdata(readdata), .mem_readdatavalid(readdatavalid), .mem_waitrequest(waitrequest),
    .wire_addr(DRAM_ADDR), .wire_ba(DRAM_BA), .wire_cas_n(DRAM_CAS_N), .wire_ras_n(DRAM_RAS_N),
    .wire_we_n(DRAM_WE_N), .wire_cs_n(DRAM_CS_N), .wire_cke(DRAM_CKE),
    .wire_dq(DRAM_DQ), .wire_dqm(DRAM_DQM)
);

sdram_sys_sdram_test_component chip (
    .clk(clk), .zs_addr(DRAM_ADDR), .zs_ba(DRAM_BA), .zs_cas_n(DRAM_CAS_N),
    .zs_ras_n(DRAM_RAS_N), .zs_we_n(DRAM_WE_N), .zs_cs_n(DRAM_CS_N), .zs_cke(DRAM_CKE),
    .zs_dq(DRAM_DQ), .zs_dqm(DRAM_DQM)
);
// For byte addresses below 2 KB (row 0, bank 0) the model index is the halfword address
`define MEM chip.sdram_sys_sdram_test_component_ram.mem_array

function [31:0] pattern(input [25:0] a);   // same as sdram_smoke
    pattern = {a[25:2], 8'h00} ^ {8'hA5, a[25:2]} ^ 32'h5A3C_96E1;
endfunction

task run_smoke;
    begin
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        wait (done);
        @(negedge clk);
    end
endtask

task check(input [8*40-1:0] what, input [31:0] got, input [31:0] expected);
    if (got !== expected) begin
        $display("FAIL %0s: got %h, expected %h", what, got, expected);
        errors_tb = errors_tb + 1;
    end
endtask

// Avalon accesses from the testbench (hold the command while waitrequest = 1)
task av_write(input [25:0] a, input [31:0] d, input [3:0] be);
    begin
        @(negedge clk);
        tb_address = a; tb_writedata = d; tb_byteenable = be; tb_write = 1;
        @(posedge clk);
        while (waitrequest) @(posedge clk);
        @(negedge clk) tb_write = 0;
    end
endtask

task av_read(input [25:0] a, output [31:0] d);
    begin
        @(negedge clk);
        tb_address = a; tb_byteenable = 4'b1111; tb_read = 1;
        @(posedge clk);
        while (waitrequest) @(posedge clk);
        @(negedge clk) tb_read = 0;
        while (!readdatavalid) @(posedge clk);
        d = readdata;
    end
endtask

reg [31:0] r;
integer cycles;

initial begin
    repeat (5) @(negedge clk);
    reset = 0;

    // 1. Whole smoke test, clean memory
    cycles = 0;
    fork
        run_smoke;
        while (!done) begin @(posedge clk); cycles = cycles + 1; end
    join
    check("1. errors", errors, 0);
    $display("smoke test: %0d words written and read in %0d cycles (includes the 100 us power-up)",
             WORDS, cycles);

    // 2. The words are really in the SDRAM, low halfword first
    check("2. word 0x000 low half",  `MEM[0],      pattern(26'h000) & 32'hFFFF);
    check("2. word 0x000 high half", `MEM[1],      pattern(26'h000) >> 16);
    check("2. word 0x1FC low half",  `MEM[26'hFE], pattern(26'h1FC) & 32'hFFFF);
    check("2. word 0x1FC high half", `MEM[26'hFF], pattern(26'h1FC) >> 16);

    // 3. Corrupt one word between the write and the read phase: it must be reported
    fork
        run_smoke;
        begin
            wait (test.state == 3'd2);       // READ: the write phase is over
            `MEM[26'h40] = `MEM[26'h40] ^ 16'h0100;   // byte address 0x80, one bit
        end
    join
    check("3. errors", errors, 1);
    check("3. first_bad", first_bad, 26'h80);

    // 4. Byte enables
    tb_owns = 1;
    av_write(26'h100, 32'hDDCC_BBAA, 4'b1111);
    av_read(26'h100, r);
    check("4. full word", r, 32'hDDCC_BBAA);
    av_write(26'h100, 32'h0000_1100, 4'b0010);     // lane 1 (byte address 0x101)
    av_read(26'h100, r);
    check("4. byte 1", r, 32'hDDCC_11AA);
    av_write(26'h100, 32'h7766_0000, 4'b1100);     // lanes 3-2 (byte addresses 0x102-0x103)
    av_read(26'h100, r);
    check("4. halfword 1", r, 32'h7766_11AA);
    av_write(26'h100, 32'h0000_0055, 4'b0001);     // lane 0 (byte address 0x100)
    av_read(26'h100, r);
    check("4. byte 0", r, 32'h7766_1155);

    if (errors_tb == 0) $display("PASS: sdram_tb, all checks");
    else $display("FAIL: sdram_tb, %0d checks failed", errors_tb);
    $stop;
end

initial begin
    #5_000_000;                              // 5 ms: something is stuck
    $display("FAIL: timeout");
    $stop;
end

endmodule
