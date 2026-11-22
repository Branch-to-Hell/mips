create_clock -name CLK50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_pll_clocks
derive_clock_uncertainty

# ---- SDRAM (PLT-7) ----
# DRAM_CLK is PLL output c1 (25 MHz, -3 ns) after the trip to the pin: the SDRAM samples
# and launches on this clock, so the I/O constraints below are relative to it
create_generated_clock -name DRAM_CLK -source [get_pins {pll|pll|auto_generated|pll1|clk[1]}] [get_ports DRAM_CLK]

# ISSI IS42S16320D-7 datasheet, CAS latency 2, plus ~0.5 ns of board trace
#   tAC (clock to data out) = 6.5 ns max   tOH (data out hold) = 2.5 ns min
#   tIS (input setup)       = 1.5 ns       tIH (input hold)    = 0.8 ns
set sdram_outputs [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CAS_N DRAM_RAS_N DRAM_WE_N DRAM_CS_N DRAM_CKE DRAM_LDQM DRAM_UDQM DRAM_DQ[*]}]

# Reads: data from the SDRAM into the FPGA
set_input_delay -clock DRAM_CLK -max 7.0 [get_ports {DRAM_DQ[*]}]
set_input_delay -clock DRAM_CLK -min 2.5 [get_ports {DRAM_DQ[*]}]
# DRAM_CLK leads the system clock by ~3 ns, so the next system edge comes only ~3 ns after
# the SDRAM launches the data (less than tAC). The controller captures it one cycle later
# (the edge after that), so the setup check moves one edge out; hold stays on the first edge
set_multicycle_path -from [get_clocks DRAM_CLK] -to [get_clocks {pll|pll|auto_generated|pll1|clk[0]}] -setup -end 2

# Writes and commands: FPGA into the SDRAM
set_output_delay -clock DRAM_CLK -max 2.0 $sdram_outputs
set_output_delay -clock DRAM_CLK -min -0.8 $sdram_outputs

# ---- Board I/O ----
# Switches, keys, LEDs and displays are asynchronous to a human: no timing to meet
# (the keys go through synchronizers in debounce.v)
set_false_path -from [get_ports {SW[*] KEY[*]}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
