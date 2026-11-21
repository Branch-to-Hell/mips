# Run from hw/sim in ModelSim: do cpu4.do
# CPU-4: five-stage pipeline (mips_pipeline) with independent instructions, lw/sw and reset.
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/mult_div.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v ../rtl/alu_control.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/data_memory.v cpu4_tb.v
vsim -voptargs=+acc work.cpu4_tb

add wave sim:/cpu4_tb/clk
add wave sim:/cpu4_tb/reset
add wave -radix hex sim:/cpu4_tb/dut/fetch_pc
add wave sim:/cpu4_tb/dut/id_valid
add wave -radix hex sim:/cpu4_tb/dut/id_pc
add wave -radix hex sim:/cpu4_tb/dut/id_instruction
add wave sim:/cpu4_tb/dut/ex_valid
add wave -radix hex sim:/cpu4_tb/dut/ex_result
add wave sim:/cpu4_tb/dut/mem_valid
add wave -radix hex sim:/cpu4_tb/mem_addr
add wave sim:/cpu4_tb/mem_we
add wave sim:/cpu4_tb/mem_re
add wave sim:/cpu4_tb/dut/wb_valid
add wave -radix unsigned sim:/cpu4_tb/dut/wb_dest
add wave -radix hex sim:/cpu4_tb/dut/wb_data

run -all
wave zoom full
