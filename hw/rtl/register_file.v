/* No RAM inference in this module: with 3 read ports (DR3 for the HEX debug view, PLT-4)
Quartus replicates the array and the copies lose ramstyle = "logic", so it puts the
registers in M9K again and the instruction memory banks 0-1 end up as logic
*/
(* altera_attribute = "-name AUTO_RAM_RECOGNITION OFF" *)
module register_file #(
	parameter INIT_FILE = ""  // binary file with initial values (simulation tests only)
)(
	input clk,
	input RegWrite,
	input [4:0] AR1, AR2, AW,
	input [31:0] DW,
	output [31:0] DR1, DR2,
	input [4:0] AR3,       // debug read port (PLT-4): the HEX debug view, not the datapath
	output [31:0] DR3
);

/* Keep the registers as logic (flip-flops), not M9K.
If not, Quartus uses the instruction memory output register to put the registers in a M9K,
and the instruction memory ends up as logic (no In-System Memory Content Editor)
*/
(* ramstyle = "logic" *) reg [31:0] registers [0:31];

assign DR1 = registers[AR1];
assign DR2 = registers[AR2];
assign DR3 = registers[AR3];

always @(posedge clk) begin // single-cycle: write at the end of the cycle (data memory reads on negedge)
    if (RegWrite && AW != 5'd0) // write enabled and the address isn't $zero?
		registers[AW] <= DW; // store data DW in register number AW
end

initial begin
    if (INIT_FILE != "") $readmemb(INIT_FILE, registers);
end

endmodule