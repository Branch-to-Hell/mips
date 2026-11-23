"""Convert a word image (.hex, one 32-bit word per line) into the CPU-12 instruction images.

For word images that do not come from our assembler (it writes these files itself, TC-13). Same output format:

    <name>_bytes.hex   one byte per address, big-endian (the professor's loadable image)
    <name>_b0.hex      bank 0: bytes at addresses with addr[1:0] = 0 (bits 31..24 of each word)
    <name>_b1.hex      bank 1: addr[1:0] = 1 (bits 23..16)
    <name>_b2.hex      bank 2: addr[1:0] = 2 (bits 15..8)
    <name>_b3.hex      bank 3: addr[1:0] = 3 (bits 7..0)

Every file has one byte per line, 2 lowercase hex digits, no address and no header.
Line i of a bank file is the byte of instruction i. instruction_memory.v loads the 4 bank files
with $readmemh, from the prefix given in IMEM_INIT (e.g. "../mem/life_board").

A data image (<name>_data.hex) gets only the 4 lanes, <name>_data_b0..b3.hex (CPU-7: data_memory
has one bank per byte lane and loads them from the prefix in DMEM_INIT, e.g. "../mem/x_data").

Usage (from the repo root):
    python src/tools/hex2banks.py mem/life_board.hex mem/life_board_data.hex [more.hex ...]
"""
import sys
from pathlib import Path

DEPTH = 4096  # instructions per bank (16 KB text region)


def read_words(path):
    words = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        line = line.split("//")[0].strip()
        if not line:
            continue
        if line.startswith("@"):
            raise ValueError(f"{path}:{n}: address markers (@) are not supported")
        value = int(line, 16)
        if value > 0xFFFFFFFF:
            raise ValueError(f"{path}:{n}: '{line}' is wider than 32 bits")
        words.append(value)
    if len(words) > DEPTH:
        raise ValueError(f"{path}: {len(words)} words don't fit in {DEPTH}")
    return words


def write_bytes(path, values):
    path.write_text("".join(f"{b:02x}\n" for b in values), newline="\n")  # LF on every OS


def convert(src, bytes_image=True):
    """bytes_image=False for a data image (<name>_data.hex): only the 4 lanes, which
    data_memory loads (CPU-7: one bank per byte lane, like the instruction memory)."""
    words = read_words(src)
    base = src.with_suffix("")
    image = [(w >> shift) & 0xFF for w in words for shift in (24, 16, 8, 0)]  # big-endian
    if bytes_image:
        write_bytes(Path(f"{base}_bytes.hex"), image)
    for k in range(4):
        write_bytes(Path(f"{base}_b{k}.hex"), image[k::4])
    made = f"{base.name}_bytes.hex + " if bytes_image else ""
    print(f"{src}: {len(words)} words -> {made}{base.name}_b0..b3.hex")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    try:
        for arg in sys.argv[1:]:
            convert(Path(arg), bytes_image=not arg.endswith("_data.hex"))
    except (OSError, ValueError) as e:
        sys.exit(f"Error: {e}")


if __name__ == "__main__":
    main()
