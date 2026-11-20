# Run from hw/sim in ModelSim: do video_mode_b.do
# Simulates one full frame (about 17 ms), checks every pixel and saves frame_b.ppm
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/vga_sync.v ../rtl/framebuffer_b.v ../rtl/palette.v ../rtl/video_mode_b.v video_mode_b_tb.v
vsim -voptargs=+acc work.video_mode_b_tb

add wave sim:/video_mode_b_tb/clk
add wave sim:/video_mode_b_tb/hs
add wave sim:/video_mode_b_tb/vs
add wave -radix unsigned sim:/video_mode_b_tb/dut/h
add wave -radix unsigned sim:/video_mode_b_tb/dut/v
add wave -radix unsigned sim:/video_mode_b_tb/dut/b_addr
add wave -radix unsigned sim:/video_mode_b_tb/dut/index
add wave -radix hex sim:/video_mode_b_tb/dut/color
add wave -radix hex sim:/video_mode_b_tb/r
add wave -radix hex sim:/video_mode_b_tb/g
add wave -radix hex sim:/video_mode_b_tb/b

run -all
wave zoom full
