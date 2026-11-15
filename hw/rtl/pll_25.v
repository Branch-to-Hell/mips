/* PLL: 50 MHz from the board to 25 MHz for the whole design (contracts.md: CPU and VGA at 25 MHz)
Same as what the IP Catalog (ALTPLL) generates, written by hand
*/
module pll_25 (
    input inclk0, // 50 MHz
    output c0, // 25 MHz
    output locked // 1 when c0 is stable
);

wire [4:0] clk_out;
assign c0 = clk_out[0];

altpll pll (
    .inclk({1'b0, inclk0}),
    .clk(clk_out),
    .locked(locked),
    .areset(1'b0)
);
defparam
    pll.intended_device_family = "MAX 10",
    pll.lpm_type = "altpll",
    pll.operation_mode = "NORMAL",
    pll.compensate_clock = "CLK0",
    pll.inclk0_input_frequency = 20000, // period in ps (50 MHz)
    pll.clk0_multiply_by = 1,
    pll.clk0_divide_by = 2,
    pll.clk0_duty_cycle = 50,
    pll.clk0_phase_shift = "0",
    pll.width_clock = 5;

endmodule
