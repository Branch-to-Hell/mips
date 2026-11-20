// CPU-4: five stages, one instruction per cycle after filling the pipeline.
// This replaces the single-cycle datapath inside the existing mips_cpu module.
// Supports existing R-type arithmetic/shifts and I-type arithmetic/lw/sw.
// CPU-5 owns hazard detection; no forwarding or automatic stalls yet.
// A producer must reach WB before its consumer finishes ID: with this timing,
// use at least TWO intervening independent instructions (or NOPs).
// CPU-6 owns branches/jumps and delay slots: they are NOT executable here yet
// and are decoded as bubbles, never as a spurious jal register write.
// CPU-11/14 still own opcode aliases and access faults.
// IMEM_INIT is the prefix of four big-endian byte-bank images (_b0..b3.hex).
// RESET_PC defaults to the contract's zero text base. CPU-13 still owns
// migration of existing program images and board tests to this base.
module mips_cpu #(
    parameter IMEM_INIT = "",
    parameter REGS_INIT = "",
    parameter RESET_PC = 32'h0000_0000
)(
    input clk, reset,
    output [31:0] mem_addr, mem_wdata,
    output mem_we, mem_re,
    input [4:0] dbg_sel,
    output [31:0] dbg_value,
    input [31:0] mem_rdata
);
// Stage enables/flushes are intentionally always-run in CPU-4. CPU-5 will
// control IF/ID and ID/EX separately; CPU-9 will add whole-pipeline memory wait.
wire if_id_enable = 1'b1, id_ex_enable = 1'b1;
wire ex_mem_enable = 1'b1, mem_wb_enable = 1'b1;
wire if_id_flush = 1'b0, id_ex_flush = 1'b0;
wire ex_mem_flush = 1'b0, mem_wb_flush = 1'b0;

// IF: this PC names the fetch request, not the instruction currently in ID.
reg [31:0] fetch_pc;
always @(posedge clk) begin
    if (reset) fetch_pc <= RESET_PC;
    else if (if_id_enable) fetch_pc <= fetch_pc + 32'd4;
end
wire [31:0] id_pc, id_instruction;
wire id_valid;
// IF/ID: 64 payload + 1 valid = 65 bits. Detailed reset/enable/update behavior
// is in if_id_register.v; RAM output and saved PC update on the same edge.
if_id_register #(.IMEM_INIT(IMEM_INIT)) if_id(
    .clk(clk), .reset(reset), .enable(if_id_enable), .flush(if_id_flush),
    .fetch_pc(fetch_pc), .pc(id_pc), .instruction(id_instruction), .valid(id_valid)
);

// ID: decode control alongside operands, so they travel with the instruction.
wire reg_dst, alu_src, mem_to_reg, reg_write, mem_read, mem_write;
wire branch, branch_ne, jump, jump_reg, link;
wire [1:0] alu_op;
wire [3:0] id_alu_ctl;
wire [31:0] id_a, id_b, id_imm;
wire [4:0] id_dest = reg_dst ? id_instruction[15:11] : id_instruction[20:16];
wire zero_extend = (id_instruction[31:26] == 6'h0c) || (id_instruction[31:26] == 6'h0d);
assign id_imm = zero_extend ? {16'd0, id_instruction[15:0]} :
                             {{16{id_instruction[15]}}, id_instruction[15:0]};
control_unit cu(
    .opcode(id_instruction[31:26]), .funct(id_instruction[5:0]),
    .RegDst(reg_dst), .ALUSrc(alu_src), .MemtoReg(mem_to_reg),
    .RegWrite(reg_write), .MemRead(mem_read), .MemWrite(mem_write),
    .Branch(branch), .BranchNE(branch_ne), .Jump(jump), .JumpReg(jump_reg),
    .Link(link), .ALUOp(alu_op)
);
alu_control aluc(.ALUOp(alu_op), .funct(id_instruction[5:0]),
    .opcode(id_instruction[31:26]), .ALUctl(id_alu_ctl));
wire [31:0] wb_data;
wire [4:0] wb_dest;
wire wb_valid, wb_reg_write;
register_file #(.INIT_FILE(REGS_INIT)) rf(
    .clk(clk), .reset(reset), .AR3(dbg_sel), .DR3(dbg_value), .RegWrite(wb_valid && wb_reg_write && !reset),
    .AR1(id_instruction[25:21]), .AR2(id_instruction[20:16]),
    .AW(wb_dest), .DW(wb_data), .DR1(id_a), .DR2(id_b)
);

// ID/EX: 115 payload + 1 valid = 116 bits.
// Payload: A(32), B/store data(32), immediate(32), destination(5), shamt(5),
// ALU control(4), ALUSrc(1), RegWrite(1), MemRead(1), MemWrite(1), MemtoReg(1).
// posedge; enable=0 holds all fields; synchronous reset/flush clears all fields
// and valid regardless of enable; invalid input inserts a bubble. See primitive.
wire ex_valid;
wire [31:0] ex_a, ex_b, ex_imm;
wire [4:0] ex_dest, ex_shamt;
wire [3:0] ex_alu_ctl;
wire ex_alu_src, ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_to_reg;
pipeline_register #(.WIDTH(115)) id_ex(
    .clk(clk), .reset(reset), .enable(id_ex_enable), .flush(id_ex_flush),
    .valid_in(id_valid && !(branch || jump || jump_reg)),
    .data_in({id_a, id_b, id_imm, id_dest, id_instruction[10:6], id_alu_ctl,
              alu_src, reg_write, mem_read, mem_write, mem_to_reg}),
    .valid_out(ex_valid),
    .data_out({ex_a, ex_b, ex_imm, ex_dest, ex_shamt, ex_alu_ctl,
               ex_alu_src, ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_to_reg})
);

// EX: all operands/control are from ID/EX, never the current ID instruction.
wire [31:0] ex_result;
alu alu_unit(.ALUctl(ex_alu_ctl), .A(ex_a), .B(ex_alu_src ? ex_imm : ex_b),
    .shamt(ex_shamt), .ALUOut(ex_result), .Zero());
// Dedicated load/store address adder matches the existing memory-bus contract.
wire [31:0] ex_address = ex_a + ex_imm;
wire [31:0] ex_value = (ex_mem_read || ex_mem_write) ? ex_address : ex_result;

// EX/MEM: 73 payload + 1 valid = 74 bits.
// Payload: result/address(32), store data(32), destination(5), RegWrite(1),
// MemRead(1), MemWrite(1), MemtoReg(1).
// posedge; enable holds all fields; synchronous reset/flush clears payload and
// valid even while disabled; invalid input inserts a bubble. valid gates bus.
wire mem_valid, mem_reg_write, mem_read_ctl, mem_write_ctl, mem_to_reg_ctl;
wire [31:0] mem_value, mem_store_data;
wire [4:0] mem_dest;
pipeline_register #(.WIDTH(73)) ex_mem(
    .clk(clk), .reset(reset), .enable(ex_mem_enable), .flush(ex_mem_flush),
    .valid_in(ex_valid),
    .data_in({ex_value, ex_b, ex_dest, ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_to_reg}),
    .valid_out(mem_valid),
    .data_out({mem_value, mem_store_data, mem_dest, mem_reg_write, mem_read_ctl, mem_write_ctl, mem_to_reg_ctl})
);

// MEM: external memory samples EX/MEM address/data/enables at negedge.
// Read data arrives before MEM/WB captures it at the following posedge.
assign mem_addr = mem_value;
assign mem_wdata = mem_store_data;
assign mem_re = mem_valid && mem_read_ctl && !reset;
assign mem_we = mem_valid && mem_write_ctl && !reset;

// MEM/WB: 38 payload + 1 valid = 39 bits.
// Payload: selected register value(32), destination(5), RegWrite(1).
// posedge; enable holds; synchronous reset/flush clears payload and valid even
// if disabled. valid gates the WB write on the FOLLOWING negedge.
// Selecting memory/ALU data before this register avoids retaining unused data.
pipeline_register #(.WIDTH(38)) mem_wb(
    .clk(clk), .reset(reset), .enable(mem_wb_enable), .flush(mem_wb_flush),
    .valid_in(mem_valid),
    .data_in({mem_to_reg_ctl ? mem_rdata : mem_value, mem_dest, mem_reg_write}),
    .valid_out(wb_valid), .data_out({wb_data, wb_dest, wb_reg_write})
);
endmodule
