`timescale 1ns/1ns
// TC-12: run any assembled program on life_system (the board hardware) and dump its final state.
// Driven by sw/tools/drill.py; by hand, from hw/sim:
//   vsim -c -GPROGRAM="<name>" -GWITH_DATA=1 work.drill_tb +out=drill_<name>.txt -do "run -all; quit -f"
/* Runs until the program reaches a self-jump (j to itself: the end of every drill program),
the CPU halts (CPU-14), or MAX_CYCLES pass. Then writes to the +out file:
    end <selfjump|halt|timeout> cycles <n> pc <hex>
    halt <cause> <pc> <addr>
    reg <0..31> <hex>
    mem <address> <hex>     (DATA_WORDS words from 0x10010000)
*/
module drill_tb;
parameter PROGRAM = "test_halt";
parameter WITH_DATA = 0;
parameter MAX_CYCLES = 2_000_000;
parameter DATA_WORDS = 64;

reg clk = 0, reset = 1;
reg [9:0] SW = 0;
reg [1:0] KEY = 2'b11;
wire [9:0] LEDR;
wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
wire [3:0] VGA_R, VGA_G, VGA_B;
wire VGA_HS, VGA_VS;

life_system #(.IMEM_INIT({"../mem/", PROGRAM}),
              .DMEM_INIT(WITH_DATA ? {"../mem/", PROGRAM, "_data.hex"} : ""),
              .DEBOUNCE_CYCLES(50)) sys (
    .clk(clk), .reset(reset), .SW(SW), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

always #20 clk = ~clk;                 // 25 MHz

wire [31:0] id_pc = sys.cpu.id_pc, id_instr = sys.cpu.id_instruction;
wire at_end = sys.cpu.id_valid && id_instr[31:26] == 6'h02 &&
              {id_pc[31:28], id_instr[25:0], 2'b00} == id_pc;

integer i, n, f;
reg [1023:0] out_file;

initial begin
    if (!$value$plusargs("out=%s", out_file)) out_file = "drill_result.txt";
    for (i = 0; i < 32; i = i + 1) sys.cpu.rf.registers[i] = 0;  // like the FPGA after power-up
    repeat (4) @(posedge clk);
    @(negedge clk) reset = 0;

    n = 0;
    while (!at_end && !sys.halted && n < MAX_CYCLES) begin @(posedge clk); n = n + 1; end
    repeat (8) @(posedge clk);         // let the older instructions finish their writes

    f = $fopen(out_file, "w");
    $fdisplay(f, "end %0s cycles %0d pc %h", sys.halted ? "halt" : (at_end ? "selfjump" : "timeout"), n, id_pc);
    $fdisplay(f, "halt %0d %h %h", sys.halt_cause, sys.halt_pc, sys.halt_addr);
    for (i = 0; i < 32; i = i + 1) $fdisplay(f, "reg %0d %h", i, sys.cpu.rf.registers[i]);
    for (i = 0; i < DATA_WORDS; i = i + 1) $fdisplay(f, "mem %h %h", 32'h1001_0000 + 4 * i, sys.dm.mem[i]);
    $fclose(f);
    $display("DRILL %0s: %0s after %0d cycles", PROGRAM, sys.halted ? "halt" : (at_end ? "selfjump" : "timeout"), n);
    $finish;
end
endmodule
