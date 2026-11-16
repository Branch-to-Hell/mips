import argparse
import os
import re
import sys

isa={
    'add': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100000'},
    'sub': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100010'},
    'and': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100100'},
    'or':  {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100101'},
    'slt': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '101010'},
    'nor': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '100111'},
    'sll': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '000000'},
    'srl': {'type': 'R', 'op': '000000','shamt': '00000','FAC': '000010'},
    'jr':  {'type': 'R', 'op': '000000','shamt': '00000','FAC': '001000'},
    'mul': {'type': 'R', 'op': '011100','shamt': '00000','FAC': '000010'},
    'addi':{'type':'I','op':'001000'},
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
DATA_BASE=0X00002000
TEXT_DEPTH = 1024
DATA_DEPTH = 1024

def DecBinary(val,bits): 
    val = val if val >= 0 else val + (1 << bits) #decimal->binary
    return format(val, f'0{bits}b')

def check_registro(registro):
    registro = registro.strip()

    if registro in REGS.keys(): #check if the register is valid
        return REGS[registro]

    raise ValueError(f"invalid reg'{registro}'")

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

def first_pass(lines):

    labels = {}
    text = []
    data = []

    section = "text"

    pc = TEXT_BASE
    dp = DATA_BASE

    for raw in lines:#iterate through the lines of the assembly code
        line = raw.split("#")[0].strip()
        if not line:
            continue
        if ":" in line:#check if the line contains a label
            label, line = line.split(":", 1)
            label = label.strip()
            if label in labels:#check if the label is already defined
                raise ValueError(
                    f"label repeat '{label}'"
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

        if word == ".text":
            section = "text"
            continue

        if word == ".data":
            section = "data"
            continue

        if section == "data":
            if word == ".word":
                valores = rest.split(",")
                for val in valores:
                    data.append( 
                        check_immediate(val)
                    )
                    dp += 4
            elif word == ".space":
                bytes_reservados = check_immediate(rest)
                palabras = (bytes_reservados + 3) // 4
                data += [0] * palabras
                dp += palabras * 4
            else:

                raise ValueError(
                    f"directive not supported '{word}'"
                )

        else:

            ops = (
                [x.strip() for x in rest.split(",")]
                if rest
                else []
            )
            text.append(
                (word, ops, pc)
            )
            pc += 4

    return labels, text, data


def encode(mn, ops, pc, labels):

    if mn == 'nop':
        return '0' * 32

    if mn not in isa:
        raise ValueError(f"unknown instruction '{mn}'")

    info = isa[mn]

    if info['type'] == 'R': #check if the instruction is of type R
        if mn in ["sll", "srl"]:
            rd = check_registro(ops[0])
            rt = check_registro(ops[1])
            shamt = check_immediate(ops[2])

            op = info['op']
            FAC = info['FAC']

            return f"{op}{DecBinary(0,5)}{DecBinary(rt,5)}{DecBinary(rd,5)}{DecBinary(shamt,5)}{FAC}"
        elif mn == "jr":
            rs = check_registro(ops[0])

            op = info['op']
            shamt = info['shamt']
            FAC = info['FAC']

            return f"{op}{DecBinary(rs,5)}{DecBinary(0,5)}{DecBinary(0,5)}{shamt}{FAC}"
        elif mn == "jr":
            rs = check_registro(ops[0])
            op = info['op']
            FAC = info['FAC']
            return f"{op}{DecBinary(rs,5)}{DecBinary(0,5)}{DecBinary(0,5)}{DecBinary(0,5)}{FAC}"
        else:
            rd = check_registro(ops[0])
            rs = check_registro(ops[1])
            rt = check_registro(ops[2])

            op = info['op']
            shamt = info['shamt']
            FAC = info['FAC']

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(rd,5)}{shamt}{FAC}"

    if info['type'] == 'I': #check if the instruction is of type I

        if mn in ['lw', 'sw']:#check if the instruction is of type lw or sw

            op = info['op']

            rt = check_registro(ops[0])

            memoria = ops[1].replace(" ", "")

            offset, registro = memoria.split("(")
            registro = registro.replace(")", "")

            rs = check_registro(registro)
            offset = check_immediate(offset)

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(offset,16)}"
        elif mn in ['beq', 'bne']:#check if the instruction is of type beq or bne

            op = info['op']

            rs = check_registro(ops[0])
            rt = check_registro(ops[1])

            label = check_label(ops[2], labels)

            offset = (label - (pc + 4)) // 4

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(offset,16)}"
        elif mn == 'lui':#check if the instruction is of type lui

            op = info['op']

            rt = check_registro(ops[0])
            inm = check_immediate(ops[1])

            return f"{op}{DecBinary(0,5)}{DecBinary(rt,5)}{DecBinary(inm,16)}"
        else:#check if the instruction is of type addi, andi, ori, slti

            rt = check_registro(ops[0])
            rs = check_registro(ops[1])
            inm = check_immediate(ops[2])

            op = info['op']

            return f"{op}{DecBinary(rs,5)}{DecBinary(rt,5)}{DecBinary(inm,16)}"

    if info['type'] == 'J':
        label = check_label(ops[0], labels)
        op = info['op']
        return f"{op}{DecBinary(label // 4, 26)}"

    raise ValueError(f"unsupported instruction type '{info['type']}'")

def second_pass(text, labels):

    program = []

    for mn, ops, pc in text:

        try:
            codigo_binario = encode(
                mn,
                ops,
                pc,
                labels
            )
            codigo_entero = int(
                codigo_binario,
                2
            )
            program.append(
                (pc, codigo_entero)
            )
        except ValueError as e:
            raise ValueError(
                f"error in '{mn}': {e}"
            )
    return program


def write_hex(path, words):
    with open(path, 'w') as f:
        for w in words:
            f.write(f"{w:08x}\n") 

def write_mif(path, words, depth):
    if len(words) > depth:#check if the number of words is greater than the depth
        raise ValueError(f"{len(words)} words don't fit in ={depth}")
    with open(path, 'w') as f:
        f.write(f"DEPTH = {depth};\n")
        f.write("WIDTH = 32;\n")
        f.write("ADDRESS_RADIX = HEX;\n")
        f.write("DATA_RADIX = HEX;\n")
        f.write("CONTENT\nBEGIN\n")
        for direction, word in enumerate(words):
         f.write(f"{direction:X} : {word:08X};\n")
        if len(words) < depth: #check if the number of words is less than the depth
            f.write(f"[{len(words):X}..{depth - 1:X}] : 00000000;\n")#write the rest of the words with 0
        f.write("END;\n")

def main():

    ap = argparse.ArgumentParser(description="Assembler MIPS -> HEX / MIF")
    ap.add_argument("source",help="file .asm" )
    ap.add_argument("-o","--outdir",help="file output")
    ap.add_argument("--list",action="store_true",help="show program assembly")
    args = ap.parse_args()
    outdir = ( args.outdir or os.path.dirname(args.source) or ".")
    base = os.path.splitext(os.path.basename(args.source))[0]

    os.makedirs(outdir,exist_ok=True)

    with open(args.source) as f:
        lines = f.read().splitlines()

    try:

        labels, text, data = first_pass(lines) 
        prog = second_pass(text, labels) 
        words = [w for _, w in prog]
        write_hex( os.path.join(outdir, base + ".hex"),words )
        write_mif(  os.path.join(outdir, base + ".mif"), words, TEXT_DEPTH )

        if data:
            write_hex( os.path.join( outdir, base + "_data.hex"),data)
            write_mif(os.path.join( outdir,base + "_data.mif"),data,DATA_DEPTH)

    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

    if args.list:
        print("\nPrograma:\n")
        for pc, word in prog:
            print(f"0x{pc:08X}  {word:08X}")
        print("\nLabels:\n")

        for label, addr in labels.items():
            print(f"{label} = 0x{addr:X}")
    print(f"\nOK: {len(words)} instructions, "
          f"{len(data)} data words")
    print( f"Files generated in: {outdir}")

if __name__ == "__main__":
     main()