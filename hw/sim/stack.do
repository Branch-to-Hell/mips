# Run from hw/sim in ModelSim: do stack.do
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/alu_control.v ../rtl/data_memory.v \
     ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/hex_debug.v ../rtl/mmio.v \
     ../rtl/vga_sync.v ../rtl/framebuffer_a.v ../rtl/video_mode_a.v ../rtl/life_system.v stack_tb.v
vsim -voptargs=+acc work.stack_tb

add wave sim:/stack_tb/clk
add wave sim:/stack_tb/reset
add wave -radix hex sim:/stack_tb/sys/cpu/id_pc
add wave -radix hex sim:/stack_tb/sys/cpu/id_instruction
add wave -radix hex sim:/stack_tb/sp
add wave -radix hex sim:/stack_tb/sys/mem_addr
add wave sim:/stack_tb/sys/mem_we
add wave sim:/stack_tb/sys/mem_re
add wave -radix hex sim:/stack_tb/sys/stack_rdata
add wave -radix hex sim:/stack_tb/LEDR
add wave -radix hex sim:/stack_tb/sys/io/hex_reg

run -all
wave zoom full
