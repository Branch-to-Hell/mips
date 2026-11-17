module data_memory(
    input clk,
    input MemRead,
    input MemWrite,
    input [31:0] Address,
    input [31:0] WriteData,
    output [31:0] ReadData
);

reg [31:0] mem [0:4095];

// Only aligned accesses to the 16 KB data region are supported.
wire ValidAddress;
wire [11:0] WordIndex;
assign ValidAddress = (Address >= 32'h1001_0000) &&
                      (Address < 32'h1001_4000) &&
                      (Address[1:0] == 2'b00);
// Base is 16 KB aligned; these bits select the word within the region.
assign WordIndex = Address[13:2];

/* Reads and writes on negedge so Quartus uses the M9K blocks.
The ALU has the first half of the cycle to compute the address,
and the data is ready before the register file writes on posedge
*/
reg [31:0] q;
reg q_valid;
always @(negedge clk) begin
    if (MemWrite && ValidAddress)
        mem[WordIndex] <= WriteData;
    q <= mem[WordIndex];
    q_valid <= MemRead && ValidAddress;
end

assign ReadData = q_valid ? q : 32'b0;

endmodule
