# Build C programs for our MIPS (TC-9). Run in WSL, from the repo root:
#     make -C src/c                    # every program in src/c (one .c file = one program)
#     make -C src/c hello_pixels       # just one
# Output: build/c/<name>.elf, .lst (disassembly), .map, and the memory images in mem/
# (<name>.hex, _data.hex, _bytes.hex, _b0..b3.hex), the same files as our assembler writes.
# Needs: sudo apt install gcc-mips-linux-gnu binutils-mips-linux-gnu make python3

CROSS   ?= mips-linux-gnu-
CC      := $(CROSS)gcc
OBJDUMP := $(CROSS)objdump
PYTHON  ?= python3

ROOT    := ../..
BUILD   := $(ROOT)/build/c
MEM     := $(ROOT)/mem

# MIPS I, no FPU, no PIC/abicalls (bare metal), nothing $gp-relative, big-endian (contracts.md)
ARCH    := -march=mips1 -mabi=32 -msoft-float -mno-abicalls -fno-pic -G0 -EB
# -mno-check-zero-division: no "break 7" trap after div/divu (the CPU has no exceptions)
CFLAGS  := $(ARCH) -O2 -ffreestanding -fno-builtin -nostdlib -mno-check-zero-division -Wall -Wextra
LDFLAGS := $(ARCH) -nostdlib -nostartfiles -static -T link.ld \
           -Wl,--build-id=none -Wl,--no-warn-rwx-segments
LIBS    := -lgcc    # helpers GCC may call (64-bit shifts, soft float)

# --phase1: fail if GCC used an instruction mips_pipeline does not run yet.
# Drop it (ELF2HEX_FLAGS=) once CPU-7 and CPU-8 are merged.
ELF2HEX_FLAGS ?= --phase1

PROGRAMS := $(basename $(wildcard *.c))

.PHONY: all clean $(PROGRAMS)
all: $(PROGRAMS)
$(PROGRAMS): %: $(MEM)/%.hex

$(BUILD)/crt0.o: crt0.S | $(BUILD)
	$(CC) $(ARCH) -c $< -o $@

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

# crt0.o goes first so _start is at address 0
$(BUILD)/%.elf: $(BUILD)/crt0.o $(BUILD)/%.o link.ld
	$(CC) $(LDFLAGS) -Wl,-Map=$(BUILD)/$*.map $(BUILD)/crt0.o $(BUILD)/$*.o $(LIBS) -o $@
	$(OBJDUMP) -d -j .text $@ > $(BUILD)/$*.lst

$(MEM)/%.hex: $(BUILD)/%.elf $(ROOT)/src/tools/elf2hex.py
	$(PYTHON) $(ROOT)/src/tools/elf2hex.py $< -o $(MEM) $(ELF2HEX_FLAGS)

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)

.SECONDARY:     # keep the .o and .elf files
