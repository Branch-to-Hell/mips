/* Debounce for one DE10-Lite push button (PLT-2)
The keys are active-low and bounce for a few ms when pressed or released.
The output is the clean level, 1 = pressed: it only changes after the input
stays at the new value for CYCLES clocks in a row (default 10 ms at 25 MHz)
Software detects the press edge (contracts.md, KEY register)
*/
module debounce #(
    parameter CYCLES = 250_000  // 10 ms at 25 MHz; the testbench uses a small value
)(
    input clk,
    input key_n,        // raw key, 0 = pressed
    output reg pressed  // debounced, 1 = pressed
);

// Two flip-flops: the key is asynchronous to clk
reg sync0 = 1'b1, sync1 = 1'b1;
reg [$clog2(CYCLES+1)-1:0] count = 0;

initial pressed = 1'b0;

always @(posedge clk) begin
    sync0 <= key_n;
    sync1 <= sync0;
    if (~sync1 == pressed)       // input agrees with the output: nothing to do
        count <= 0;
    else if (count == CYCLES - 1) begin // different for CYCLES clocks: accept it
        pressed <= ~sync1;
        count <= 0;
    end else
        count <= count + 1'b1;
end

endmodule
