"""TC-12: make a MARS program assemble and run on our CPU.

Rewrites the MARS pseudo-instructions and syscalls that our assembler or the current CPU
(Phase 1, contracts.md "ISA") don't have, using only Phase 1 instructions and $at, the
register MARS itself reserves for pseudo-instructions. Everything it can't rewrite is
reported as an error with the line, so you know what to change by hand.

    python sw/tools/mars_compat.py <program.asm> -o <out.asm>

Rewrites (MARS semantics, delayed branching off):
  blt bgt ble bge a, b|imm, L     slt/slti into $at + beq/bne
  beqz bnez a, L / b L            beq/bne with $zero
  beq bne a, imm, L               li $at, imm + beq/bne
  bltz bgez blez bgtz a, L        slt into $at + beq/bne (Phase 2 on the CPU)
  subi, not, neg                  addi with -imm, nor with $zero, sub from $zero
  addi addiu slti andi ori        with an immediate that doesn't fit: li $at + the R-type
  lw sw rt, label[+n] | address   la/li $at + lw/sw n($at)
  syscall 10 / 17 (exit)          a self-jump (end of program, result visible)
  syscall 1 / 11 / 34 / 36        removed: the value MARS would print stays in $a0
  end of .text without a jump     a self-jump is added, so the CPU stops there
Errors (change by hand): input syscalls, strings and bytes (.asciiz .ascii .byte .half),
multiply/divide and the other Phase 2 instructions, floating point, macros.
"""
import argparse
import re
import sys

PHASE1 = {"add", "addu", "sub", "subu", "and", "or", "nor", "slt", "sll", "srl", "jr",
          "addi", "addiu", "andi", "ori", "slti", "lui", "lw", "sw", "beq", "bne", "j", "jal",
          "li", "la", "move", "nop"}
PHASE2 = {"sltu", "sltiu", "xor", "xori", "sra", "sllv", "srlv", "srav", "lb", "lbu", "lh",
          "lhu", "sb", "sh", "jalr", "mult", "multu", "div", "divu", "mfhi", "mflo", "mthi",
          "mtlo", "mul", "rem", "remu", "mulo", "mulu", "abs", "rol", "ror", "seq", "sne", "sge",
          "sgt", "sle", "sgeu", "sgtu", "sleu", "bltu", "bgtu", "bleu", "bgeu", "bltzal", "bgezal"}
DIRECTIVES_OK = {".text", ".data", ".word", ".space", ".globl", ".align"}
DIRECTIVES_BAD = {".asciiz", ".ascii", ".byte", ".half", ".float", ".double", ".eqv", ".macro",
                  ".end_macro", ".include", ".extern", ".kdata", ".ktext", ".set"}
EXIT_SERVICES = {10, 17}
PRINT_SERVICES = {1: "print integer", 11: "print character", 34: "print hex", 36: "print unsigned"}
REG = re.compile(r"^\$(\w+)$")


def is_reg(s):
    return bool(REG.match(s.strip()))


def to_int(s):
    s = s.strip()
    if len(s) == 3 and s[0] == s[2] == "'":
        return ord(s[1])
    return int(s, 0)


def is_imm(s):
    try:
        to_int(s)
        return True
    except ValueError:
        return False


def split_line(raw):
    """-> (labels, mnemonic, operands, comment)"""
    code, sep, comment = raw.partition("#")
    comment = (sep + comment) if sep else ""
    labels = []
    code = code.strip()
    while True:
        m = re.match(r"^([A-Za-z_.$][\w.$]*)\s*:\s*(.*)$", code)
        if not m:
            break
        labels.append(m.group(1))
        code = m.group(2).strip()
    if not code:
        return labels, "", [], comment
    parts = code.split(None, 1)
    mn = parts[0].lower()
    ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
    return labels, mn, ops, comment


class Converter:
    def __init__(self):
        self.out, self.changes, self.warnings, self.errors = [], [], [], []
        self.v0 = None            # last constant put in $v0 (for syscall)
        self.n_exit = 0
        self.section = "text"
        self.last_text_mn = None
        self.uses_at = False

    def emit(self, labels, lines, comment=""):
        """Labels on their own lines, then the instructions; the comment goes on the first one."""
        for label in labels:
            self.out.append(f"{label}:")
        for i, line in enumerate(lines):
            self.out.append(f"    {line}" + (f"    {comment}" if i == 0 and comment else ""))
        if not lines and comment:
            self.out.append(f"    {comment}")

    def change(self, n, src, lines):
        self.changes.append(f"line {n}: {src.split('#')[0].strip()}  ->  {' ; '.join(lines)}")

    def li_at(self, value):
        return f"li $at, {value}"

    def branch_cmp(self, mn, a, b, target):
        """blt/bgt/ble/bge with a register or an immediate second operand, through $at."""
        taken_if_set = mn in ("blt", "ble") if not is_reg(b) else mn in ("blt", "bgt")
        branch = f"{'bne' if taken_if_set else 'beq'} $at, $zero, {target}"
        if is_reg(b):
            first, second = (a, b) if mn in ("blt", "bge") else (b, a)
            return [f"slt $at, {first}, {second}", branch]
        # a < k, with k = imm for blt/bge and imm + 1 for ble/bgt (a <= imm  <=>  a < imm + 1)
        k = to_int(b) + (0 if mn in ("blt", "bge") else 1)
        if -32768 <= k <= 32767:
            return [f"slti $at, {a}, {k}", branch]
        return [self.li_at(k), f"slt $at, {a}, $at", branch]

    def convert(self, n, raw):
        labels, mn, ops, comment = split_line(raw)
        if "$at" in raw.split("#")[0]:
            self.uses_at = True
        if not mn:
            self.emit(labels, [], comment)
            return
        if mn.startswith("."):
            if mn in (".text", ".ktext"):
                self.section = "text"
            elif mn in (".data", ".kdata"):
                self.section = "data"
            if mn in DIRECTIVES_BAD:
                self.errors.append(f"line {n}: directive {mn} is not supported (only .word and .space for data): "
                                   "turn the strings/bytes into .word values, or drop them if only printed")
            elif mn not in DIRECTIVES_OK:
                self.errors.append(f"line {n}: unknown directive {mn}")
            self.out.append(raw.rstrip())
            return
        if self.section != "text":
            self.out.append(raw.rstrip())
            return

        lines = None
        # constants put in $v0, for the syscall service number
        if mn in ("li", "addi", "addiu", "ori") and ops and ops[0] == "$v0":
            src = ops[-1]
            if is_imm(src) and (mn == "li" or ops[1] in ("$zero", "$0")):
                self.v0 = to_int(src)
            else:
                self.v0 = None
        elif ops and ops[0] == "$v0":
            self.v0 = None

        if mn == "syscall":
            if self.v0 in EXIT_SERVICES:
                self.n_exit += 1
                lab = f"__exit{self.n_exit}"
                self.change(n, raw, [f"{lab}: j {lab}"])
                self.emit(labels + [lab], [f"j    {lab}"], "# was: syscall (exit): the program stops here")
                self.last_text_mn = "j"
                return
            if self.v0 in PRINT_SERVICES:
                self.warnings.append(f"line {n}: syscall {self.v0} ({PRINT_SERVICES[self.v0]}) removed: "
                                     "the value is in $a0 at that point (see it with SW9 + SW4-0 = 4)")
                self.emit(labels, ["nop"], f"# was: syscall {self.v0} ({PRINT_SERVICES[self.v0]})")
                return
            if self.v0 == 4:
                self.errors.append(f"line {n}: syscall 4 (print string) needs .asciiz: remove it by hand")
            elif self.v0 in (5, 8, 12):
                self.errors.append(f"line {n}: syscall {self.v0} reads input: put the value in the program instead "
                                   "(for example li $v0, <value>) and remove the syscall")
            else:
                self.errors.append(f"line {n}: syscall with $v0 = {self.v0} is not supported")
            self.out.append(raw.rstrip())
            return

        if mn in ("blt", "bgt", "ble", "bge") and len(ops) == 3:
            lines = self.branch_cmp(mn, ops[0], ops[1], ops[2])
        elif mn in ("beqz", "bnez") and len(ops) == 2:
            lines = [f"{'beq' if mn == 'beqz' else 'bne'} {ops[0]}, $zero, {ops[1]}"]
        elif mn == "b" and len(ops) == 1:
            lines = [f"beq $zero, $zero, {ops[0]}"]
        elif mn in ("beq", "bne") and len(ops) == 3 and not is_reg(ops[1]) and is_imm(ops[1]):
            lines = [self.li_at(to_int(ops[1])), f"{mn} {ops[0]}, $at, {ops[2]}"]
        elif mn in ("bltz", "bgez", "blez", "bgtz") and len(ops) == 2:
            r, t = ops
            lines = {"bltz": [f"slt $at, {r}, $zero", f"bne $at, $zero, {t}"],
                     "bgez": [f"slt $at, {r}, $zero", f"beq $at, $zero, {t}"],
                     "blez": [f"slt $at, $zero, {r}", f"beq $at, $zero, {t}"],
                     "bgtz": [f"slt $at, $zero, {r}", f"bne $at, $zero, {t}"]}[mn]
        elif mn == "subi" and len(ops) == 3 and is_imm(ops[2]):
            v = -to_int(ops[2])
            lines = ([f"addi {ops[0]}, {ops[1]}, {v}"] if -32768 <= v <= 32767
                     else [self.li_at(v), f"add {ops[0]}, {ops[1]}, $at"])
        elif mn == "not" and len(ops) == 2:
            lines = [f"nor {ops[0]}, {ops[1]}, $zero"]
        elif mn == "neg" and len(ops) == 2:
            lines = [f"sub {ops[0]}, $zero, {ops[1]}"]
        elif mn in ("addi", "addiu", "slti") and len(ops) == 3 and is_imm(ops[2]) \
                and not -32768 <= to_int(ops[2]) <= 32767:
            r = {"addi": "add", "addiu": "addu", "slti": "slt"}[mn]
            lines = [self.li_at(to_int(ops[2])), f"{r} {ops[0]}, {ops[1]}, $at"]
        elif mn in ("andi", "ori") and len(ops) == 3 and is_imm(ops[2]) and not 0 <= to_int(ops[2]) <= 0xFFFF:
            lines = [self.li_at(to_int(ops[2])), f"{mn[:-1]} {ops[0]}, {ops[1]}, $at"]
        elif mn in ("add", "sub", "and", "or", "slt", "addu", "subu", "nor") and len(ops) == 3 \
                and not is_reg(ops[2]) and is_imm(ops[2]):
            lines = [self.li_at(to_int(ops[2])), f"{mn} {ops[0]}, {ops[1]}, $at"]   # MARS: add rd, rs, imm
        elif mn in ("lw", "sw") and len(ops) == 2 and "(" not in ops[1]:
            m = re.match(r"^([A-Za-z_.$][\w.$]*)\s*(?:([+-])\s*(\w+))?$", ops[1])
            if is_imm(ops[1]):
                lines = [self.li_at(to_int(ops[1])), f"{mn} {ops[0]}, 0($at)"]
            elif m:
                off = (1 if m.group(2) != "-" else -1) * to_int(m.group(3)) if m.group(3) else 0
                lines = [f"la $at, {m.group(1)}", f"{mn} {ops[0]}, {off}($at)"]

        if lines is not None:
            self.change(n, raw, lines)
            self.emit(labels, lines, f"# was: {raw.split('#')[0].strip()}")
            self.last_text_mn = lines[-1].split()[0]
            return

        if mn in PHASE2:
            self.errors.append(f"line {n}: {mn} is not in the CPU used for the demo (Phase 1, contracts.md 'ISA'): "
                               "rewrite it with Phase 1 instructions")
        elif mn not in PHASE1:
            self.errors.append(f"line {n}: unknown instruction {mn}")
        self.out.append(raw.rstrip())
        self.last_text_mn = mn

    def finish(self):
        if self.last_text_mn not in ("j", "jr"):
            self.out += ["", "# added by mars_compat.py: the CPU stops here when the program ends",
                         "__end: j __end"]
            self.changes.append("end of .text: added '__end: j __end' (the program had no final jump or exit)")
        if self.uses_at:
            self.warnings.append("the program uses $at: the rewrites also use $at, check that it is not live across them")


def main():
    ap = argparse.ArgumentParser(description="Rewrite a MARS program for our assembler and Phase 1 CPU")
    ap.add_argument("source")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    with open(args.source) as f:
        src = f.read().splitlines()
    c = Converter()
    for n, raw in enumerate(src, 1):
        c.convert(n, raw)
    c.finish()
    with open(args.output, "w", newline="\n") as f:
        f.write(f"# Generated by sw/tools/mars_compat.py from {args.source}. Edit the original, not this file.\n")
        f.write("\n".join(c.out) + "\n")
    for line in c.changes:
        print(f"changed  {line}")
    for line in c.warnings:
        print(f"warning  {line}")
    for line in c.errors:
        print(f"ERROR    {line}")
    print(f"{len(c.changes)} change(s), {len(c.warnings)} warning(s), {len(c.errors)} error(s) -> {args.output}")
    sys.exit(1 if c.errors else 0)


if __name__ == "__main__":
    main()
