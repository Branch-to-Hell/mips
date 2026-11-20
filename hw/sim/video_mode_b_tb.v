`timescale 1ns/1ps
// PLT-6 test: video_mode_b alone. Run from hw/sim: do video_mode_b.do
/* Checks:
  1. CPU port, pixels: a word write puts its 4 pixels big-endian (bits 31..24 = pixel 4n),
     reads come back, and byte enables only change their own pixel
  2. CPU port, palette: power-up RGB 3-3-2 contents, write + read back (top 4 bits kept)
  3. one full frame: every pixel of the 640x480 output is palette[pixel(h/2, (v-40)/2)]
     inside the 640x400 image and black outside, hsync/vsync low the right number of
     pixels. The frame is saved in frame_b.ppm to look at it
The framebuffer starts with pixel (x, y) = (x + 2y) mod 256 and some entries of the
palette are changed, so a wrong address, lane or palette lookup shows up
*/
module video_mode_b_tb;

reg clk = 0;
always #20 clk = ~clk;                   // 25 MHz

reg fb_we = 0, pal_we = 0;
reg [3:0] fb_be = 4'b1111;
reg [13:0] fb_addr = 0;
reg [7:0] pal_addr = 0;
reg [31:0] fb_wdata = 0, pal_wdata = 0;
wire [31:0] fb_rdata, pal_rdata;
wire [3:0] r, g, b;
wire hs, vs;

video_mode_b dut (
    .clk(clk), .a_clk(clk),
    .fb_we(fb_we), .fb_be(fb_be), .fb_addr(fb_addr), .fb_wdata(fb_wdata), .fb_rdata(fb_rdata),
    .pal_we(pal_we), .pal_addr(pal_addr), .pal_wdata(pal_wdata), .pal_rdata(pal_rdata),
    .VGA_R(r), .VGA_G(g), .VGA_B(b), .VGA_HS(hs), .VGA_VS(vs)
);

integer errors = 0, pixels = 0, hs_low = 0, vs_low = 0, f, i, x, y;
reg checking = 0;

task check(input [8*40-1:0] what, input [31:0] got, input [31:0] expected);
    if (got !== expected) begin
        $display("FAIL %0s: got %h, expected %h", what, got, expected);
        errors = errors + 1;
    end
endtask

// Like the CPU: address and data change after posedge, the memories work on negedge
task fb_write(input [13:0] a, input [31:0] d, input [3:0] be);
    begin
        @(posedge clk); #1;
        fb_addr = a; fb_wdata = d; fb_be = be; fb_we = 1;
        @(posedge clk); #1;
        fb_we = 0; fb_be = 4'b1111;
    end
endtask

task fb_read(input [13:0] a, output [31:0] d);
    begin
        @(posedge clk); #1;
        fb_addr = a;
        @(posedge clk);
        d = fb_rdata;
    end
endtask

task pal_write(input [7:0] a, input [31:0] d);
    begin
        @(posedge clk); #1;
        pal_addr = a; pal_wdata = d; pal_we = 1;
        @(posedge clk); #1;
        pal_we = 0;
    end
endtask

task pal_read(input [7:0] a, output [31:0] d);
    begin
        @(posedge clk); #1;
        pal_addr = a;
        @(posedge clk);
        d = pal_rdata;
    end
endtask

// Expected contents, from the testbench's own copy (the model)
reg [7:0] pix [0:63999];
reg [11:0] pal [0:255];
reg [31:0] d;

initial begin
    // Start image straight into the banks (as if the CPU had drawn it)
    for (y = 0; y < 200; y = y + 1)
        for (x = 0; x < 320; x = x + 1)
            pix[y * 320 + x] = (x + 2 * y) % 256;
    for (i = 0; i < 16000; i = i + 1) begin
        dut.fb.bank0[i] = pix[4 * i];
        dut.fb.bank1[i] = pix[4 * i + 1];
        dut.fb.bank2[i] = pix[4 * i + 2];
        dut.fb.bank3[i] = pix[4 * i + 3];
    end

    // 1. Pixels through the CPU port
    fb_write(14'd0, 32'h11223344, 4'b1111);          // pixels (0..3, 0)
    fb_read(14'd0, d);
    check("1. word read", d, 32'h11223344);
    check("1. pixel 0 = bits 31..24", dut.fb.bank0[0], 8'h11);
    check("1. pixel 3 = bits 7..0", dut.fb.bank3[0], 8'h44);
    fb_write(14'd0, 32'hAABBCCDD, 4'b0100);          // only pixel 1
    fb_read(14'd0, d);
    check("1. byte enable pixel 1", d, 32'h11BB3344);
    fb_write(14'd0, 32'hAABBCCDD, 4'b1001);          // pixels 0 and 3
    fb_read(14'd0, d);
    check("1. byte enable pixels 0, 3", d, 32'hAABB33DD);
    fb_write(14'd15999, 32'h01020304, 4'b1111);      // last 4 pixels (316..319, 199)
    fb_read(14'd15999, d);
    check("1. last word", d, 32'h01020304);
    {pix[0], pix[1], pix[2], pix[3]} = 32'hAABB33DD;
    {pix[63996], pix[63997], pix[63998], pix[63999]} = 32'h01020304;

    // 2. Palette
    pal_read(8'b111_000_00, d);
    check("2. power-up red", d, 32'h00FF0000);
    pal_read(8'b000_111_11, d);
    check("2. power-up cyan", d, 32'h0000FFFF);
    pal_read(8'b101_010_01, d);                       // R 5 -> 1011, G 2 -> 0100, B 1 -> 0101
    check("2. power-up mixed", d, 32'h00BB4455);
    for (i = 0; i < 256; i = i + 1) pal[i] = dut.pal.mem[i];
    pal_write(8'd0, 32'h00123456);
    pal_read(8'd0, d);
    check("2. write entry 0", d, 32'h00113355);       // top 4 bits of each color
    pal_write(8'd255, 32'h00FFFFFF);
    pal_write(8'd100, 32'h00F0A050);
    pal[0] = 12'h135; pal[255] = 12'hFFF; pal[100] = 12'hFA5;

    // 3. Check one whole frame from the start
    f = $fopen("frame_b.ppm", "w");
    $fwrite(f, "P3\n640 480\n15\n");
    wait (dut.h == 799 && dut.v == 524);
    @(posedge clk);                                   // the next pixel is (0, 0)
    @(posedge clk);
    checking = 1;
end

// The color leaves 2 cycles after h/v: delay them the same
reg [9:0] h1, v1, h2, v2;
always @(posedge clk) begin
    h1 <= dut.h; v1 <= dut.v;
    h2 <= h1;    v2 <= v1;
end

reg [11:0] expected;
always @(posedge clk) begin
    if (checking) begin
        #1;
        if (h2 < 640 && v2 >= 40 && v2 < 440)
            expected = pal[pix[((v2 - 40) / 2) * 320 + h2 / 2]];
        else
            expected = 12'h000;
        if ({r, g, b} !== expected) begin
            if (errors < 10) $display("FAIL pixel h=%0d v=%0d: %h, expected %h", h2, v2, {r, g, b}, expected);
            errors = errors + 1;
        end
        if (h2 < 640 && v2 < 480) begin
            $fwrite(f, "%0d %0d %0d\n", r, g, b);
            pixels = pixels + 1;
        end
        if (!hs) hs_low = hs_low + 1;
        if (!vs) vs_low = vs_low + 1;

        if (h2 == 799 && v2 == 524) begin             // end of the frame
            $fclose(f);
            if (hs_low != 96 * 525) begin $display("FAIL hsync low %0d pixels, expected %0d", hs_low, 96 * 525); errors = errors + 1; end
            if (vs_low != 2 * 800) begin $display("FAIL vsync low %0d pixels, expected %0d", vs_low, 2 * 800); errors = errors + 1; end
            $display("%0d pixels checked, frame_b.ppm saved", pixels);
            if (errors == 0) $display("PASS: video_mode_b_tb, all checks");
            else $display("FAIL: video_mode_b_tb, %0d errors", errors);
            $stop;
        end
    end
end

endmodule
