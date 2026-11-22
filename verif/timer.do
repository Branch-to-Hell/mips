# Run from verif in ModelSim: do timer.do
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_cpu.v ../rtl/pc.v ../rtl/adder.v ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/alu_control.v ../rtl/data_memory.v \
     ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/mmio.v timer_tb.v
vsim -voptargs=+acc work.timer_tb

add wave sim:/timer_tb/clk
add wave sim:/timer_tb/reset
add wave -radix hex sim:/timer_tb/dut/PC_out
add wave -radix hex sim:/timer_tb/mem_addr
add wave sim:/timer_tb/mem_re
add wave -radix unsigned sim:/timer_tb/io/prescaler
add wave -radix unsigned sim:/timer_tb/io/timer_ms
add wave -radix unsigned sim:/timer_tb/io/hex_reg
add wave -radix unsigned sim:/timer_tb/LEDR

run -all
wave zoom full
