import argparse
import os
import sys

isa={
    'add': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100001'},
    'addu': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100001'},
    'sub': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100011'},
    'subu': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100011'},
    'and': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100100'},
    'or':  {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100101'},
    'slt': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '101010'},
    'nor': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100111'},
    'sll': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '000000'},
    'srl': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '000010'},
    'jr':  {'type': 'R', 'op': '000000','shamt': '00000','FAC': '001000'},
    'addi':{'type':'I','op':'001001'},
    'addiu':{'type':'I','op':'001001'},
    'andi':{'type':'I','op':'001100'},
    'ori': {'type': 'I', 'op': '001101'},
    'slti': {'type': 'I', 'op': '001010'},
    'lw':  {'type': 'I', 'op': '100011'},
    'sw':  {'type': 'I', 'op': '101011'},
    'beq': {'type': 'I', 'op': '000100'},
    'lui': {'type': 'I', 'op': '001111'},
    'bne': {'type': 'I', 'op': '000101'},
    'j':   {'type': 'J', 'op': '000010'},
    'jal': {'type': 'J', 'op': '000011'}
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

def write_banks(base_path, words):

    image = [
        (w >> shift) & 0xFF
        for w in words
        for shift in (24, 16, 8, 0) # shift the word to get each byte
    ]

    def write_bytes(path, values):
        with open(path, "w", newline="\n") as f:
            for b in values:
                f.write(f"{b:02x}\n")

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

    raise ValueError(f"invalid label '{label}'")

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
                if word in ["beq", "bne", "j", "jal", "jr"]:
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
        if mn in ["sll", "srl"]:
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

        if mn in ['lw', 'sw']:#check if the instruction is of type lw or sw

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
        elif mn in ['beq', 'bne']:#check if the instruction is of type beq or bne

            check_operands(ops, 3, mn)
            op = info['op']

            rs = check_register(ops[0])
            rt = check_register(ops[1])

            label = check_label(ops[2], labels)

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
        elif mn in ["addi", "slti","addiu"]:#check if the instruction is of type addi or slti
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
        else:#check if the instruction is of type andi or ori

            check_operands(ops, 3, mn)
            rt = check_register(ops[0])
            rs = check_register(ops[1])

            inm = check_range(check_immediate(ops[2]),0,65535,"immediate")
            op = info["op"]

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(inm,16)}"

    if info['type'] == 'J':
        check_operands(ops, 1, mn)
        label = check_label(ops[0], labels)
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
    ap.add_argument("-o","--outdir",help="output directory (default: hw/mem)")
    ap.add_argument("--list",action="store_true",help="show program assembly")
    ap.add_argument("--text-base",default="0",help="text base address")

    args = ap.parse_args()
    global TEXT_BASE
    TEXT_BASE = int(args.text_base, 0)
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) #get the directory of the script
    MEM_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "../../hw/mem")) #get the default memory directory

    outdir = args.outdir or MEM_DIR
    base = os.path.splitext(os.path.basename(args.source))[0]

    os.makedirs(outdir,exist_ok=True)
    os.makedirs(MEM_DIR, exist_ok=True)
    with open(args.source) as f:
        lines = f.read().splitlines()

    try:

        labels, text, data = first_pass(lines) 
        prog = second_pass(text, labels) 
        words = [w for _, w, _ in prog]
        write_hex(os.path.join(outdir, base + ".hex"), words)
        write_banks(os.path.join(outdir, base), words) #.byte .b0, b1,b2 and b3

        if data:
            write_hex( os.path.join( outdir, base + "_data.hex"),data)
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

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