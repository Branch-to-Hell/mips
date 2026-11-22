# Run from verif in ModelSim: do instruction_memory.do   (CPU-12)
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/instruction_memory.v instruction_memory_tb.v
vsim -voptargs=+acc work.instruction_memory_tb

add wave sim:/instruction_memory_tb/clk
add wave -radix hex sim:/instruction_memory_tb/Address
add wave -radix hex sim:/instruction_memory_tb/dut/Row
add wave -radix hex sim:/instruction_memory_tb/Instruction
add wave -radix hex {sim:/instruction_memory_tb/b[0]}
add wave -radix hex {sim:/instruction_memory_tb/b[1]}
add wave -radix hex {sim:/instruction_memory_tb/b[2]}
add wave -radix hex {sim:/instruction_memory_tb/b[3]}

run -all
wave zoom full
