/* PLT-8 + PLT-12: everything between life_system's external side (EXT_BUS = 1) and the
SDRAM's Avalon-MM port (sdram_sys "mem"), docs/contracts.md "Doom memory":
    loads/stores to the SDRAM region -> dcache (data cache, DCACHE_LINES_LOG2 > 0) or, with
        DCACHE_LINES_LOG2 = 0, sdram_bridge (every load/store goes to the SDRAM); either one
        holds the CPU with ext_stall while it waits
    instruction fetch from the region -> icache (ifetch_ready on a hit)
Arbiter: the two masters share the one port, one transaction at a time. A master that
starts a command keeps the port until its busy drops (the bridge: its read data is back;
the cache: the 4 words of the line are back), so readdatavalid always belongs to the owner.
When both want it, the data side goes first: its load/store is older than the fetch, and the
CPU cannot fetch past it anyway. The master that waits sees waitrequest = 1 (Avalon: it
holds its command).
The JTAG master (PLT-10) is arbitrated inside sdram_sys by Platform Designer.
*/
module ext_memory #(
    parameter CACHE_LINES_LOG2 = 9,     // instruction cache: 512 lines x 16 bytes = 8 KB
    parameter DCACHE_LINES_LOG2 = 0     // data cache: 0 = none (sdram_bridge), 9 = 8 KB, 10 = 16 KB, 11 = 32 KB
)(
    input clk,
    input reset,

    // life_system external side
    input [31:0] bus_addr,
    input [31:0] bus_wdata,
    input [3:0] bus_be,
    input bus_re,
    input bus_we,
    input [31:0] bus_addr_next,         // bus_addr after this edge (data cache RAM address)
    input ext_sel,
    output [31:0] ext_rdata,
    output ext_stall,
    input [31:0] ifetch_addr,
    input ifetch_req,
    input [31:0] ifetch_next,
    output [31:0] ifetch_data,
    output ifetch_ready,

    // Avalon-MM master (to sdram_sys "mem")
    output [25:0] avm_address,
    output avm_read,
    output avm_write,
    output [31:0] avm_writedata,
    output [3:0] avm_byteenable,
    input [31:0] avm_readdata,
    input avm_readdatavalid,
    input avm_waitrequest
);

// ---- master 0: data ----
wire [25:0] d_address;
wire d_read, d_write, d_busy, d_waitrequest, d_readdatavalid;
wire [31:0] d_writedata;
wire [3:0] d_byteenable;
wire ev_load, ev_miss, ev_store;    // statistics for the Verilator harness
generate
if (DCACHE_LINES_LOG2 > 0) begin : data_cache
    dcache #(.LINES_LOG2(DCACHE_LINES_LOG2)) dc (
        .clk(clk), .reset(reset),
        .addr(bus_addr), .addr_next(bus_addr_next), .wdata(bus_wdata), .be(bus_be),
        .re(bus_re), .we(bus_we), .sel(ext_sel),
        .rdata(ext_rdata), .stall(ext_stall),
        .avm_address(d_address), .avm_read(d_read), .avm_write(d_write),
        .avm_writedata(d_writedata), .avm_byteenable(d_byteenable),
        .avm_readdata(avm_readdata), .avm_readdatavalid(d_readdatavalid),
        .avm_waitrequest(d_waitrequest), .busy(d_busy),
        .ev_load(ev_load), .ev_miss(ev_miss), .ev_store(ev_store)
    );
end else begin : no_data_cache
    sdram_bridge bridge (
        .clk(clk), .reset(reset),
        .addr(bus_addr), .wdata(bus_wdata), .be(bus_be), .re(bus_re), .we(bus_we), .sel(ext_sel),
        .rdata(ext_rdata), .stall(ext_stall),
        .avm_address(d_address), .avm_read(d_read), .avm_write(d_write),
        .avm_writedata(d_writedata), .avm_byteenable(d_byteenable),
        .avm_readdata(avm_readdata), .avm_readdatavalid(d_readdatavalid),
        .avm_waitrequest(d_waitrequest), .busy(d_busy),
        .ev_load(ev_load), .ev_store(ev_store)
    );
    assign ev_miss = ev_load;                   // every load goes to the SDRAM
end
endgenerate

// ---- master 1: instruction cache ----
wire [25:0] i_address;
wire i_read, i_busy, i_waitrequest, i_readdatavalid;
icache #(.LINES_LOG2(CACHE_LINES_LOG2)) cache (
    .clk(clk), .reset(reset),
    .addr(ifetch_addr), .addr_next(ifetch_next), .req(ifetch_req),
    .data(ifetch_data), .ready(ifetch_ready),
    .avm_address(i_address), .avm_read(i_read),
    .avm_readdata(avm_readdata), .avm_readdatavalid(i_readdatavalid),
    .avm_waitrequest(i_waitrequest), .busy(i_busy)
);

// ---- arbiter ----
reg locked = 1'b0;          // a transaction is under way
reg owner = 1'b0;           // its master: 0 = data side (dcache or bridge), 1 = instruction cache
wire d_cmd = d_read || d_write;
wire i_cmd = i_read;
wire owner_busy = owner ? i_busy : d_busy;
wire sel = locked ? owner : (!d_cmd && i_cmd);

always @(posedge clk) begin
    if (reset)
        locked <= 1'b0;
    else if (!locked) begin
        if (d_cmd || i_cmd) begin
            locked <= 1'b1;
            owner <= sel;
        end
    end else if (!owner_busy)
        locked <= 1'b0;
end

assign avm_address    = sel ? i_address : d_address;
assign avm_read       = sel ? i_read : d_read;
assign avm_write      = sel ? 1'b0 : d_write;
assign avm_writedata  = d_writedata;
assign avm_byteenable = sel ? 4'b1111 : d_byteenable;
assign d_waitrequest  = sel ? 1'b1 : avm_waitrequest;
assign i_waitrequest  = sel ? avm_waitrequest : 1'b1;
assign d_readdatavalid = avm_readdatavalid && !owner;
assign i_readdatavalid = avm_readdatavalid && owner;

endmodule
