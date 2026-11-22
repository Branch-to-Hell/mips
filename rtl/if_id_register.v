module if_id_register #(
    parameter IMEM_INIT = ""
)(
    input clk, reset, enable, flush,
    input [31:0] fetch_pc,
    output reg [31:0] pc,
    output [31:0] instruction,
    output reg valid,
    // CPU-9: fetch_pc is in the external text region; the word is ext_instruction
    // (from the instruction cache), taken on the same edge as the PC
    input fetch_ext,
    input [31:0] ext_instruction
);
wire [31:0] ram_instruction;
// Hold without a RAM enable: while enable=0 the RAM re-reads the address of the
// instruction already in ID (pc), so its output stays the same word. This keeps
// instruction_memory's interface shared with the single-cycle mips_cpu.
// During reset/flush the RAM may read anything: valid=0 masks it.
instruction_memory #(.INIT_FILE(IMEM_INIT)) im(
    .clk(clk), .Address(enable ? fetch_pc : pc), .Instruction(ram_instruction)
);
reg from_ext = 1'b0;          // the instruction in ID came from the external port
reg [31:0] ext_q = 32'd0;     // and this is it (held like pc while enable = 0)
assign instruction = !valid ? 32'd0 : from_ext ? ext_q : ram_instruction;
always @(posedge clk) begin
    if (reset || flush) begin
        pc <= 32'd0;
        valid <= 1'b0;
        from_ext <= 1'b0;
    end else if (enable) begin
        pc <= fetch_pc;
        valid <= 1'b1;
        from_ext <= fetch_ext;
        ext_q <= ext_instruction;
    end
end
endmodule
// IF/ID: 65 stored bits = instruction[31:0] + pc[31:0] + valid.
// The synchronous instruction RAM output IS the 32-bit instruction register.
// Do not latch it again: that would add a sixth pipeline stage and misalign PC.
// Update: posedge; RAM reads fetch_pc while pc captures that SAME address.
// Enable=0 holds RAM output (by re-reading pc), pc and valid; no clock gating.
// Priority: synchronous reset > flush > enable > hold.
// Reset/flush clears pc and valid. RAM output has no reset to preserve M9K
// inference; instruction is masked to zero while invalid (raw bits are ignored).
// Valid=1 means pc/instruction describe a fetched instruction, including a NOP.