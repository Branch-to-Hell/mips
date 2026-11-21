# Run from hw/sim in ModelSim: do cpu14.do
# CPU-14: visible halt on invalid or misaligned fetch, lw and sw (mips_pipeline).
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/mult_div.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v ../rtl/alu_control.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/data_memory.v cpu14_tb.v
vsim -voptargs=+acc work.cpu14_tb

add wave sim:/cpu14_tb/clk
add wave sim:/cpu14_tb/reset
add wave -radix hex sim:/cpu14_tb/dut/fetch_pc
add wave -radix hex sim:/cpu14_tb/dut/id_pc
add wave -radix hex sim:/cpu14_tb/dut/id_instruction
add wave sim:/cpu14_tb/dut/fetch_fault
add wave sim:/cpu14_tb/dut/access_fault
add wave -radix hex sim:/cpu14_tb/mem_addr
add wave sim:/cpu14_tb/mem_fault
add wave sim:/cpu14_tb/mem_we
add wave sim:/cpu14_tb/mem_re
add wave sim:/cpu14_tb/halted
add wave -radix unsigned sim:/cpu14_tb/halt_cause
add wave -radix hex sim:/cpu14_tb/halt_pc
add wave -radix hex sim:/cpu14_tb/halt_addr

run -all
wave zoom full
