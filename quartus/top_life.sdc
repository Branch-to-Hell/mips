create_clock -name CLK50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_pll_clocks
derive_clock_uncertainty

# Switches, keys, LEDs and displays are asynchronous to a human: no timing to meet
# (the inputs go through synchronizers in mmio.v)
set_false_path -from [get_ports {SW[*] KEY[*]}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
