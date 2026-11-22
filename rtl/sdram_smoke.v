/* SDRAM smoke test (PLT-7): an Avalon-MM master that writes WORDS 32-bit words
to the SDRAM from address 0, then reads them back and compares
The pattern depends on the address (pattern() below), so a wrong address line
shows up as a mismatch, not only a stuck data bit
One access at a time: hold read/write while waitrequest = 1, then for reads wait
for readdatavalid. This is the same handshake the CPU bridge (PLT-8) will use.
PLT-9 runs it over the whole 64 MB (WORDS = 16M)
*/
module sdram_smoke #(
    parameter WORDS = 4096              // how many 32-bit words to test
)(
    input clk,
    input reset,
    input start,                        // 1-cycle pulse: run the test (again)

    // Avalon-MM master (to sdram_sys "mem")
    output reg [25:0] address,          // byte address, always a multiple of 4
    output reg read,
    output reg write,
    output [31:0] writedata,
    output [3:0] byteenable,
    input [31:0] readdata,
    input readdatavalid,
    input waitrequest,

    // Result
    output reg busy,
    output reg done,
    output reg [23:0] errors,           // mismatching words (saturates)
    output reg [25:0] first_bad         // byte address of the first mismatch
);

localparam IDLE = 3'd0, WRITE = 3'd1, READ = 3'd2, WAIT_DATA = 3'd3, FINISH = 3'd4;
localparam [25:0] LAST = (WORDS - 1) * 4;

reg [2:0] state;

function [31:0] pattern(input [25:0] a);
    pattern = {a[25:2], 8'h00} ^ {8'hA5, a[25:2]} ^ 32'h5A3C_96E1;
endfunction

assign writedata = pattern(address);
assign byteenable = 4'b1111;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        address <= 0;
        read <= 0;
        write <= 0;
        busy <= 0;
        done <= 0;
        errors <= 0;
        first_bad <= 0;
    end else begin
        case (state)
        IDLE: begin
            if (start) begin
                address <= 0;
                errors <= 0;
                first_bad <= 0;
                done <= 0;
                busy <= 1;
                write <= 1;
                state <= WRITE;
            end
        end
        WRITE: begin
            if (!waitrequest) begin     // this word was accepted
                if (address == LAST) begin
                    write <= 0;
                    read <= 1;
                    address <= 0;
                    state <= READ;
                end else
                    address <= address + 26'd4;
            end
        end
        READ: begin
            if (!waitrequest) begin     // the read command was accepted
                read <= 0;
                state <= WAIT_DATA;
            end
        end
        WAIT_DATA: begin
            if (readdatavalid) begin
                if (readdata != pattern(address)) begin
                    if (errors == 0) first_bad <= address;
                    if (errors != 24'hFF_FFFF) errors <= errors + 1'b1;
                end
                if (address == LAST)
                    state <= FINISH;
                else begin
                    address <= address + 26'd4;
                    read <= 1;
                    state <= READ;
                end
            end
        end
        FINISH: begin
            busy <= 0;
            done <= 1;
            state <= IDLE;
        end
        default: state <= IDLE;
        endcase
    end
end

endmodule
