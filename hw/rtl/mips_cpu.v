module mips_cpu #(
	parameter IMEM_INIT = "",  // program (.hex) for simulation
	parameter REGS_INIT = ""   // initial register values (simulation tests only)
)(
	input clk,
	input reset
);

// Data wires
wire [31:0] PC_out, PC_next, Instruction;
wire [31:0] DR1, DR2, ALUResult;
wire [3:0] ALUctl;
wire Zero;
wire [4:0] WriteReg;
wire [31:0] ExtendedImm, ALU_B;
wire [31:0] WriteData, MemReadData;
wire ZeroExtend;

// Control signals
wire RegDst, ALUSrc, MemtoReg, RegWrite, MemRead, MemWrite, Branch;
wire [1:0] ALUOp;

// R-type writes rd; I-type writes rt.
assign WriteReg = RegDst? Instruction[15:11]: Instruction[20:16];
// ANDI and ORI need zero extension.
assign ZeroExtend = (Instruction[31:26] == 6'b001100) ||(Instruction[31:26] == 6'b001101);
assign ExtendedImm = ZeroExtend? {16'b0, Instruction[15:0]}: {{16{Instruction[15]}}, Instruction[15:0]};
// Select the ALU's second operand.
assign ALU_B = ALUSrc ? ExtendedImm : DR2;
assign WriteData = MemtoReg ? MemReadData : ALUResult;

// 1. Fetch the instruction
pc pc_reg(.clk(clk), .reset(reset), .PC_next(PC_next), .PC_out(PC_out));
adder add4(.A(PC_out), .B(32'd4), .R(PC_next));
instruction_memory #(.INIT_FILE(IMEM_INIT)) im(.Address(PC_out), .Instruction(Instruction));

// 2. Decide what to do
control_unit cu(
	.opcode(Instruction[31:26]),
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

// 5. Data memory
data_memory dm(
    .clk(clk),
    .MemRead(MemRead && !reset),
    .MemWrite(MemWrite && !reset),
    .Address(ALUResult),
    .WriteData(DR2),
    .ReadData(MemReadData)
);

endmodule