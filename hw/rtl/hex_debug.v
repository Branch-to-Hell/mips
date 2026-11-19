/* HEX debug view (PLT-4): one CPU register on the 6 displays
    HEX5-4 = register number in decimal (00-31, like $0-$31 in MARS),
             decimal point of HEX4 on to mark the debug view
    HEX3-0 = 16 bits of the register: half = 0 -> bits 15:0, half = 1 -> bits 31:16
Purely combinational; the segments are active-low like in mmio.v
*/
module hex_debug (
    input [4:0] reg_num,
    input half,
    input [31:0] value,
    output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
);

// Register number in decimal: tens 0-3, units 0-9
wire [1:0] tens = (reg_num >= 5'd30) ? 2'd3 :
                  (reg_num >= 5'd20) ? 2'd2 :
                  (reg_num >= 5'd10) ? 2'd1 : 2'd0;
wire [4:0] units = reg_num - tens * 5'd10;

wire [15:0] shown = half ? value[31:16] : value[15:0];

wire [6:0] seg0, seg1, seg2, seg3, seg4, seg5;
hex7seg h0(.value(shown[3:0]),   .seg(seg0));
hex7seg h1(.value(shown[7:4]),   .seg(seg1));
hex7seg h2(.value(shown[11:8]),  .seg(seg2));
hex7seg h3(.value(shown[15:12]), .seg(seg3));
hex7seg h4(.value(units[3:0]),   .seg(seg4));
hex7seg h5(.value({2'b0, tens}), .seg(seg5));

assign HEX0 = {1'b1, seg0};
assign HEX1 = {1'b1, seg1};
assign HEX2 = {1'b1, seg2};
assign HEX3 = {1'b1, seg3};
assign HEX4 = {1'b0, seg4};  // decimal point on: separates the number from the value
assign HEX5 = {1'b1, seg5};

endmodule
