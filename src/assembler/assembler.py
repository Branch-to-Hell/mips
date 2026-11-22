import argparse
import os
import sys

isa = {
    # --- R-type (opcode 000000, except mul: SPECIAL2 011100) ---
    'add':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '100001'},
    'addu':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '100001'},
    'sub':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '100011'},
    'subu':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '100011'},
    'and':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '100100'},
    'or':    {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '100101'},
    'xor':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '100110'},
    'nor':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '100111'},
    'slt':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '101010'},
    'sltu':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '101011'},
    'sll':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '000000'},
    'srl':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '000010'},
    'sra':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '000011'},
    'sllv':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '000100'},
    'srlv':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '000110'},
    'srav':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '000111'},
    'jr':    {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '001000'},
    'jalr':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '001001'},
    'mfhi':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '010000'},
    'mthi':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '010001'},
    'mflo':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '010010'},
    'mtlo':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '010011'},
    'mult':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '011000'},
    'multu': {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '011001'},
    'div':   {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '011010'},
    'divu':  {'type': 'R', 'op': '000000', 'shamt': '00000', 'FAC': '011011'},
    'mul':   {'type': 'R', 'op': '011100', 'shamt': '00000', 'FAC': '000010'},
    # --- I-type (bltz/bgez: REGIMM 000001, the fixed rt picks the branch) ---
    'addi':  {'type': 'I', 'op': '001001'},
    'addiu': {'type': 'I', 'op': '001001'},
    'slti':  {'type': 'I', 'op': '001010'},
    'sltiu': {'type': 'I', 'op': '001011'},
    'andi':  {'type': 'I', 'op': '001100'},
    'ori':   {'type': 'I', 'op': '001101'},
    'xori':  {'type': 'I', 'op': '001110'},
    'lui':   {'type': 'I', 'op': '001111'},
    'lb':    {'type': 'I', 'op': '100000'},
    'lh':    {'type': 'I', 'op': '100001'},
    'lw':    {'type': 'I', 'op': '100011'},
    'lbu':   {'type': 'I', 'op': '100100'},
    'lhu':   {'type': 'I', 'op': '100101'},
    'sb':    {'type': 'I', 'op': '101000'},
    'sh':    {'type': 'I', 'op': '101001'},
    'sw':    {'type': 'I', 'op': '101011'},
    'beq':   {'type': 'I', 'op': '000100'},
    'bne':   {'type': 'I', 'op': '000101'},
    'blez':  {'type': 'I', 'op': '000110'},
    'bgtz':  {'type': 'I', 'op': '000111'},
    'bltz':  {'type': 'I', 'op': '000001', 'rt': '00000'},
    'bgez':  {'type': 'I', 'op': '000001', 'rt': '00001'},
    # --- J-type ---
    'j':     {'type': 'J', 'op': '000010'},
    'jal':   {'type': 'J', 'op': '000011'},
}


REG_NAMES = ['zero', 'at', 'v0', 'v1', 'a0', 'a1', 'a2', 'a3',
             't0', 't1', 't2', 't3', 't4', 't5', 't6', 't7',
             's0', 's1', 's2', 's3', 's4', 's5', 's6', 's7',
             't8', 't9', 'k0', 'k1', 'gp', 'sp', 'fp', 'ra']
REGS = {f'${n}': i for i, n in enumerate(REG_NAMES)}
REGS['$s8'] = 30                                
REGS.update({f'${i}': i for i in range(32)})       

TEXT_BASE=0x00000000
DATA_BASE=0X10010000
TEXT_DEPTH = 4096
DATA_DEPTH = 4096

def DecBinary(val,bits): 
    val = val if val >= 0 else val + (1 << bits) #decimal->binary
    return format(val, f'0{bits}b')

def write_banks(base_path, words, bytes_image=True):

    image = [
        (w >> shift) & 0xFF
        for w in words
        for shift in (24, 16, 8, 0) # shift the word to get each byte
    ]

    def write_bytes(path, values):
        with open(path, "w", newline="\n") as f:
            for b in values:
                f.write(f"{b:02x}\n")

    if bytes_image:
        write_bytes(base_path + "_bytes.hex", image)

    for k in range(4):
        write_bytes(
            base_path + f"_b{k}.hex",
            image[k::4] # get every 4th byte starting from k
        )

def check_register(register):
    register = register.strip()

    if register in REGS.keys(): #check if the register is valid
        return REGS[register]

    raise ValueError(f"invalid register '{register}'")

def check_immediate(imm):
    imm = imm.strip()

    try:
        return int(imm, 0)

    except ValueError:
        try:
            return int(imm, 10)

        except ValueError:
            raise ValueError(
                f"invalid immediate '{imm}'"
            )

def check_label(label, labels):
    label = label.strip()

    if label in labels.keys(): #check if the label is valid
        return labels[label]

    raise ValueError(f"undefined label '{label}'")

def check_target(target, labels):
    # Branch/jump target: a label or a literal address, word aligned.
    target = target.strip()
    if target in labels:
        addr = labels[target]
    else:
        try:
            addr = int(target, 0)
        except ValueError:
            raise ValueError(f"undefined label '{target}'")
    if addr < 0 or addr > 0xFFFFFFFF:
        raise ValueError(f"target {target} out of range")
    if addr % 4 != 0:
        raise ValueError(f"misaligned target 0x{addr:08X} (must be a multiple of 4)")
    return addr

def check_range(value, minimum, maximum, name):
    if value < minimum or value > maximum:
        raise ValueError(
            f"{name} {value} out of range "
            f"[{minimum}, {maximum}]"
        )

    return value

def check_operands(ops, expected, mn):

    if len(ops) != expected:
        raise ValueError(
            f"'{mn}' expects {expected} operands, got {len(ops)}"
        )

def first_pass(lines):

    labels = {}
    text = []
    data = []

    section = "text"

    pc = TEXT_BASE
    dp = DATA_BASE

    for line_number, raw in enumerate(lines, 1): # enumerate the lines of the assembly code
        try:
            line = raw.split("#")[0].strip()
            if not line:
                continue
            if ":" in line:#check if the line contains a label
                label, line = line.split(":", 1)
                label = label.strip()
                if label in labels:#check if the label is already defined
                    raise ValueError(
                        f"duplicate label '{label}'"
                    )
                if section == "text":#check if the label is in the text section
                    labels[label] = pc
                else:#check if the label is in the data section
                    labels[label] = dp
                line = line.strip()
                if not line:
                    continue
            parts = line.split(None, 1) 
            word = parts[0].lower()
            rest = parts[1] if len(parts) > 1 else "" # get the rest of the line after the first word
            ops = (
                            [x.strip() for x in rest.split(",")]
                            if rest
                            else []
                        )
            if word == ".text":
                section = "text"
                continue

            if word == ".data":
                section = "data"
                continue
            if word in [".globl", ".align"]:
                continue
            
            if section == "data":
                if word == ".word":
                    values = rest.split(",")
                    for val in values:
                        data.append( 
                            check_immediate(val) & 0xFFFFFFFF
                        )
                        dp += 4
                elif word == ".space":
                    bytes_reserved = check_immediate(rest)
                    words = (bytes_reserved + 3) // 4
                    data += [0] * words
                    dp += words * 4
                else:

                    raise ValueError(
                        f"directive not supported '{word}'"
                    )

            else:
                if word == "move":
                    # Pseudoinstruction: convert to add with $zero as source register.
                    check_operands(ops, 2, "move")
                    rd = ops[0]
                    rs = ops[1]
                    text.append(("add", [rd, rs, "$zero"], pc, line_number,f"add {rd}, {rs}, $zero"))
                    pc += 4
                    continue

                if word == "li":
                    # Load immediate using addi or lui/ori.
                    check_operands(ops, 2, "li")
                    rt = ops[0]
                    value = check_immediate(ops[1])
                    if -32768 <= value <= 32767:
                        text.append(("addi",[rt, "$zero", str(value)],pc,line_number,f"addi {rt}, $zero, {value}"))
                        pc += 4
                    else:
                        value &= 0xFFFFFFFF
                        upper = (value >> 16) & 0xFFFF
                        lower = value & 0xFFFF
                        text.append(("lui", [rt, str(upper)], pc, line_number,f"lui {rt}, {upper}"))
                        pc += 4
                        text.append(("ori", [rt, rt, str(lower)], pc, line_number,f"ori {rt}, {rt}, {lower}"))
                        pc += 4
                    continue

                if word == "la":
                    check_operands(ops, 2, "la")
                    rt = ops[0]
                    label = ops[1]
                    text.append(("la", [rt, label], pc, line_number,line))
                    pc += 8
                    continue

                text.append((word, ops, pc, line_number,line))
                pc += 4
                if word in ["beq", "bne", "j", "jal", "jr", "jalr", "bltz", "bgez", "blez", "bgtz"]:
                    text.append(("nop", [], pc, line_number,"nop"))
                    pc += 4

        except ValueError as e:
            raise ValueError(f"line {line_number}: {e}")

    return labels, text, data


def encode(mn, ops, pc, labels):

    if mn == 'nop':
        return '0' * 32

    if mn not in isa:
        raise ValueError(f"unknown instruction '{mn}'")

    info = isa[mn]

    if info['type'] == 'R': #check if the instruction is of type R
        if mn in ["sll", "srl", "sra"]:
            check_operands(ops, 3, mn)
            rd = check_register(ops[0])
            rt = check_register(ops[1])
            shamt = check_range( check_immediate(ops[2]),0,31,"shamt")

            op = info['op']
            FAC = info['FAC']

            return f"{op}{DecBinary(0,5)}{DecBinary(rt,5)}{DecBinary(rd,5)}{DecBinary(shamt,5)}{FAC}"
        elif mn == "jr":
            check_operands(ops, 1, mn)
            rs = check_register(ops[0])
            op = info['op']
            FAC = info['FAC']
            return f"{op}{DecBinary(rs,5)}{DecBinary(0,5)}{DecBinary(0,5)}{DecBinary(0,5)}{FAC}"
        elif mn in ["sllv", "srlv", "srav"]:
            check_operands(ops, 3, mn)
            rd = check_register(ops[0])
            rt = check_register(ops[1])
            rs = check_register(ops[2])
            return f"{info['op']}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(rd,5)}{info['shamt']}{info['FAC']}"
        elif mn == "jalr":
            if len(ops) == 1:
                rd, rs = 31, check_register(ops[0])
            else:
                check_operands(ops, 2, mn)
                rd, rs = check_register(ops[0]), check_register(ops[1])
            return f"{info['op']}{DecBinary(rs,5)}{DecBinary(0,5)}{DecBinary(rd,5)}{info['shamt']}{info['FAC']}"
        elif mn in ["mfhi", "mflo"]:
            check_operands(ops, 1, mn)
            rd = check_register(ops[0])
            return f"{info['op']}{DecBinary(0,10)}{DecBinary(rd,5)}{info['shamt']}{info['FAC']}"
        elif mn in ["mthi", "mtlo"]:
            check_operands(ops, 1, mn)
            rs = check_register(ops[0])
            return f"{info['op']}{DecBinary(rs,5)}{DecBinary(0,10)}{info['shamt']}{info['FAC']}"
        elif mn in ["mult", "multu", "div", "divu"]:
            check_operands(ops, 2, mn)
            rs = check_register(ops[0])
            rt = check_register(ops[1])
            return f"{info['op']}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(0,10)}{info['FAC']}"
        else:
            check_operands(ops, 3, mn)
            rd = check_register(ops[0])
            rs = check_register(ops[1])
            rt = check_register(ops[2])

            op = info['op']
            shamt = info['shamt']
            FAC = info['FAC']

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(rd,5)}{shamt}{FAC}"

    if info['type'] == 'I': #check if the instruction is of type I

        if mn in ['lw', 'sw', 'lb', 'lbu', 'lh', 'lhu', 'sb', 'sh']:  # loads and stores: rt, offset(rs)

            check_operands(ops, 2, mn)
            op = info['op']

            rt = check_register(ops[0])

            memory = ops[1].replace(" ", "")

            offset, register = memory.split("(")
            if offset == "":
                offset = "0"
            register = register.replace(")", "")

            rs = check_register(register)
            offset = check_range(check_immediate(offset),-32768,32767,"offset")
            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(offset,16)}"
        elif mn in ['blez', 'bgtz']:
            check_operands(ops, 2, mn)
            rs = check_register(ops[0])
            label = check_target(ops[1], labels)
            offset = check_range((label - (pc + 4)) // 4, -32768, 32767, "branch offset")
            return f"{info['op']}{DecBinary(rs,5)}{DecBinary(0,5)}{DecBinary(offset,16)}"
        elif mn in ['bltz', 'bgez']:
            check_operands(ops, 2, mn)
            rs = check_register(ops[0])
            label = check_target(ops[1], labels)
            offset = check_range((label - (pc + 4)) // 4, -32768, 32767, "branch offset")
            return f"{info['op']}{DecBinary(rs,5)}{info['rt']}{DecBinary(offset,16)}"
        elif mn in ['beq', 'bne']:#check if the instruction is of type beq or bne

            check_operands(ops, 3, mn)
            op = info['op']

            rs = check_register(ops[0])
            rt = check_register(ops[1])

            label = check_target(ops[2], labels)

            offset = (label - (pc + 4)) // 4 #calculate the offset for the branch instruction
            offset = check_range(offset,-32768,32767,"branch offset")#check if the offset is in the range of -32768 to 32767

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(offset,16)}"
        elif mn == 'lui':#check if the instruction is of type lui
            check_operands(ops, 2, mn)
            op = info['op']

            rt = check_register(ops[0])
            inm = check_range(
            check_immediate(ops[1]),0,65535,"immediate")
            return f"{op}{DecBinary(0,5)}{DecBinary(rt,5)}{DecBinary(inm,16)}"
        elif mn in ["addi", "slti", "addiu", "sltiu"]:  # signed 16-bit immediate
            check_operands(ops, 3, mn)
            rt = check_register(ops[0])
            rs = check_register(ops[1])

            inm = check_range(
                check_immediate(ops[2]),
                -32768,
                32767,
                "immediate"
            )

            op = info["op"]

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(inm,16)}"
        else:  # andi ori xori: unsigned 16-bit immediate

            check_operands(ops, 3, mn)
            rt = check_register(ops[0])
            rs = check_register(ops[1])

            inm = check_range(check_immediate(ops[2]),0,65535,"immediate")
            op = info["op"]

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(inm,16)}"

    if info['type'] == 'J':
        check_operands(ops, 1, mn)
        label = check_target(ops[0], labels)
        op = info['op']
        pc_region = (pc + 4) >> 28
        label_region = label >> 28

        if pc_region != label_region:
            raise ValueError(f"jump target 0x{label:08X} outside 256 MiB region")
        target = (label >> 2) & 0x3FFFFFF  #calculate the target address for the jump instruction
        return f"{op}{DecBinary(target, 26)}"

    raise ValueError(f"unsupported instruction type '{info['type']}'")

def second_pass(text, labels):

    program = []

    for mn, ops, pc , line_number, source_line in text:

        try:
            if mn == "la":

                rt = ops[0]
                label = ops[1]

                addr = check_label(label, labels)

                upper = (addr >> 16) & 0xFFFF
                lower = addr & 0xFFFF

                for pseudo_mn, pseudo_ops, pseudo_pc in [

                    ("lui", [rt, str(upper)], pc),
                    ("ori", [rt, rt, str(lower)], pc + 4)

                ]:

                    binary_code = encode(
                        pseudo_mn,
                        pseudo_ops,
                        pseudo_pc,
                        labels
                    )

                    machine_code = int(binary_code, 2)

                    program.append((pseudo_pc, machine_code,f"{pseudo_mn} {', '.join(pseudo_ops)}"))

                continue

            binary_code = encode(
                mn,
                ops,
                pc,
                labels
            )
            machine_code = int(
                binary_code,
                2
            )
            program.append(
                (pc, machine_code,source_line)
            )
        except ValueError as e:
            raise ValueError(f"line {line_number}, instruction '{mn}': {e}")
    return program


def write_hex(path, words):
    with open(path, 'w', newline='\n') as f:
        for w in words:
            f.write(f"{(w & 0xFFFFFFFF):08x}\n") 

def main():

    ap = argparse.ArgumentParser(description="Assembler MIPS -> HEX")
    ap.add_argument("source",help="file .asm" )
    ap.add_argument("-o","--outdir",help="output directory (default: mem)")
    ap.add_argument("--list",action="store_true",help="show program assembly")
    ap.add_argument("--text-base",default="0",help="text base address")

    args = ap.parse_args()
    global TEXT_BASE
    try:
        TEXT_BASE = int(args.text_base, 0)
    except ValueError:
        ap.error(f"--text-base: invalid address '{args.text_base}'")
    if TEXT_BASE < 0 or TEXT_BASE > 0xFFFFFFFF or TEXT_BASE % 4 != 0:
        ap.error(f"--text-base: 0x{TEXT_BASE:X} must be a 32-bit multiple of 4")

    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) #get the directory of the script
    MEM_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "../../mem")) #get the default memory directory

    outdir = args.outdir or MEM_DIR
    base = os.path.splitext(os.path.basename(args.source))[0]

    with open(args.source) as f:
        lines = f.read().splitlines()

    try:
        labels, text, data = first_pass(lines)
        prog = second_pass(text, labels)
        words = [w for _, w, _ in prog]
        if len(words) > TEXT_DEPTH:
            raise ValueError(f"program has {len(words)} instructions, the instruction memory holds {TEXT_DEPTH}")
        if len(data) > DATA_DEPTH:
            raise ValueError(f"data has {len(data)} words, the data image holds {DATA_DEPTH}")
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

    os.makedirs(outdir, exist_ok=True)
    write_hex(os.path.join(outdir, base + ".hex"), words)
    write_banks(os.path.join(outdir, base), words) # _bytes, _b0 .. _b3
    if data:
        write_hex(os.path.join(outdir, base + "_data.hex"), data)
        # CPU-7: data_memory has one bank per byte lane and loads <name>_data_b0..b3.hex
        write_banks(os.path.join(outdir, base + "_data"), data, bytes_image=False)

    if args.list:
        print("\nProgram:\n")
        for pc, word, source in prog:
            print(f"0x{pc:08X}  {word:08X} {source}")
        print("\nLabels:\n")

        for label, addr in labels.items():
            print(f"{label} = 0x{addr:X}")
    print(f"\nOK: {len(words)} instructions, "
          f"{len(data)} data words")
    print( f"Files generated in: {outdir}")

if __name__ == "__main__":
    main()
