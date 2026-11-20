/* 256-color palette for video mode B (PLT-6)
The CPU writes entry i as one word 0x00RRGGBB, the same format as a mode A pixel.
The VGA only has 4 bits per color, so only the top 4 bits of each one are stored
After power-up it holds the RGB 3-3-2 palette (index bits RRRGGGBB), so an image
shows something even before the program writes its own colors
*/
module palette (
    // port A: CPU
    input a_clk,
    input a_we,
    input [7:0] a_addr,         // entry (0 to 255)
    input [31:0] a_wdata,       // 0x00RRGGBB
    output [31:0] a_rdata,

    // port B: VGA, read only
    input b_clk,
    input [7:0] b_addr,         // palette index of the pixel
    output reg [11:0] b_data    // {R, G, B}, 1 cycle after b_addr
);
    reg [11:0] mem [0:255];

    // RGB 3-3-2: 3 bits are scaled to 4 as {b2 b1 b0 b2}, 2 bits as {b1 b0 b1 b0}
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = {i[7:5], i[7], i[4:2], i[4], i[1:0], i[1:0]};
    end

    // Port A reads and writes on negedge, like the data memory (contracts.md, "Memory timing")
    reg [11:0] a_q;
    always @(negedge a_clk) begin
        if (a_we)
            mem[a_addr] <= {a_wdata[23:20], a_wdata[15:12], a_wdata[7:4]};
        a_q <= mem[a_addr];
    end

    // each 4 bits are repeated so 0xFF comes back as 0xFF (same as framebuffer_a)
    assign a_rdata = {8'h00, a_q[11:8], a_q[11:8], a_q[7:4], a_q[7:4], a_q[3:0], a_q[3:0]};

    always @(posedge b_clk)
        b_data <= mem[b_addr];
endmodule
