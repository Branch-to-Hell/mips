# Run from verif in ModelSim: do tc9.do
# TC-9: the C "hello pixels" (src/c/hello_pixels.c, GCC) on life_system with mips_pipeline.
# Build first, in WSL from the repo root: make -C src/c
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/mips_pipeline.v ../rtl/hazard_unit.v ../rtl/if_id_register.v ../rtl/pipeline_register.v \
     ../rtl/instruction_memory.v ../rtl/control_unit.v \
     ../rtl/register_file.v ../rtl/alu.v ../rtl/alu_control.v ../rtl/data_memory.v \
     ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/hex_debug.v ../rtl/mmio.v \
     ../rtl/vga_sync.v ../rtl/framebuffer_a.v ../rtl/video_mode_a.v ../rtl/life_system.v tc9_tb.v
vsim -voptargs=+acc work.tc9_tb
run -all
