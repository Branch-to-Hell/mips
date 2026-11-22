"""Reference MIPS simulator for the .hex images written by sw/assembler.

Usage:
    python sw/tools/ref_sim.py <file>.hex [--text-base 0x00400000]
           [--data <file>_data.hex] [--max-steps N] [--no-delay-slot]
           [--init R<n>=<value> ...] [--dump-regs] [--dump-mem ADDR:COUNT ...]

Each register write prints:  PC=0x00400000 R8 <= 0x00000005
The run stops and says why:
  - the program jumps to its own address (e.g. "end: j end"),
  - the PC leaves the loaded program,
  - --max-steps instructions have run (default 1000000).

Delay slot: by default a jump takes effect after the next instruction, as in
the pipeline. The assembler always puts a nop there. --no-delay-slot makes
jumps take effect at once, as MARS does with delayed branching off.
jal writes PC+8 with delay slot and PC+4 without it.
"""
import argparse
import os
import sys
TEXT_BASE = 0x00000000
DATA_BASE = 0x10010000


def signed32(value):
    value &= 0xFFFFFFFF
    if value & 0x80000000:
        return value - 0x100000000
    return value


def signed16(value):
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


class ReferenceSim:

    def __init__(self, delay_slot=True):

        self.pc = TEXT_BASE

        self.regs = [0] * 32

        self.data_mem = {}

        self.program = []

        self.running = True

        self.steps = 0

        self.halt_reason = ""

        self.delay_slot = delay_slot

        self.delay_pending = False

        self.jump_target = None

        self.jump_from = None

        self.regs[28] = 0x10008000   # $gp, MARS Default

        self.regs[29] = 0x7FFFEFFC   # $sp, MARS Default

        self.hi = 0

        self.lo = 0

    def load_hex(self, path):

        with open(path) as f:

            for line in f:

                line = line.strip()

                if not line:
                    continue

                self.program.append(
                    int(line, 16)
                )

    def load_data(self, path):

        with open(path) as f:

            index = 0

            for line in f:

                line = line.strip()

                if line:

                    self.write_word(DATA_BASE + 4 * index, int(line, 16))

                    index += 1

    def mem_addr(self, rs, offset16):

        return (self.regs[rs] + signed16(offset16)) & 0xFFFFFFFF

    def check_aligned(self, addr, size):

        if addr % size != 0:
            raise ValueError(f"misaligned {size}-byte access at 0x{addr:08X}")

    def read_byte(self, addr):

        return self.data_mem.get(addr & 0xFFFFFFFF, 0)

    def write_byte(self, addr, value):

        self.data_mem[addr & 0xFFFFFFFF] = value & 0xFF

    def read_half(self, addr):

        self.check_aligned(addr, 2)
        return (self.read_byte(addr) << 8) | self.read_byte(addr + 1)

    def write_half(self, addr, value):

        self.check_aligned(addr, 2)
        self.write_byte(addr, value >> 8)
        self.write_byte(addr + 1, value)

    def read_word(self, addr):

        self.check_aligned(addr, 4)
        value = 0
        for i in range(4):
            value |= self.read_byte(addr + i) << (8 * (3 - i))
        return value

    def write_word(self, addr, value):

        self.check_aligned(addr, 4)
        for i in range(4):
            self.write_byte(addr + i, value >> (8 * (3 - i)))

    def write_hilo(self, hi, lo):

        self.hi = hi & 0xFFFFFFFF
        self.lo = lo & 0xFFFFFFFF
        print(f"PC=0x{self.pc:08X} HI <= 0x{self.hi:08X}")
        print(f"PC=0x{self.pc:08X} LO <= 0x{self.lo:08X}")

    def return_address(self):

        return self.pc + (8 if self.delay_slot else 4)

    def jump_to(self, target):

        target &= 0xFFFFFFFF

        if not self.delay_slot:
            self.pc = target
            return

        if self.delay_pending:
            raise ValueError("jump inside a delay slot")

        self.delay_pending = True
        self.jump_target = target
        self.jump_from = self.pc
        self.pc += 4

    def fetch(self):

        index = (self.pc - TEXT_BASE) // 4

        if index < 0 or index >= len(self.program):

            self.running = False

            self.halt_reason = f"PC left the program at 0x{self.pc:08X}"

            return None

        return self.program[index]

    def write_reg(self, reg, value):

        if reg == 0:
            return

        value &= 0xFFFFFFFF

        self.regs[reg] = value

        print(
            f"PC=0x{self.pc:08X} "
            f"R{reg} <= 0x{value:08X}"
        )

    def decode_execute(self, instr):

        opcode = (instr >> 26) & 0x3F # get the opcode from the instruction

        if opcode == 0:

            self.execute_r_type(instr)

        elif opcode in [2, 3]:

            self.execute_j_type(instr)

        elif opcode == 0x1C:

            self.execute_special2(instr)

        elif opcode == 0x01:

            self.execute_regimm(instr)

        else:

            self.execute_i_type(instr)

    def execute_r_type(self, instr):

        rs = (instr >> 21) & 0x1F 
        rt = (instr >> 16) & 0x1F
        rd = (instr >> 11) & 0x1F
        shamt = (instr >> 6) & 0x1F
        funct = instr & 0x3F
        r = self.regs

        if funct in [0b100000, 0b100001]:  # add

            result = (
                self.regs[rs] +
                self.regs[rt]
            ) & 0xFFFFFFFF

            self.write_reg(
                rd,
                result
            )

            self.pc += 4
        elif funct in [0b100010, 0b100011]: # sub

            result = (
                self.regs[rs] -
                self.regs[rt]
            ) & 0xFFFFFFFF

            self.write_reg(
                rd,
                result
            )

            self.pc += 4
        elif funct == 0b100100:  # and

            result = (
                self.regs[rs] &
                self.regs[rt]
            ) & 0xFFFFFFFF

            self.write_reg(
                rd,
                result
            )

            self.pc += 4
        elif funct == 0b100101:  # or

            result = (
                self.regs[rs] |
                self.regs[rt]
            ) & 0xFFFFFFFF

            self.write_reg(
                rd,
                result
            )

            self.pc += 4
        elif funct == 0b101010:  # slt
            if signed32(self.regs[rs]) < signed32(self.regs[rt]):
                result = 1
            else:
                result = 0
            self.write_reg(
                rd,
                result
            )
            self.pc += 4
        elif funct == 0b000000:  # sll
            
            result = (self.regs[rt] << shamt) & 0xFFFFFFFF
            self.write_reg(
                rd,
                result
            )
            self.pc += 4
        elif funct == 0b000010:  # srl
            
            value = self.regs[rt] & 0xFFFFFFFF
            result = value >> shamt
            self.write_reg(
                rd,
                result
            )
            self.pc += 4
        elif funct == 0b001000:  # jr
            
            self.jump_to(self.regs[rs])
        elif funct == 0b100111:  # nor

            result = ~(self.regs[rs] | self.regs[rt]) & 0xFFFFFFFF
            self.write_reg(
                rd,
                result
            )
            self.pc += 4
        elif funct == 0b000011:  # sra
            self.write_reg(rd, signed32(r[rt]) >> shamt)
            self.pc += 4
        elif funct == 0b000100:  # sllv
            self.write_reg(rd, r[rt] << (r[rs] & 0x1F))
            self.pc += 4
        elif funct == 0b000110:  # srlv
            self.write_reg(rd, (r[rt] & 0xFFFFFFFF) >> (r[rs] & 0x1F))
            self.pc += 4
        elif funct == 0b000111:  # srav
            self.write_reg(rd, signed32(r[rt]) >> (r[rs] & 0x1F))
            self.pc += 4
        elif funct == 0b001001:  # jalr: rd = return address, jump to rs
            target = r[rs]  # read rs before rd is written (rd may equal rs)
            self.write_reg(rd, self.return_address())
            self.jump_to(target)
        elif funct == 0b010000:  # mfhi
            self.write_reg(rd, self.hi)
            self.pc += 4
        elif funct == 0b010001:  # mthi
            self.hi = r[rs] & 0xFFFFFFFF
            print(f"PC=0x{self.pc:08X} HI <= 0x{self.hi:08X}")
            self.pc += 4
        elif funct == 0b010010:  # mflo
            self.write_reg(rd, self.lo)
            self.pc += 4
        elif funct == 0b010011:  # mtlo
            self.lo = r[rs] & 0xFFFFFFFF
            print(f"PC=0x{self.pc:08X} LO <= 0x{self.lo:08X}")
            self.pc += 4
        elif funct == 0b011000:  # mult (signed)
            product = signed32(r[rs]) * signed32(r[rt])
            self.write_hilo(product >> 32, product)
            self.pc += 4
        elif funct == 0b011001:  # multu
            product = (r[rs] & 0xFFFFFFFF) * (r[rt] & 0xFFFFFFFF)
            self.write_hilo(product >> 32, product)
            self.pc += 4
        elif funct == 0b011010:  # div (signed): LO = quotient, HI = remainder
            if r[rt] != 0:
                a, b = signed32(r[rs]), signed32(r[rt])
                q = abs(a) // abs(b)
                if (a < 0) != (b < 0):
                    q = -q
                self.write_hilo(a - q * b, q)
            self.pc += 4
        elif funct == 0b011011:  # divu
            if r[rt] != 0:
                a, b = r[rs] & 0xFFFFFFFF, r[rt] & 0xFFFFFFFF
                self.write_hilo(a % b, a // b)
            self.pc += 4
        elif funct == 0b100110:  # xor
            self.write_reg(rd, r[rs] ^ r[rt])
            self.pc += 4
        elif funct == 0b101011:  # sltu
            self.write_reg(rd, 1 if (r[rs] & 0xFFFFFFFF) < (r[rt] & 0xFFFFFFFF) else 0)
            self.pc += 4
        else:

            raise ValueError(
                f"unsupported R funct 0x{funct:02X}"
            )

    def execute_i_type(self, instr):
        opcode = (instr >> 26) & 0x3F
        rs = (instr >> 21) & 0x1F 
        rt = (instr >> 16) & 0x1F
        offset = (instr >> 0) & 0xFFFF
        r = self.regs
        if opcode in [0b001000, 0b001001]:  # addi
            imm = (offset if offset < 0x8000 else offset - 0x10000)
            result = (self.regs[rs] + imm) & 0xFFFFFFFF
            self.write_reg(rt, result)
            self.pc += 4
        elif opcode == 0b001100:  # andi

            result = self.regs[rs] & (offset & 0xFFFF)
            self.write_reg(rt, result)
            self.pc += 4
        elif opcode == 0b001101:  # ori

            result = self.regs[rs] | (offset & 0xFFFF)
            self.write_reg(rt, result)
            self.pc += 4
        elif opcode == 0b100011:  # lw

            addr = (self.regs[rs] + (offset if offset < 0x8000 else offset - 0x10000)) & 0xFFFFFFFF
            value = self.read_word(addr)
            self.write_reg(rt, value)
            self.pc += 4
        elif opcode == 0b101011:  # sw
            
            addr = (self.regs[rs] + (offset if offset < 0x8000 else offset - 0x10000)) & 0xFFFFFFFF
            self.write_word(addr, self.regs[rt])
            self.pc += 4
            
        elif opcode == 0b000100:  # beq
            
            if self.regs[rs] == self.regs[rt]:
                self.jump_to(self.pc + 4 + ((offset if offset < 0x8000 else offset - 0x10000) << 2))
            else:
                self.pc += 4
        elif opcode == 0b000101:  # bne
            
            if self.regs[rs] != self.regs[rt]:
                self.jump_to(self.pc + 4 + ((offset if offset < 0x8000 else offset - 0x10000) << 2))
            else:
                self.pc += 4
        elif opcode == 0b001010:  # slti

            imm = (
                offset
                if offset < 0x8000
                else offset - 0x10000
            )

            result = 1 if signed32(self.regs[rs]) < imm else 0
            self.write_reg(rt, result)
            self.pc += 4
        elif opcode == 0b001111:  # lui
            
            result = (offset << 16) & 0xFFFFFFFF
            self.write_reg(rt, result)
            self.pc += 4
        elif opcode == 0b001011:  # sltiu: immediate is sign-extended, compared unsigned
            imm = signed16(offset) & 0xFFFFFFFF
            self.write_reg(rt, 1 if (r[rs] & 0xFFFFFFFF) < imm else 0)
            self.pc += 4
        elif opcode == 0b001110:  # xori
            self.write_reg(rt, r[rs] ^ offset)
            self.pc += 4
        elif opcode == 0b100000:  # lb
            byte = self.read_byte(self.mem_addr(rs, offset))
            self.write_reg(rt, byte - 0x100 if byte & 0x80 else byte)
            self.pc += 4
        elif opcode == 0b100100:  # lbu
            self.write_reg(rt, self.read_byte(self.mem_addr(rs, offset)))
            self.pc += 4
        elif opcode == 0b100001:  # lh
            half = self.read_half(self.mem_addr(rs, offset))
            self.write_reg(rt, half - 0x10000 if half & 0x8000 else half)
            self.pc += 4
        elif opcode == 0b100101:  # lhu
            self.write_reg(rt, self.read_half(self.mem_addr(rs, offset)))
            self.pc += 4
        elif opcode == 0b101000:  # sb
            self.write_byte(self.mem_addr(rs, offset), r[rt])
            self.pc += 4
        elif opcode == 0b101001:  # sh
            self.write_half(self.mem_addr(rs, offset), r[rt])
            self.pc += 4
        elif opcode == 0b000110:  # blez: rs <= 0
            if signed32(r[rs]) <= 0:
                self.jump_to(self.pc + 4 + (signed16(offset) << 2))
            else:
                self.pc += 4
        elif opcode == 0b000111:  # bgtz: rs > 0
            if signed32(r[rs]) > 0:
                self.jump_to(self.pc + 4 + (signed16(offset) << 2))
            else:
                self.pc += 4
        else:

            raise ValueError(
                f"unsupported I opcode 0x{opcode:02X}"
            )


    def execute_special2(self, instr):

        rs = (instr >> 21) & 0x1F
        rt = (instr >> 16) & 0x1F
        rd = (instr >> 11) & 0x1F
        funct = instr & 0x3F
        if funct == 0b000010:  # mul: rd = low 32 bits of rs * rt
            self.write_reg(rd, signed32(self.regs[rs]) * signed32(self.regs[rt]))
            self.pc += 4
        else:
            raise ValueError(f"unsupported SPECIAL2 funct 0x{funct:02X}")

    def execute_regimm(self, instr):

        rs = (instr >> 21) & 0x1F
        rt = (instr >> 16) & 0x1F
        offset = instr & 0xFFFF
        value = signed32(self.regs[rs])
        if rt == 0b00000:      # bltz
            taken = value < 0
        elif rt == 0b00001:    # bgez
            taken = value >= 0
        else:
            raise ValueError(f"unsupported REGIMM rt 0x{rt:02X}")
        if taken:
            self.jump_to(self.pc + 4 + (signed16(offset) << 2))
        else:
            self.pc += 4

    def execute_j_type(self, instr):

        opcode = (instr >> 26) & 0x3F
        target = instr & 0x3FFFFFF
        if opcode == 0b000010:  # j

            self.jump_to(((self.pc + 4) & 0xF0000000) | (target << 2))
        elif opcode == 0b000011:  # jal

            self.write_reg(31, self.return_address())
            self.jump_to(((self.pc + 4) & 0xF0000000) | (target << 2))
        else:
            raise ValueError(
                f"unsupported J opcode 0x{opcode:02X}"
            )


    def run(self, max_steps):

        while self.running:

            if self.steps >= max_steps:
                self.running = False
                self.halt_reason = f"reached --max-steps {max_steps} at PC=0x{self.pc:08X}"
                break

            instr = self.fetch()

            if instr is None:
                break

            before = self.pc
            in_delay = self.delay_pending

            self.decode_execute(instr)

            self.steps += 1

            if in_delay:
                self.delay_pending = False
                self.pc = self.jump_target
                if self.pc == self.jump_from:
                    self.running = False
                    self.halt_reason = f"jumps to itself at 0x{self.jump_from:08X}"
            elif self.running and self.pc == before:
                self.running = False
                self.halt_reason = f"jumps to itself at 0x{before:08X}"


def main():
    

    ap = argparse.ArgumentParser(
        description="Reference MIPS simulator"
    )

    ap.add_argument(
        "hexfile",
        help=".hex generated by assembler"
    )
    ap.add_argument("--text-base",default="0",help="text base address")
    ap.add_argument("--data", help="data .hex (default: <name>_data.hex next to hexfile, if it exists)")
    ap.add_argument("--max-steps", type=int, default=1000000, help="stop after this many instructions")
    ap.add_argument("--no-delay-slot", action="store_true", help="jumps take effect at once (MARS with delayed branching off)")
    ap.add_argument("--dump-regs", action="store_true", help="print the final register values as R<n> = 0x<value>")
    ap.add_argument("--dump-mem", action="append", default=[], metavar="ADDR:COUNT",
                    help="print COUNT words of data memory starting at ADDR, e.g. 0x1001000C:37 (repeatable)")
    ap.add_argument("--init", action="append", default=[], metavar="R<n>=<value>",
                    help="set a register before running (repeatable)")
    args = ap.parse_args()

    global TEXT_BASE
    TEXT_BASE = int(args.text_base, 0)

    sim = ReferenceSim(delay_slot=not args.no_delay_slot)

    for item in args.init:
        name, _, value = item.partition("=")
        if not (name[:1] in ("R", "r") and name[1:].isdigit()) or not value:
            print(f"Error: --init expects R<n>=<value>, got '{item}'")
            sys.exit(1)
        reg = int(name[1:])
        if not 1 <= reg <= 31:
            print(f"Error: --init register R{reg} is out of range (use R1 to R31)")
            sys.exit(1)
        try:
            sim.regs[reg] = int(value, 0) & 0xFFFFFFFF
        except ValueError:
            print(f"Error: --init value '{value}' is not a number")
            sys.exit(1)

    sim.load_hex(args.hexfile)

    data_path = args.data
    if data_path is None:
        root = os.path.splitext(args.hexfile)[0]
        if os.path.exists(root + "_data.hex"):
            data_path = root + "_data.hex"
    if data_path:
        sim.load_data(data_path)

    try:
        sim.run(args.max_steps)
    except ValueError as e:
        print(f"Error: {e} at PC=0x{sim.pc:08X} after {sim.steps} instructions")
        sys.exit(1)

    print(f"HALT: {sim.halt_reason}  (steps={sim.steps})")

    if args.dump_regs:
        for i, value in enumerate(sim.regs):
            print(f"R{i} = 0x{value:08X}")

    for item in args.dump_mem:
        addr_text, _, count_text = item.partition(":")
        try:
            addr = int(addr_text, 0) & 0xFFFFFFFF
            count = int(count_text, 0)
            for i in range(count):
                a = addr + 4 * i
                print(f"MEM[0x{a:08X}] = 0x{sim.read_word(a):08X}")
        except ValueError as e:
            print(f"Error: --dump-mem '{item}': {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()