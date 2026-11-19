# Run from hw/sim in ModelSim: do life.do   (simulates ~200 ms of the board, takes a few minutes)
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_cpu.v ../rtl/pc.v ../rtl/adder.v ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/alu_control.v ../rtl/data_memory.v \
     ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/hex_debug.v ../rtl/mmio.v \
     ../rtl/vga_sync.v ../rtl/framebuffer_a.v ../rtl/video_mode_a.v ../rtl/life_system.v life_tb.v
vsim -voptargs=+acc work.life_tb

add wave sim:/life_tb/clk
add wave sim:/life_tb/reset
add wave -radix hex sim:/life_tb/sys/cpu/PC_out
add wave -radix hex sim:/life_tb/sys/cpu/Instruction
add wave -radix hex sim:/life_tb/sys/mem_addr
add wave sim:/life_tb/sys/mem_we
add wave sim:/life_tb/sys/fb_sel
add wave -radix hex sim:/life_tb/SW
add wave sim:/life_tb/KEY
add wave sim:/life_tb/LEDR
add wave -radix unsigned sim:/life_tb/sys/io/hex_reg
add wave -radix unsigned sim:/life_tb/gens

run -all
wave zoom full
