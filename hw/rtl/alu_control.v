module alu_control(
    input  [1:0] ALUOp,
    input  [5:0] funct,
    input  [5:0] opcode,
    output reg [3:0] ALUctl
);

always @(*) begin
    case (ALUOp) // 00 and 01: the operation is already decided, funct is ignored (lw, sw, beq)
        2'b00: ALUctl = 4'b0010; // add for loads/stores, and for the link value of jal/bltzal/bgezal
        2'b01: ALUctl = 4'b0110; // sub for beq
        2'b11: begin
            case (opcode)
                6'b001100: ALUctl = 4'b0000; // andi
                6'b001101: ALUctl = 4'b0001; // ori
                6'b001010: ALUctl = 4'b0111; // slti
                6'b001011: ALUctl = 4'b1000; // sltiu (CPU-7)
                6'b001110: ALUctl = 4'b1001; // xori (CPU-7)
                6'b001111: ALUctl = 4'b0101; // lui
                default: ALUctl = 4'b0000;
            endcase
        end
        2'b10: begin
            case (funct) // here funct matters
                6'b100100: ALUctl = 4'b0000; // and
                6'b100101: ALUctl = 4'b0001; // or
				6'b100000, 6'b100001: ALUctl = 4'b0010; // add, addu (CPU-11: the professor's add = 0x21)
                6'b100010, 6'b100011: ALUctl = 4'b0110; // sub, subu (CPU-11: the professor's sub = 0x23)
                6'b101010: ALUctl = 4'b0111; // slt
				6'b100111: ALUctl = 4'b1100; // nor
                6'b000000: ALUctl = 4'b0011; // sll (also nop = 0x00000000)
                6'b000010: ALUctl = 4'b0100; // srl
                // CPU-7
                6'b101011: ALUctl = 4'b1000; // sltu
                6'b100110: ALUctl = 4'b1001; // xor
                6'b000011: ALUctl = 4'b1010; // sra
                6'b000100: ALUctl = 4'b1011; // sllv
                6'b000110: ALUctl = 4'b1101; // srlv
                6'b000111: ALUctl = 4'b1110; // srav
                6'b001001: ALUctl = 4'b0010; // jalr: the link value PC + 8 comes in as A + 0
                default:   ALUctl = 4'b0000;
            endcase
        end
        default: ALUctl = 4'b0000;
    endcase
end

endmodule
