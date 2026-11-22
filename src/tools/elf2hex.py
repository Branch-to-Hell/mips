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

Usage (from the repo root):
    python src/tools/elf2hex.py build/c/hello_pixels.elf [-o mem] [--phase1]
"""
import argparse
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hex2banks  # noqa: E402

TEXT_BASE, TEXT_SIZE = 0x00000000, 0x4000      # contracts.md "Memory map"
DATA_BASE, DATA_SIZE = 0x10010000, 0x4000
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


def read_segments(path):
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
    if e_entry != TEXT_BASE:
        raise ValueError(f"{path}: entry point is 0x{e_entry:08X}, must be 0x{TEXT_BASE:08X} "
                         "(link crt0.o first with src/c/link.ld)")
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


def write_words(path, values):
    path.write_text("".join(f"{w:08x}\n" for w in values), newline="\n")


def convert(elf_path, out_dir, phase1):
    text, data = place(read_segments(elf_path))
    text_words, data_words = words(text), words(data)
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
    args = ap.parse_args()
    try:
        for elf in args.elf:
            convert(elf, args.out_dir, args.phase1)
    except (OSError, ValueError, struct.error) as e:
        sys.exit(f"Error: {e}")


if __name__ == "__main__":
    main()
