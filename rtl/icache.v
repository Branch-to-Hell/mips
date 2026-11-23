/* PLT-12: instruction cache for code in the SDRAM, docs/contracts.md "Doom memory"
Direct-mapped, 2^LINES_LOG2 lines of 16 bytes (4 words), read-only (code is never written):
LINES_LOG2 = 9 -> 512 lines = 8 KB of instructions.
    address bits (inside the 64 MB region): tag = [25:LINES_LOG2+4], index = [LINES_LOG2+3:4], word = [3:2]

One hit per cycle with M9K RAMs (synchronous read): the RAMs are read with ifetch_next, the
address fetch_pc will hold after the edge, so in the next cycle their outputs belong to
fetch_pc (ifetch_addr) and ready/data are just a tag compare (CPU-9 fetch port: data must stay
valid while the address doesn't change, and it does, since the RAMs keep reading fetch_pc).

Miss: the line's 4 words are read from the SDRAM (Avalon-MM, pipelined: up to 4 reads in
flight, readdatavalid in order) and written into the data RAM as they arrive, then the tag.
The RAM write inputs are registered, so the last write happens one edge after FILL ends; SETTLE
waits two cycles, until the RAMs have been read again after it, before a hit/miss is decided
again (a RAM read on the same edge as the write returns the old data).
Reset: CLEAR walks all the lines and writes valid = 0 (2^LINES_LOG2 cycles), so after a CPU
reset with a new image in the SDRAM nothing old is used.
Byte order: like sdram_bridge, the 4 bytes of each Avalon word are swapped (big-endian CPU).
*/
module icache #(
    parameter LINES_LOG2 = 9
)(
    input clk,
    input reset,

    // CPU fetch port (life_system ifetch_*)
    input [31:0] addr,              // ifetch_addr = fetch_pc
    input [31:0] addr_next,         // ifetch_next = fetch_pc after this edge
    input req,                      // fetch_pc is in the SDRAM region
    output [31:0] data,
    output ready,

    // Avalon-MM master (reads only)
    output reg [25:0] avm_address,
    output reg avm_read,
    input [31:0] avm_readdata,
    input avm_readdatavalid,
    input avm_waitrequest,
    output busy                     // holds the port: from the first read to the last word
);

localparam INDEX_LO = 4, INDEX_HI = LINES_LOG2 + 3;
localparam TAG_BITS = 26 - (LINES_LOG2 + 4);
localparam LINES = 1 << LINES_LOG2;

localparam CLEAR = 2'd0, IDLE = 2'd1, FILL = 2'd2, SETTLE = 2'd3;
reg [1:0] state = CLEAR;
reg settle_wait = 1'b0;         // SETTLE: first of its two cycles

// ---- RAMs: tag (valid + tag per line) and data (one word per entry), registered read address ----
reg [TAG_BITS:0] tag_ram [0:LINES-1];
reg [31:0] data_ram [0:4*LINES-1];
reg [TAG_BITS:0] tag_q;
reg [31:0] data_q;

reg tag_we;
reg [LINES_LOG2-1:0] tag_waddr;
reg [TAG_BITS:0] tag_wdata;
reg data_we;
reg [LINES_LOG2+1:0] data_waddr;
reg [31:0] data_wdata;

always @(posedge clk) begin
    if (tag_we) tag_ram[tag_waddr] <= tag_wdata;
    tag_q <= tag_ram[addr_next[INDEX_HI:INDEX_LO]];
end
always @(posedge clk) begin
    if (data_we) data_ram[data_waddr] <= data_wdata;
    data_q <= data_ram[addr_next[INDEX_HI:2]];
end

// ---- hit ----
wire [TAG_BITS-1:0] tag = addr[25:INDEX_HI+1];
wire [LINES_LOG2-1:0] index = addr[INDEX_HI:INDEX_LO];
wire hit = tag_q[TAG_BITS] && tag_q[TAG_BITS-1:0] == tag;
assign ready = state == IDLE && req && hit;
assign data = data_q;
assign busy = state == FILL;

// ---- miss: fill the line ----
reg [LINES_LOG2-1:0] clear_index = 0;
reg [2:0] sent;                 // reads accepted so far (0..4)
reg [2:0] got;                  // words back so far (0..4)
reg [LINES_LOG2-1:0] fill_index;
reg [TAG_BITS-1:0] fill_tag;

always @(posedge clk) begin
    tag_we <= 1'b0;
    data_we <= 1'b0;
    if (reset) begin
        state <= CLEAR;
        clear_index <= 0;
        avm_read <= 1'b0;
    end else begin
        case (state)
        CLEAR: begin
            tag_we <= 1'b1;
            tag_waddr <= clear_index;
            tag_wdata <= 0;
            clear_index <= clear_index + 1'b1;
            if (clear_index == LINES - 1) begin
                state <= SETTLE;
                settle_wait <= 1'b1;
            end
        end
        IDLE:
            if (req && !hit) begin
                fill_index <= index;
                fill_tag <= tag;
                avm_address <= {addr[25:4], 4'b0000};
                avm_read <= 1'b1;
                sent <= 0;
                got <= 0;
                state <= FILL;
            end
        FILL: begin
            if (avm_read && !avm_waitrequest) begin     // this read was accepted
                sent <= sent + 1'b1;
                avm_address <= avm_address + 26'd4;
                if (sent == 3) avm_read <= 1'b0;
            end
            if (avm_readdatavalid) begin
                data_we <= 1'b1;
                data_waddr <= {fill_index, got[1:0]};
                data_wdata <= {avm_readdata[7:0], avm_readdata[15:8], avm_readdata[23:16], avm_readdata[31:24]};
                got <= got + 1'b1;
                if (got == 3) begin
                    tag_we <= 1'b1;
                    tag_waddr <= fill_index;
                    tag_wdata <= {1'b1, fill_tag};
                    state <= SETTLE;
                    settle_wait <= 1'b1;
                end
            end
        end
        SETTLE: begin
            settle_wait <= 1'b0;
            if (!settle_wait) state <= IDLE;
        end
        endcase
    end
end

endmodule
