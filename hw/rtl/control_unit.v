module control_unit(
	input [5:0] opcode, // bits [31:26]: tell the instruction type
	output reg RegDst, // destination register: rt (0) or rd (1)
	output reg ALUSrc, // where the ALU takes its second operand from: register (0) or immediate (1)
	output reg MemtoReg, // does data memory send something to the register file?
	output reg RegWrite, // is the register file written?
	output reg MemRead, // does data memory read?
	output reg MemWrite, // is something written to data memory?
	output reg Branch, // is it a conditional branch? (beq)
	output reg [1:0] ALUOp // tells ALU Control the operation type
);

always @(*) begin
	case (opcode)
		6'b000000: begin // R-type
			RegDst = 1'b1;
			ALUSrc = 1'b0;
			MemtoReg = 1'b0;
			RegWrite = 1'b1;
			MemRead = 1'b0;
			MemWrite = 1'b0;
			Branch = 1'b0;
			ALUOp = 2'b10;
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