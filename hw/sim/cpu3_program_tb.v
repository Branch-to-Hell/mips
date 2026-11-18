`timescale 1ns/1ps
// Execute the team's TC-4 programs and observe their LEDR/HEX pass protocol.
module cpu3_program_tb;
reg clk = 0, reset = 1;
reg [1023:0] program_file;
wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire mem_we, mem_re;
reg [31:0] leds = 0;
integer i;
mips_cpu dut(.clk(clk), .reset(reset), .mem_addr(mem_addr),
    .mem_wdata(mem_wdata), .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata));
data_memory dm(.clk(clk), .MemRead(mem_re), .MemWrite(mem_we),
    .Address(mem_addr), .WriteData(mem_wdata), .ReadData(mem_rdata));
always #5 clk = ~clk;
initial begin
    if (!$value$plusargs("program=%s", program_file)) $fatal(1, "Missing +program=path.hex");
    #1;
    for (i = 0; i < 32; i = i + 1) dut.rf.registers[i] = 0;
    for (i = 0; i < 4096; i = i + 1) dut.im.mem[i] = 0;
    $readmemh(program_file, dut.im.mem);
    @(posedge clk); #1; reset = 0;
end
always @(negedge clk) begin
    if (mem_we && mem_addr == 32'hffff0018) leds <= mem_wdata;
    if (mem_we && mem_addr == 32'hffff001c) begin
        if (mem_wdata !== 32'h0000600d || leds !== 32'h000003ff)
            $fatal(1, "TC-4 failure: HEX=%h LEDR=%h PC=%h", mem_wdata, leds, dut.PC_out);
        $display("PASS: TC-4 program %0s", program_file);
        $finish;
    end
end
initial begin #100000; $fatal(1, "TC-4 timeout"); end
endmodule
