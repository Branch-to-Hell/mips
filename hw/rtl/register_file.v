module register_file #(
	parameter INIT_FILE = ""  // binary file with initial values (simulation tests only)
)(
	input clk,
	input RegWrite,
	input [4:0] AR1, AR2, AW,
	input [31:0] DW,
	output [31:0] DR1, DR2
);

reg [31:0] registers [0:31];

assign DR1 = registers[AR1];
assign DR2 = registers[AR2];

always @(negedge clk) begin // contracts.md: write on negedge, read afterwards
    if (RegWrite && AW != 5'd0) // write enabled and the address isn't $zero?
		registers[AW] <= DW; // store data DW in register number AW
end

initial begin
    if (INIT_FILE != "") $readmemb(INIT_FILE, registers);
end

endmodule