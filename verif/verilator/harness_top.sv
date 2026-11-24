// TC-7: Verilator harness. Runs a program on life_system (mips_pipeline + the board's memory map,
// MMIO and video) and prints the same trace as src/tools/ref_sim.py (docs/contracts.md
// "Reference simulator trace"), so the two compare with a plain diff (TC-8, TC-11).
//
// Plusargs (sim_main.cpp passes the command line):
//   +program=<prefix>    e.g. mem/hello_pixels: loads <prefix>_b0..b3.hex into the instruction
//                        banks and <prefix>_data_b0..b3.hex (if they exist) into the data memory
//   +max-cycles=<N>      stop after N clock cycles (default 10,000,000)
//   +ppm=<file>          at the end, save framebuffer A (128x96) as a PPM image
//   CPU-9 (the trace must not change):
//   +stall=<P>           raise mem_stall in P% of the cycles, at random (default 0)
//   +fetch_delay=<N>     external fetches (mips_sim_ext) take 1 to N+1 cycles, at random (default 0)
//   +seed=<S>            seed for both (default 1)
// mips_sim_ext (EXT_START = 1) starts at 0x2000_0000 and fetches every instruction through the
// CPU's external fetch port, from <prefix>.hex in a memory of the harness: assemble the program
// with --text-base 0x20000000.
// mips_sim_sdram (EXT_START = 2, PLT-8/PLT-12/DOOM-6): the real external side, ext_memory (the
// SDRAM bridge, the instruction cache and their arbiter), on a behavioural SDRAM (avalon_sdram.sv).
// It starts at 0x2000_0000; code, data and .bss in the SDRAM, like top_doom after boot.S.
//   +sdram=<file>        word image loaded at SDRAM offset 0 (= 0x2000_0000), e.g.
//                        build/doom/doom_sdram.hex or <name>_sdram.hex from elf2hex.py --sdram
//   +wad=<file>          binary file loaded at SDRAM offset 0x0300_0000 (= 0x2300_0000)
//   +program=<prefix>    optional here: on-chip banks/data, if the program has any
//   +sdram_wait=<P>      waitrequest = 1 in P% of the cycles (default 0)
//   +sdram_extra=<N>     read latency 5 to 5+N cycles (default 0)
//   +stall still adds random mem_stall on top of the bridge's.
// mips_sim_boot (EXT_START = 3, DOOM-7): the same hardware as mips_sim_sdram, but it starts at 0x0
// like top_doom, running the on-chip boot code (+program=mem/doom_boot: waits for KEY0, then jr
// to 0x2000_0000). Press KEY0 with +inputs.
// Inputs (any harness; default SW = 0, no key pressed):
//   +inputs=<file>       lines "<cycle> <SW hex> <KEY0> <KEY1>" (KEYn: 1 = pressed), in cycle
//                        order; from that cycle on, the board inputs have those values.
//                        '#' starts a comment. Keys go through life_system's debounce
//                        (50 cycles here), so hold a key for more than that.
// Video mode B (Doom's frame, DOOM-6), any harness:
//   +ppm_b=<file>        at the end, save framebuffer B (320x200) through the mode B palette
//   +ppm_b_every=<N>     also every N cycles (the same file, overwritten), to watch a long run
//   +notrace             no trace lines (only the HALT line): much faster for long runs (Doom)
//   +snap_pc=<hex>       every time the instruction at this PC finishes (WB), save framebuffer B
//   +snap_prefix=<path>  as <path>_NNN.ppm (default build/verilator/snap), N = 0, 1, ...; skips
//   +snap_skip=<K>       the first K hits (default 0) and ends the run after
//   +snap_max=<N>        N saved frames (default 1). stderr gets "snap N at cycle C" each time.
//                        Doom: snap_pc = doomgeneric_Tick: on its entry the previous frame is
//                        complete, palette included (DG_DrawFrame writes the palette).
//
// Trace, one line per register write, in program order (they happen in WB):
//   PC=0x00000050 R2 <= 0x00000000
//   PC=0x00000060 HI <= 0x00000000     mult multu div divu print HI then LO, mthi/mtlo one line
// HI/LO lines go out when the instruction reaches WB, in its place. A divide takes 32 cycles
// more while the pipeline keeps going, so its lines wait in a queue (and the lines after it)
// until the divider is done. Divide by zero prints nothing, like ref_sim.py (the hardware
// still writes HI/LO, see mult_div.v).
// The last line says why the run ended, like ref_sim.py:
//   HALT: jumps to itself at 0x00000040  (steps=87016)
//   HALT: cause 2 (load) pc 0x... addr 0x...  (steps=N)
//   HALT: reached +max-cycles N at PC=0x...  (steps=N)
// steps = instructions that finished (nops too, bubbles not), the same count as ref_sim.py.
// Cycles go to stderr, so stdout is only the trace.
module harness_top #(
    parameter EXT_START = 0   // 1 = mips_sim_ext: run from 0x2000_0000 through the external fetch port
                              // 2 = mips_sim_sdram: from 0x2000_0000 through ext_memory + avalon_sdram
                              // 3 = mips_sim_boot: the same, from 0x0 (boot code on chip, like top_doom)
)(
    input clk,
    input reset,
    output logic done = 0   // the run ended; sim_main.cpp stops (no $finish: its message would go to stdout)
);

localparam [31:0] EXT_BASE = 32'h2000_0000;
localparam EXT_WORDS = 65536;             // 256 KB of external text for the tests

localparam SDRAM = EXT_START >= 2;
logic ext_stall;
logic rand_stall = 0;
logic [31:0] ifetch_addr, ifetch_data, ifetch_next;
logic ifetch_req, ifetch_ready;
logic [31:0] bus_addr, bus_wdata, ext_rdata;
logic [3:0] bus_be;
logic bus_we, bus_re, ext_sel;
logic [9:0] sw = 0;
logic [1:0] key = 0;                      // 1 = pressed (the board's KEY pins are active-low)

life_system #(.MODE_B(1), .DEBOUNCE_CYCLES(50), .EXT_BUS(1),
              .RESET_PC((EXT_START == 1 || EXT_START == 2) ? EXT_BASE : 32'h0)) sys (
    .clk(clk), .reset(reset), .SW(sw), .KEY(~key), .LEDR(),
    .HEX0(), .HEX1(), .HEX2(), .HEX3(), .HEX4(), .HEX5(),
    .VGA_R(), .VGA_G(), .VGA_B(), .VGA_HS(), .VGA_VS(),
    .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we), .bus_re(bus_re), .bus_be(bus_be),
    .ext_sel(ext_sel), .ext_rdata(SDRAM ? ext_rdata : 32'd0), .ext_stall(ext_stall),
    .ifetch_addr(ifetch_addr), .ifetch_req(ifetch_req), .ifetch_next(ifetch_next),
    .ifetch_data(SDRAM ? cache_data : port_data), .ifetch_ready(SDRAM ? cache_ready : port_ready)
);

// ---- EXT_START = 2: ext_memory on the behavioural SDRAM ----
logic [31:0] cache_data, port_data;
logic cache_ready, port_ready, bridge_stall;
logic [25:0] avm_address;
logic avm_read, avm_write, avm_readdatavalid, avm_waitrequest;
logic [31:0] avm_writedata, avm_readdata;
logic [3:0] avm_byteenable;
int sdram_wait = 0, sdram_extra = 0;
assign ext_stall = (SDRAM && bridge_stall) || rand_stall;

ext_memory xm (
    .clk(clk), .reset(reset),
    .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_be(bus_be), .bus_re(bus_re), .bus_we(bus_we),
    .ext_sel(ext_sel && SDRAM), .ext_rdata(ext_rdata), .ext_stall(bridge_stall),
    .ifetch_addr(ifetch_addr), .ifetch_req(ifetch_req && SDRAM), .ifetch_next(ifetch_next),
    .ifetch_data(cache_data), .ifetch_ready(cache_ready),
    .avm_address(avm_address), .avm_read(avm_read), .avm_write(avm_write),
    .avm_writedata(avm_writedata), .avm_byteenable(avm_byteenable),
    .avm_readdata(avm_readdata), .avm_readdatavalid(avm_readdatavalid),
    .avm_waitrequest(avm_waitrequest)
);

avalon_sdram ram (
    .clk(clk), .address(avm_address), .read(avm_read), .write(avm_write),
    .writedata(avm_writedata), .byteenable(avm_byteenable),
    .readdata(avm_readdata), .readdatavalid(avm_readdatavalid), .waitrequest(avm_waitrequest),
    .wait_pct(sdram_wait), .extra(sdram_extra)
);

// ---- CPU-9: random waits ----
int stall_pct = 0, fetch_delay = 0, seed = 1;
logic [31:0] ext_text [0:EXT_WORDS-1];
logic [31:0] fetch_last = 32'hFFFF_FFFF;
int fetch_count = 0;
// Ready once the address has stayed the same for its random delay; stays ready while it does
assign port_ready = ifetch_req && ifetch_addr == fetch_last && fetch_count == 0;
assign port_data = ext_text[ifetch_addr[17:2]];
always @(posedge clk) begin
    rand_stall <= stall_pct > 0 && ($urandom % 100) < stall_pct;
    if (!ifetch_req || ifetch_addr != fetch_last) begin
        fetch_last <= ifetch_req ? ifetch_addr : 32'hFFFF_FFFF;
        fetch_count <= fetch_delay > 0 ? $urandom % (fetch_delay + 1) : 0;
    end else if (fetch_count > 0)
        fetch_count <= fetch_count - 1;
end

// ---- loading: once, on the first clock edge in reset ----
// (not in an initial block: data_memory's own initial zeroes its RAM, and the order of
// initial blocks between modules is not defined, so it could erase the .data image)
string program_prefix, ppm_file, sdram_file, wad_file, ppm_b_file, inputs_file, snap_prefix;
logic [31:0] snap_pc = 32'hFFFF_FFFF;
int snap_skip = 0, snap_max = 1, snap_hits = 0, snap_saved = 0;

// ---- inputs: a schedule of SW/KEY values ----
typedef struct { longint cycle; logic [9:0] sw; logic [1:0] key; } input_t;
input_t input_q[$];
task automatic load_inputs();
    int ifd, n;
    string line;
    input_t v;
    longint c;
    int sw_v, k0, k1;
    ifd = $fopen(inputs_file, "r");
    if (ifd == 0) $fatal(1, "Can't open %s", inputs_file);
    while ($fgets(line, ifd) > 0) begin
        if (line.len() == 0 || line.getc(0) == "#") continue;
        n = $sscanf(line, "%d %h %d %d", c, sw_v, k0, k1);
        if (n == 4) begin
            v.cycle = c; v.sw = sw_v[9:0]; v.key = {k1[0], k0[0]};
            input_q.push_back(v);
        end
    end
    $fclose(ifd);
    $fwrite(32'h8000_0002, "inputs: %0d changes from %s\n", input_q.size(), inputs_file);
endtask
longint ppm_b_every = 0;
bit trace_on = 1;
longint max_cycles = 10_000_000;
bit loaded = 0;
integer fd, i;

initial begin
    if (!$value$plusargs("program=%s", program_prefix)) begin
        program_prefix = "";
        if (!SDRAM) $fatal(1, "Usage: mips_sim +program=mem/<name> [+max-cycles=N] [+ppm=file.ppm]");
    end
    if (!$value$plusargs("sdram=%s", sdram_file)) sdram_file = "";
    if (!$value$plusargs("wad=%s", wad_file)) wad_file = "";
    if (SDRAM && sdram_file == "") $fatal(1, "Usage: mips_sim_sdram +sdram=<name>_sdram.hex [+wad=file] [+program=prefix]");
    if (EXT_START == 3 && program_prefix == "") $fatal(1, "Usage: mips_sim_boot +program=mem/doom_boot +sdram=... [+wad=...] +inputs=...");
    if ($value$plusargs("inputs=%s", inputs_file)) load_inputs();
    if (!$value$plusargs("snap_prefix=%s", snap_prefix)) snap_prefix = "build/verilator/snap";
    void'($value$plusargs("snap_pc=%h", snap_pc));
    void'($value$plusargs("snap_skip=%d", snap_skip));
    void'($value$plusargs("snap_max=%d", snap_max));
    void'($value$plusargs("sdram_wait=%d", sdram_wait));
    void'($value$plusargs("sdram_extra=%d", sdram_extra));
    void'($value$plusargs("max-cycles=%d", max_cycles));
    if (!$value$plusargs("ppm=%s", ppm_file)) ppm_file = "";
    if (!$value$plusargs("ppm_b=%s", ppm_b_file)) ppm_b_file = "";
    void'($value$plusargs("ppm_b_every=%d", ppm_b_every));
    trace_on = !$test$plusargs("notrace");
    void'($value$plusargs("stall=%d", stall_pct));
    void'($value$plusargs("fetch_delay=%d", fetch_delay));
    void'($value$plusargs("seed=%d", seed));
    void'($urandom(seed));
end

task automatic load_banks();
    if (SDRAM) begin
        ram.load_words(sdram_file, 0);
        if (wad_file != "") ram.load_bin(wad_file, 32'h0300_0000);
        if (program_prefix == "") begin
            for (i = 0; i < 32; i = i + 1)
                if (i != 29) sys.cpu.rf.registers[i] = 32'd0;
            return;
        end
    end
    fd = $fopen({program_prefix, "_b0.hex"}, "r");
    if (fd == 0) $fatal(1, "Can't open %s_b0.hex (build it with the assembler or make -C src/c)", program_prefix);
    $fclose(fd);
    $readmemh({program_prefix, "_b0.hex"}, sys.cpu.if_id.im.bank0);
    $readmemh({program_prefix, "_b1.hex"}, sys.cpu.if_id.im.bank1);
    $readmemh({program_prefix, "_b2.hex"}, sys.cpu.if_id.im.bank2);
    $readmemh({program_prefix, "_b3.hex"}, sys.cpu.if_id.im.bank3);
    if (EXT_START == 1) begin
        for (i = 0; i < EXT_WORDS; i = i + 1) ext_text[i] = 32'd0;
        $readmemh({program_prefix, ".hex"}, ext_text);
    end
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

// A branch/jump in ID that really redirects (IF/ID advances: not stalled, so its operands
// are current, and its delay slot is fetched) to its own address: the program's "end: j end".
// ref_sim.py stops after its delay slot.
wire self_jump = sys.cpu.id_valid && sys.cpu.redirect && sys.cpu.if_id_enable &&
                 sys.cpu.redirect_pc == sys.cpu.id_pc;

longint cycles = 0, steps = 0;
// EXT_START = 2: what the external side cost (stderr at the end)
longint cache_misses = 0, sdram_loads = 0, sdram_stores = 0, fetch_wait_cycles = 0, data_wait_cycles = 0;
always @(posedge clk) if (SDRAM && !reset && !done) begin
    if (xm.cache.state == 2'd1 && xm.cache.req && !xm.cache.hit) cache_misses <= cache_misses + 1;
    if (xm.bridge.state == 2'd3 && xm.bridge.was_read) sdram_loads <= sdram_loads + 1;
    if (xm.bridge.state == 2'd3 && !xm.bridge.was_read) sdram_stores <= sdram_stores + 1;
    if (ifetch_req && !cache_ready && !bridge_stall) fetch_wait_cycles <= fetch_wait_cycles + 1;
    if (bridge_stall) data_wait_cycles <= data_wait_cycles + 1;
end
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
    if (SDRAM)
        $fwrite(32'h8000_0002, "ext_memory: %0d cache misses, %0d SDRAM loads, %0d stores; cycles waiting: %0d fetch, %0d data\n",
                cache_misses, sdram_loads, sdram_stores, fetch_wait_cycles, data_wait_cycles);
    if (ppm_file != "") save_ppm();
    if (ppm_b_file != "") save_ppm_b();
    done = 1;
endtask

// Framebuffer B: pixel 4n+k in bank k, word n; palette entries are {R, G, B}, 4 bits each
task automatic save_ppm_b();
    write_ppm_b(ppm_b_file);
endtask
task automatic write_ppm_b(input string file);
    logic [7:0] index;
    logic [11:0] color;
    fd = $fopen(file, "w");
    if (fd == 0) $fatal(1, "Can't write %s", file);
    $fwrite(fd, "P3\n320 200\n15\n");
    for (i = 0; i < 320 * 200; i = i + 1) begin
        case (i % 4)
            0: index = sys.mode_b.video_b.fb.bank0[i / 4];
            1: index = sys.mode_b.video_b.fb.bank1[i / 4];
            2: index = sys.mode_b.video_b.fb.bank2[i / 4];
            default: index = sys.mode_b.video_b.fb.bank3[i / 4];
        endcase
        color = sys.mode_b.video_b.pal.mem[index];
        $fwrite(fd, "%0d %0d %0d\n", color[11:8], color[7:4], color[3:0]);
    end
    $fclose(fd);
endtask
always @(posedge clk)
    if (ppm_b_file != "" && ppm_b_every > 0 && cycles > 0 && cycles % ppm_b_every == 0) save_ppm_b();

// +snap_pc: a frame each time the instruction at snap_pc finishes
always @(posedge clk) if (!reset && !done && wb_valid && wb_pc == snap_pc) begin
    snap_hits = snap_hits + 1;
    if (snap_hits > snap_skip) begin
        write_ppm_b($sformatf("%s_%03d.ppm", snap_prefix, snap_saved));
        $fwrite(32'h8000_0002, "snap %0d at cycle %0d (%0d instructions)\n", snap_saved, cycles, steps);
        snap_saved = snap_saved + 1;
        if (snap_saved >= snap_max) finish($sformatf("saved %0d snapshots at 0x%s", snap_saved, hex8(snap_pc)));
    end
end

// +inputs: apply each change from its cycle on
always @(posedge clk)
    while (input_q.size() > 0 && input_q[0].cycle <= cycles) begin
        sw <= input_q[0].sw;
        key <= input_q[0].key;
        void'(input_q.pop_front());
    end

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
    if (md_wb.valid && !end_pending && trace_on) begin
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
    if (wb_write && !end_pending && trace_on)
        out_q.push_back($sformatf("PC=0x%s R%0d <= 0x%s", hex8(wb_pc), wb_dest, hex8(wb_data)));
    if (wb_valid && !end_pending) steps = steps + 1;
    flush();
    if (end_pending && hole() < 0) finish_now();

    // Move the HI/LO trackers along with EX/MEM and MEM/WB. CPU-9: while mem_stall holds,
    // EX/MEM keeps its instruction and WB gets a bubble.
    if (sys.cpu.mem_stall) begin
        md_wb.valid = 0;
    end else begin
        md_wb = md_mem;
        md_wb.valid = md_mem.valid && !sys.cpu.access_fault;
        if (md_mem.valid) begin             // in MEM now: HI/LO already hold its result
            md_wb.hi = sys.cpu.hi;
            md_wb.lo = sys.cpu.lo;
        end
        md_mem.valid = sys.cpu.ex_valid && !sys.cpu.access_fault && writes_hilo(sys.cpu.ex_md_op);
        md_mem.op = sys.cpu.ex_md_op;
        md_mem.pc = sys.cpu.ex_pc;
        md_mem.div_by_zero = sys.cpu.ex_b == 32'd0;
    end

    // End 1: the self-jump, then its delay slot, finished
    if (end_state == 0 && self_jump) begin
        end_pc = sys.cpu.id_pc;
        end_state = 1;
    end else if (end_state == 1 && wb_valid && wb_pc == end_pc) begin
        end_state = 2;
    end else if (end_state == 2 && wb_valid && wb_pc == end_pc + 4) begin
        finish($sformatf("jumps to itself at 0x%s", hex8(end_pc)));
    end

    // End 2: CPU-14 halt. Older instructions still finish: wait until EX, MEM and WB are
    // empty (CPU-9: mem_stall can make that take longer than 3 cycles)
    if (sys.halted && !sys.cpu.ex_valid && !sys.cpu.mem_valid && !wb_valid) begin
        drain = drain + 1;
        if (drain == 1)
            finish($sformatf("cause %0d (%s) pc 0x%s addr 0x%s", sys.halt_cause,
                   sys.halt_cause == 1 ? "fetch" : sys.halt_cause == 2 ? "load" : "store",
                   hex8(sys.halt_pc), hex8(sys.halt_addr)));
    end

    // End 3: too long
    if (cycles + 1 >= max_cycles)
        finish($sformatf("reached +max-cycles %0d at PC=0x%s", max_cycles, hex8(sys.cpu.id_pc)));
end

endmodule
