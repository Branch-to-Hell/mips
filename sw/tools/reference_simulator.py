import argparse
import sys
TEXT_BASE = 0x00400000
DATA_BASE = 0x10010000


def signed32(value):

        value &= 0xFFFFFFFF

        if value & 0x80000000:
            return value - 0x100000000

        return value


class ReferenceSim:

    def __init__(self):

        self.pc = TEXT_BASE

        self.regs = [0] * 32

        self.data_mem = {}

        self.program = []

        self.running = True

    def load_hex(self, path):

        with open(path) as f:

            for line in f:

                line = line.strip()

                if not line:
                    continue

                self.program.append(
                    int(line, 16)
                )

    def fetch(self):

        index = (self.pc - TEXT_BASE) // 4

        if index < 0 or index >= len(self.program):

            self.running = False

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

        else:

            self.execute_i_type(instr)

    def execute_r_type(self, instr):

        rs = (instr >> 21) & 0x1F 
        rt = (instr >> 16) & 0x1F
        rd = (instr >> 11) & 0x1F
        shamt = (instr >> 6) & 0x1F
        funct = instr & 0x3F

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
            
            self.pc = self.regs[rs]
        elif funct == 0b100111:  # nor

            result = ~(self.regs[rs] | self.regs[rt]) & 0xFFFFFFFF
            self.write_reg(
                rd,
                result
            )
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
            value = self.data_mem.get(addr, 0)
            self.write_reg(rt, value)
            self.pc += 4
        elif opcode == 0b101011:  # sw
            
            addr = (self.regs[rs] + (offset if offset < 0x8000 else offset - 0x10000)) & 0xFFFFFFFF
            self.data_mem[addr] = self.regs[rt]
            self.pc += 4
            
        elif opcode == 0b000100:  # beq
            
            if self.regs[rs] == self.regs[rt]:
                self.pc += 4 + ((offset if offset < 0x8000 else offset - 0x10000) << 2)
            else:
                self.pc += 4
        elif opcode == 0b000101:  # bne
            
            if self.regs[rs] != self.regs[rt]:
                self.pc += 4 + ((offset if offset < 0x8000 else offset - 0x10000) << 2)
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
        else:

            raise ValueError(
                f"unsupported I opcode 0x{opcode:02X}"
            )


    def execute_j_type(self, instr):

        opcode = (instr >> 26) & 0x3F
        target = instr & 0x3FFFFFF
        if opcode == 0b000010:  # j

            self.pc = (self.pc & 0xF0000000) | (target << 2)
        elif opcode == 0b000011:  # jal

            self.write_reg(31, self.pc + 4)
            self.pc = (self.pc & 0xF0000000) | (target << 2)
        else:
            raise ValueError(
                f"unsupported J opcode 0x{opcode:02X}"
            )


    def run(self):

        while self.running:

            instr = self.fetch()

            if instr is None:
                break

            self.decode_execute(instr)


def main():
    

    ap = argparse.ArgumentParser(
        description="Reference MIPS simulator"
    )

    ap.add_argument(
        "hexfile",
        help=".hex generated by assembler"
    )
    ap.add_argument("--text-base",default="0",help="text base address")
    args = ap.parse_args()

    global TEXT_BASE
    TEXT_BASE = int(args.text_base, 0)

    sim = ReferenceSim()

    sim.load_hex(args.hexfile)

    sim.run()


if __name__ == "__main__":
    main()