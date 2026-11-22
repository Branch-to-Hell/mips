# Run from verif in ModelSim: do cpu11.do
# CPU-11: add/sub/addi with the professor's codes 0x21 0x23 0x09 and the old ones, on both CPUs.
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_cpu.v ../rtl/pc.v ../rtl/adder.v ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/mult_div.v ../rtl/if_id_register.v \
     ../rtl/pipeline_register.v ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/alu_control.v ../rtl/register_file.v ../rtl/alu.v cpu11_tb.v
vsim -voptargs=+acc work.cpu11_tb

add wave sim:/cpu11_tb/clk
add wave sim:/cpu11_tb/reset
add wave -radix hex sim:/cpu11_tb/sc/PC_out
add wave -radix hex sim:/cpu11_tb/sc/Instruction
add wave -radix hex sim:/cpu11_tb/sc/ALUctl
add wave -radix hex sim:/cpu11_tb/pl/id_pc
add wave -radix hex sim:/cpu11_tb/pl/id_instruction
add wave -radix unsigned sim:/cpu11_tb/pl/wb_dest
add wave -radix hex sim:/cpu11_tb/pl/wb_data

run -all
wave zoom full
