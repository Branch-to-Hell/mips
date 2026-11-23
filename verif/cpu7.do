# Run from verif in ModelSim: do cpu7.do
# CPU-7/CPU-8: full MIPS I integer set on mips_pipeline. Runs two self-checking programs
# (assembled with GNU as by src/tools/gas_image.sh): cpu7_isa (ALU, byte/half memory,
# branches against zero, links) and cpu8_muldiv (HI/LO, multiply, divide).
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/mult_div.v ../rtl/if_id_register.v \
     ../rtl/pipeline_register.v ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/alu_control.v ../rtl/register_file.v ../rtl/alu.v cpu7_tb.v

vsim -onfinish stop -voptargs=+acc work.cpu7_tb +program=../mem/cpu8_muldiv.hex
run -all
quit -sim

vsim -onfinish stop -voptargs=+acc work.cpu7_tb +program=../mem/cpu7_isa.hex
add wave sim:/cpu7_tb/clk
add wave -radix hex sim:/cpu7_tb/dut/id_pc
add wave -radix hex sim:/cpu7_tb/dut/id_instruction
add wave sim:/cpu7_tb/dut/stall
add wave -radix hex sim:/cpu7_tb/mem_addr
add wave sim:/cpu7_tb/mem_be
add wave -radix hex sim:/cpu7_tb/mem_wdata
add wave -radix hex sim:/cpu7_tb/mem_rdata
add wave sim:/cpu7_tb/mem_we
add wave sim:/cpu7_tb/mem_re
add wave -radix hex sim:/cpu7_tb/dut/hi
add wave -radix hex sim:/cpu7_tb/dut/lo
add wave sim:/cpu7_tb/dut/md_busy
run -all
wave zoom full
