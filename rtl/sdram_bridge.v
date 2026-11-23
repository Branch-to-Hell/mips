/* PLT-8: CPU data bus -> SDRAM (Avalon-MM master), docs/contracts.md "Doom memory"
A load or store to the SDRAM region (ext_sel) holds the CPU with stall (its mem_stall)
until the SDRAM is done, one access at a time:
    IDLE -> CMD (read/write held while waitrequest = 1)
         -> WAIT (reads only: until readdatavalid)
         -> DONE (stall = 0 for one cycle: the CPU takes rdata on this edge and moves on)
A store costs ~3 cycles plus the controller's waitrequest; a load ~6-7 (CAS latency 2 and
the 32 -> 16 width adapter in sdram_sys).
DONE always goes back to IDLE: after it EX/MEM moves, so a load/store seen in IDLE is
always a new one, even at the same address.

Byte order (contracts.md "SDRAM"): the CPU is big-endian (mem_be[3] = bits 31..24 = the byte
at the lowest address), Avalon lanes are little-endian (byteenable[k] = bits 8k+7..8k =
byte address A+k). So the 4 bytes of writedata/readdata are swapped and byteenable is
reversed: byte A+k of the SDRAM is the byte the CPU sees at A+k.
busy tells the arbiter (sdram_arbiter) that this master holds the port: from its first
command cycle until the read data is back.
*/
module sdram_bridge (
    input clk,
    input reset,

    // CPU side (life_system bus_* / ext_*)
    input [31:0] addr,
    input [31:0] wdata,
    input [3:0] be,
    input re,
    input we,
    input sel,                      // addr is in the SDRAM region
    output [31:0] rdata,            // 0 unless answering a load (it is OR'd into the read bus)
    output stall,                   // the load/store in MEM is not done

    // Avalon-MM master
    output reg [25:0] avm_address,  // byte address, multiple of 4
    output reg avm_read,
    output reg avm_write,
    output reg [31:0] avm_writedata,
    output reg [3:0] avm_byteenable,
    input [31:0] avm_readdata,
    input avm_readdatavalid,
    input avm_waitrequest,
    output busy
);

localparam IDLE = 2'd0, CMD = 2'd1, WAIT = 2'd2, DONE = 2'd3;
reg [1:0] state = IDLE;
reg [31:0] rdata_q = 32'd0;
reg was_read = 1'b0;

wire access = sel && (re || we);

function [31:0] swap(input [31:0] w);
    swap = {w[7:0], w[15:8], w[23:16], w[31:24]};
endfunction

assign stall = access && state != DONE;
assign rdata = (state == DONE && was_read) ? rdata_q : 32'd0;
assign busy = state == CMD || state == WAIT;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        avm_read <= 1'b0;
        avm_write <= 1'b0;
        was_read <= 1'b0;
    end else begin
        case (state)
        IDLE:
            if (access) begin
                avm_address <= {addr[25:2], 2'b00};
                avm_writedata <= swap(wdata);
                avm_byteenable <= {be[0], be[1], be[2], be[3]};
                avm_read <= re;
                avm_write <= we && !re;
                was_read <= re;
                state <= CMD;
            end
        CMD:
            if (!avm_waitrequest) begin         // the command was accepted on this edge
                avm_read <= 1'b0;
                avm_write <= 1'b0;
                state <= avm_read ? WAIT : DONE;
            end
        WAIT:
            if (avm_readdatavalid) begin
                rdata_q <= swap(avm_readdata);
                state <= DONE;
            end
        DONE:
            state <= IDLE;
        endcase
    end
end

endmodule
