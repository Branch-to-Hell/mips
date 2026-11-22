/* Video mode B (PLT-6): 320x200, 8 bits per pixel + 256-color palette, for Doom
Each pixel is drawn as a 2x2 square: 640x400, centered on the 640x480 monitor
with 40 black lines above and below
Two reads per pixel, one cycle each: framebuffer (palette index) -> palette (color),
so the sync signals are delayed 2 cycles to arrive with their color
*/
module video_mode_b (
    input clk, // pixel clock (25 MHz)

    // CPU port: pixels (framebuffer_b)
    input a_clk,
    input fb_we,
    input [3:0] fb_be,
    input [13:0] fb_addr,       // word number (0 to 15999)
    input [31:0] fb_wdata,
    output [31:0] fb_rdata,

    // CPU port: palette
    input pal_we,
    input [7:0] pal_addr,       // entry (0 to 255)
    input [31:0] pal_wdata,     // 0x00RRGGBB
    output [31:0] pal_rdata,

    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B,
    output VGA_HS,
    output VGA_VS
);

// 1. VGA timing
wire pix_en, hsync, vsync, visible;
wire [9:0] h, v;
vga_sync sync (
    .clk(clk), .pix_en(pix_en), .h(h), .v(v),
    .hsync(hsync), .vsync(vsync), .visible(visible)
);

// 2. Scale x2: drop the lowest bit of h and of (v - 40)
wire in_image = visible && (v >= 10'd40) && (v < 10'd440);
wire [9:0] v_img = v - 10'd40;
wire [8:0] x = h[9:1];          // 0 to 319
wire [7:0] y = v_img[8:1];      // 0 to 199
// y*320 + x: y*320 = y*256 + y*64 (outside the image the address doesn't matter)
wire [15:0] b_addr = {y, 8'b0} + {2'b0, y, 6'b0} + {7'b0, x};

// 3. Framebuffer -> palette index (1 cycle), palette -> color (1 cycle)
wire [7:0] index;
framebuffer_b fb (
    .a_clk(a_clk), .a_we(fb_we), .a_be(fb_be), .a_addr(fb_addr),
    .a_wdata(fb_wdata), .a_rdata(fb_rdata),
    .b_clk(clk), .b_addr(b_addr), .b_data(index)
);

wire [11:0] color;
palette pal (
    .a_clk(a_clk), .a_we(pal_we), .a_addr(pal_addr), .a_wdata(pal_wdata), .a_rdata(pal_rdata),
    .b_clk(clk), .b_addr(index), .b_data(color)
);

// 4. Delay the signals 2 cycles so they arrive with their color
reg [1:0] hs_d = 2'b11, vs_d = 2'b11, img_d = 2'b00;
always @(posedge clk) begin
    hs_d <= {hs_d[0], hsync};
    vs_d <= {vs_d[0], vsync};
    img_d <= {img_d[0], in_image};
end

// 5. Output, black outside the 640x400 image
assign VGA_HS = hs_d[1];
assign VGA_VS = vs_d[1];
assign VGA_R = img_d[1] ? color[11:8] : 4'h0;
assign VGA_G = img_d[1] ? color[7:4] : 4'h0;
assign VGA_B = img_d[1] ? color[3:0] : 4'h0;

endmodule
