// CPU-4: five-stage pipeline, one instruction per cycle after filling the pipeline.
// Separate from the single-cycle mips_cpu until LIFE-6 checks it on the board
// with Game of Life; then it replaces mips_cpu.
// Supports R-type arithmetic/shifts, I-type arithmetic/lw/sw and beq/bne/j/jal/jr.
// CPU-5: hazard_unit stalls IF/ID while the instruction in ID reads a register
// that EX or MEM will still write (no forwarding: the value reaches ID from WB
// through the bypass). Programs need no NOPs for data or load-use hazards.
// CPU-6: beq/bne/j/jal/jr are resolved in ID with ONE delay slot: the
// instruction after a branch/jump always runs, then fetch continues at the
// target. Nothing is flushed. jal writes PC + 8 (the instruction after the
// delay slot) into $ra. The branch compare and jr read operands in ID, so they
// stall like any other consumer.
// CPU-14 still owns access faults.
// IMEM_INIT is the prefix of four big-endian byte-bank images (_b0..b3.hex).
// RESET_PC = 0 like mips_cpu (contracts.md: text base 0, CPU-13).
module mips_pipeline #(
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
// CPU-5: a stall holds fetch_pc and IF/ID and sends a bubble into ID/EX
// (valid_in = 0 below); EX, MEM and WB keep going. CPU-9 will add the
// whole-pipeline memory wait. No flushes: the delay slot always runs (CPU-6).
wire stall;
wire if_id_enable = !stall, id_ex_enable = 1'b1;
wire ex_mem_enable = 1'b1, mem_wb_enable = 1'b1;
wire if_id_flush = 1'b0, id_ex_flush = 1'b0;
wire ex_mem_flush = 1'b0, mem_wb_flush = 1'b0;

// IF: this PC names the fetch request, not the instruction currently in ID.
// While a branch/jump is in ID, fetch_pc already points at its delay slot
// (id_pc + 4), which is fetched on this edge; next_fetch_pc is the address
// fetched on the edge AFTER it: the target if taken, else sequential.
reg [31:0] fetch_pc;
wire [31:0] id_pc, id_instruction;
wire id_valid;
wire redirect;
wire [31:0] redirect_pc;
wire [31:0] next_fetch_pc = redirect ? redirect_pc : fetch_pc + 32'd4;
always @(posedge clk) begin
    if (reset) fetch_pc <= RESET_PC;
    else if (if_id_enable) fetch_pc <= next_fetch_pc;
end
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
wire [31:0] rf_a, rf_b;
wire [4:0] id_rs = id_instruction[25:21], id_rt = id_instruction[20:16];
// The shared register_file writes on posedge (single-cycle timing), i.e. at the
// END of the WB cycle. The write-through bypass below gives ID the value being
// written in the same cycle, like a register file that writes in the first half
// of the cycle and reads in the second. $zero is never bypassed.
wire wb_write = wb_valid && wb_reg_write && (wb_dest != 5'd0);
register_file #(.INIT_FILE(REGS_INIT)) rf(
    .clk(clk), .reset(reset), .AR3(dbg_sel), .DR3(dbg_value), .RegWrite(wb_write && !reset),
    .AR1(id_rs), .AR2(id_rt),
    .AW(wb_dest), .DW(wb_data), .DR1(rf_a), .DR2(rf_b)
);
assign id_a = (wb_write && wb_dest == id_rs) ? wb_data : rf_a;
assign id_b = (wb_write && wb_dest == id_rt) ? wb_data : rf_b;

// CPU-6: branch/jump resolution in ID (contracts.md "Pipeline").
// beq/bne compare the ID operands directly (no ALU), targets use PC + 4 of the
// branch, i.e. the delay slot's address, like MIPS and the single-cycle CPU.
wire [31:0] id_pc_plus4 = id_pc + 32'd4;
wire [31:0] branch_target = id_pc_plus4 + {id_imm[29:0], 2'b00};
wire [31:0] jump_target = {id_pc_plus4[31:28], id_instruction[25:0], 2'b00};
wire operands_equal = (id_a == id_b);
wire branch_taken = branch && (branch_ne ? !operands_equal : operands_equal);
assign redirect = id_valid && (branch_taken || jump || jump_reg);
assign redirect_pc = jump_reg ? id_a : (jump ? jump_target : branch_target);
// jal: the link value PC + 8 travels as operand A with B = 0; the ALU adds
// (ALUOp 00), so EX produces it like any result and WB writes $ra.
wire [31:0] link_value = id_pc + 32'd8;
wire [31:0] ex_a_in = link ? link_value : id_a;
wire [31:0] ex_b_in = link ? 32'd0 : id_b;
wire [4:0] ex_dest_in = link ? 5'd31 : id_dest;

// CPU-5 hazard detection (hazard_unit.v). Declared here, driven by later stages.
wire ex_valid, ex_reg_write;
wire [4:0] ex_dest;
wire mem_valid, mem_reg_write;
wire [4:0] mem_dest;
hazard_unit hu(
    .opcode(id_instruction[31:26]), .funct(id_instruction[5:0]),
    .rs(id_rs), .rt(id_rt), .id_valid(id_valid),
    .ex_valid(ex_valid), .ex_reg_write(ex_reg_write), .ex_dest(ex_dest),
    .mem_valid(mem_valid), .mem_reg_write(mem_reg_write), .mem_dest(mem_dest),
    .stall(stall)
);

// ID/EX: 115 payload + 1 valid = 116 bits.
// Payload: A or jal link value(32), B/store data(32), immediate(32), destination(5), shamt(5),
// ALU control(4), ALUSrc(1), RegWrite(1), MemRead(1), MemWrite(1), MemtoReg(1).
// posedge; enable=0 holds all fields; synchronous reset/flush clears all fields
// and valid regardless of enable; invalid input inserts a bubble. See primitive.
wire [31:0] ex_a, ex_b, ex_imm;
wire [4:0] ex_shamt;
wire [3:0] ex_alu_ctl;
wire ex_alu_src, ex_mem_read, ex_mem_write, ex_mem_to_reg;
pipeline_register #(.WIDTH(115)) id_ex(
    .clk(clk), .reset(reset), .enable(id_ex_enable), .flush(id_ex_flush),
    .valid_in(id_valid && !stall),   // a stalled instruction leaves a bubble
    .data_in({ex_a_in, ex_b_in, id_imm, ex_dest_in, id_instruction[10:6], id_alu_ctl,
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
wire mem_read_ctl, mem_write_ctl, mem_to_reg_ctl;
wire [31:0] mem_value, mem_store_data;
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
// if disabled. valid gates the register write at the end of the WB cycle
// (next posedge), bypassed to ID during that cycle.
// Selecting memory/ALU data before this register avoids retaining unused data.
pipeline_register #(.WIDTH(38)) mem_wb(
    .clk(clk), .reset(reset), .enable(mem_wb_enable), .flush(mem_wb_flush),
    .valid_in(mem_valid),
    .data_in({mem_to_reg_ctl ? mem_rdata : mem_value, mem_dest, mem_reg_write}),
    .valid_out(wb_valid), .data_out({wb_data, wb_dest, wb_reg_write})
);
endmodule
