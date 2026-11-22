`timescale 1ns/1ps
// Run a self-checking program (TC-4, TC-5) on mips_pipeline and observe its LEDR/HEX
// pass protocol: LEDR = 0x3FF, then HEX = 0x00600D. Also reports cycles and stalls.
// Usage: vsim -c work.pipeline_program_tb +program=../mem/<name>.hex -do "run -all"
module pipeline_program_tb;
reg clk = 0, reset = 1;
reg [1023:0] program_file;
reg [31:0] program_words [0:4095];
wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire mem_we, mem_re;
wire halted;
wire [1:0] halt_cause;
wire [31:0] halt_pc, halt_addr;
reg [31:0] leds = 0;
integer i, cycles = 0, stalls = 0;
mips_pipeline dut(.clk(clk), .reset(reset), .mem_addr(mem_addr), .dbg_sel(5'd0), .dbg_value(),
    .mem_wdata(mem_wdata), .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata), .mem_fault(1'b0),
    .halted(halted), .halt_cause(halt_cause), .halt_pc(halt_pc), .halt_addr(halt_addr));
data_memory dm(.clk(clk), .MemRead(mem_re), .MemWrite(mem_we),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(mem_rdata));
always #5 clk = ~clk;
initial begin
    if (!$value$plusargs("program=%s", program_file)) $fatal(1, "Missing +program=path.hex");
    #1;
    for (i = 0; i < 32; i = i + 1) dut.rf.registers[i] = 0;
    // The program is the assembler's word image; load it word by word into the 4 byte banks.
    for (i = 0; i < 4096; i = i + 1) program_words[i] = 0;
    $readmemh(program_file, program_words);
    for (i = 0; i < 4096; i = i + 1) dut.if_id.im.write_word(i, program_words[i]);
    @(posedge clk); #1; reset = 0;
end
always @(posedge clk) if (!reset) begin
    // CPU-14: an invalid or misaligned access stops the CPU; report it instead of a timeout.
    if (halted) $fatal(1, "FAIL: CPU halted, cause %0d at PC %h, address %h", halt_cause, halt_pc, halt_addr);
    cycles <= cycles + 1;
    if (dut.stall) stalls <= stalls + 1;
end
always @(negedge clk) begin
    if (mem_we && mem_addr == 32'hffff0018) leds <= mem_wdata;
    if (mem_we && mem_addr == 32'hffff001c) begin
        if (mem_wdata !== 32'h0000600d || leds !== 32'h000003ff)
            $fatal(1, "FAIL: HEX=%h LEDR=%h PC=%h", mem_wdata, leds, dut.id_pc);
        $display("PASS: %0s in %0d cycles (%0d stalls)", program_file, cycles, stalls);
        $finish;
    end
end
initial begin #100000; $fatal(1, "timeout"); end
endmodule
