# Run from verif in ModelSim: do video_b.do   (CPU fills the screen and cycles the palette)
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/mult_div.v ../rtl/hazard_unit.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/alu_control.v ../rtl/data_memory.v \
     ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/hex_debug.v ../rtl/mmio.v \
     ../rtl/vga_sync.v ../rtl/framebuffer_a.v ../rtl/video_mode_a.v \
     ../rtl/framebuffer_b.v ../rtl/palette.v ../rtl/video_mode_b.v ../rtl/life_system.v video_b_tb.v
vsim -voptargs=+acc work.video_b_tb

add wave sim:/video_b_tb/clk
add wave sim:/video_b_tb/reset
add wave -radix hex sim:/video_b_tb/sys/cpu/id_pc
add wave -radix hex sim:/video_b_tb/sys/mem_addr
add wave sim:/video_b_tb/sys/mem_we
add wave sim:/video_b_tb/sys/io/video_mode_reg
add wave -radix unsigned sim:/video_b_tb/sys/io/hex_reg
add wave -radix unsigned sim:/video_b_tb/updates
add wave sim:/video_b_tb/SW
add wave sim:/video_b_tb/KEY
add wave sim:/video_b_tb/LEDR
add wave -radix hex sim:/video_b_tb/VGA_R
add wave -radix hex sim:/video_b_tb/VGA_G
add wave -radix hex sim:/video_b_tb/VGA_B

run -all
wave zoom full
