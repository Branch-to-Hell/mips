/* Video mode A: shows the 128x96 framebuffer on the 640x480 monitor
Each pixel is drawn as a 5x5 square (640/5 = 128, 480/5 = 96)
*/
module video_mode_a #(
    parameter INIT_FILE = "" // initial image (.hex)
)(
    input clk, // 50 MHz

    // CPU port, goes straight to the framebuffer
    input a_we,
    input [13:0] a_addr,
    input [31:0] a_wdata,
    output [31:0] a_rdata,

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

// 2. Scale x5
/* Dividing by 5 can't be done by dropping bits like /2, so we count:
x_sub goes from 0 to 4 and every time it starts again x_cell moves to the next column
Rows work the same way but only move once per line
*/
reg [2:0] x_sub = 3'd0, y_sub = 3'd0; // 0 to 4
reg [6:0] x_cell = 7'd0, y_cell = 7'd0; // column (0 to 127) and row (0 to 95)

always @(posedge clk) begin
    if (pix_en) begin
        if (h == 10'd799) begin // new line, start from column 0
            x_sub <= 3'd0;
            x_cell <= 7'd0;
        end else if (x_sub == 3'd4) begin
            x_sub <= 3'd0;
            x_cell <= x_cell + 7'd1;
        end else
            x_sub <= x_sub + 3'd1;

        if (h == 10'd799) begin
            if (v == 10'd524) begin // new frame, start from row 0
                y_sub <= 3'd0;
                y_cell <= 7'd0;
            end else if (y_sub == 3'd4) begin
                y_sub <= 3'd0;
                y_cell <= y_cell + 7'd1;
            end else
                y_sub <= y_sub + 3'd1;
        end
    end
end

wire [13:0] b_addr = {y_cell, x_cell}; // same as y*128 + x

// 3. Read the framebuffer
wire [11:0] color;
framebuffer_a #(.INIT_FILE(INIT_FILE)) fb (
    .clk(clk),
    .a_we(a_we), .a_addr(a_addr), .a_wdata(a_wdata), .a_rdata(a_rdata),
    .b_addr(b_addr), .b_data(color)
);

// 4. Delay the signals 1 cycle so they arrive with their color
reg hs_d = 1'b1, vs_d = 1'b1, vis_d = 1'b0, pe_d = 1'b0; // pe_d is only for the testbench
always @(posedge clk) begin
    hs_d <= hsync;
    vs_d <= vsync;
    vis_d <= visible;
    pe_d <= pix_en;
end

// 5. Output, black outside the visible area
assign VGA_HS = hs_d;
assign VGA_VS = vs_d;
assign VGA_R = vis_d ? color[11:8] : 4'h0;
assign VGA_G = vis_d ? color[7:4] : 4'h0;
assign VGA_B = vis_d ? color[3:0] : 4'h0;

endmodule
