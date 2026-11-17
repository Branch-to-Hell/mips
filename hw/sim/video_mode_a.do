# Run from hw/sim/ in ModelSim:  cd <repo>/hw/sim ; do video_mode_a.do
# Simulates one full frame (about 17 ms) and saves frame.ppm
catch {quit -sim}
vlib work
vlog ../rtl/vga_sync.v ../rtl/framebuffer_a.v ../rtl/video_mode_a.v video_mode_a_tb.v
vsim -voptargs=+acc work.video_mode_a_tb

add wave sim:/video_mode_a_tb/clk
add wave sim:/video_mode_a_tb/hs
add wave sim:/video_mode_a_tb/vs
add wave -radix unsigned sim:/video_mode_a_tb/dut/h
add wave -radix unsigned sim:/video_mode_a_tb/dut/v
add wave -radix unsigned sim:/video_mode_a_tb/dut/x_cell
add wave -radix unsigned sim:/video_mode_a_tb/dut/y_cell
add wave -radix unsigned sim:/video_mode_a_tb/dut/b_addr
add wave -radix hex sim:/video_mode_a_tb/dut/color

run -all
