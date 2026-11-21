`timescale 1ns/1ps
// CPU-7/CPU-8: run a self-checking program on mips_pipeline with a byte-lane memory.
// Same pass protocol as pipeline_program_tb: LEDR = 0x3FF, then HEX = 0x00600D.
// On a failure the program writes HEX = 0xBAD0nn, nn = the test number.
// The memory honours mem_be (big-endian lanes, mem_be[3] = bits 31..24), which
// data_memory does not do yet, and the testbench checks every store on the bus:
// mem_be must be a legal pattern for the address, and the written lanes of
// mem_wdata must hold the byte/half the CPU stores.
// Programs: sw/programs/cpu7_isa.s and cpu8_muldiv.s, assembled with
// sw/tools/gas_image.sh (GNU as) into hw/mem/<name>.hex.
// Usage: vsim -c work.cpu7_tb +program=../mem/cpu7_isa.hex -do "run -all"  (or: do cpu7.do)
module cpu7_tb;
reg clk = 0, reset = 1;
reg [1023:0] program_file;
reg [31:0] program_words [0:4095];
wire [31:0] mem_addr, mem_wdata;
reg [31:0] mem_rdata;
wire [3:0] mem_be;
wire mem_we, mem_re;
wire halted;
wire [1:0] halt_cause;
wire [31:0] halt_pc, halt_addr;
reg [31:0] leds = 0;
integer i, cycles = 0, stalls = 0, stores = 0, sub_word_stores = 0;

// Data region 0x1001_0000 - 0x1001_3FFF (16 KB) and the MMIO page; anything else faults.
wire in_data = (mem_addr[31:14] == 18'h0400_4);
wire in_mmio = (mem_addr[31:8] == 24'hFFFF00);
wire mem_fault = !(in_data || in_mmio);
reg [31:0] data [0:4095];

mips_pipeline dut(.clk(clk), .reset(reset), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_be(mem_be), .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata),
    .dbg_sel(5'd0), .dbg_value(), .mem_fault(mem_fault), .halted(halted),
    .halt_cause(halt_cause), .halt_pc(halt_pc), .halt_addr(halt_addr));
always #5 clk = ~clk;

// Memory with byte enables: read and write on negedge, like data_memory.
wire [11:0] word = mem_addr[13:2];
always @(negedge clk) begin
    mem_rdata <= 32'd0;
    if (in_data) begin
        if (mem_we) begin
            if (mem_be[3]) data[word][31:24] <= mem_wdata[31:24];
            if (mem_be[2]) data[word][23:16] <= mem_wdata[23:16];
            if (mem_be[1]) data[word][15:8]  <= mem_wdata[15:8];
            if (mem_be[0]) data[word][7:0]   <= mem_wdata[7:0];
        end
        if (mem_re) mem_rdata <= data[word];
    end
end

// Bus checks on every store: a legal mem_be for the address, and replicated data.
always @(negedge clk) if (mem_we) begin
    stores = stores + 1;
    case (mem_be)
        4'b1111: if (mem_addr[1:0] != 2'b00) $fatal(1, "FAIL: sw with be=1111 at %h", mem_addr);
        4'b1100, 4'b0011: begin
            sub_word_stores = sub_word_stores + 1;
            if (mem_be != (mem_addr[1] ? 4'b0011 : 4'b1100) || mem_addr[0])
                $fatal(1, "FAIL: sh with be=%b at %h", mem_be, mem_addr);
            if (mem_wdata[31:16] !== mem_wdata[15:0])
                $fatal(1, "FAIL: sh data %h is not replicated", mem_wdata);
        end
        4'b1000, 4'b0100, 4'b0010, 4'b0001: begin
            sub_word_stores = sub_word_stores + 1;
            if (mem_be != (4'b1000 >> mem_addr[1:0]))
                $fatal(1, "FAIL: sb with be=%b at %h", mem_be, mem_addr);
            if (mem_wdata !== {4{mem_wdata[7:0]}})
                $fatal(1, "FAIL: sb data %h is not replicated", mem_wdata);
        end
        default: $fatal(1, "FAIL: illegal mem_be %b at %h", mem_be, mem_addr);
    endcase
end

initial begin
    if (!$value$plusargs("program=%s", program_file)) $fatal(1, "Missing +program=path.hex");
    #1;
    for (i = 0; i < 32; i = i + 1) dut.rf.registers[i] = 0;
    for (i = 0; i < 4096; i = i + 1) data[i] = 32'h0;
    for (i = 0; i < 4096; i = i + 1) program_words[i] = 0;
    $readmemh(program_file, program_words);
    for (i = 0; i < 4096; i = i + 1) dut.if_id.im.write_word(i, program_words[i]);
    @(posedge clk); #1; reset = 0;
end

always @(posedge clk) if (!reset) begin
    cycles <= cycles + 1;
    if (dut.stall) stalls <= stalls + 1;
    if (halted) $fatal(1, "FAIL: halted, cause %0d at PC %h, address %h", halt_cause, halt_pc, halt_addr);
end

always @(negedge clk) begin
    if (mem_we && mem_addr == 32'hffff0018) leds <= mem_wdata;
    if (mem_we && mem_addr == 32'hffff001c) begin
        if (mem_wdata !== 32'h0000600d || leds !== 32'h000003ff)
            $fatal(1, "FAIL: %0s test %0d (HEX=%h LEDR=%h)", program_file, mem_wdata[7:0], mem_wdata, leds);
        $display("PASS: %0s in %0d cycles (%0d stalls, %0d stores, %0d byte/half)",
                 program_file, cycles, stalls, stores, sub_word_stores);
        $finish;
    end
end
initial begin #200000; $fatal(1, "FAIL: timeout"); end
endmodule
