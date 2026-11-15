/* Top level for PLT-1: shows the image from fb_test.hex on the monitor
The CPU port is not connected yet (PLT-3)
*/
module top_video_test (
    input MAX10_CLK1_50,
    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B,
    output VGA_HS,
    output VGA_VS
);

video_mode_a #(.INIT_FILE("../mem/fb_test.hex")) video ( // path from hw/quartus
    .clk(MAX10_CLK1_50),
    .a_we(1'b0), .a_addr(14'd0), .a_wdata(32'd0), .a_rdata(),
    .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
    .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
);

endmodule
