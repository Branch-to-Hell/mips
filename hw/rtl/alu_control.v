module alu_control(
    input  [1:0] ALUOp,
    input  [5:0] funct,
    output reg [3:0] ALUctl
);

always @(*) begin
    case (ALUOp) // 00 and 01: the operation is already decided, funct is ignored (lw, sw, beq)
        2'b00: ALUctl = 4'b0010; // add for lw and sw
        2'b01: ALUctl = 4'b0110; // sub for beq
        2'b10: begin
            case (funct) // here funct matters
                6'b100100: ALUctl = 4'b0000; // and
                6'b100101: ALUctl = 4'b0001; // or
				6'b100000: ALUctl = 4'b0010; // add
                6'b100010: ALUctl = 4'b0110; // sub
                6'b101010: ALUctl = 4'b0111; // slt
				6'b100111: ALUctl = 4'b1100; // nor
                6'b000000: ALUctl = 4'b0011; // sll (also nop = 0x00000000)
                6'b000010: ALUctl = 4'b0100; // srl
                default:   ALUctl = 4'b0000;
            endcase
        end
        default: ALUctl = 4'b0000;
    endcase
end

endmodule