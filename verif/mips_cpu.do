# Run from hw/sim/ in ModelSim:  cd <repo>/hw/sim ; do mips_cpu.do
catch {quit -sim}
vlib work
vlog ../rtl/*.v mips_cpu_tb.v
vsim work.mips_cpu_tb

add wave sim:/mips_cpu_tb/clk
add wave sim:/mips_cpu_tb/reset
add wave -radix hex sim:/mips_cpu_tb/dut/PC_out
add wave -radix hex sim:/mips_cpu_tb/dut/Instruction
add wave sim:/mips_cpu_tb/dut/RegWrite
add wave -radix decimal sim:/mips_cpu_tb/dut/ALUResult
add wave -radix decimal {sim:/mips_cpu_tb/dut/rf/registers[8]}
add wave -radix decimal {sim:/mips_cpu_tb/dut/rf/registers[11]}
add wave -radix decimal {sim:/mips_cpu_tb/dut/rf/registers[12]}
add wave -radix decimal {sim:/mips_cpu_tb/dut/rf/registers[13]}
add wave -radix decimal {sim:/mips_cpu_tb/dut/rf/registers[14]}
add wave -radix decimal {sim:/mips_cpu_tb/dut/rf/registers[15]}
add wave -radix decimal {sim:/mips_cpu_tb/dut/rf/registers[16]}

run -all
wave zoom full
