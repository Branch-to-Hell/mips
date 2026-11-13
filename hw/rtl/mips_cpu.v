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

// Control signals
wire RegDst, ALUSrc, MemtoReg, RegWrite, MemRead, MemWrite, Branch;
wire [1:0] ALUOp;

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
	.RegWrite(RegWrite),
	.AR1(Instruction[25:21]),
	.AR2(Instruction[20:16]),
	.AW(Instruction[15:11]), // R-type only: rd. CPU-2 adds the RegDst mux (rt for I-type)
	.DW(ALUResult),
	.DR1(DR1),
	.DR2(DR2)
);

// 4. Execute
alu_control aluc(.ALUOp(ALUOp), .funct(Instruction[5:0]), .ALUctl(ALUctl));
alu alu_unit(.ALUctl(ALUctl), .A(DR1), .B(DR2), .shamt(Instruction[10:6]), .ALUOut(ALUResult), .Zero(Zero));

endmodule