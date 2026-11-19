module register_file #(
	parameter INIT_FILE = ""  // binary file with initial values (simulation tests only)
)(
	input clk,
	input RegWrite,
	input [4:0] AR1, AR2, AW,
	input [31:0] DW,
	output [31:0] DR1, DR2
);
/* Keep the registers as logic (flip-flops), not M9K. If not, Quartus uses the instruction memory output register to put the registers in a M9K, and the instruction memory ends up as logic (no In-System Memory Content Editor)
*/
(* ramstyle = "logic" *) reg [31:0] registers [0:31];
assign DR1 = (AR1 == 5'd0) ? 32'd0 : registers[AR1];
assign DR2 = (AR2 == 5'd0) ? 32'd0 : registers[AR2];
always @(negedge clk) begin // WB writes before ID is captured at the next posedge
    if (RegWrite && AW != 5'd0) registers[AW] <= DW;
end
initial begin
    if (INIT_FILE != "") $readmemb(INIT_FILE, registers);
end
endmodule
