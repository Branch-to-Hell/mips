/* Framebuffer for video mode A: 128x96 pixels, one word per pixel (0x00RRGGBB, like MARS)
The VGA only has 4 bits per color, so we only store the top 4 bits of each one (12 bits per pixel)
Pixel (x, y) is in position y*128 + x
*/
module framebuffer_a #(
    parameter INIT_FILE = "" // .hex file with the initial image; empty = no init
)(
    // port A: CPU (not used yet, it gets connected in PLT-3)
    input a_clk, // CPU clock
    input a_we,
    input [13:0] a_addr, // pixel number (0 to 12287)
    input [31:0] a_wdata, // 0x00RRGGBB
    output reg [31:0] a_rdata,

    // port B: VGA, read only
    input b_clk, // pixel clock
    input [13:0] b_addr, // pixel number (0 to 12287)
    output reg [11:0] b_data // {R, G, B}
);
    reg [11:0] mem [0:12287];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    /* Port A reads and writes on negedge, like the data memory (contracts.md, "Memory timing"),
    so a single-cycle lw gets the data in the same cycle.
    Each port has its own clock, the M9K blocks support it
    */
    reg [11:0] a_q;
    always @(negedge a_clk) begin
        if (a_we)
            mem[a_addr] <= {a_wdata[23:20], a_wdata[15:12], a_wdata[7:4]}; // keep the top 4 bits of each color
        a_q <= mem[a_addr];
    end

    // each 4 bits are repeated so 0xFF comes back as 0xFF
    always @(*)
        a_rdata = {8'h00, a_q[11:8], a_q[11:8], a_q[7:4], a_q[7:4], a_q[3:0], a_q[3:0]};

    // reads use the clock so Quartus puts the memory in the M9K blocks
    always @(posedge b_clk)
        b_data <= mem[b_addr];
endmodule
