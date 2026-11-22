# Run from hw/sim in ModelSim: do cpu5.do
# CPU-5: hazard detection unit (stalls for data, load-use, branch and jr hazards).
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v ../rtl/alu_control.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/data_memory.v cpu5_tb.v
vsim -voptargs=+acc work.cpu5_tb

add wave sim:/cpu5_tb/clk
add wave sim:/cpu5_tb/reset
add wave -radix hex sim:/cpu5_tb/dut/fetch_pc
add wave -radix hex sim:/cpu5_tb/dut/id_pc
add wave -radix hex sim:/cpu5_tb/dut/id_instruction
add wave sim:/cpu5_tb/dut/stall
add wave sim:/cpu5_tb/dut/ex_valid
add wave -radix unsigned sim:/cpu5_tb/dut/ex_dest
add wave sim:/cpu5_tb/dut/mem_valid
add wave -radix unsigned sim:/cpu5_tb/dut/mem_dest
add wave -radix unsigned sim:/cpu5_tb/dut/wb_dest
add wave -radix hex sim:/cpu5_tb/dut/wb_data

run -all
wave zoom full
