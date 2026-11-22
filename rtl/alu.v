module alu(
	input [3:0]ALUctl,
	input [31:0]A,
	input [31:0]B,
	input [4:0]shamt, // Instruction[10:6], used by sll/srl/sra
	output reg [31:0]ALUOut,
	output Zero
);

assign Zero = (ALUOut==0);
always @*
	begin
		case(ALUctl)
			4'd0: ALUOut = A & B;
			4'd1: ALUOut = A | B;
			4'd2: ALUOut = A + B;
			4'd3: ALUOut = B << shamt;  // sll: rd = rt << shamt
			4'd4: ALUOut = B >> shamt;  // srl: rd = rt >> shamt (logical)
			4'd5: ALUOut = {B[15:0], 16'b0}; // lui
			4'd6: ALUOut = A - B;
			4'd7: ALUOut = ($signed(A) < $signed(B)) ? 1:0;
			// CPU-7: the rest of the MIPS I integer operations
			4'd8: ALUOut = (A < B) ? 1:0;               // sltu, sltiu: unsigned compare
			4'd9: ALUOut = A ^ B;                       // xor, xori
			4'd10: ALUOut = $signed(B) >>> shamt;       // sra: rd = rt >> shamt (arithmetic)
			4'd11: ALUOut = B << A[4:0];                // sllv: rd = rt << rs[4:0]
			4'd12: ALUOut = ~(A | B);
			4'd13: ALUOut = B >> A[4:0];                // srlv: rd = rt >> rs[4:0] (logical)
			4'd14: ALUOut = $signed(B) >>> A[4:0];      // srav: rd = rt >> rs[4:0] (arithmetic)
			default: ALUOut = 0;
		endcase
	end

endmodule
