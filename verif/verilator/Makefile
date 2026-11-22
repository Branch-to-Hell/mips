# TC-7: Verilator harness. Run in WSL, from the repo root (needs: sudo apt install verilator):
#     make -C verif/verilator                          # build build/verilator/mips_sim (once)
#     make -C verif/verilator run PROG=hello_pixels    # trace of mem/hello_pixels* on stdout
#     make -C verif/verilator compare PROG=tc4_rtype   # diff against src/tools/ref_sim.py
# Or call the simulator directly, from the repo root:
#     build/verilator/mips_sim +program=mem/<name> [+max-cycles=N] [+ppm=file.ppm]
# The program is loaded at run time, so one build runs every program.

ROOT    := $(abspath ../..)
BUILD   := $(ROOT)/build/verilator
SIM     := $(BUILD)/mips_sim
PYTHON  ?= python3

# life_system with mode B and what it instantiates (no PLL or board top-levels)
RTL := $(addprefix $(ROOT)/rtl/, life_system.v mips_pipeline.v mult_div.v hazard_unit.v if_id_register.v \
       pipeline_register.v instruction_memory.v control_unit.v alu_control.v register_file.v alu.v \
       data_memory.v debounce.v hex7seg.v hex_debug.v mmio.v vga_sync.v framebuffer_a.v \
       video_mode_a.v framebuffer_b.v palette.v video_mode_b.v)

# The RTL is written for ModelSim and Quartus: Verilator's style warnings (widths, unused
# signals, both clock edges) are shown but do not stop the build.
VFLAGS := --cc --exe --build -j 0 -O3 --top-module harness_top -Wno-fatal -Wno-lint -Wno-style \
          -Wno-MULTIDRIVEN -Wno-UNOPTFLAT --x-initial fast -Mdir $(BUILD)/obj_dir -o $(SIM)

PROG ?= hello_pixels
TRACE := $(BUILD)/$(PROG)

.PHONY: all run compare clean
all: $(SIM)

$(SIM): harness_top.sv sim_main.cpp $(RTL)
	mkdir -p $(BUILD)
	verilator $(VFLAGS) $(CURDIR)/harness_top.sv $(CURDIR)/sim_main.cpp $(RTL)

run: $(SIM)
	cd $(ROOT) && $(SIM) +program=mem/$(PROG)

# Same trace as the reference simulator, without the HALT line (contracts.md)
compare: $(SIM)
	cd $(ROOT) && $(SIM) +program=mem/$(PROG) | grep -v '^HALT:' > $(TRACE).cpu.txt
	cd $(ROOT) && $(PYTHON) src/tools/ref_sim.py mem/$(PROG).hex | grep -v '^HALT:' > $(TRACE).ref.txt
	diff $(TRACE).ref.txt $(TRACE).cpu.txt && \
	    echo "PASS: $(PROG): $$(wc -l < $(TRACE).cpu.txt) register writes, same trace as ref_sim.py"

clean:
	rm -rf $(BUILD)
