# Run from hw/sim in ModelSim: do pipeline_register.do
# CPU-4: IF/ID, ID/EX, EX/MEM and MEM/WB registers (enable, flush, reset, valid).
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/pipeline_register.v ../rtl/if_id_register.v ../rtl/instruction_memory.v pipeline_register_tb.v
vsim -voptargs=+acc work.pipeline_register_tb

add wave sim:/pipeline_register_tb/clk
add wave sim:/pipeline_register_tb/reset
add wave sim:/pipeline_register_tb/enable
add wave sim:/pipeline_register_tb/flush
add wave sim:/pipeline_register_tb/valid_in
add wave sim:/pipeline_register_tb/id_ex_valid
add wave -radix hex sim:/pipeline_register_tb/fetch_pc
add wave sim:/pipeline_register_tb/if_valid
add wave -radix hex sim:/pipeline_register_tb/id_pc
add wave -radix hex sim:/pipeline_register_tb/instruction

run -all
wave zoom full
