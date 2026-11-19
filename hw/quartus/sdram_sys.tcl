# PLT-7: Platform Designer system with the SDRAM controller of the DE10-Lite
# Rebuilds sdram_sys.qsys from scratch (run from hw/quartus):
#     qsys-script --script=sdram_sys.tcl
# Chip: ISSI IS42S16320D-7TL, 32M x 16 (64 MB), 4 banks, 13 row bits, 10 column bits
#
#   clk (25 MHz, from pll_sdram c0) ──┬── bridge (32-bit, byte addresses, exported "mem")
#                                     ├── jtag   (JTAG to Avalon Master, PLT-10, no ports)
#                                     └── sdram (16-bit, exported "wire" to the DRAM_* pins)
# Platform Designer adds the 32 → 16 width adapter between them, so the CPU side sees
# 64 MB of 32-bit words with byte enables.
# PLT-10: bridge and jtag are two masters of sdram.s1 (Platform Designer adds the arbiter).
# System Console drives jtag over the USB-Blaster to load the WAD (sw/tools/wad_load.tcl).

package require -exact qsys 16.0

create_system sdram_sys
set_project_property DEVICE_FAMILY {MAX 10}
set_project_property DEVICE {10M50DAF484C7G}

# ---- Clock and reset (driven from the top level) ----
add_instance clk clock_source
set_instance_parameter_value clk clockFrequency 25000000
set_instance_parameter_value clk clockFrequencyKnown true
set_instance_parameter_value clk resetSynchronousEdges DEASSERT

# ---- SDRAM controller ----
add_instance sdram altera_avalon_new_sdram_controller
set_instance_parameter_value sdram dataWidth 16
set_instance_parameter_value sdram numberOfChipSelects 1
set_instance_parameter_value sdram numberOfBanks 4
set_instance_parameter_value sdram rowWidth 13
set_instance_parameter_value sdram columnWidth 10
set_instance_parameter_value sdram casLatency 2
set_instance_parameter_value sdram initRefreshCommands 2
set_instance_parameter_value sdram refreshPeriod 7.8125
set_instance_parameter_value sdram powerUpDelay 100.0
set_instance_parameter_value sdram initNOPDelay 0.0
set_instance_parameter_value sdram TRFC 70.0
set_instance_parameter_value sdram TRP 20.0
set_instance_parameter_value sdram TRCD 20.0
set_instance_parameter_value sdram TAC 6.0
set_instance_parameter_value sdram TWR 14.0
set_instance_parameter_value sdram TMRD 3
set_instance_parameter_value sdram registerDataIn true
set_instance_parameter_value sdram pinsSharedViaTriState false
set_instance_parameter_value sdram generateSimulationModel true   ;# memory model for sdram_tb (simulation only)

# ---- 32-bit bridge the CPU (PLT-8) will master ----
add_instance bridge altera_avalon_mm_bridge
set_instance_parameter_value bridge DATA_WIDTH 32
set_instance_parameter_value bridge SYMBOL_WIDTH 8
set_instance_parameter_value bridge ADDRESS_WIDTH 26
set_instance_parameter_value bridge ADDRESS_UNITS SYMBOLS
set_instance_parameter_value bridge MAX_BURST_SIZE 1
set_instance_parameter_value bridge MAX_PENDING_RESPONSES 4
set_instance_parameter_value bridge PIPELINE_COMMAND 0
set_instance_parameter_value bridge PIPELINE_RESPONSE 0

# ---- JTAG to Avalon Master (PLT-10): lets System Console read and write the SDRAM ----
add_instance jtag altera_jtag_avalon_master
set_instance_parameter_value jtag USE_PLI 0

# ---- Connections ----
add_connection clk.clk sdram.clk
add_connection clk.clk bridge.clk
add_connection clk.clk_reset sdram.reset
add_connection clk.clk_reset bridge.reset
add_connection clk.clk jtag.clk
add_connection clk.clk_reset jtag.clk_reset
add_connection bridge.m0 sdram.s1
set_connection_parameter_value bridge.m0/sdram.s1 baseAddress 0x00000000
add_connection jtag.master sdram.s1
set_connection_parameter_value jtag.master/sdram.s1 baseAddress 0x00000000

# ---- Exported interfaces ----
set_interface_property clk EXPORT_OF clk.clk_in
set_interface_property reset EXPORT_OF clk.clk_in_reset
set_interface_property mem EXPORT_OF bridge.s0
set_interface_property wire EXPORT_OF sdram.wire

save_system sdram_sys.qsys
