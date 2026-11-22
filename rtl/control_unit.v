/* Main decoder, shared by mips_cpu (single-cycle) and mips_pipeline.
CPU-7/CPU-8 add the rest of the MIPS I integer set (contracts.md "ISA", phase 2).
The new outputs (BranchZ, MemSize, MemUnsigned, MdOp) are only used by mips_pipeline;
the phase 1 outputs keep their meaning, so mips_cpu runs phase 1 programs as before.
Unknown opcodes and unknown R-type functs (syscall, break...) write nothing: no exceptions.
*/
module control_unit(
	input [5:0] opcode, // bits [31:26]: tell the instruction type
	input [5:0] funct, // R-type: picks the operation
	input [4:0] rt, // bits [20:16]: REGIMM (opcode 1) uses it to pick bltz/bgez/bltzal/bgezal
	output reg BranchNE, Jump, JumpReg, Link,
	output reg RegDst, // destination register: rt (0) or rd (1)
	output reg ALUSrc, // where the ALU takes its second operand from: register (0) or immediate (1)
	output reg MemtoReg, // does data memory send something to the register file?
	output reg RegWrite, // is the register file written?
	output reg MemRead, // does data memory read?
	output reg MemWrite, // is something written to data memory?
	output reg Branch, // is it a conditional branch that compares two registers? (beq or bne)
	output reg [1:0] ALUOp, // tells ALU Control the operation type
	// CPU-7
	output reg BranchZ, // branch that compares rs with zero: bltz bgez bltzal bgezal blez bgtz
	output reg [1:0] MemSize, // loads/stores: 0 = byte, 1 = half, 2 = word
	output reg MemUnsigned, // lbu, lhu: zero-extend the loaded value
	// CPU-8: HI/LO operation (mult_div.v): 0 = none, 1 mfhi, 2 mflo, 3 mthi, 4 mtlo,
	// 8 mult, 9 multu, 10 div, 11 divu (bit 3 = start a multiply/divide)
	output reg [3:0] MdOp
);

// R-type functs that write rd
reg r_writes;
always @(*) begin
	case (funct)
		6'h20, 6'h21, 6'h22, 6'h23, 6'h24, 6'h25, 6'h26, 6'h27, // add addu sub subu and or xor nor
		6'h2A, 6'h2B,                                           // slt sltu
		6'h00, 6'h02, 6'h03, 6'h04, 6'h06, 6'h07,               // sll srl sra sllv srlv srav
		6'h09,                                                  // jalr
		6'h10, 6'h12:                                           // mfhi mflo
			r_writes = 1'b1;
		default: r_writes = 1'b0;                               // jr, mult/div, mthi/mtlo, syscall, break
	endcase
end

always @(*) begin
	BranchNE = 1'b0;
	Jump = 1'b0;
	JumpReg = 1'b0;
	Link = 1'b0;
	BranchZ = 1'b0;
	MemSize = 2'd2;
	MemUnsigned = 1'b0;
	MdOp = 4'd0;
	case (opcode)
		6'b000000: begin // R-type
			RegDst = 1'b1;
			ALUSrc = 1'b0;
			MemtoReg = 1'b0;
			RegWrite = r_writes;
			JumpReg = (funct == 6'h08) || (funct == 6'h09); // jr, jalr
			Link = (funct == 6'h09);                        // jalr writes PC + 8 into rd
			MemRead = 1'b0;
			MemWrite = 1'b0;
			Branch = 1'b0;
			ALUOp = 2'b10; // ALU Control uses funct
			case (funct)
				6'h10: MdOp = 4'd1;  // mfhi
				6'h12: MdOp = 4'd2;  // mflo
				6'h11: MdOp = 4'd3;  // mthi
				6'h13: MdOp = 4'd4;  // mtlo
				6'h18: MdOp = 4'd8;  // mult
				6'h19: MdOp = 4'd9;  // multu
				6'h1A: MdOp = 4'd10; // div
				6'h1B: MdOp = 4'd11; // divu
				default: MdOp = 4'd0;
			endcase
		end
		6'b000001: begin // REGIMM: rt = 0 bltz, 1 bgez, 16 bltzal, 17 bgezal
			RegDst = 1'b0;
			ALUSrc = 1'b0;
			MemtoReg = 1'b0;
			Link = (rt[4:1] == 4'b1000);  // bltzal/bgezal write PC + 8 into $ra, taken or not
			RegWrite = (rt[4:1] == 4'b1000);
			MemRead = 1'b0;
			MemWrite = 1'b0;
			Branch = 1'b0;
			BranchZ = (rt[3:1] == 3'b000); // 0, 1, 16, 17
			ALUOp = 2'b00;
		end
		6'b000110, 6'b000111: begin // blez, bgtz
			RegDst = 1'b0;
			ALUSrc = 1'b0;
			MemtoReg = 1'b0;
			RegWrite = 1'b0;
			MemRead = 1'b0;
			MemWrite = 1'b0;
			Branch = 1'b0;
			BranchZ = 1'b1;
			ALUOp = 2'b00;
		end
		6'b001000, 6'b001001: begin // addi, addiu (CPU-11: the professor's addi = 0x09)
			RegDst   = 1'b0;
			ALUSrc   = 1'b1;
			MemtoReg = 1'b0;
			RegWrite = 1'b1;
			MemRead  = 1'b0;
			MemWrite = 1'b0;
			Branch   = 1'b0;
			ALUOp    = 2'b00;
		end
		6'b001100, 6'b001101, 6'b001010, 6'b001011, 6'b001110: begin // andi, ori, slti, sltiu, xori
			RegDst = 1'b0;
			ALUSrc = 1'b1;
			MemtoReg = 1'b0;
			RegWrite = 1'b1;
			MemRead = 1'b0;
			MemWrite = 1'b0;
			Branch = 1'b0;
			ALUOp = 2'b11; // ALU Control uses the opcode
		end
		6'b001111: begin // lui
			RegDst   = 1'b0;
			ALUSrc   = 1'b1; // operand B gets the immediate
			MemtoReg = 1'b0;
			RegWrite = 1'b1;
			MemRead  = 1'b0;
			MemWrite = 1'b0;
			Branch   = 1'b0;
			ALUOp    = 2'b11; // ALU Control uses the opcode
		end
		6'b100011, 6'b100000, 6'b100001, 6'b100100, 6'b100101: begin // lw, lb, lh, lbu, lhu
			RegDst = 1'b0;
			ALUSrc = 1'b1;
			MemtoReg = 1'b1;
			RegWrite = 1'b1;
			MemRead = 1'b1;
			MemWrite = 1'b0;
			Branch = 1'b0;
			ALUOp = 2'b00; // add: base + offset
			MemSize = (opcode[1:0] == 2'b11) ? 2'd2 : {1'b0, opcode[0]}; // lw : lh/lhu or lb/lbu
			MemUnsigned = opcode[2];                                      // lbu, lhu
		end
		6'b101011, 6'b101000, 6'b101001: begin // sw, sb, sh
			RegDst = 1'b0;
			ALUSrc = 1'b1;
			MemtoReg = 1'b0;
			RegWrite = 1'b0;
			MemRead = 1'b0;
			MemWrite = 1'b1;
			Branch = 1'b0;
			ALUOp = 2'b00; // add: base + offset
			MemSize = (opcode[1:0] == 2'b11) ? 2'd2 : {1'b0, opcode[0]};
		end
		6'b000100, 6'b000101: begin // beq, bne
			RegDst = 1'b0;
			ALUSrc = 1'b0;
			MemtoReg = 1'b0;
			RegWrite = 1'b0;
			MemRead = 1'b0;
			MemWrite = 1'b0;
			Branch = 1'b1;
			BranchNE = (opcode == 6'b000101);
			ALUOp = 2'b01;
		end
		6'b000010, 6'b000011: begin // j, jal
			RegDst = 1'b0;
			ALUSrc = 1'b0;
			MemtoReg = 1'b0;
			RegWrite = (opcode == 6'b000011);
			MemRead = 1'b0;
			MemWrite = 1'b0;
			Branch = 1'b0;
			ALUOp = 2'b00;
			Jump = 1'b1;
			Link = (opcode == 6'b000011);
		end
		default: begin
			RegDst = 1'b0;
			ALUSrc = 1'b0;
			MemtoReg = 1'b0;
			RegWrite = 1'b0;
			MemRead = 1'b0;
			MemWrite = 1'b0;
			Branch = 1'b0;
			ALUOp = 2'b00;
		end
	endcase
end
endmodule
