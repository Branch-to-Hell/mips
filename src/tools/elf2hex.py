"""Convert a GCC ELF (built with src/c/link.ld) into the same memory images as our assembler (TC-9).

    <name>.hex          text region, one 32-bit word per line from 0x00000000
    <name>_data.hex     data region, one word per line from 0x10010000 (.rodata + .data)
    <name>_bytes.hex, <name>_b0..b3.hex   instruction images (CPU-12), made by hex2banks.py
    <name>_data_b0..b3.hex                the data image in 4 byte lanes, what data_memory loads (CPU-7)

Every word is big-endian (the ELF must be -EB). .bss is not in the image: crt0.S zeroes it.
The files go to mem/ (or -o DIR), so the testbenches, ref_sim.py and Quartus use them like
any assembled program.

--phase1 fails if the code uses an instruction the CPU does not run yet (phase 2 of
docs/contracts.md "ISA": CPU-7, CPU-8), and lists them with their addresses.

--sdram (Doom, docs/contracts.md "Doom memory"): the ELF is linked at 0x2000_0000
(src/doom/link_sdram.ld) and everything goes to the SDRAM:
    <name>.bin          the image from 0x2000_0000 (.text .rodata .data), for wad_load.tcl at offset 0
    <name>_sdram.hex    the same, one word per line, for the simulation
It checks that the image and .bss end below the WAD (0x2300_0000) and prints the sizes.

--isa fails if the code (.text) has an instruction outside our CPU's ISA, the MIPS I integer
set of docs/contracts.md "ISA" (no lwl/lwr/swl/swr, no FPU, no MIPS32 like mul or clz, no
traps like teq), and lists them. The cross compiler's libgcc.a is MIPS32 hard float: this is
what catches one of its routines sneaking in.

Usage (from the repo root):
    python src/tools/elf2hex.py build/c/hello_pixels.elf [-o mem] [--phase1]
    python src/tools/elf2hex.py build/doom/doom.elf --sdram -o build/doom --isa
"""
import argparse
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hex2banks  # noqa: E402

TEXT_BASE, TEXT_SIZE = 0x00000000, 0x4000      # contracts.md "Memory map"
DATA_BASE, DATA_SIZE = 0x10010000, 0x4000
SDRAM_BASE = 0x20000000
WAD_BASE = 0x23000000                           # SDRAM offset 0x0300_0000: the WAD (PLT-10)
# The whole ISA of mips_pipeline (contracts.md "ISA", phases 1 and 2): R-type functs,
# REGIMM rt values and opcodes. syscall/break run as nops but GCC never needs them.
ISA_FUNCT = {0x00, 0x02, 0x03, 0x04, 0x06, 0x07, 0x08, 0x09, 0x10, 0x11, 0x12, 0x13,
             0x18, 0x19, 0x1A, 0x1B, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B}
ISA_REGIMM = {0x00, 0x01, 0x10, 0x11}                  # bltz bgez bltzal bgezal
ISA_OPCODE = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
              0x0E, 0x0F, 0x20, 0x21, 0x23, 0x24, 0x25, 0x28, 0x29, 0x2B}
OPCODE_NAMES = {0x10: "COP0", 0x11: "COP1 (FPU)", 0x1C: "SPECIAL2 (MIPS32: mul, clz...)",
                0x22: "lwl", 0x26: "lwr", 0x2A: "swl", 0x2E: "swr", 0x31: "lwc1", 0x35: "ldc1",
                0x39: "swc1", 0x3D: "sdc1", 0x30: "ll", 0x38: "sc"}
FUNCT_NAMES = {0x0C: "syscall", 0x0D: "break", 0x34: "teq", 0x30: "tge", 0x36: "tne", 0x01: "movf/movt",
               0x0A: "movz", 0x0B: "movn", 0x0F: "sync"}
PT_LOAD = 1
EM_MIPS = 8

# Phase 1 ISA (what mips_pipeline runs today): R-type funct codes and opcodes.
PHASE1_FUNCT = {0x00: "sll", 0x02: "srl", 0x08: "jr", 0x20: "add", 0x21: "addu", 0x22: "sub",
                0x23: "subu", 0x24: "and", 0x25: "or", 0x27: "nor", 0x2A: "slt"}
PHASE1_OPCODE = {0x02: "j", 0x03: "jal", 0x04: "beq", 0x05: "bne", 0x08: "addi", 0x09: "addiu",
                 0x0A: "slti", 0x0C: "andi", 0x0D: "ori", 0x0F: "lui", 0x23: "lw", 0x2B: "sw"}
PHASE2_FUNCT = {0x03: "sra", 0x04: "sllv", 0x06: "srlv", 0x07: "srav", 0x09: "jalr",
                0x10: "mfhi", 0x11: "mthi", 0x12: "mflo", 0x13: "mtlo", 0x18: "mult",
                0x19: "multu", 0x1A: "div", 0x1B: "divu", 0x26: "xor", 0x2B: "sltu",
                0x0C: "syscall (never: no exceptions)", 0x0D: "break (never: no exceptions)"}
PHASE2_OPCODE = {0x01: "bltz/bgez", 0x06: "blez", 0x07: "bgtz", 0x0B: "sltiu", 0x0E: "xori",
                 0x20: "lb", 0x21: "lh", 0x24: "lbu", 0x25: "lhu", 0x28: "sb", 0x29: "sh"}


def read_segments(path, entry=TEXT_BASE):
    """Return the ELF's PT_LOAD segments as (address, bytes in the file, memory size)."""
    elf = path.read_bytes()
    if elf[:4] != b"\x7fELF":
        raise ValueError(f"{path}: not an ELF file")
    if elf[4] != 1 or elf[5] != 2:
        raise ValueError(f"{path}: must be ELF32 big-endian (build with -EB)")
    (e_type, e_machine, _, e_entry, e_phoff, _, _, _, e_phentsize, e_phnum) = \
        struct.unpack_from(">HHIIIIIHHH", elf, 16)
    if e_machine != EM_MIPS:
        raise ValueError(f"{path}: not a MIPS ELF (e_machine = {e_machine})")
    if e_entry != entry:
        raise ValueError(f"{path}: entry point is 0x{e_entry:08X}, must be 0x{entry:08X} "
                         "(link crt0.o first, with src/c/link.ld or src/doom/link_sdram.ld)")
    segments = []
    for i in range(e_phnum):
        p_type, p_offset, p_vaddr, _, p_filesz, p_memsz, _, _ = \
            struct.unpack_from(">IIIIIIII", elf, e_phoff + i * e_phentsize)
        if p_type == PT_LOAD and p_memsz:
            segments.append((p_vaddr, elf[p_offset:p_offset + p_filesz], p_memsz))
    return segments


def place(segments):
    """Put each segment's bytes in the text or data region. Returns (text, data) bytearrays."""
    text, data = bytearray(), bytearray()
    for addr, payload, memsz in segments:
        end = addr + memsz
        if TEXT_BASE <= addr and end <= TEXT_BASE + TEXT_SIZE:
            image, offset = text, addr - TEXT_BASE
        elif DATA_BASE <= addr and end <= DATA_BASE + DATA_SIZE:
            image, offset = data, addr - DATA_BASE
        else:
            raise ValueError(f"segment 0x{addr:08X}-0x{end - 1:08X} is outside the text "
                             f"(16 KB at 0x{TEXT_BASE:08X}) and data (16 KB at 0x{DATA_BASE:08X}) regions")
        if len(image) < offset + len(payload):
            image.extend(bytes(offset + len(payload) - len(image)))
        image[offset:offset + len(payload)] = payload
    for image in (text, data):
        image.extend(bytes(-len(image) % 4))   # whole words
    return text, data


def words(image):
    return [struct.unpack_from(">I", image, i)[0] for i in range(0, len(image), 4)]


def phase2_uses(text_words):
    """(address, name) of every instruction outside the phase 1 ISA."""
    found = []
    for i, w in enumerate(text_words):
        opcode, funct = w >> 26, w & 0x3F
        if opcode == 0:
            ok, name = funct in PHASE1_FUNCT, PHASE2_FUNCT.get(funct, f"funct 0x{funct:02X}")
        else:
            ok, name = opcode in PHASE1_OPCODE, PHASE2_OPCODE.get(opcode, f"opcode 0x{opcode:02X}")
        if not ok:
            found.append((TEXT_BASE + 4 * i, name))
    return found


def text_section(path):
    """(address, size) of the ELF's .text section: the code, without .rodata/.data."""
    elf = path.read_bytes()
    e_shoff, = struct.unpack_from(">I", elf, 32)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(">HHH", elf, 46)
    def header(i):
        return struct.unpack_from(">IIIIIIIIII", elf, e_shoff + i * e_shentsize)
    names_offset = header(e_shstrndx)[4]
    for i in range(e_shnum):
        sh_name, _, _, sh_addr, _, sh_size = header(i)[:6]
        name = elf[names_offset + sh_name:elf.index(b"\0", names_offset + sh_name)]
        if name == b".text":
            return sh_addr, sh_size
    raise ValueError(f"{path}: no .text section")


def isa_violations(code_words, base):
    """(address, name) of every instruction outside our CPU's ISA."""
    found = []
    for i, w in enumerate(code_words):
        opcode, funct, rt = w >> 26, w & 0x3F, (w >> 16) & 0x1F
        if opcode == 0:
            ok, name = funct in ISA_FUNCT, FUNCT_NAMES.get(funct, f"funct 0x{funct:02X}")
        elif opcode == 1:
            ok, name = rt in ISA_REGIMM, f"REGIMM rt 0x{rt:02X}"
        else:
            ok, name = opcode in ISA_OPCODE, OPCODE_NAMES.get(opcode, f"opcode 0x{opcode:02X}")
        if not ok:
            found.append((base + 4 * i, name))
    return found


def check_isa(elf_path, code_words, base):
    found = isa_violations(code_words, base)
    if found:
        lines = "\n".join(f"  0x{a:08X}  {n}" for a, n in found[:20])
        raise ValueError(f"{elf_path}: {len(found)} instructions our CPU doesn't run "
                         f"(see the .lst for their functions):\n{lines}")


def convert_sdram(elf_path, out_dir, isa):
    """Doom: one image from SDRAM_BASE (docs/contracts.md "Doom memory")."""
    segments = read_segments(elf_path, entry=SDRAM_BASE)
    image = bytearray()
    end = SDRAM_BASE
    for addr, payload, memsz in segments:
        if addr < SDRAM_BASE or addr + memsz > WAD_BASE:
            raise ValueError(f"segment 0x{addr:08X}-0x{addr + memsz - 1:08X} is outside the SDRAM "
                             f"below the WAD (0x{SDRAM_BASE:08X}-0x{WAD_BASE - 1:08X})")
        offset = addr - SDRAM_BASE
        if len(image) < offset + len(payload):
            image.extend(bytes(offset + len(payload) - len(image)))
        image[offset:offset + len(payload)] = payload
        end = max(end, addr + memsz)
    image.extend(bytes(-len(image) % 4))
    image_words = words(image)
    if isa:                                     # only the code: .rodata/.data are not instructions
        text_addr, text_size = text_section(elf_path)
        first = (text_addr - SDRAM_BASE) // 4
        check_isa(elf_path, image_words[first:first + text_size // 4], text_addr)
    name = elf_path.stem
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{name}.bin").write_bytes(image)
    write_words(out_dir / f"{name}_sdram.hex", image_words)
    heap = WAD_BASE - ((end + 7) & ~7)
    print(f"{elf_path}: image {len(image)} bytes (0x{SDRAM_BASE:08X}-0x{SDRAM_BASE + len(image) - 1:08X}), "
          f"with .bss up to 0x{end:08X}; heap {heap // 1024} KB up to the WAD at 0x{WAD_BASE:08X}")
    print(f"  -> {out_dir}/{name}.bin + {name}_sdram.hex")


def write_words(path, values):
    path.write_text("".join(f"{w:08x}\n" for w in values), newline="\n")


def convert(elf_path, out_dir, phase1, isa=False):
    text, data = place(read_segments(elf_path))
    text_words, data_words = words(text), words(data)
    if isa:
        check_isa(elf_path, text_words, TEXT_BASE)
    if phase1:
        uses = phase2_uses(text_words)
        if uses:
            lines = "\n".join(f"  0x{a:08X}  {n}" for a, n in uses)
            raise ValueError(f"{elf_path}: {len(uses)} instructions the CPU does not run yet "
                             f"(phase 2, CPU-7/CPU-8):\n{lines}")
    name = elf_path.stem
    out_dir.mkdir(parents=True, exist_ok=True)
    hex_path = out_dir / f"{name}.hex"
    write_words(hex_path, text_words)
    write_words(out_dir / f"{name}_data.hex", data_words or [0])  # $readmemh warns on an empty file
    print(f"{elf_path}: {len(text_words)} text words, {len(data_words)} data words -> "
          f"{out_dir}/{name}.hex + {name}_data.hex")
    hex2banks.convert(hex_path)
    hex2banks.convert(out_dir / f"{name}_data.hex", bytes_image=False)  # data_memory's 4 lanes


def main():
    ap = argparse.ArgumentParser(description="ELF -> memory images (TC-9)")
    ap.add_argument("elf", nargs="+", type=Path, help="ELF linked with src/c/link.ld")
    ap.add_argument("-o", "--out-dir", type=Path, default=Path("mem"), help="output folder (default: mem)")
    ap.add_argument("--phase1", action="store_true",
                    help="fail if the code uses phase 2 instructions (not in mips_pipeline yet)")
    ap.add_argument("--sdram", action="store_true",
                    help="Doom: ELF linked at 0x2000_0000, write <name>.bin and <name>_sdram.hex")
    ap.add_argument("--isa", action="store_true",
                    help="fail if the code has an instruction outside our CPU's ISA (FPU, MIPS32, lwl...)")
    args = ap.parse_args()
    try:
        for elf in args.elf:
            if args.sdram:
                convert_sdram(elf, args.out_dir, args.isa)
            else:
                convert(elf, args.out_dir, args.phase1, args.isa)
    except (OSError, ValueError, struct.error) as e:
        sys.exit(f"Error: {e}")


if __name__ == "__main__":
    main()
