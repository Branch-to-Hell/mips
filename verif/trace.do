# Run from verif in ModelSim: do trace.do
# TC-16: one trace per format (R add, I lw, J j) on mips_pipeline. Writes verif/traces/trace_R.txt,
# trace_I.txt and trace_J.txt. Assemble first, from the repo root:
#   python src/assembler/assembler.py src/programs/tc16_trace.asm
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v ../rtl/alu_control.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/data_memory.v trace_tb.v
vsim -onfinish stop -voptargs=+acc work.trace_tb

add wave sim:/trace_tb/clk
add wave -radix unsigned sim:/trace_tb/cycle
add wave -radix hex sim:/trace_tb/dut/fetch_pc
add wave -radix hex sim:/trace_tb/dut/id_pc
add wave -radix hex sim:/trace_tb/dut/id_instruction
add wave -radix hex sim:/trace_tb/dut/ex_pc
add wave -radix hex sim:/trace_tb/dut/ex_result
add wave -radix hex sim:/trace_tb/dut/mem_pc
add wave -radix hex sim:/trace_tb/mem_addr
add wave -radix hex sim:/trace_tb/mem_rdata
add wave -radix unsigned sim:/trace_tb/dut/wb_dest
add wave -radix hex sim:/trace_tb/dut/wb_data

run -all
wave zoom full
