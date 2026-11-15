/* VGA timing for 640x480 at 60 Hz
Horizontal: 640 visible, 16 front porch, 96 sync, 48 back porch = 800
Vertical: 480 visible, 10 front porch, 2 sync, 33 back porch = 525
*/
module vga_sync (
    input clk, // 50 MHz
    output reg pix_en, // 1 every other cycle, so one pixel at 25 MHz
    output reg [9:0] h, // current column (0 to 799)
    output reg [9:0] v, // current line (0 to 524)
    output hsync,
    output vsync,
    output visible // 1 inside the 640x480 area
);
    initial begin
        pix_en = 1'b0;
        h = 10'd0;
        v = 10'd0;
    end

    always @(posedge clk)
        pix_en <= ~pix_en;

    always @(posedge clk) begin
        if (pix_en) begin
            if (h == 10'd799) begin // end of the line, go to the next one
                h <= 10'd0;
                v <= (v == 10'd524) ? 10'd0 : v + 10'd1;
            end else
                h <= h + 10'd1;
        end
    end

    // both syncs are active low
    assign hsync = ~((h >= 10'd656) && (h < 10'd752));
    assign vsync = ~((v >= 10'd490) && (v < 10'd492));
    assign visible = (h < 10'd640) && (v < 10'd480);
endmodule
