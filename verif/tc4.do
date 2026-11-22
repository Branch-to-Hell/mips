# Run from verif in ModelSim: do tc4.do
# TC-4: one self-checking program per instruction group (src/programs/tc4_*.asm) on mips_pipeline with pipeline_program_tb.
# Each program must end with LEDR = 0x3FF and HEX = 0x00600D; on a failure HEX = 0xBAD0nn (nn = test).
# Assemble first, from the repo root: python src/assembler/assembler.py src/programs/<name>.asm
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v ../rtl/alu_control.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/data_memory.v pipeline_program_tb.v

foreach program {tc4_rtype tc4_itype tc4_shifts tc4_memory tc4_branches tc4_jumps} {
    vsim -onfinish stop -voptargs=+acc work.pipeline_program_tb +program=../mem/$program.hex
    run -all
    quit -sim
}
