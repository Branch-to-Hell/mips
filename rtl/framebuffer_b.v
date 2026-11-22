/* Framebuffer for video mode B (PLT-6): 320x200 pixels, 8 bits per pixel (a palette index)
Pixel (x, y) is the byte at offset y*320 + x. Big-endian like the rest of the system
(contracts.md): the word at offset 4n holds pixels 4n..4n+3, and pixel 4n is bits 31..24
Built as 4 byte-lane banks of 16,000 bytes (like the instruction memory, CPU-12):
bank k holds the pixels with offset[1:0] = k, indexed by offset[15:2]. That gives each
byte its own write enable, ready for sb/sh (CPU-7)
*/
module framebuffer_b (
    // port A: CPU, one word (4 pixels) at a time
    input a_clk,
    input a_we,
    input [3:0] a_be,           // byte enables, Avalon style: a_be[3] = bits 31..24 = pixel 4n
    input [13:0] a_addr,        // word number (0 to 15999) = offset[15:2]
    input [31:0] a_wdata,
    output reg [31:0] a_rdata,

    // port B: VGA, one pixel at a time, read only
    input b_clk,
    input [15:0] b_addr,        // pixel number (0 to 63999)
    output [7:0] b_data         // palette index, 1 cycle after b_addr
);
    reg [7:0] bank0 [0:15999];  // pixels 4n   (bits 31..24)
    reg [7:0] bank1 [0:15999];  // pixels 4n+1 (bits 23..16)
    reg [7:0] bank2 [0:15999];  // pixels 4n+2 (bits 15..8)
    reg [7:0] bank3 [0:15999];  // pixels 4n+3 (bits 7..0)

    /* Port A reads and writes on negedge, like the data memory (contracts.md, "Memory timing")
    Each port has its own clock, the M9K blocks support it
    */
    always @(negedge a_clk) begin
        if (a_we && a_be[3]) bank0[a_addr] <= a_wdata[31:24];
        if (a_we && a_be[2]) bank1[a_addr] <= a_wdata[23:16];
        if (a_we && a_be[1]) bank2[a_addr] <= a_wdata[15:8];
        if (a_we && a_be[0]) bank3[a_addr] <= a_wdata[7:0];
        a_rdata <= {bank0[a_addr], bank1[a_addr], bank2[a_addr], bank3[a_addr]};
    end

    /* Port B reads the 4 banks at the same index on posedge (so Quartus uses M9K blocks)
    and keeps which bank it wants; the mux after the registers picks the pixel
    */
    reg [7:0] q0, q1, q2, q3;
    reg [1:0] lane;
    always @(posedge b_clk) begin
        q0 <= bank0[b_addr[15:2]];
        q1 <= bank1[b_addr[15:2]];
        q2 <= bank2[b_addr[15:2]];
        q3 <= bank3[b_addr[15:2]];
        lane <= b_addr[1:0];
    end

    assign b_data = (lane == 2'd0) ? q0 :
                    (lane == 2'd1) ? q1 :
                    (lane == 2'd2) ? q2 : q3;
endmodule
