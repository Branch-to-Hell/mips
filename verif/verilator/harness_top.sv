// TC-7: Verilator harness. Runs a program on life_system (mips_pipeline + the board's memory map,
// MMIO and video) and prints the same trace as src/tools/ref_sim.py (docs/contracts.md
// "Reference simulator trace"), so the two compare with a plain diff (TC-8, TC-11).
//
// Plusargs (sim_main.cpp passes the command line):
//   +program=<prefix>    e.g. mem/hello_pixels: loads <prefix>_b0..b3.hex into the instruction
//                        banks and <prefix>_data_b0..b3.hex (if they exist) into the data memory
//   +max-cycles=<N>      stop after N clock cycles (default 10,000,000)
//   +ppm=<file>          at the end, save framebuffer A (128x96) as a PPM image
//
// Trace, one line per register write, in program order (they happen in WB):
//   PC=0x00000050 R2 <= 0x00000000
//   PC=0x00000060 HI <= 0x00000000     mult multu div divu print HI then LO, mthi/mtlo one line
// HI/LO lines go out when the instruction reaches WB, in its place. A divide takes 32 cycles
// more while the pipeline keeps going, so its lines wait in a queue (and the lines after it)
// until the divider is done. Divide by zero prints nothing, like ref_sim.py (the hardware
// still writes HI/LO, see mult_div.v).
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
    fd = $fopen({program_prefix, "_data_b0.hex"}, "r");
    if (fd != 0) begin
        $fclose(fd);
        $readmemh({program_prefix, "_data_b0.hex"}, sys.dm.bank0);
        $readmemh({program_prefix, "_data_b1.hex"}, sys.dm.bank1);
        $readmemh({program_prefix, "_data_b2.hex"}, sys.dm.bank2);
        $readmemh({program_prefix, "_data_b3.hex"}, sys.dm.bank3);
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

// ---- output queue: lines in program order; "?<PC>" = a divide whose HI/LO are not ready ----
string out_q[$];
bit end_pending = 0;            // the run ended; waiting for a divide to fill its lines
string end_reason;

function automatic bit is_hole(input string line);
    return line.len() > 0 && line.getc(0) == "?";
endfunction

task automatic flush();
    while (out_q.size() > 0 && !is_hole(out_q[0])) $display("%s", out_q.pop_front());
endtask

function automatic int hole();
    for (int k = 0; k < out_q.size(); k++) if (is_hole(out_q[k])) return k;
    return -1;
endfunction

task automatic finish(input string reason);
    if (done || end_pending) return;    // two ends on the same edge: report the first one
    end_reason = reason;
    end_pending = 1;
    if (hole() < 0) finish_now();
endtask

task automatic finish_now();
    flush();
    $display("HALT: %s  (steps=%0d)", end_reason, steps);
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

// ---- HI/LO (CPU-8): follow each HI/LO-writing instruction from EX to WB ----
localparam [3:0] MTHI = 4'd3, MTLO = 4'd4, MULT = 4'd8, MULTU = 4'd9, DIV = 4'd10, DIVU = 4'd11;
function automatic bit writes_hilo(input logic [3:0] op);
    return op == MTHI || op == MTLO || op == MULT || op == MULTU || op == DIV || op == DIVU;
endfunction
typedef struct packed {
    logic valid;
    logic [3:0] op;
    logic div_by_zero;
    logic [31:0] pc, hi, lo;    // hi/lo: the values it wrote (taken while it is in MEM)
} md_t;
md_t md_mem = '0, md_wb = '0;
bit div_ending = 0;             // the divider writes HI/LO on this edge: read them next cycle

always @(posedge clk) if (!reset && !done) begin
    cycles <= cycles + 1;

    // HI/LO lines of the instruction in WB, in its place (it writes no register)
    if (md_wb.valid && !end_pending) begin
        if (md_wb.op == MTHI)
            out_q.push_back($sformatf("PC=0x%s HI <= 0x%s", hex8(md_wb.pc), hex8(md_wb.hi)));
        else if (md_wb.op == MTLO)
            out_q.push_back($sformatf("PC=0x%s LO <= 0x%s", hex8(md_wb.pc), hex8(md_wb.lo)));
        else if (md_wb.op == MULT || md_wb.op == MULTU) begin
            out_q.push_back($sformatf("PC=0x%s HI <= 0x%s", hex8(md_wb.pc), hex8(md_wb.hi)));
            out_q.push_back($sformatf("PC=0x%s LO <= 0x%s", hex8(md_wb.pc), hex8(md_wb.lo)));
        end else if (!md_wb.div_by_zero) begin
            out_q.push_back({"?", hex8(md_wb.pc)});     // its place, until the divider is done
        end
    end
    // A divide finished on the last edge: fill its place
    if (div_ending) begin
        int k = hole();
        if (k >= 0) begin
            string pc_text = out_q[k].substr(1, 8);
            out_q[k] = $sformatf("PC=0x%s HI <= 0x%s", pc_text, hex8(sys.cpu.hi));
            out_q.insert(k + 1, $sformatf("PC=0x%s LO <= 0x%s", pc_text, hex8(sys.cpu.lo)));
        end
        div_ending = 0;
    end
    if (sys.cpu.md.count == 6'd1) div_ending = 1;

    // The register write that happens on this edge (the register file writes on posedge)
    if (wb_write && !end_pending)
        out_q.push_back($sformatf("PC=0x%s R%0d <= 0x%s", hex8(wb_pc), wb_dest, hex8(wb_data)));
    if (wb_valid && !end_pending) steps = steps + 1;
    flush();
    if (end_pending && hole() < 0) finish_now();

    // Move the HI/LO trackers along with EX/MEM and MEM/WB (both always enabled)
    md_wb = md_mem;
    md_wb.valid = md_mem.valid && !sys.cpu.access_fault;
    if (md_mem.valid) begin                 // in MEM now: HI/LO already hold its result
        md_wb.hi = sys.cpu.hi;
        md_wb.lo = sys.cpu.lo;
    end
    md_mem.valid = sys.cpu.ex_valid && !sys.cpu.access_fault && writes_hilo(sys.cpu.ex_md_op);
    md_mem.op = sys.cpu.ex_md_op;
    md_mem.pc = sys.cpu.ex_pc;
    md_mem.div_by_zero = sys.cpu.ex_b == 32'd0;

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
