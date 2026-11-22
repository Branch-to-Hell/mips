"""Reference MIPS simulator for the .hex images written by src/assembler (TC-6).

Usage:
    python src/tools/ref_sim.py <file>.hex [--text-base 0x00400000]
           [--data <file>_data.hex] [--max-steps N] [--no-delay-slot] [--flat-mem]
           [--init R<n>=<value> ...] [--dump-regs] [--dump-mem ADDR:COUNT ...]

Trace (docs/contracts.md "Reference simulator trace"), one line per write:
    PC=0x00000000 R8 <= 0x00000005
    PC=0x00000010 HI <= 0x00000000      (mult, multu, div, divu, mthi)
    PC=0x00000010 LO <= 0x0000001E      (mult, multu, div, divu, mtlo)
Writes to $zero are not printed.

The run stops and the last line says why:
  - HALT: jumps to itself at ...       (e.g. "end: j end")
  - HALT: PC left the program at ...   (past the last instruction, inside the text region)
  - HALT: reached --max-steps N ...
  - HALT: cause C (...) pc ... addr ... the same halt as the CPU (contracts.md, CPU-14):
        cause 1 = fetch outside the 16 KB text region or not aligned to 4,
        cause 2 = load, 3 = store, to no region of the memory map or misaligned.
    The failing instruction writes nothing. --flat-mem turns the memory map check off
    (every address is RAM); alignment is always checked.

Delay slot: by default a jump takes effect after the next instruction, as in the
pipeline (the assembler puts a nop there; GCC fills it). --no-delay-slot makes jumps
take effect at once, as MARS does with delayed branching off. jal/jalr write PC+8 with
the delay slot and PC+4 without it.

Initial state, the same as mips_pipeline after reset: PC = text base, $sp = 0x7FFFEFFC,
every other register 0 (MARS also sets $gp = 0x10008000: --init R28=0x10008000).
Memory is big-endian. MMIO addresses behave like RAM (no switches, timer or LEDs).
"""
import argparse
import os
import sys

TEXT_BASE = 0x00000000
TEXT_SIZE = 0x4000          # 16 KB text region (contracts.md "Memory map")
DATA_BASE = 0x10010000

# Regions of the memory map, as decoded in rtl/life_system.v (inclusive ranges).
REGIONS = [
    (0x10010000, 0x10013FFF, "data"),
    (0x10040000, 0x1004BFFF, "framebuffer A"),
    (0x10050000, 0x1005F9FF, "framebuffer B"),
    (0x1005FC00, 0x1005FFFF, "palette B"),
    (0x7FFFE000, 0x7FFFEFFF, "stack"),
    (0xFFFF0010, 0xFFFF0027, "MMIO"),
]

CAUSE_FETCH, CAUSE_LOAD, CAUSE_STORE = 1, 2, 3
CAUSE_NAMES = {CAUSE_FETCH: "fetch", CAUSE_LOAD: "load", CAUSE_STORE: "store"}


def signed32(value):
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


def signed16(value):
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


class Fault(Exception):
    """A CPU-14 halt: an invalid fetch, load or store."""

    def __init__(self, cause, addr):
        super().__init__(f"{CAUSE_NAMES[cause]} fault at 0x{addr:08X}")
        self.cause = cause
        self.addr = addr & 0xFFFFFFFF


class ReferenceSim:

    def __init__(self, delay_slot=True, check_map=True):
        self.pc = TEXT_BASE
        self.regs = [0] * 32
        self.regs[29] = 0x7FFFEFFC      # $sp, as mips_pipeline after reset
        self.hi = 0
        self.lo = 0
        self.data_mem = {}              # byte address -> byte
        self.program = []
        self.running = True
        self.steps = 0
        self.halt_reason = ""
        self.delay_slot = delay_slot
        self.check_map = check_map
        self.delay_pending = False
        self.jump_target = None
        self.jump_from = None

    # ---- loading ----

    def load_hex(self, path):
        with open(path) as f:
            self.program = [int(line, 16) for line in (l.strip() for l in f) if line]

    def load_data(self, path):
        with open(path) as f:
            words = [int(line, 16) for line in (l.strip() for l in f) if line]
        for i, word in enumerate(words):
            for k in range(4):
                self.data_mem[DATA_BASE + 4 * i + k] = (word >> (8 * (3 - k))) & 0xFF

    # ---- memory (big-endian) ----

    def check_access(self, addr, size, cause):
        """Raise a Fault, before anything is written, if the access is invalid."""
        if addr % size != 0:
            raise Fault(cause, addr)
        if self.check_map and not any(lo <= addr <= hi for lo, hi, _ in REGIONS):
            raise Fault(cause, addr)

    def mem_addr(self, rs, offset16):
        return (self.regs[rs] + signed16(offset16)) & 0xFFFFFFFF

    def load(self, addr, size):
        self.check_access(addr, size, CAUSE_LOAD)
        value = 0
        for k in range(size):
            value = (value << 8) | self.data_mem.get(addr + k, 0)
        return value

    def store(self, addr, size, value):
        self.check_access(addr, size, CAUSE_STORE)
        for k in range(size):
            self.data_mem[addr + k] = (value >> (8 * (size - 1 - k))) & 0xFF

    def read_word(self, addr):
        """For --dump-mem: no memory map check."""
        value = 0
        for k in range(4):
            value = (value << 8) | self.data_mem.get((addr + k) & 0xFFFFFFFF, 0)
        return value

    # ---- registers and control flow ----

    def write_reg(self, reg, value):
        if reg == 0:
            return
        self.regs[reg] = value & 0xFFFFFFFF
        print(f"PC=0x{self.pc:08X} R{reg} <= 0x{self.regs[reg]:08X}")

    def write_hi(self, value):
        self.hi = value & 0xFFFFFFFF
        print(f"PC=0x{self.pc:08X} HI <= 0x{self.hi:08X}")

    def write_lo(self, value):
        self.lo = value & 0xFFFFFFFF
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

    def branch(self, taken, offset16):
        if taken:
            self.jump_to(self.pc + 4 + (signed16(offset16) << 2))
        else:
            self.pc += 4

    def fetch(self):
        if self.pc % 4 != 0 or not TEXT_BASE <= self.pc < TEXT_BASE + TEXT_SIZE:
            raise Fault(CAUSE_FETCH, self.pc)
        index = (self.pc - TEXT_BASE) // 4
        if index >= len(self.program):
            self.running = False
            self.halt_reason = f"PC left the program at 0x{self.pc:08X}"
            return None
        return self.program[index]

    # ---- execution ----

    def decode_execute(self, instr):
        opcode = (instr >> 26) & 0x3F
        if opcode == 0x00:
            self.execute_r_type(instr)
        elif opcode in (0x02, 0x03):
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

        if funct == 0b001000:                           # jr
            self.jump_to(r[rs])
            return
        if funct == 0b001001:                           # jalr: rd = return address, jump to rs
            target = r[rs]                              # read rs first (rd may equal rs)
            self.write_reg(rd, self.return_address())
            self.jump_to(target)
            return

        if funct in (0b100000, 0b100001):               # add, addu (no overflow trap)
            self.write_reg(rd, r[rs] + r[rt])
        elif funct in (0b100010, 0b100011):             # sub, subu
            self.write_reg(rd, r[rs] - r[rt])
        elif funct == 0b100100:                         # and
            self.write_reg(rd, r[rs] & r[rt])
        elif funct == 0b100101:                         # or
            self.write_reg(rd, r[rs] | r[rt])
        elif funct == 0b100110:                         # xor
            self.write_reg(rd, r[rs] ^ r[rt])
        elif funct == 0b100111:                         # nor
            self.write_reg(rd, ~(r[rs] | r[rt]))
        elif funct == 0b101010:                         # slt
            self.write_reg(rd, 1 if signed32(r[rs]) < signed32(r[rt]) else 0)
        elif funct == 0b101011:                         # sltu
            self.write_reg(rd, 1 if r[rs] < r[rt] else 0)
        elif funct == 0b000000:                         # sll (also nop)
            self.write_reg(rd, r[rt] << shamt)
        elif funct == 0b000010:                         # srl
            self.write_reg(rd, r[rt] >> shamt)
        elif funct == 0b000011:                         # sra
            self.write_reg(rd, signed32(r[rt]) >> shamt)
        elif funct == 0b000100:                         # sllv
            self.write_reg(rd, r[rt] << (r[rs] & 0x1F))
        elif funct == 0b000110:                         # srlv
            self.write_reg(rd, r[rt] >> (r[rs] & 0x1F))
        elif funct == 0b000111:                         # srav
            self.write_reg(rd, signed32(r[rt]) >> (r[rs] & 0x1F))
        elif funct == 0b010000:                         # mfhi
            self.write_reg(rd, self.hi)
        elif funct == 0b010001:                         # mthi
            self.write_hi(r[rs])
        elif funct == 0b010010:                         # mflo
            self.write_reg(rd, self.lo)
        elif funct == 0b010011:                         # mtlo
            self.write_lo(r[rs])
        elif funct in (0b011000, 0b011001):             # mult, multu
            if funct == 0b011000:
                product = signed32(r[rs]) * signed32(r[rt])
            else:
                product = r[rs] * r[rt]
            self.write_hi(product >> 32)
            self.write_lo(product)
        elif funct == 0b011010:                         # div: LO = quotient, HI = remainder
            # Division by zero leaves HI and LO unchanged (MIPS: unpredictable; MARS does this).
            if r[rt] != 0:
                a, b = signed32(r[rs]), signed32(r[rt])
                q = abs(a) // abs(b)                    # MIPS truncates toward zero
                if (a < 0) != (b < 0):
                    q = -q
                self.write_hi(a - q * b)
                self.write_lo(q)
        elif funct == 0b011011:                         # divu (same rule for zero)
            if r[rt] != 0:
                self.write_hi(r[rs] % r[rt])
                self.write_lo(r[rs] // r[rt])
        else:
            raise ValueError(f"unsupported R funct 0x{funct:02X}")
        self.pc += 4

    def execute_i_type(self, instr):
        opcode = (instr >> 26) & 0x3F
        rs = (instr >> 21) & 0x1F
        rt = (instr >> 16) & 0x1F
        imm = instr & 0xFFFF
        r = self.regs

        if opcode == 0b000100:                          # beq
            self.branch(r[rs] == r[rt], imm)
            return
        if opcode == 0b000101:                          # bne
            self.branch(r[rs] != r[rt], imm)
            return
        if opcode == 0b000110:                          # blez
            self.branch(signed32(r[rs]) <= 0, imm)
            return
        if opcode == 0b000111:                          # bgtz
            self.branch(signed32(r[rs]) > 0, imm)
            return

        if opcode in (0b001000, 0b001001):              # addi, addiu (no overflow trap)
            self.write_reg(rt, r[rs] + signed16(imm))
        elif opcode == 0b001010:                        # slti
            self.write_reg(rt, 1 if signed32(r[rs]) < signed16(imm) else 0)
        elif opcode == 0b001011:                        # sltiu: sign-extended, compared unsigned
            self.write_reg(rt, 1 if r[rs] < (signed16(imm) & 0xFFFFFFFF) else 0)
        elif opcode == 0b001100:                        # andi
            self.write_reg(rt, r[rs] & imm)
        elif opcode == 0b001101:                        # ori
            self.write_reg(rt, r[rs] | imm)
        elif opcode == 0b001110:                        # xori
            self.write_reg(rt, r[rs] ^ imm)
        elif opcode == 0b001111:                        # lui
            self.write_reg(rt, imm << 16)
        elif opcode == 0b100011:                        # lw
            self.write_reg(rt, self.load(self.mem_addr(rs, imm), 4))
        elif opcode == 0b100000:                        # lb
            self.write_reg(rt, signed32(self.load(self.mem_addr(rs, imm), 1) << 24) >> 24)
        elif opcode == 0b100100:                        # lbu
            self.write_reg(rt, self.load(self.mem_addr(rs, imm), 1))
        elif opcode == 0b100001:                        # lh
            self.write_reg(rt, signed32(self.load(self.mem_addr(rs, imm), 2) << 16) >> 16)
        elif opcode == 0b100101:                        # lhu
            self.write_reg(rt, self.load(self.mem_addr(rs, imm), 2))
        elif opcode == 0b101011:                        # sw
            self.store(self.mem_addr(rs, imm), 4, r[rt])
        elif opcode == 0b101000:                        # sb
            self.store(self.mem_addr(rs, imm), 1, r[rt])
        elif opcode == 0b101001:                        # sh
            self.store(self.mem_addr(rs, imm), 2, r[rt])
        else:
            raise ValueError(f"unsupported I opcode 0x{opcode:02X}")
        self.pc += 4

    def execute_special2(self, instr):
        rs = (instr >> 21) & 0x1F
        rt = (instr >> 16) & 0x1F
        rd = (instr >> 11) & 0x1F
        funct = instr & 0x3F
        if funct != 0b000010:
            raise ValueError(f"unsupported SPECIAL2 funct 0x{funct:02X}")
        self.write_reg(rd, signed32(self.regs[rs]) * signed32(self.regs[rt]))  # mul: low 32 bits
        self.pc += 4

    def execute_regimm(self, instr):
        rs = (instr >> 21) & 0x1F
        rt = (instr >> 16) & 0x1F
        value = signed32(self.regs[rs])
        if rt == 0b00000:                               # bltz
            self.branch(value < 0, instr)
        elif rt == 0b00001:                             # bgez
            self.branch(value >= 0, instr)
        else:
            raise ValueError(f"unsupported REGIMM rt 0x{rt:02X}")

    def execute_j_type(self, instr):
        opcode = (instr >> 26) & 0x3F
        target = ((self.pc + 4) & 0xF0000000) | ((instr & 0x3FFFFFF) << 2)
        if opcode == 0b000011:                          # jal
            self.write_reg(31, self.return_address())
        self.jump_to(target)                            # j, jal

    def run(self, max_steps):
        while self.running:
            if self.steps >= max_steps:
                self.running = False
                self.halt_reason = f"reached --max-steps {max_steps} at PC=0x{self.pc:08X}"
                break
            pc = self.pc
            in_delay = self.delay_pending
            try:
                instr = self.fetch()
                if instr is None:
                    break
                self.decode_execute(instr)
            except Fault as fault:
                self.running = False
                self.halt_reason = (f"cause {fault.cause} ({CAUSE_NAMES[fault.cause]}) "
                                    f"pc 0x{pc:08X} addr 0x{fault.addr:08X}")
                break
            self.steps += 1

            if in_delay:
                self.delay_pending = False
                self.pc = self.jump_target
                if self.pc == self.jump_from:
                    self.running = False
                    self.halt_reason = f"jumps to itself at 0x{self.jump_from:08X}"
            elif self.pc == pc:
                self.running = False
                self.halt_reason = f"jumps to itself at 0x{pc:08X}"


def main():
    global TEXT_BASE
    ap = argparse.ArgumentParser(description="Reference MIPS simulator (TC-6)")
    ap.add_argument("hexfile", help="<name>.hex written by the assembler")
    ap.add_argument("--text-base", default="0", help="address of the first instruction (the same as the assembler's)")
    ap.add_argument("--data", help="data .hex (default: <name>_data.hex next to hexfile, if it exists)")
    ap.add_argument("--max-steps", type=int, default=1000000, help="stop after this many instructions")
    ap.add_argument("--no-delay-slot", action="store_true",
                    help="jumps take effect at once (MARS with delayed branching off)")
    ap.add_argument("--flat-mem", action="store_true",
                    help="no memory map check: every data address is RAM")
    ap.add_argument("--dump-regs", action="store_true", help="print the final register values as R<n> = 0x<value>")
    ap.add_argument("--dump-mem", action="append", default=[], metavar="ADDR:COUNT",
                    help="print COUNT words of data memory starting at ADDR, e.g. 0x10010000:37 (repeatable)")
    ap.add_argument("--init", action="append", default=[], metavar="R<n>=<value>",
                    help="set a register before running (repeatable)")
    args = ap.parse_args()

    TEXT_BASE = int(args.text_base, 0)
    sim = ReferenceSim(delay_slot=not args.no_delay_slot, check_map=not args.flat_mem)

    for item in args.init:
        name, _, value = item.partition("=")
        if not (name[:1] in ("R", "r") and name[1:].isdigit()) or not value:
            sys.exit(f"Error: --init expects R<n>=<value>, got '{item}'")
        reg = int(name[1:])
        if not 1 <= reg <= 31:
            sys.exit(f"Error: --init register R{reg} is out of range (use R1 to R31)")
        try:
            sim.regs[reg] = int(value, 0) & 0xFFFFFFFF
        except ValueError:
            sys.exit(f"Error: --init value '{value}' is not a number")

    dumps = []
    for item in args.dump_mem:
        addr_text, _, count_text = item.partition(":")
        try:
            dumps.append((int(addr_text, 0) & 0xFFFFFFFF, int(count_text, 0)))
        except ValueError:
            sys.exit(f"Error: --dump-mem expects ADDR:COUNT, got '{item}'")

    sim.load_hex(args.hexfile)
    data_path = args.data
    if data_path is None:
        candidate = os.path.splitext(args.hexfile)[0] + "_data.hex"
        if os.path.exists(candidate):
            data_path = candidate
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
    for addr, count in dumps:
        for i in range(count):
            a = (addr + 4 * i) & 0xFFFFFFFF
            print(f"MEM[0x{a:08X}] = 0x{sim.read_word(a):08X}")


if __name__ == "__main__":
    main()
