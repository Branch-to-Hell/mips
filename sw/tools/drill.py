"""TC-12 professor drill: unseen MARS program -> assemble -> check -> board, in one command.

From the repo root:
    python sw/tools/drill.py <program.asm> [--mars <Mars4_5.jar>] [--cycles N]

Steps (each one timed):
  1. mars_compat.py rewrites MARS pseudo-instructions/syscalls -> build/drill/<name>.asm
  2. our assembler -> hw/mem/<name>_b0..b3.hex (+ <name>_data.hex)
  3. MARS runs the ORIGINAL program: final registers and data words (the expected values)
  4. ModelSim runs our image on life_system with mips_pipeline (hw/sim/drill_tb.v)
  5. compares registers and data, and prints what to set in hw/quartus/program.qsf and
     which registers to look at on the board (SW9 debug view)
MARS: --mars, or the MARS_JAR environment variable, or ~/Downloads/Mars4_5.jar.
ModelSim (vlog/vsim) must be on PATH. Without MARS, step 3 and the comparison are skipped.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.."))
SIM = os.path.join(ROOT, "hw", "sim")
NAMES = ["zero", "at", "v0", "v1", "a0", "a1", "a2", "a3", "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7",
         "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra"]
DATA_BASE = 0x10010000
DATA_WORDS = 64
MARS_TEXT = (0x00400000, 0x00404000)
RTL = ["mips_pipeline.v", "hazard_unit.v", "if_id_register.v", "pipeline_register.v", "instruction_memory.v",
       "control_unit.v", "register_file.v", "alu.v", "alu_control.v", "data_memory.v", "debounce.v",
       "hex7seg.v", "hex_debug.v", "mmio.v", "vga_sync.v", "framebuffer_a.v", "video_mode_a.v", "life_system.v"]

steps = []


def step(title, func):
    t0 = time.time()
    print(f"\n== {title}")
    result = func()
    dt = time.time() - t0
    steps.append((title, dt))
    print(f"   ({dt:.1f} s)")
    return result


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def find_mars(arg):
    for path in (arg, os.environ.get("MARS_JAR"), os.path.expanduser("~/Downloads/Mars4_5.jar")):
        if path and os.path.isfile(path):
            return path
    return None


def mars_reference(jar, source, max_steps):
    regs = [f"${n}" for n in NAMES]
    mem = f"0x{DATA_BASE:08x}-0x{DATA_BASE + 4 * (DATA_WORDS - 1):08x}"
    r = run(["java", "-jar", jar, "nc", str(max_steps)] + regs + [mem, source])
    values, data, console = {}, {}, []
    for line in (r.stdout + r.stderr).splitlines():
        m = re.match(r"^\$(\w+)\s+0x([0-9a-fA-F]{8})", line)
        mm = re.match(r"^Mem\[0x([0-9a-fA-F]{8})\]\s+(.*)$", line)
        if m:
            values[NAMES.index(m.group(1))] = int(m.group(2), 16)
        elif mm:
            addr = int(mm.group(1), 16)
            for k, v in enumerate(re.findall(r"0x([0-9a-fA-F]{8})", mm.group(2))):
                data[addr + 4 * k] = int(v, 16)
        elif line.strip():
            console.append(line.rstrip())
    return values, data, console


def simulate(name, with_data, cycles):
    out = f"drill_{name}.txt"
    lib = os.path.join(SIM, "work")
    if not os.path.isdir(lib):
        run(["vlib", "work"], cwd=SIM)
    r = run(["vlog", "-quiet"] + [f"../rtl/{f}" for f in RTL] + ["drill_tb.v"], cwd=SIM)
    if r.returncode != 0:
        sys.exit(f"vlog failed:\n{r.stdout}{r.stderr}")
    r = run(["vsim", "-c", "-quiet", f"-GPROGRAM={name}", f"-GWITH_DATA={1 if with_data else 0}",
             f"-GMAX_CYCLES={cycles}", f"-GDATA_WORDS={DATA_WORDS}", "work.drill_tb",
             f"+out={out}", "-do", "run -all; quit -f"], cwd=SIM)
    path = os.path.join(SIM, out)
    if not os.path.isfile(path):
        sys.exit(f"vsim produced no result:\n{r.stdout[-2000:]}")
    regs, data, end = {}, {}, ""
    with open(path) as f:
        for line in f:
            p = line.split()
            if p[0] == "end":
                end = line.strip()
            elif p[0] == "halt":
                halt = p[1:]
            elif p[0] == "reg":
                regs[int(p[1])] = int(p[2], 16)
            elif p[0] == "mem":
                data[int(p[1], 16)] = int(p[2], 16)
    os.remove(path)
    for leftover in [f for f in os.listdir(SIM) if f.startswith("wlft")]:
        try:
            os.remove(os.path.join(SIM, leftover))
        except OSError:
            pass
    return regs, data, end, halt


def main():
    ap = argparse.ArgumentParser(description="TC-12 professor drill")
    ap.add_argument("source")
    ap.add_argument("--mars", help="path to Mars4_5.jar")
    ap.add_argument("--cycles", type=int, default=2_000_000, help="simulation limit (default 2,000,000 = 80 ms)")
    ap.add_argument("--steps", type=int, default=1_000_000, help="MARS step limit")
    args = ap.parse_args()
    t_start = time.time()

    name = re.sub(r"\W", "_", os.path.splitext(os.path.basename(args.source))[0])
    build = os.path.join(ROOT, "build", "drill")
    os.makedirs(build, exist_ok=True)
    converted = os.path.join(build, name + ".asm")

    def compat():
        r = run([sys.executable, os.path.join(ROOT, "sw", "tools", "mars_compat.py"), args.source, "-o", converted])
        print(r.stdout.rstrip())
        if r.returncode != 0:
            sys.exit("\nFix the ERROR lines in the original program and run the drill again.")
    step("1. MARS compatibility (mars_compat.py)", compat)

    def assemble():
        r = run([sys.executable, os.path.join(ROOT, "sw", "assembler", "assembler.py"), converted])
        print(r.stdout.strip())
        if r.returncode != 0:
            sys.exit("Assembler error: fix the program (the line numbers are in build/drill/" + name + ".asm)")
        return os.path.isfile(os.path.join(ROOT, "hw", "mem", name + "_data.hex")) and ".data" in open(converted).read()
    with_data = step("2. Assemble (sw/assembler/assembler.py -> hw/mem)", assemble)

    jar = find_mars(args.mars)
    mars = None
    if jar and shutil.which("java"):
        mars = step(f"3. Reference run in MARS ({jar})", lambda: mars_reference(jar, args.source, args.steps))
        if mars[2]:
            print("   MARS output:\n" + "\n".join("     " + l for l in mars[2][-12:]))
    else:
        print("\n== 3. MARS not found (--mars, MARS_JAR or ~/Downloads/Mars4_5.jar): no reference to compare")

    regs, data, end, halt = step("4. Our CPU in simulation (life_system + mips_pipeline, drill_tb.v)",
                                 lambda: simulate(name, with_data, args.cycles))
    print(f"   {end}")
    if end.startswith("end halt"):
        cause = {"1": "fetch", "2": "lw", "3": "sw"}.get(halt[0], halt[0])
        print(f"   CPU HALT: {cause} at PC {halt[1]}, address {halt[2]} (address outside the memory map or misaligned)")
    elif end.startswith("end timeout"):
        print("   the program did not reach a self-jump: an infinite loop that is not 'j itself'? raise --cycles?")

    ok = end.startswith("end selfjump")
    print("\n== 5. Comparison")
    if mars:
        m_regs, m_data = mars[0], mars[1]
        print(f"   {'register':10} {'MARS':>10} {'our CPU':>10}")
        for i, n in enumerate(NAMES):
            mv, ov = m_regs.get(i), regs.get(i)
            if i in (1, 26, 27) or mv is None:          # $at is used by the rewrites; $k0/$k1 by nothing
                continue
            if mv == ov == 0:
                continue
            note = ""
            if mv != ov:
                if MARS_TEXT[0] <= mv < MARS_TEXT[1]:
                    note = "code address: MARS text starts at 0x00400000, ours at 0 (+ delay-slot nops)"
                elif n == "gp" and mv == 0x10008000 and ov == 0:
                    note = "MARS's initial $gp; our reset leaves it at 0"
                else:
                    note = "DIFFERENT"
                    ok = False
            print(f"   ${n:<9} {mv:08x}   {ov:08x}   {note}")
        bad = [a for a in sorted(m_data) if m_data[a] != data.get(a)]
        used = [a for a in sorted(m_data) if m_data[a] or data.get(a)]
        print(f"   data 0x{DATA_BASE:08x}..: {len(used)} non-zero word(s), {len(bad)} different")
        for a in bad[:10]:
            print(f"     0x{a:08x}: MARS {m_data[a]:08x}  our CPU {data.get(a, 0):08x}")
        ok = ok and not bad
    else:
        for i, n in enumerate(NAMES):
            if regs.get(i):
                print(f"   ${n:<9} {regs[i]:08x}")

    print("\n== Board (hw/quartus/program.qsf, revision 'program')")
    print(f'   set_parameter -name PROGRAM "{name}"')
    print(f"   set_parameter -name WITH_DATA {1 if with_data else 0}")
    print("   Compile, program the board. Check with SW9 up and SW4-0 = register number (SW5 = upper half):")
    shown = [i for i in range(2, 32) if regs.get(i) and i not in (26, 27, 29)][:8]
    for i in shown:
        print(f"     ${NAMES[i]:<4} = register {i:2d} (SW4-0 = {i:05b}): {regs[i]:08x}")

    total = time.time() - t_start
    print("\n" + ("PASS" if ok else "FAIL") + f": drill {name} in {total:.0f} s " +
          "(" + ", ".join(f"{t.split('.')[0]}: {d:.0f} s" for t, d in steps) + ")")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
