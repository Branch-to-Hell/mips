# TC-7: Verilator harness. Run in WSL, from the repo root (needs: sudo apt install verilator):
#     make -C verif/verilator                          # build mips_sim and mips_sim_ext (once)
#     make -C verif/verilator run PROG=hello_pixels    # trace of mem/hello_pixels* on stdout
#     make -C verif/verilator compare PROG=tc4_rtype   # diff against src/tools/ref_sim.py
# CPU-9, the same comparison with random waits (the trace must not change):
#     make -C verif/verilator compare PROG=tc4_rtype STALL=30 SEED=7      # mem_stall in 30% of cycles
#     make -C verif/verilator compare-ext PROG=tc4_rtype FETCH=6 STALL=20 # fetch from 0x2000_0000
# compare-ext assembles src/programs/$(PROG).asm with --text-base 0x20000000 into build/verilator/ext/.
# Or call the simulators directly, from the repo root:
#     build/verilator/mips_sim +program=mem/<name> [+max-cycles=N] [+ppm=file.ppm] [+stall=P] [+seed=S]
#     build/verilator/mips_sim_ext +program=<prefix> [+fetch_delay=N] [+stall=P] [+seed=S]
# The program is loaded at run time, so one build runs every program.

ROOT    := $(abspath ../..)
BUILD   := $(ROOT)/build/verilator
SIM     := $(BUILD)/mips_sim
SIM_EXT := $(BUILD)/mips_sim_ext
PYTHON  ?= python3

# life_system with mode B and what it instantiates (no PLL or board top-levels)
RTL := $(addprefix $(ROOT)/rtl/, life_system.v mips_pipeline.v mult_div.v hazard_unit.v if_id_register.v \
       pipeline_register.v instruction_memory.v control_unit.v alu_control.v register_file.v alu.v \
       data_memory.v debounce.v hex7seg.v hex_debug.v mmio.v vga_sync.v framebuffer_a.v \
       video_mode_a.v framebuffer_b.v palette.v video_mode_b.v)
SOURCES := $(CURDIR)/harness_top.sv $(CURDIR)/sim_main.cpp $(RTL)

# The RTL is written for ModelSim and Quartus: Verilator's style warnings (widths, unused
# signals, both clock edges) are shown but do not stop the build.
VFLAGS := --cc --exe --build -j 0 -O3 --top-module harness_top -Wno-fatal -Wno-lint -Wno-style \
          -Wno-MULTIDRIVEN -Wno-UNOPTFLAT --x-initial fast

PROG  ?= hello_pixels
STALL ?= 0
FETCH ?= 0
SEED  ?= 1
WAITS := +stall=$(STALL) +fetch_delay=$(FETCH) +seed=$(SEED)
TRACE := $(BUILD)/$(PROG)
EXT   := $(BUILD)/ext

.PHONY: all run compare compare-ext clean
all: $(SIM) $(SIM_EXT)

$(SIM): harness_top.sv sim_main.cpp $(RTL)
	mkdir -p $(BUILD)
	verilator $(VFLAGS) -Mdir $(BUILD)/obj_dir -o $(SIM) $(SOURCES)

$(SIM_EXT): harness_top.sv sim_main.cpp $(RTL)
	mkdir -p $(BUILD)
	verilator $(VFLAGS) -GEXT_START=1 -Mdir $(BUILD)/obj_dir_ext -o $(SIM_EXT) $(SOURCES)

run: $(SIM)
	cd $(ROOT) && $(SIM) +program=mem/$(PROG) $(WAITS)

# Same trace as the reference simulator, without the HALT line (contracts.md)
compare: $(SIM)
	cd $(ROOT) && $(SIM) +program=mem/$(PROG) $(WAITS) | grep -v '^HALT:' > $(TRACE).cpu.txt
	cd $(ROOT) && $(PYTHON) src/tools/ref_sim.py mem/$(PROG).hex | grep -v '^HALT:' > $(TRACE).ref.txt
	diff $(TRACE).ref.txt $(TRACE).cpu.txt && \
	    echo "PASS: $(PROG): $$(wc -l < $(TRACE).cpu.txt) register writes, same trace as ref_sim.py"

# CPU-9: the program runs from the external text region, every fetch through ifetch_*
compare-ext: $(SIM_EXT)
	mkdir -p $(EXT)
	cd $(ROOT) && $(PYTHON) src/assembler/assembler.py src/programs/$(PROG).asm -o $(EXT) --text-base 0x20000000 > /dev/null
	cd $(ROOT) && $(SIM_EXT) +program=$(EXT)/$(PROG) $(WAITS) | grep -v '^HALT:' > $(EXT)/$(PROG).cpu.txt
	cd $(ROOT) && $(PYTHON) src/tools/ref_sim.py $(EXT)/$(PROG).hex --text-base 0x20000000 | grep -v '^HALT:' > $(EXT)/$(PROG).ref.txt
	diff $(EXT)/$(PROG).ref.txt $(EXT)/$(PROG).cpu.txt && \
	    echo "PASS: $(PROG) from 0x20000000: $$(wc -l < $(EXT)/$(PROG).cpu.txt) register writes, same trace as ref_sim.py"

clean:
	rm -rf $(BUILD)
