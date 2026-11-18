/* MMIO registers for switches, keys, LEDs and HEX displays (PLT-2)
Addresses from contracts.md:
    0xFFFF_0010  SW    read   bits 9..0 = switches
    0xFFFF_0014  KEY   read   bits 1..0 = keys, 1 = pressed (debounced here)
    0xFFFF_0018  LEDR  write  bits 9..0 = LEDs (also readable, for debugging)
    0xFFFF_001C  HEX   write  bits 23..0 in hexadecimal on HEX5..HEX0 (also readable)
TIMER (0x20, PLT-5) and VIDEO_MODE (0x24, PLT-6) come later.
Reads and writes on negedge, like data memory (contracts.md, memory timing)
*/
module mmio #(
    parameter DEBOUNCE_CYCLES = 250_000  // 10 ms at 25 MHz
)(
    input clk,
    input reset,

    // CPU memory bus
    input [31:0] addr,
    input [31:0] wdata,
    input we,
    input re,
    output [31:0] rdata,  // 0 when the last access was not an MMIO read

    // Board
    input [9:0] SW,
    input [1:0] KEY,      // raw, active-low
    output [9:0] LEDR,
    output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5  // active-low, bit 7 = decimal point
);

localparam ADDR_SW   = 32'hFFFF_0010;
localparam ADDR_KEY  = 32'hFFFF_0014;
localparam ADDR_LEDR = 32'hFFFF_0018;
localparam ADDR_HEX  = 32'hFFFF_001C;

// Inputs: switches only need synchronizing, keys also need debouncing
reg [9:0] sw_sync0 = 0, sw_sync1 = 0;
always @(posedge clk) begin
    sw_sync0 <= SW;
    sw_sync1 <= sw_sync0;
end

wire [1:0] key_pressed;
debounce #(.CYCLES(DEBOUNCE_CYCLES)) db0(.clk(clk), .key_n(KEY[0]), .pressed(key_pressed[0]));
debounce #(.CYCLES(DEBOUNCE_CYCLES)) db1(.clk(clk), .key_n(KEY[1]), .pressed(key_pressed[1]));

// Output registers and read port
reg [9:0] ledr_reg = 0;
reg [23:0] hex_reg = 0;
reg [31:0] q = 0;

always @(negedge clk) begin
    if (reset) begin
        ledr_reg <= 0;
        hex_reg <= 0;
    end else if (we) begin
        case (addr)
            ADDR_LEDR: ledr_reg <= wdata[9:0];
            ADDR_HEX:  hex_reg  <= wdata[23:0];
            default: ;
        endcase
    end

    if (re) begin
        case (addr)
            ADDR_SW:   q <= {22'b0, sw_sync1};
            ADDR_KEY:  q <= {30'b0, key_pressed};
            ADDR_LEDR: q <= {22'b0, ledr_reg};
            ADDR_HEX:  q <= {8'b0, hex_reg};
            default:   q <= 32'b0;
        endcase
    end else
        q <= 32'b0;
end

assign rdata = q;
assign LEDR = ledr_reg;

// One display per nibble; decimal points off (1 = off)
wire [6:0] seg0, seg1, seg2, seg3, seg4, seg5;
hex7seg h0(.value(hex_reg[3:0]),   .seg(seg0));
hex7seg h1(.value(hex_reg[7:4]),   .seg(seg1));
hex7seg h2(.value(hex_reg[11:8]),  .seg(seg2));
hex7seg h3(.value(hex_reg[15:12]), .seg(seg3));
hex7seg h4(.value(hex_reg[19:16]), .seg(seg4));
hex7seg h5(.value(hex_reg[23:20]), .seg(seg5));
assign HEX0 = {1'b1, seg0};
assign HEX1 = {1'b1, seg1};
assign HEX2 = {1'b1, seg2};
assign HEX3 = {1'b1, seg3};
assign HEX4 = {1'b1, seg4};
assign HEX5 = {1'b1, seg5};

endmodule
