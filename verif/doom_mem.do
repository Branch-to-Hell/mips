# Run from verif in ModelSim: do doom_mem.do
# PLT-8 + PLT-12 on the real SDRAM controller (doom_mem_tb.v). Like sdram.do, it first
# generates the simulation HDL of sdram_sys (sdram_sys_sim/, not in git).
# Needs mem/test_ext*.hex (committed; rebuilt from src/programs/test_ext.s with
# src/tools/gas_image.sh and src/tools/hex2banks.py).
onerror {quit -code 1 -f}
catch {quit -sim}

if {[info exists env(QUARTUS_ROOTDIR)]} {
    set qroot $env(QUARTUS_ROOTDIR)
} else {
    set qroot C:/intelFPGA_lite/20.1/quartus
}
if {![file exists sdram_sys_sim/simulation/sdram_sys.v]} {
    echo "Generating sdram_sys_sim/ with qsys-generate (takes ~30 s)..."
    set log [exec $qroot/sopc_builder/bin/qsys-generate ../quartus/sdram_sys.qsys --simulation=VERILOG \
        --output-directory=sdram_sys_sim --family=MAX\ 10 --part=10M50DAF484C7G 2>@1]
}

vlib work
set sim sdram_sys_sim/simulation
foreach f [glob $sim/submodules/*.v $sim/submodules/*.sv] {
    vlog -sv -suppress 2583 $f
}
vlog $sim/sdram_sys.v
vlog ../rtl/life_system.v ../rtl/mips_pipeline.v ../rtl/mult_div.v ../rtl/hazard_unit.v \
     ../rtl/if_id_register.v ../rtl/pipeline_register.v ../rtl/instruction_memory.v \
     ../rtl/control_unit.v ../rtl/alu_control.v ../rtl/register_file.v ../rtl/alu.v \
     ../rtl/data_memory.v ../rtl/debounce.v ../rtl/hex7seg.v ../rtl/hex_debug.v ../rtl/mmio.v \
     ../rtl/vga_sync.v ../rtl/framebuffer_a.v ../rtl/video_mode_a.v \
     ../rtl/ext_memory.v ../rtl/sdram_bridge.v ../rtl/icache.v doom_mem_tb.v
vsim -voptargs=+acc -L altera_mf_ver work.doom_mem_tb

add wave sim:/doom_mem_tb/clk
add wave -radix hex sim:/doom_mem_tb/sys/cpu/id_pc
add wave -radix hex sim:/doom_mem_tb/bus_addr
add wave sim:/doom_mem_tb/bus_re
add wave sim:/doom_mem_tb/bus_we
add wave sim:/doom_mem_tb/ext_stall
add wave -radix hex sim:/doom_mem_tb/ifetch_addr
add wave sim:/doom_mem_tb/ifetch_ready
add wave -radix unsigned sim:/doom_mem_tb/xm/cache/state
add wave -radix unsigned sim:/doom_mem_tb/xm/bridge/state
add wave sim:/doom_mem_tb/xm/locked
add wave sim:/doom_mem_tb/xm/owner
add wave -radix hex sim:/doom_mem_tb/avm_address
add wave sim:/doom_mem_tb/avm_read
add wave sim:/doom_mem_tb/avm_write
add wave sim:/doom_mem_tb/avm_waitrequest
add wave sim:/doom_mem_tb/avm_readdatavalid
add wave -radix hex sim:/doom_mem_tb/avm_readdata

run -all
wave zoom full
