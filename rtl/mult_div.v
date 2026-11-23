/* CPU-8: HI/LO registers and the multiply/divide unit of mips_pipeline (contracts.md "Pipeline").
Lives in EX. `en` = the instruction in EX is valid and will complete (not dropped by a halt);
it is the only way HI/LO change, so a bubble or a dropped instruction never touches them.
    mult/multu  64-bit product in ONE cycle (combinational, MAX 10 DSP blocks), {HI, LO}
                written at the end of the EX cycle.
    div/divu    restoring divider, 1 quotient bit per cycle: busy for 32 cycles after the
                div leaves EX, then LO = quotient, HI = remainder. Like the R2000, the
                pipeline keeps running independent instructions meanwhile; hazard_unit
                stalls in ID any HI/LO instruction (mfhi mflo mthi mtlo mult div) until the
                divide is done. Signed: the quotient rounds toward zero and the remainder
                has the dividend's sign (C semantics). Divide by zero gives LO = all ones
                for divu (or +/-1 for div) and HI = the dividend; MIPS leaves it undefined
                (GCC checks it in software).
    mthi/mtlo   HI or LO = A at the end of the EX cycle.
    mfhi/mflo   read `hi`/`lo` combinationally in EX (they never write HI/LO).
Older HI/LO instructions always reach EX first (in-order pipeline), so `hi`/`lo` in EX are
always up to date; the only wait is the busy divider.
*/
module mult_div(
    input clk, reset,
    input en,                 // the instruction in EX is valid and completes
    input [3:0] op,           // control_unit MdOp
    input [31:0] a, b,        // rs, rt
    output reg [31:0] hi, lo,
    output busy               // 1 = a divide is running; HI/LO are not ready
);

localparam MFHI = 4'd1, MFLO = 4'd2, MTHI = 4'd3, MTLO = 4'd4,
           MULT = 4'd8, MULTU = 4'd9, DIV = 4'd10, DIVU = 4'd11;

// Multiply: one 33x33 signed multiplier does both. The extra top bit is the sign (mult)
// or 0 (multu), so the low 64 bits of the product are the right result for each.
wire is_signed = !op[0];
wire signed [32:0] a33 = {is_signed & a[31], a};
wire signed [32:0] b33 = {is_signed & b[31], b};
wire signed [65:0] product_full = a33 * b33;
wire [63:0] product = product_full[63:0];

// Divide: work on magnitudes, fix the signs at the end.
wire a_neg = is_signed & a[31];
wire b_neg = is_signed & b[31];
wire [31:0] a_mag = a_neg ? -a : a;
wire [31:0] b_mag = b_neg ? -b : b;

reg [5:0] count;          // quotient bits still to compute (0 = idle)
reg [31:0] divisor, rem, quo;
reg neg_q, neg_r;
assign busy = (count != 6'd0);

// One restoring step: shift the next dividend bit into the remainder, subtract if it fits.
wire [32:0] shifted = {rem, quo[31]};
wire [32:0] diff = shifted - {1'b0, divisor};
wire fits = !diff[32];
wire [31:0] rem_next = fits ? diff[31:0] : shifted[31:0];
wire [31:0] quo_next = {quo[30:0], fits};

always @(posedge clk) begin
    if (reset) begin
        hi <= 32'd0;
        lo <= 32'd0;
        count <= 6'd0;
        divisor <= 32'd0;
        rem <= 32'd0;
        quo <= 32'd0;
        neg_q <= 1'b0;
        neg_r <= 1'b0;
    end else if (busy) begin
        // hazard_unit keeps every HI/LO instruction out of EX while busy, so en never
        // carries a HI/LO op here.
        rem <= rem_next;
        quo <= quo_next;
        count <= count - 6'd1;
        if (count == 6'd1) begin
            lo <= neg_q ? -quo_next : quo_next;
            hi <= neg_r ? -rem_next : rem_next;
        end
    end else if (en) begin
        case (op)
            MULT, MULTU: {hi, lo} <= product;
            DIV, DIVU: begin
                divisor <= b_mag;
                rem <= 32'd0;
                quo <= a_mag;
                neg_q <= a_neg ^ b_neg;
                neg_r <= a_neg;
                count <= 6'd32;
            end
            MTHI: hi <= a;
            MTLO: lo <= a;
            default: ;
        endcase
    end
end

endmodule
