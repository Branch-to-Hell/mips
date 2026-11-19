module if_id_register #(
    parameter IMEM_INIT = ""
)(
    input clk, reset, enable, flush,
    input [31:0] fetch_pc,
    output reg [31:0] pc,
    output [31:0] instruction,
    output reg valid
);
wire [31:0] ram_instruction;
instruction_memory #(.INIT_FILE(IMEM_INIT)) im(
    .clk(clk), .enable(enable && !reset && !flush),
    .Address(fetch_pc), .Instruction(ram_instruction)
);
assign instruction = valid ? ram_instruction : 32'd0;
always @(posedge clk) begin
    if (reset || flush) begin
        pc <= 32'd0;
        valid <= 1'b0;
    end else if (enable) begin
        pc <= fetch_pc;
        valid <= 1'b1;
    end
end
endmodule
// IF/ID: 65 stored bits = instruction[31:0] + pc[31:0] + valid.
// The synchronous instruction RAM output IS the 32-bit instruction register.
// Do not latch it again: that would add a sixth pipeline stage and misalign PC.
// Update: posedge; RAM reads fetch_pc while pc captures that SAME address.
// Enable=0 holds RAM output, pc and valid; no clock gating.
// Priority: synchronous reset > flush > enable > hold.
// Reset/flush clears pc and valid. RAM output has no reset to preserve M9K
// inference; instruction is masked to zero while invalid (raw bits are ignored).
// Valid=1 means pc/instruction describe a fetched instruction, including a NOP.