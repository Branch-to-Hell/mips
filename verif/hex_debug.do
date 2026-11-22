# Run from verif in ModelSim: do hex_debug.do
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/mult_div.v ../rtl/hazard_unit.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/alu_control.v ../rtl/data_memory.v \
     ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/hex_debug.v ../rtl/mmio.v \
     ../rtl/vga_sync.v ../rtl/framebuffer_a.v ../rtl/video_mode_a.v ../rtl/life_system.v hex_debug_tb.v
vsim -voptargs=+acc work.hex_debug_tb

add wave sim:/hex_debug_tb/clk
add wave sim:/hex_debug_tb/reset
add wave -radix hex sim:/hex_debug_tb/SW
add wave -radix hex sim:/hex_debug_tb/sys/dbg_value
add wave -radix hex sim:/hex_debug_tb/HEX5
add wave -radix hex sim:/hex_debug_tb/HEX4
add wave -radix hex sim:/hex_debug_tb/HEX3
add wave -radix hex sim:/hex_debug_tb/HEX2
add wave -radix hex sim:/hex_debug_tb/HEX1
add wave -radix hex sim:/hex_debug_tb/HEX0

run -all
wave zoom full
