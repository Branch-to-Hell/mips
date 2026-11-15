`timescale 1ns/1ps
/* Testbench for video_mode_a
Simulates one full frame, checks every pixel against the framebuffer and saves
what the monitor would show in frame.ppm (640x480), so the image can be seen without the board
*/
module video_mode_a_tb;

reg clk = 0;
always #10 clk = ~clk; // 50 MHz

reg a_we = 0;
reg [13:0] a_addr = 0;
reg [31:0] a_wdata = 0;
wire [31:0] a_rdata;
wire [3:0] r, g, b;
wire hs, vs;

video_mode_a #(.INIT_FILE("../mem/fb_test.hex")) dut (
    .clk(clk),
    .a_we(a_we), .a_addr(a_addr), .a_wdata(a_wdata), .a_rdata(a_rdata),
    .VGA_R(r), .VGA_G(g), .VGA_B(b), .VGA_HS(hs), .VGA_VS(vs)
);

integer f, errors = 0, pixels = 0, hs_low = 0, vs_low = 0;
reg [9:0] h_d, v_d; // h and v delayed 1 cycle, like the color

// 1. CPU port: write a color and read it back
initial begin
    @(posedge clk);
    a_we = 1; a_addr = 14'd12287; a_wdata = 32'h00FF8000; // last pixel, orange
    @(posedge clk);
    a_we = 0;
    @(posedge clk);
    #1;
    if (a_rdata !== 32'h00FF8800) begin
        $display("ERROR port A: read %h, expected 00FF8800", a_rdata);
        errors = errors + 1;
    end
end

// 2. Check the frame and save it
initial begin
    f = $fopen("frame.ppm", "w");
    $fwrite(f, "P3\n640 480\n15\n"); // text image, 4 bits per color
end

always @(posedge clk) begin
    h_d <= dut.h;
    v_d <= dut.v;
end

always @(posedge clk) begin
    if (dut.pe_d) begin // one pixel every other cycle
        if (h_d < 640 && v_d < 480) begin
            if ({r, g, b} !== dut.fb.mem[(v_d / 5) * 128 + h_d / 5]) begin
                if (errors < 10) $display("ERROR pixel h=%0d v=%0d: %h, expected %h", h_d, v_d, {r, g, b}, dut.fb.mem[(v_d / 5) * 128 + h_d / 5]);
                errors = errors + 1;
            end
            $fwrite(f, "%0d %0d %0d\n", r, g, b);
            pixels = pixels + 1;
        end else if ({r, g, b} !== 12'h000) begin
            if (errors < 10) $display("ERROR color outside the visible area at h=%0d v=%0d", h_d, v_d);
            errors = errors + 1;
        end
        if (!hs) hs_low = hs_low + 1;
        if (!vs) vs_low = vs_low + 1;

        if (h_d == 799 && v_d == 524) begin // end of the frame
            $fclose(f);
            if (hs_low != 96 * 525) begin $display("ERROR hsync low %0d pixels, expected %0d", hs_low, 96 * 525); errors = errors + 1; end
            if (vs_low != 2 * 800) begin $display("ERROR vsync low %0d pixels, expected %0d", vs_low, 2 * 800); errors = errors + 1; end
            $display("%0d pixels checked, frame.ppm saved", pixels);
            if (errors == 0) $display("PASS");
            else $display("FAIL: %0d errors", errors);
            $stop;
        end
    end
end

endmodule
