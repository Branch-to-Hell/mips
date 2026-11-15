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
assign ReadData = (MemRead && ValidAddress) ? mem[WordIndex] : 32'b0;

always @(negedge clk) begin
    if (MemWrite && ValidAddress)
        mem[WordIndex] <= WriteData;
end

endmodule
