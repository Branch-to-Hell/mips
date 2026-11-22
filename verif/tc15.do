# Run from verif in ModelSim: do tc15.do
# TC-15: the graded algorithm (src/programs/count_value_in1..3.asm) on life_system with mips_pipeline.
# Assemble first, from the repo root: python src/assembler/assembler.py src/programs/count_value_in<k>.asm
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/alu_control.v ../rtl/data_memory.v \
     ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/hex_debug.v ../rtl/mmio.v \
     ../rtl/vga_sync.v ../rtl/framebuffer_a.v ../rtl/video_mode_a.v ../rtl/life_system.v tc15_tb.v

# Input 1: normal case, negatives included
vsim -voptargs=+acc -GPROGRAM="count_value_in1" -GN=8 -GTARGET=3 -GEXPECTED=4 work.tc15_tb
run -all
quit -sim
# Input 2: every element matches
vsim -voptargs=+acc -GPROGRAM="count_value_in2" -GN=4 -GTARGET=7 -GEXPECTED=4 work.tc15_tb
run -all
quit -sim
# Input 3: edge case, empty array
vsim -voptargs=+acc -GPROGRAM="count_value_in3" -GN=0 -GTARGET=5 -GEXPECTED=0 work.tc15_tb
run -all
quit -sim
