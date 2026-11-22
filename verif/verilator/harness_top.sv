// TC-7: Verilator harness. Runs a program on life_system (mips_pipeline + the board's memory map,
// MMIO and video) and prints the same trace as src/tools/ref_sim.py (docs/contracts.md
// "Reference simulator trace"), so the two compare with a plain diff (TC-8, TC-11).
//
// Plusargs (sim_main.cpp passes the command line):
//   +program=<prefix>    e.g. mem/hello_pixels: loads <prefix>_b0..b3.hex into the instruction
//                        banks and <prefix>_data.hex (if it exists) into the data memory
//   +max-cycles=<N>      stop after N clock cycles (default 10,000,000)
//   +ppm=<file>          at the end, save framebuffer A (128x96) as a PPM image
//
// Trace, one line per register write, in program order (they happen in WB):
//   PC=0x00000050 R2 <= 0x00000000
// The last line says why the run ended, like ref_sim.py:
//   HALT: jumps to itself at 0x00000040  (steps=87028)
//   HALT: cause 2 (load) pc 0x... addr 0x...  (steps=N)
//   HALT: reached +max-cycles N at PC=0x...  (steps=N)
// steps = instructions that finished (nops too, bubbles not), the same count as ref_sim.py.
// Cycles go to stderr, so stdout is only the trace.
module harness_top (
    input clk,
    input reset,
    output logic done = 0   // the run ended; sim_main.cpp stops (no $finish: its message would go to stdout)
);

life_system #(.MODE_B(1), .DEBOUNCE_CYCLES(50)) sys (
    .clk(clk), .reset(reset), .SW(10'd0), .KEY(2'b11), .LEDR(),
    .HEX0(), .HEX1(), .HEX2(), .HEX3(), .HEX4(), .HEX5(),
    .VGA_R(), .VGA_G(), .VGA_B(), .VGA_HS(), .VGA_VS()
);

// ---- loading: once, on the first clock edge in reset ----
// (not in an initial block: data_memory's own initial zeroes its RAM, and the order of
// initial blocks between modules is not defined, so it could erase the .data image)
string program_prefix, ppm_file;
longint max_cycles = 10_000_000;
bit loaded = 0;
integer fd, i;

initial begin
    if (!$value$plusargs("program=%s", program_prefix))
        $fatal(1, "Usage: mips_sim +program=mem/<name> [+max-cycles=N] [+ppm=file.ppm]");
    void'($value$plusargs("max-cycles=%d", max_cycles));
    if (!$value$plusargs("ppm=%s", ppm_file)) ppm_file = "";
end

task automatic load_banks();
    fd = $fopen({program_prefix, "_b0.hex"}, "r");
    if (fd == 0) $fatal(1, "Can't open %s_b0.hex (build it with the assembler or make -C src/c)", program_prefix);
    $fclose(fd);
    $readmemh({program_prefix, "_b0.hex"}, sys.cpu.if_id.im.bank0);
    $readmemh({program_prefix, "_b1.hex"}, sys.cpu.if_id.im.bank1);
    $readmemh({program_prefix, "_b2.hex"}, sys.cpu.if_id.im.bank2);
    $readmemh({program_prefix, "_b3.hex"}, sys.cpu.if_id.im.bank3);
    fd = $fopen({program_prefix, "_data.hex"}, "r");
    if (fd != 0) begin
        $fclose(fd);
        $readmemh({program_prefix, "_data.hex"}, sys.dm.mem);
    end
    // Like the FPGA after power-up (and the ModelSim testbenches); reset then sets $sp
    for (i = 0; i < 32; i = i + 1)
        if (i != 29) sys.cpu.rf.registers[i] = 32'd0;
endtask

always @(posedge clk)
    if (reset && !loaded) begin
        load_banks();
        loaded <= 1;
    end

// ---- trace ----
// MEM/WB is always enabled, so the instruction in WB is the one that was in MEM last cycle
logic [31:0] wb_pc;
always @(posedge clk) wb_pc <= sys.cpu.mem_pc;

wire        wb_valid = sys.cpu.wb_valid;
wire        wb_write = sys.cpu.wb_write;        // valid, RegWrite, not $zero
wire [4:0]  wb_dest  = sys.cpu.wb_dest;
wire [31:0] wb_data  = sys.cpu.wb_data;

// A branch/jump in ID that really redirects (not stalled, so its operands are current)
// to its own address: the program's "end: j end". ref_sim.py stops after its delay slot.
wire self_jump = sys.cpu.id_valid && sys.cpu.redirect && !sys.cpu.stall && !sys.cpu.stop &&
                 sys.cpu.redirect_pc == sys.cpu.id_pc;

longint cycles = 0, steps = 0;
logic [31:0] end_pc;
logic [1:0] end_state = 0;      // 0 running, 1 self-jump seen in ID, 2 the jump finished
integer drain = 0;

// 8 uppercase hex digits, like ref_sim.py (Verilator prints %X in lowercase)
function automatic string hex8(input logic [31:0] value);
    string text = $sformatf("%08h", value);
    return text.toupper();
endfunction

task automatic finish(input string reason);
    if (done) return;           // two ends on the same edge: report the first one
    $display("HALT: %s  (steps=%0d)", reason, steps);
    $fwrite(32'h8000_0002, "mips_sim: %0d cycles, %0d instructions\n", cycles, steps);  // stderr
    if (ppm_file != "") save_ppm();
    done = 1;
endtask

task automatic save_ppm();
    logic [11:0] px;
    fd = $fopen(ppm_file, "w");
    if (fd == 0) $fatal(1, "Can't write %s", ppm_file);
    $fwrite(fd, "P3\n128 96\n15\n");
    for (i = 0; i < 128 * 96; i = i + 1) begin
        px = sys.video.fb.mem[i];
        $fwrite(fd, "%0d %0d %0d\n", px[11:8], px[7:4], px[3:0]);
    end
    $fclose(fd);
endtask

always @(posedge clk) if (!reset && !done) begin
    cycles <= cycles + 1;

    // The write that happens on this edge (the register file writes on posedge)
    if (wb_write) $display("PC=0x%s R%0d <= 0x%s", hex8(wb_pc), wb_dest, hex8(wb_data));
    if (wb_valid) steps = steps + 1;

    // End 1: the self-jump, then its delay slot, finished
    if (end_state == 0 && self_jump) begin
        end_pc = sys.cpu.id_pc;
        end_state = 1;
    end else if (end_state == 1 && wb_valid && wb_pc == end_pc) begin
        end_state = 2;
    end else if (end_state == 2 && wb_valid && wb_pc == end_pc + 4) begin
        finish($sformatf("jumps to itself at 0x%s", hex8(end_pc)));
    end

    // End 2: CPU-14 halt. Older instructions still finish (up to 3 in EX, MEM, WB)
    if (sys.halted) begin
        drain = drain + 1;
        if (drain == 3)
            finish($sformatf("cause %0d (%s) pc 0x%s addr 0x%s", sys.halt_cause,
                   sys.halt_cause == 1 ? "fetch" : sys.halt_cause == 2 ? "load" : "store",
                   hex8(sys.halt_pc), hex8(sys.halt_addr)));
    end

    // End 3: too long
    if (cycles + 1 >= max_cycles)
        finish($sformatf("reached +max-cycles %0d at PC=0x%s", max_cycles, hex8(sys.cpu.id_pc)));
end

endmodule
