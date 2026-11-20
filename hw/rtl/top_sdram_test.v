/* Top level for PLT-7 / PLT-9: SDRAM controller on the board (Quartus revision sdram_test)
pll_sdram (25 MHz + shifted DRAM_CLK) -> sdram_sys (Platform Designer: 32-bit bridge +
Intel SDRAM controller) <- sdram_smoke (writes a pattern, reads it back)
PLT-9: the whole 64 MB (16M words), about 10 s per run
The test runs once after reset and again on every KEY0 press
PLT-10: sdram_sys also has a JTAG to Avalon Master, so System Console can load a file
(the WAD) into the SDRAM while this design runs (sw/tools/wad_load.tcl). The smoke test
writes all 64 MB, so SW9 = 1 keeps it from starting: set SW9 before loading the WAD
    LEDR0 = test running, LEDR1 = done and passed, LEDR2 = done with errors,
    LEDR8 = SW9 lock on (smoke test will not start), LEDR9 = PLL locked
    HEX = no errors: KB tested (010000 = 64 MB); errors: count of bad words
          (SW0 = 1: number of the first bad word = its byte address / 4)
KEY1 = reset
*/
module top_sdram_test (
    input MAX10_CLK1_50,
    input [9:0] SW,
    input [1:0] KEY,
    output [9:0] LEDR,
    output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,

    // SDRAM (ISSI IS42S16320D, 32M x 16)
    output [12:0] DRAM_ADDR,
    output [1:0] DRAM_BA,
    output DRAM_CAS_N, DRAM_RAS_N, DRAM_WE_N, DRAM_CS_N,
    output DRAM_CKE, DRAM_CLK,
    output DRAM_LDQM, DRAM_UDQM,
    inout [15:0] DRAM_DQ
);

localparam [24:0] WORDS = 25'd16777216;       // PLT-9: all 64 MB (16M words of 32 bits)

wire clk, locked;
pll_sdram pll (.inclk0(MAX10_CLK1_50), .c0(clk), .c1(DRAM_CLK), .locked(locked));

// Keys, debounced (1 = pressed)
wire key0, key1;
debounce db0 (.clk(clk), .key_n(KEY[0]), .pressed(key0));
debounce db1 (.clk(clk), .key_n(KEY[1]), .pressed(key1));

// Reset: PLL not locked or KEY1 pressed, then 16 more cycles
reg [4:0] por = 0;
always @(posedge clk)
    if (!locked || key1) por <= 0;
    else if (!por[4]) por <= por + 1'b1;
wire reset = !por[4];

// Start once after reset and on every KEY0 press, unless SW9 locks the SDRAM for the WAD
// (SW9 is a slow manual switch, only gating a start pulse: a 2-flop sync is enough)
reg [1:0] lock_sync = 0;
reg key0_prev = 0, after_reset = 1;
always @(posedge clk) begin
    lock_sync <= {lock_sync[0], SW[9]};
    key0_prev <= key0;
    after_reset <= reset;
end
wire lock = lock_sync[1];
wire start = !lock && ((after_reset && !reset) || (key0 && !key0_prev));

// Avalon-MM between the test and the SDRAM system
wire [25:0] address;
wire [31:0] writedata, readdata;
wire [3:0] byteenable;
wire read, write, readdatavalid, waitrequest;

sdram_sys sdram (
    .clk_clk(clk),
    .reset_reset_n(!reset),
    .mem_address(address),
    .mem_read(read),
    .mem_write(write),
    .mem_writedata(writedata),
    .mem_byteenable(byteenable),
    .mem_burstcount(1'b1),
    .mem_debugaccess(1'b0),
    .mem_readdata(readdata),
    .mem_readdatavalid(readdatavalid),
    .mem_waitrequest(waitrequest),
    .wire_addr(DRAM_ADDR),
    .wire_ba(DRAM_BA),
    .wire_cas_n(DRAM_CAS_N),
    .wire_ras_n(DRAM_RAS_N),
    .wire_we_n(DRAM_WE_N),
    .wire_cs_n(DRAM_CS_N),
    .wire_cke(DRAM_CKE),
    .wire_dq(DRAM_DQ),
    .wire_dqm({DRAM_UDQM, DRAM_LDQM})
);

wire busy, done;
wire [23:0] errors;
wire [25:0] first_bad;
sdram_smoke #(.WORDS(WORDS)) test (
    .clk(clk), .reset(reset), .start(start),
    .address(address), .read(read), .write(write),
    .writedata(writedata), .byteenable(byteenable),
    .readdata(readdata), .readdatavalid(readdatavalid), .waitrequest(waitrequest),
    .busy(busy), .done(done), .errors(errors), .first_bad(first_bad)
);

assign LEDR = {locked, lock, 5'b0, done && errors != 0, done && errors == 0, busy};

wire [23:0] kb_tested = WORDS >> 8;             // words * 4 / 1024
wire [23:0] shown = (errors == 0) ? kb_tested : (SW[0] ? first_bad[25:2] : errors);
hex7seg h0 (.value(shown[3:0]),   .seg(HEX0[6:0]));
hex7seg h1 (.value(shown[7:4]),   .seg(HEX1[6:0]));
hex7seg h2 (.value(shown[11:8]),  .seg(HEX2[6:0]));
hex7seg h3 (.value(shown[15:12]), .seg(HEX3[6:0]));
hex7seg h4 (.value(shown[19:16]), .seg(HEX4[6:0]));
hex7seg h5 (.value(shown[23:20]), .seg(HEX5[6:0]));
assign {HEX5[7], HEX4[7], HEX3[7], HEX2[7], HEX1[7], HEX0[7]} = 6'b111111;

endmodule
