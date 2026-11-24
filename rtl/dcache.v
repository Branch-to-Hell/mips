/* Data cache for the SDRAM region (replaces sdram_bridge in ext_memory when DCACHE_LINES_LOG2 > 0),
docs/contracts.md "Doom memory". Direct-mapped, 2^LINES_LOG2 lines of 16 bytes (4 words):
LINES_LOG2 = 9 -> 8 KB, 10 -> 16 KB, 11 -> 32 KB.
    address bits (inside the 64 MB region): tag = [25:LINES_LOG2+4], index = [LINES_LOG2+3:4], word = [3:2]
Write-through, no write-allocate: every store goes to the SDRAM (so the SDRAM is always up to
date: nothing to write back, nothing stale for the JTAG master or the instruction cache), and
also into the line if the line is in the cache.

Loads:
  hit  -> answered in the same cycle, no wait: the RAMs are read with addr_next (mem_addr after
          the edge, from the CPU), so in the next cycle their outputs belong to addr (mem_addr).
  miss -> FILL: the line's 4 words are read from the SDRAM (pipelined, all 4 in flight) and
          written as they arrive, then the tag; DONE answers with the word that was asked for.
Stores: IDLE writes the bytes into the line if it hits (byte enables), then WCMD sends the write
to the SDRAM (held while waitrequest = 1), then DONE.
Every RAM write happens on the edge of the cycle that decides it (the write port is not
registered), so the RAM read on the next edge, the one the next load uses, already sees it.
DONE (stall = 0 for one cycle) always goes back to IDLE: EX/MEM moves on that edge.
Reset: CLEAR writes valid = 0 in every line (2^LINES_LOG2 cycles), then one SETTLE cycle so the
tag RAM is read once more before a hit is trusted.
Byte order like sdram_bridge: the CPU is big-endian, Avalon lanes little-endian, so Avalon words
are byte-swapped; the data RAM keeps CPU words (bank 0 = bits 31..24 = the lowest address).
busy tells the arbiter in ext_memory that this master holds the port (WCMD, FILL).
*/
module dcache #(
    parameter LINES_LOG2 = 9
)(
    input clk,
    input reset,

    // CPU side (life_system bus_* / ext_*)
    input [31:0] addr,              // bus_addr = mem_addr
    input [31:0] addr_next,         // bus_addr_next = mem_addr after this edge
    input [31:0] wdata,
    input [3:0] be,
    input re,
    input we,
    input sel,                      // addr is in the SDRAM region
    output [31:0] rdata,            // 0 unless answering a load (it is OR'd into the read bus)
    output stall,                   // the load/store in MEM is not done

    // Avalon-MM master
    output reg [25:0] avm_address,
    output reg avm_read,
    output reg avm_write,
    output reg [31:0] avm_writedata,
    output reg [3:0] avm_byteenable,
    input [31:0] avm_readdata,
    input avm_readdatavalid,
    input avm_waitrequest,
    output busy,

    // for the harness statistics: a load answered (hit or after a miss), a miss starts, a store done
    output ev_load,
    output ev_miss,
    output ev_store
);

localparam INDEX_LO = 4, INDEX_HI = LINES_LOG2 + 3;
localparam TAG_BITS = 26 - (LINES_LOG2 + 4);
localparam LINES = 1 << LINES_LOG2;
localparam WORDS = 4 * LINES;

localparam CLEAR = 3'd0, SETTLE = 3'd1, IDLE = 3'd2, WCMD = 3'd3, FILL = 3'd4, DONE = 3'd5;
reg [2:0] state = CLEAR;

function [31:0] swap(input [31:0] w);
    swap = {w[7:0], w[15:8], w[23:16], w[31:24]};
endfunction

// ---- RAMs: tags (valid + tag) and 4 byte banks, read with addr_next ----
reg [TAG_BITS:0] tag_ram [0:LINES-1];
reg [7:0] bank0 [0:WORDS-1];        // bits 31..24
reg [7:0] bank1 [0:WORDS-1];        // bits 23..16
reg [7:0] bank2 [0:WORDS-1];        // bits 15..8
reg [7:0] bank3 [0:WORDS-1];        // bits 7..0
reg [TAG_BITS:0] tag_q;
reg [7:0] q0, q1, q2, q3;

wire tag_we;
wire [LINES_LOG2-1:0] tag_waddr;
wire [TAG_BITS:0] tag_wdata;
wire [3:0] data_we;                 // per bank: [0] = bank0 (bits 31..24)
wire [LINES_LOG2+1:0] data_waddr;
wire [31:0] data_wdata;

wire [LINES_LOG2-1:0] read_line = addr_next[INDEX_HI:INDEX_LO];
wire [LINES_LOG2+1:0] read_word = addr_next[INDEX_HI:2];

always @(posedge clk) begin
    if (tag_we) tag_ram[tag_waddr] <= tag_wdata;
    tag_q <= tag_ram[read_line];
end
always @(posedge clk) begin
    if (data_we[0]) bank0[data_waddr] <= data_wdata[31:24];
    q0 <= bank0[read_word];
end
always @(posedge clk) begin
    if (data_we[1]) bank1[data_waddr] <= data_wdata[23:16];
    q1 <= bank1[read_word];
end
always @(posedge clk) begin
    if (data_we[2]) bank2[data_waddr] <= data_wdata[15:8];
    q2 <= bank2[read_word];
end
always @(posedge clk) begin
    if (data_we[3]) bank3[data_waddr] <= data_wdata[7:0];
    q3 <= bank3[read_word];
end

// ---- hit ----
wire [TAG_BITS-1:0] tag = addr[25:INDEX_HI+1];
wire [LINES_LOG2-1:0] index = addr[INDEX_HI:INDEX_LO];
wire hit = tag_q[TAG_BITS] && tag_q[TAG_BITS-1:0] == tag;
wire access = sel && (re || we);
wire load_hit = state == IDLE && sel && re && hit;
wire store_hit = state == IDLE && sel && we && hit;

reg [31:0] word_q = 32'd0;          // the word a missed load asked for
reg was_read = 1'b0;
assign stall = access && !(load_hit || state == DONE);
assign rdata = load_hit ? {q0, q1, q2, q3} : (state == DONE && was_read) ? word_q : 32'd0;
assign busy = state == WCMD || state == FILL;

// ---- fill bookkeeping ----
reg [LINES_LOG2-1:0] clear_index = 0;
reg [2:0] sent, got;
reg [1:0] want;                     // word of the line the load asked for
reg [LINES_LOG2-1:0] fill_index;
reg [TAG_BITS-1:0] fill_tag;
wire fill_word = state == FILL && avm_readdatavalid;

// ---- RAM writes, decided in this cycle, done on this edge ----
assign tag_we = state == CLEAR || (fill_word && got == 3);
assign tag_waddr = state == CLEAR ? clear_index : fill_index;
assign tag_wdata = state == CLEAR ? {(TAG_BITS + 1){1'b0}} : {1'b1, fill_tag};
assign data_we = fill_word ? 4'b1111 : store_hit ? {be[0], be[1], be[2], be[3]} : 4'b0000;
assign data_waddr = fill_word ? {fill_index, got[1:0]} : addr[INDEX_HI:2];
assign data_wdata = fill_word ? swap(avm_readdata) : wdata;

assign ev_load = load_hit || (state == DONE && was_read);
assign ev_miss = state == IDLE && sel && re && !hit;
assign ev_store = state == DONE && !was_read;

always @(posedge clk) begin
    if (reset) begin
        state <= CLEAR;
        clear_index <= 0;
        avm_read <= 1'b0;
        avm_write <= 1'b0;
        was_read <= 1'b0;
    end else begin
        case (state)
        CLEAR: begin
            clear_index <= clear_index + 1'b1;
            if (clear_index == LINES - 1) state <= SETTLE;
        end
        SETTLE:
            state <= IDLE;
        IDLE:
            if (access && !load_hit) begin
                if (we) begin                                   // store: write-through
                    avm_address <= {addr[25:2], 2'b00};
                    avm_writedata <= swap(wdata);
                    avm_byteenable <= {be[0], be[1], be[2], be[3]};
                    avm_write <= 1'b1;
                    was_read <= 1'b0;
                    state <= WCMD;
                end else begin                                  // load miss: fill the line
                    fill_index <= index;
                    fill_tag <= tag;
                    want <= addr[3:2];
                    avm_address <= {addr[25:4], 4'b0000};
                    avm_byteenable <= 4'b1111;
                    avm_read <= 1'b1;
                    sent <= 0;
                    got <= 0;
                    was_read <= 1'b1;
                    state <= FILL;
                end
            end
        WCMD:
            if (!avm_waitrequest) begin
                avm_write <= 1'b0;
                state <= DONE;
            end
        FILL: begin
            if (avm_read && !avm_waitrequest) begin
                sent <= sent + 1'b1;
                avm_address <= avm_address + 26'd4;
                if (sent == 3) avm_read <= 1'b0;
            end
            if (avm_readdatavalid) begin
                if (got[1:0] == want) word_q <= swap(avm_readdata);
                got <= got + 1'b1;
                if (got == 3) state <= DONE;
            end
        end
        DONE:
            state <= IDLE;
        default:
            state <= IDLE;
        endcase
    end
end

endmodule
