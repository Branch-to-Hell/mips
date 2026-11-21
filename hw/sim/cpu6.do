# Run from hw/sim in ModelSim: do cpu6.do
# CPU-6: branches/jumps resolved in ID with one delay slot (mips_pipeline).
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/mult_div.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v ../rtl/alu_control.v \
     ../rtl/register_file.v ../rtl/alu.v cpu6_tb.v
vsim -voptargs=+acc work.cpu6_tb

add wave sim:/cpu6_tb/clk
add wave sim:/cpu6_tb/reset
add wave -radix hex sim:/cpu6_tb/dut/fetch_pc
add wave -radix hex sim:/cpu6_tb/dut/id_pc
add wave -radix hex sim:/cpu6_tb/dut/id_instruction
add wave sim:/cpu6_tb/dut/branch_taken
add wave sim:/cpu6_tb/dut/redirect
add wave -radix hex sim:/cpu6_tb/dut/redirect_pc
add wave -radix unsigned sim:/cpu6_tb/dut/wb_dest
add wave -radix hex sim:/cpu6_tb/dut/wb_data

run -all
wave zoom full
