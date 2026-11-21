#!/usr/bin/env bash
# Assemble a GNU-as test program (sw/programs/*.s) with the real MIPS toolchain and write
# its word image hw/mem/<name>.hex (one 32-bit big-endian word per line, text base 0),
# the same format as our assembler's word image, so pipeline testbenches load it as is.
# Needs the cross binutils (contracts.md "Tool settings": package gcc-mips-linux-gnu in WSL).
# Usage (from the repo root, in WSL):  sw/tools/gas_image.sh sw/programs/cpu7_isa.s
# From Windows:  wsl -d Ubuntu -- sw/tools/gas_image.sh sw/programs/cpu7_isa.s
set -euo pipefail
src="$1"
name="$(basename "${src%.*}")"
out="${2:-hw/mem}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mips-linux-gnu-as -EB -march=mips1 -mno-shared -o "$tmp/$name.o" "$src"
mips-linux-gnu-ld -EB -Ttext=0 -e main -o "$tmp/$name.elf" "$tmp/$name.o"
mips-linux-gnu-objcopy -O binary -j .text "$tmp/$name.elf" "$tmp/$name.bin"
od -An -v -tx1 "$tmp/$name.bin" | tr -s ' \n' '\n' | grep -v '^$' | paste -d '' - - - - > "$out/$name.hex"
echo "$out/$name.hex: $(wc -l < "$out/$name.hex") words"
