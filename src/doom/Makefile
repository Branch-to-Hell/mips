# Build Doom for our MIPS (DOOM-5). Run in WSL, from the repo root:
#     make -C src/doom
# Output:
#   build/doom/doom.elf, .map, .lst    Doom linked at 0x2000_0000 (src/doom/link_sdram.ld)
#   build/doom/doom.bin                the SDRAM image from 0x2000_0000: load it at offset 0 with
#                                      src/tools/wad_load.tcl (the WAD goes at 0x0300_0000)
#   build/doom/doom_sdram.hex          the same image, one word per line, for the simulation
#   mem/doom_boot*.hex                 boot.S for the on-chip text (top_doom)
# DOOM-1, the same Doom on the PC without a window (reference frames for DOOM-6/7):
#     make -C src/doom host-run [WAD=build/wad/doom1.wad] [FRAMES=40]
#   build/doom/host/doom_host           native build (gcc), src/doom/host/doomgeneric_host.c
#   build/doom/host/frame_NNN.ppm       the first FRAMES frames, palette applied
# Memory map and build flags: docs/contracts.md "Doom memory" and "Tool settings".

CROSS   ?= mips-linux-gnu-
CC      := $(CROSS)gcc
OBJDUMP := $(CROSS)objdump
PYTHON  ?= python3

ROOT    := ../..
BUILD   := $(ROOT)/build/doom
MEM     := $(ROOT)/mem
LIBC    := $(ROOT)/build/c/libc.a
CRT0    := $(ROOT)/build/c/crt0.o
DG      := doomgeneric

ARCH    := -march=mips1 -mabi=32 -msoft-float -mno-abicalls -fno-pic -G0 -EB
INCLUDE := -nostdinc -isystem $(ROOT)/src/c/libc/include -isystem $(shell $(CC) -print-file-name=include)
# -mmemcpy: block copies call memcpy instead of using lwl/lwr (with PACKEDATTR empty in doomtype.h)
# CMAP256 + 320x200: Doom's frame is 8-bit palette indices, the format of video mode B
DOOM_DEFS := -DNORMALUNIX -DCMAP256 -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200
CFLAGS  := $(ARCH) -O2 -ffreestanding -fno-builtin -mno-check-zero-division -mmemcpy \
           -ffunction-sections -fdata-sections $(INCLUDE) $(DOOM_DEFS) -I$(DG) -MMD -MP
# Doom's own code has many old-style warnings; ours doesn't
DOOM_WARN := -w
LDFLAGS := $(ARCH) -nostdlib -nostartfiles -static -Wl,--gc-sections \
           -Wl,--build-id=none -Wl,--no-warn-rwx-segments

DOOM_SRCS := $(wildcard $(DG)/*.c)
OBJS := $(patsubst $(DG)/%.c,$(BUILD)/dg/%.o,$(DOOM_SRCS)) $(BUILD)/doomgeneric_mips.o $(BUILD)/wad_mem.o

.PHONY: all clean host host-run
all: $(BUILD)/doom.bin $(MEM)/doom_boot.hex

$(BUILD)/dg/%.o: $(DG)/%.c
	@mkdir -p $(BUILD)/dg
	$(CC) $(CFLAGS) $(DOOM_WARN) -c $< -o $@

$(BUILD)/doomgeneric_mips.o $(BUILD)/wad_mem.o: $(BUILD)/%.o: %.c
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -Wall -Wextra -c $< -o $@

# Our C library and crt0 come from src/c: rebuild them there when their sources change
LIBC_SRCS := $(wildcard $(ROOT)/src/c/libc/*.c $(ROOT)/src/c/libc/include/*.h $(ROOT)/src/c/libc/include/sys/*.h)
$(LIBC): $(LIBC_SRCS)
	$(MAKE) -s -C $(ROOT)/src/c ../../build/c/libc.a
$(CRT0): $(ROOT)/src/c/crt0.S
	$(MAKE) -s -C $(ROOT)/src/c ../../build/c/crt0.o

# crt0.o first: _start at 0x2000_0000
$(BUILD)/doom.elf: $(CRT0) $(OBJS) $(LIBC) link_sdram.ld
	$(CC) $(LDFLAGS) -T link_sdram.ld -Wl,-Map=$(BUILD)/doom.map $(CRT0) $(OBJS) $(LIBC) -lgcc -o $@
	$(OBJDUMP) -d $@ > $(BUILD)/doom.lst

$(BUILD)/doom.bin: $(BUILD)/doom.elf $(ROOT)/src/tools/elf2hex.py
	$(PYTHON) $(ROOT)/src/tools/elf2hex.py $< --sdram -o $(BUILD) --isa

# Boot code: on-chip text, linked like any C program (src/c/link.ld)
$(BUILD)/boot.o: boot.S
	@mkdir -p $(BUILD)
	$(CC) $(ARCH) -c $< -o $@

$(BUILD)/doom_boot.elf: $(BUILD)/boot.o
	$(CC) $(LDFLAGS) -T $(ROOT)/src/c/link.ld $< -o $@

$(MEM)/doom_boot.hex: $(BUILD)/doom_boot.elf $(ROOT)/src/tools/elf2hex.py
	$(PYTHON) $(ROOT)/src/tools/elf2hex.py $< -o $(MEM) --isa

# ---- DOOM-1: host build (native gcc, same sources and defines, files and time like on the MIPS) ----
HOST_CC     ?= gcc
HOST        := $(BUILD)/host
HOST_CFLAGS := -O2 -g $(DOOM_DEFS) -I$(DG) -I. -MMD -MP
HOST_OBJS   := $(patsubst $(DG)/%.c,$(HOST)/dg/%.o,$(DOOM_SRCS)) $(HOST)/doomgeneric_host.o $(HOST)/wad_mem.o
WAD         ?= $(ROOT)/build/wad/doom1.wad
FRAMES      ?= 40

host: $(HOST)/doom_host

$(HOST)/dg/%.o: $(DG)/%.c host/host_files.h
	@mkdir -p $(HOST)/dg
	$(HOST_CC) $(HOST_CFLAGS) $(DOOM_WARN) -include host/host_files.h -c $< -o $@

$(HOST)/doomgeneric_host.o: host/doomgeneric_host.c
	@mkdir -p $(HOST)
	$(HOST_CC) $(HOST_CFLAGS) -Wall -Wextra -c $< -o $@

$(HOST)/wad_mem.o: wad_mem.c
	@mkdir -p $(HOST)
	$(HOST_CC) $(HOST_CFLAGS) -Wall -Wextra -c $< -o $@

$(HOST)/doom_host: $(HOST_OBJS)
	$(HOST_CC) $^ -lm -o $@

host-run: $(HOST)/doom_host
	rm -f $(HOST)/frame_*.ppm
	cd $(HOST) && ./doom_host $(abspath $(WAD)) . $(FRAMES)

clean:
	rm -rf $(BUILD)

-include $(wildcard $(BUILD)/*.d $(BUILD)/dg/*.d $(HOST)/*.d $(HOST)/dg/*.d)
