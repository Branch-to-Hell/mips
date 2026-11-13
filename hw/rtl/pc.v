module pc(
    input clk, reset,
    input [31:0] PC_next,
    output reg [31:0] PC_out
);

always @(posedge clk) begin // updates on every rising clock edge (sequential)
    if (reset) PC_out <= 32'h0040_0000; // contracts.md: PC reset = 0x00400000
    else       PC_out <= PC_next;
end

endmodule