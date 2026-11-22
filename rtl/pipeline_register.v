// Common ID/EX, EX/MEM and MEM/WB register primitive.
// Width: WIDTH payload bits + one separately stored valid bit.
// Update: common clock, posedge only (no gated or derived clocks).
// Priority: synchronous reset > flush > enable > hold.
// Reset/flush: zero payload and valid, including when enable=0.
// Enable=1: latch data_in if valid_in=1; otherwise insert a zeroed bubble.
// Enable=0: retain payload AND valid. Consumers must gate effects with valid.
module pipeline_register #(
    parameter WIDTH = 1
)(
    input clk, reset, enable, flush,
    input valid_in,
    input [WIDTH-1:0] data_in,
    output reg valid_out,
    output reg [WIDTH-1:0] data_out
);
always @(posedge clk) begin
    if (reset || flush) begin
        valid_out <= 1'b0;
        data_out <= {WIDTH{1'b0}};
    end else if (enable) begin
        valid_out <= valid_in;
        data_out <= valid_in ? data_in : {WIDTH{1'b0}};
    end
end
endmodule
