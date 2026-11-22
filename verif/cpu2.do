# Run from verif in ModelSim: do cpu2.do
onerror {quit -code 1 -f}
catch {quit -sim}
vlib work
vlog ../rtl/*.v cpu2_tb.v
vsim work.cpu2_tb
run -all
