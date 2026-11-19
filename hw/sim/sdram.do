# Run from hw/sim in ModelSim: do sdram.do
# First generates the simulation HDL of the Platform Designer system (sdram_sys_sim/,
# not in git) from ../quartus/sdram_sys.qsys, including the controller's memory model
onerror {quit -code 1 -f}
catch {quit -sim}

if {[info exists env(QUARTUS_ROOTDIR)]} {
    set qroot $env(QUARTUS_ROOTDIR)
} else {
    set qroot C:/intelFPGA_lite/20.1/quartus
}
echo "Generating sdram_sys_sim/ with qsys-generate (takes ~30 s)..."
set log [exec $qroot/sopc_builder/bin/qsys-generate ../quartus/sdram_sys.qsys --simulation=VERILOG \
    --output-directory=sdram_sys_sim --family=MAX\ 10 --part=10M50DAF484C7G 2>@1]

vlib work
set sim sdram_sys_sim/simulation
foreach f [glob $sim/submodules/*.v $sim/submodules/*.sv] {
    vlog -sv -suppress 2583 $f
}
vlog $sim/sdram_sys.v ../rtl/sdram_smoke.v sdram_tb.v
# altera_mf_ver: altera_std_synchronizer, used by the JTAG master (PLT-10)
vsim -voptargs=+acc -L altera_mf_ver work.sdram_tb

add wave sim:/sdram_tb/clk
add wave sim:/sdram_tb/reset
add wave -radix unsigned sim:/sdram_tb/test/state
add wave -radix hex sim:/sdram_tb/address
add wave sim:/sdram_tb/read
add wave sim:/sdram_tb/write
add wave -radix hex sim:/sdram_tb/writedata
add wave -radix binary sim:/sdram_tb/byteenable
add wave sim:/sdram_tb/waitrequest
add wave sim:/sdram_tb/readdatavalid
add wave -radix hex sim:/sdram_tb/readdata
add wave -radix unsigned sim:/sdram_tb/errors
add wave -radix hex sim:/sdram_tb/DRAM_ADDR
add wave -radix unsigned sim:/sdram_tb/DRAM_BA
add wave sim:/sdram_tb/DRAM_RAS_N
add wave sim:/sdram_tb/DRAM_CAS_N
add wave sim:/sdram_tb/DRAM_WE_N
add wave -radix hex sim:/sdram_tb/DRAM_DQ

run -all
wave zoom full
