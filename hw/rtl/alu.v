module alu(
	input [3:0]ALUctl,
	input [31:0]A,
	input [31:0]B,
	input [4:0]shamt, // Instruction[10:6], used by sll/srl
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
			4'd6: ALUOut = A - B;
			4'd7: ALUOut = ($signed(A) < $signed(B)) ? 1:0;
			4'd12: ALUOut = ~(A | B);
			default: ALUOut = 0;
		endcase
	end

endmodule  