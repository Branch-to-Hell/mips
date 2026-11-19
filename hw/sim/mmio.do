# CPU-4 transition: existing dependent/branch programs require CPU-5/6 before these tests can pass.
# Run from hw/sim in ModelSim: do mmio.do
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_cpu.v ../rtl/if_id_register.v ../rtl/pipeline_register.v ../rtl/pc.v ../rtl/adder.v ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/alu_control.v ../rtl/data_memory.v \
     ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/mmio.v mmio_tb.v
vsim -voptargs=+acc work.mmio_tb

add wave sim:/mmio_tb/clk
add wave sim:/mmio_tb/reset
add wave -radix hex sim:/mmio_tb/dut/id_pc
add wave -radix hex sim:/mmio_tb/dut/id_instruction
add wave -radix hex sim:/mmio_tb/mem_addr
add wave sim:/mmio_tb/mem_we
add wave sim:/mmio_tb/mem_re
add wave -radix hex sim:/mmio_tb/mem_rdata
add wave -radix hex sim:/mmio_tb/SW
add wave sim:/mmio_tb/KEY
add wave sim:/mmio_tb/io/key_pressed
add wave -radix hex sim:/mmio_tb/LEDR
add wave -radix hex sim:/mmio_tb/io/hex_reg

run -all
wave zoom full
