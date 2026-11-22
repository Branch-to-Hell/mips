/* PLL for the SDRAM designs (PLT-7): 50 MHz from the board to
    c0 = 25 MHz  system clock: CPU, VGA, SDRAM controller (one clock domain, contracts.md)
    c1 = 25 MHz  same clock shifted -3 ns, goes out on the DRAM_CLK pin
Why the shift: c1 has to travel from the PLL to the DRAM_CLK pin (a few ns of output
delay), so sending it a little earlier makes the SDRAM see its edge close to the edge
that launched the commands and data. TimeQuest checks the reads and writes against
the chip's timing with sdram_test.sdc
Same style as pll_25.v: what the IP Catalog (ALTPLL) generates, written by hand
*/
module pll_sdram (
    input inclk0, // 50 MHz
    output c0,    // 25 MHz, system
    output c1,    // 25 MHz, -3 ns, to DRAM_CLK
    output locked // 1 when c0 and c1 are stable
);

wire [4:0] clk_out;
assign c0 = clk_out[0];
assign c1 = clk_out[1];

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
    pll.clk1_multiply_by = 1,
    pll.clk1_divide_by = 2,
    pll.clk1_duty_cycle = 50,
    pll.clk1_phase_shift = "-3000",     // ps
    pll.width_clock = 5;

endmodule
