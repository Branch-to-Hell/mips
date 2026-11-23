// PLT-8 / PLT-12 / DOOM-6: behavioural model of sdram_sys's "mem" port (docs/contracts.md "SDRAM")
// for the Verilator harness: 64 MB, Avalon-MM with waitrequest and pipelined reads (readdatavalid
// in order, LATENCY cycles or more after the read is accepted), byte lanes little-endian like
// Avalon (byte address A+k = bits 8k+7..8k = byteenable[k]).
// The memory is kept as bytes by SDRAM byte address, like the real chip after wad_load.tcl:
//   load_words(file, offset): a word image (one 32-bit word per line, the CPU's big-endian view,
//                             e.g. build/doom/doom_sdram.hex) -> byte offset+4i = bits 31..24
//   load_bin(file, offset):   a binary file (the WAD) byte by byte from offset
// Random timing (plusargs, read by the harness and passed in): wait_pct = % of cycles with
// waitrequest = 1, extra = up to this many more cycles of read latency (in order).
module avalon_sdram #(
    parameter LATENCY = 5            // cycles from an accepted read to readdatavalid (at least)
)(
    input clk,
    input [25:0] address,
    input read,
    input write,
    input [31:0] writedata,
    input [3:0] byteenable,
    output logic [31:0] readdata = 0,
    output logic readdatavalid = 0,
    output logic waitrequest = 0,
    input int wait_pct,
    input int extra
);

logic [7:0] mem [0:(1 << 26) - 1];

typedef struct {
    logic [31:0] data;
    longint due;
} pending_t;
pending_t q[$];
longint now = 0;
longint last_due = 0;

function automatic logic [31:0] word_at(input logic [25:0] a);
    return {mem[{a[25:2], 2'd3}], mem[{a[25:2], 2'd2}], mem[{a[25:2], 2'd1}], mem[{a[25:2], 2'd0}]};
endfunction

always @(posedge clk) begin
    now <= now + 1;
    // A command is accepted on an edge where waitrequest = 0
    if (!waitrequest && write)
        for (int k = 0; k < 4; k++)
            if (byteenable[k]) mem[{address[25:2], 2'(k)}] <= writedata[8*k +: 8];
    if (!waitrequest && read) begin
        pending_t p;
        longint due = now + LATENCY + (extra > 0 ? longint'($urandom % (extra + 1)) : 0);
        if (due <= last_due) due = last_due + 1;            // in order, one word per cycle
        last_due = due;
        p.data = word_at(address);
        p.due = due;
        q.push_back(p);
    end
    readdatavalid <= 0;
    if (q.size() > 0 && q[0].due <= now) begin
        readdata <= q[0].data;
        readdatavalid <= 1;
        void'(q.pop_front());
    end
    waitrequest <= wait_pct > 0 && ($urandom % 100) < wait_pct;
end

task automatic load_words(input string file, input int offset);
    logic [31:0] words [];
    int fd, n = 0;
    string line;
    fd = $fopen(file, "r");
    if (fd == 0) $fatal(1, "Can't open %s", file);
    while ($fgets(line, fd) > 0) begin
        logic [31:0] w;
        if ($sscanf(line, "%h", w) == 1) begin
            mem[offset + 4*n + 0] = w[31:24];
            mem[offset + 4*n + 1] = w[23:16];
            mem[offset + 4*n + 2] = w[15:8];
            mem[offset + 4*n + 3] = w[7:0];
            n++;
        end
    end
    $fclose(fd);
    $fwrite(32'h8000_0002, "avalon_sdram: %s: %0d words at offset 0x%h\n", file, n, offset);
endtask

task automatic load_bin(input string file, input int offset);
    int fd, c, n = 0;
    fd = $fopen(file, "rb");
    if (fd == 0) $fatal(1, "Can't open %s", file);
    c = $fgetc(fd);
    while (c != -1) begin
        mem[offset + n] = c[7:0];
        n++;
        c = $fgetc(fd);
    end
    $fclose(fd);
    $fwrite(32'h8000_0002, "avalon_sdram: %s: %0d bytes at offset 0x%h\n", file, n, offset);
endtask

endmodule
