module mips_cpu #(
	parameter IMEM_INIT = "",  // program (.hex) for simulation
	parameter REGS_INIT = ""   // initial register values (simulation tests only)
)(
	input clk,
	input reset,

	// Memory bus (contracts.md): the top level connects it to data memory, stack, framebuffer and MMIO
	output [31:0] mem_addr,
	output [31:0] mem_wdata,
	output mem_we,
	output mem_re,
	input [31:0] mem_rdata
);

// Data wires
wire [31:0] PC_out, PC_next, PC_fetch, Instruction;
wire [31:0] PC_plus4, BranchTarget, JumpTarget;
wire BranchTaken;
wire [31:0] DR1, DR2, ALUResult;
wire [3:0] ALUctl;
wire Zero;
wire [4:0] WriteReg;
wire [31:0] ExtendedImm, ALU_B;
wire [31:0] WriteData, MemReadData;
wire ZeroExtend;

// Control signals
wire RegDst, ALUSrc, MemtoReg, RegWrite, MemRead, MemWrite, Branch;
wire BranchNE, Jump, JumpReg, Link;
wire [1:0] ALUOp;

// R-type writes rd; I-type writes rt.
assign WriteReg = Link ? 5'd31 : (RegDst ? Instruction[15:11] : Instruction[20:16]);
// ANDI and ORI need zero extension.
assign ZeroExtend = (Instruction[31:26] == 6'b001100) ||(Instruction[31:26] == 6'b001101);
assign ExtendedImm = ZeroExtend? {16'b0, Instruction[15:0]}: {{16{Instruction[15]}}, Instruction[15:0]};
// Select the ALU's second operand.
assign ALU_B = ALUSrc ? ExtendedImm : DR2;
// CPU-3 single-cycle has no delay slot: jal returns to PC + 4.
// CPU-6 will introduce the pipeline delay slot and PC + 8 link value.
assign WriteData = Link ? PC_plus4 : (MemtoReg ? MemReadData : ALUResult);

// 1. Fetch the instruction
pc pc_reg(.clk(clk), .reset(reset), .PC_next(PC_next), .PC_out(PC_out));
adder add4(.A(PC_out), .B(32'd4), .R(PC_plus4));
assign BranchTarget = PC_plus4 + (ExtendedImm << 2);
assign JumpTarget = {PC_plus4[31:28], Instruction[25:0], 2'b00};
assign BranchTaken = Branch && (BranchNE ? !Zero : Zero);
assign PC_next = JumpReg ? DR1 :
                 Jump ? JumpTarget :
                 BranchTaken ? BranchTarget : PC_plus4;
// the instruction memory gets the same value as the PC, including the reset value
assign PC_fetch = reset ? 32'h0040_0000 : PC_next;
instruction_memory #(.INIT_FILE(IMEM_INIT)) im(.clk(clk), .Address(PC_fetch), .Instruction(Instruction));

// 2. Decide what to do
control_unit cu(
	.opcode(Instruction[31:26]),
	.funct(Instruction[5:0]),
	.BranchNE(BranchNE), .Jump(Jump), .JumpReg(JumpReg), .Link(Link),
	.RegDst(RegDst), .ALUSrc(ALUSrc), .MemtoReg(MemtoReg),
	.RegWrite(RegWrite), .MemRead(MemRead), .MemWrite(MemWrite),
	.Branch(Branch), .ALUOp(ALUOp)
);

// 3. Read and write registers
register_file #(.INIT_FILE(REGS_INIT)) rf(
	.clk(clk),
	.RegWrite(RegWrite && !reset),
	.AR1(Instruction[25:21]),
	.AR2(Instruction[20:16]),
	.AW(WriteReg), // rd for R-type; rt for I-type
	.DW(WriteData),
	.DR1(DR1),
	.DR2(DR2)
);

// 4. Execute
alu_control aluc(.ALUOp(ALUOp), .funct(Instruction[5:0]), .opcode(Instruction[31:26]), .ALUctl(ALUctl));
alu alu_unit(.ALUctl(ALUctl), .A(DR1), .B(ALU_B), .shamt(Instruction[10:6]), .ALUOut(ALUResult), .Zero(Zero));

// 5. Memory access, through the bus
/* The address has its own adder (base + offset) instead of using ALUResult,
so it doesn't wait for the whole ALU (shifter included) before the negedge
*/
assign mem_addr = DR1 + ExtendedImm;
assign mem_wdata = DR2;
assign mem_we = MemWrite && !reset;
assign mem_re = MemRead && !reset;
assign MemReadData = mem_rdata;

endmodule
