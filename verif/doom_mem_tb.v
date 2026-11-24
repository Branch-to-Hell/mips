`timescale 1ns/1ps
// PLT-8 + PLT-12 test with the real SDRAM: life_system (EXT_BUS = 1) + ext_memory (bridge,
// instruction cache, arbiter) + sdram_sys (Platform Designer: Intel SDRAM controller) + the
// controller's own memory model, wired like rtl/top_doom.v. Run from verif: do doom_mem.do
// The CPU runs src/programs/test_ext.s from the on-chip text: words, bytes and halves to the
// SDRAM through the data cache (DCACHE > 0) or the plain bridge (DCACHE = 0; doom_mem.do runs both),
// then a routine copied into the SDRAM and called from there (the instruction cache
// fills its lines from the controller), twice, and again after its line was replaced.
// The program reports on HEX (0xFFFF001C): 0x00600D = pass, 0xBAD0nn = test nn failed.
// The model has no I/O delays: this checks the logic (handshakes, pipelined reads through the
// 32 -> 16 width adapter, byte lanes), not the board timing (TimeQuest does that).
module doom_mem_tb #(
    parameter DCACHE = 10              // data cache size (DCACHE_LINES_LOG2); doom_mem.do also runs 0
);

reg clk = 0, reset = 1;
always #20 clk = ~clk;                   // 25 MHz

// ---- CPU side ----
wire [31:0] bus_addr, bus_wdata, ext_rdata, ifetch_addr, ifetch_next, ifetch_data, bus_addr_next;
wire [3:0] bus_be;
wire bus_we, bus_re, ext_sel, ext_stall, ifetch_req, ifetch_ready;

life_system #(.IMEM_INIT("../mem/test_ext"), .DEBOUNCE_CYCLES(50), .EXT_BUS(1)) sys (
    .clk(clk), .reset(reset),
    .SW(10'd0), .KEY(2'b11), .LEDR(),
    .HEX0(), .HEX1(), .HEX2(), .HEX3(), .HEX4(), .HEX5(),
    .VGA_R(), .VGA_G(), .VGA_B(), .VGA_HS(), .VGA_VS(),
    .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we), .bus_re(bus_re), .bus_be(bus_be),
    .ext_sel(ext_sel), .ext_rdata(ext_rdata), .ext_stall(ext_stall),
    .ifetch_addr(ifetch_addr), .ifetch_req(ifetch_req), .ifetch_next(ifetch_next),
    .bus_addr_next(bus_addr_next),
    .ifetch_data(ifetch_data), .ifetch_ready(ifetch_ready)
);

// ---- SDRAM side ----
wire [25:0] avm_address;
wire [31:0] avm_writedata, avm_readdata;
wire [3:0] avm_byteenable;
wire avm_read, avm_write, avm_readdatavalid, avm_waitrequest;

ext_memory #(.DCACHE_LINES_LOG2(DCACHE)) xm (
    .clk(clk), .reset(reset),
    .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_be(bus_be), .bus_re(bus_re), .bus_we(bus_we),
    .ext_sel(ext_sel), .ext_rdata(ext_rdata), .ext_stall(ext_stall),
    .ifetch_addr(ifetch_addr), .ifetch_req(ifetch_req), .ifetch_next(ifetch_next),
    .bus_addr_next(bus_addr_next),
    .ifetch_data(ifetch_data), .ifetch_ready(ifetch_ready),
    .avm_address(avm_address), .avm_read(avm_read), .avm_write(avm_write),
    .avm_writedata(avm_writedata), .avm_byteenable(avm_byteenable),
    .avm_readdata(avm_readdata), .avm_readdatavalid(avm_readdatavalid),
    .avm_waitrequest(avm_waitrequest)
);

wire [12:0] DRAM_ADDR;
wire [1:0] DRAM_BA, DRAM_DQM;
wire DRAM_CAS_N, DRAM_RAS_N, DRAM_WE_N, DRAM_CS_N, DRAM_CKE;
wire [15:0] DRAM_DQ;

sdram_sys dut (
    .clk_clk(clk), .reset_reset_n(!reset),
    .mem_address(avm_address), .mem_read(avm_read), .mem_write(avm_write),
    .mem_writedata(avm_writedata), .mem_byteenable(avm_byteenable),
    .mem_burstcount(1'b1), .mem_debugaccess(1'b0),
    .mem_readdata(avm_readdata), .mem_readdatavalid(avm_readdatavalid),
    .mem_waitrequest(avm_waitrequest),
    .wire_addr(DRAM_ADDR), .wire_ba(DRAM_BA), .wire_cas_n(DRAM_CAS_N), .wire_ras_n(DRAM_RAS_N),
    .wire_we_n(DRAM_WE_N), .wire_cs_n(DRAM_CS_N), .wire_cke(DRAM_CKE),
    .wire_dq(DRAM_DQ), .wire_dqm(DRAM_DQM)
);

sdram_sys_sdram_test_component chip (
    .clk(clk), .zs_addr(DRAM_ADDR), .zs_ba(DRAM_BA), .zs_cas_n(DRAM_CAS_N),
    .zs_ras_n(DRAM_RAS_N), .zs_we_n(DRAM_WE_N), .zs_cs_n(DRAM_CS_N), .zs_cke(DRAM_CKE),
    .zs_dq(DRAM_DQ), .zs_dqm(DRAM_DQM)
);

// ---- result: the program's write to HEX ----
integer cycles = 0, misses = 0, fills_words = 0, loads = 0, dmisses = 0, stores = 0;
always @(posedge clk) if (!reset) begin
    cycles = cycles + 1;
    if (xm.cache.state == 2'd1 && xm.cache.req && !xm.cache.hit) misses = misses + 1;
    if (xm.i_readdatavalid) fills_words = fills_words + 1;
    if (xm.ev_load) loads = loads + 1;
    if (xm.ev_miss) dmisses = dmisses + 1;
    if (xm.ev_store) stores = stores + 1;
    if (bus_we && bus_addr == 32'hFFFF_001C && !ext_stall) begin
        if (bus_wdata == 32'h0000_600D) begin
            $display("PASS: doom_mem_tb (DCACHE %0d): test_ext on ext_memory + the real SDRAM controller in %0d cycles (%0d instruction cache misses, %0d words filled, %0d loads from the SDRAM region, %0d went to the SDRAM, %0d stores)",
                     DCACHE, cycles, misses, fills_words, loads, dmisses, stores);
            $finish;
        end else begin
            $display("FAIL: doom_mem_tb (DCACHE %0d): HEX = %h (BAD0nn = test nn) after %0d cycles", DCACHE, bus_wdata, cycles);
            $finish;
        end
    end
    if (sys.halted) begin
        $display("FAIL: doom_mem_tb: CPU-14 halt, cause %0d pc %h addr %h", sys.halt_cause, sys.halt_pc, sys.halt_addr);
        $finish;
    end
end

integer i;
initial begin
    #1;
    for (i = 0; i < 32; i = i + 1) sys.cpu.rf.registers[i] = 0;  // like the FPGA after power-up
    repeat (4) @(negedge clk);
    reset = 0;
    #20_000_000;                         // 20 ms: something is stuck
    $display("FAIL: doom_mem_tb (DCACHE %0d): timeout (pc in ID %h, instruction cache state %0d, data side stalled %b)",
             DCACHE, sys.cpu.id_pc, xm.cache.state, ext_stall);
    $finish;
end

endmodule
