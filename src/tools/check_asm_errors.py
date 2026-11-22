"""TC-16: run the assembler on every src/programs/errors/*.asm and compare its error.

Each example starts with "# Expected: <message>". The assembler must exit with code 1
and print exactly that message. From the repo root:
    python src/tools/check_asm_errors.py
"""
import glob
import os
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.."))
ASSEMBLER = os.path.join(ROOT, "src", "assembler", "assembler.py")
OUT = os.path.join(ROOT, "build", "asm_errors")   # never mem: nothing should be written anyway

failures = 0
files = sorted(glob.glob(os.path.join(ROOT, "src", "programs", "errors", "*.asm")))
for path in files:
    with open(path) as f:
        first = f.readline().strip()
    if not first.startswith("# Expected: "):
        print(f"FAIL  {os.path.basename(path)}: first line has no '# Expected: ...'")
        failures += 1
        continue
    expected = first[len("# Expected: "):]
    run = subprocess.run([sys.executable, ASSEMBLER, path, "-o", OUT], capture_output=True, text=True)
    output = (run.stdout + run.stderr).strip()
    if run.returncode == 1 and expected in output.splitlines():
        print(f"ok    {os.path.basename(path)}: {expected}")
    else:
        print(f"FAIL  {os.path.basename(path)}: exit {run.returncode}, got '{output}', expected '{expected}'")
        failures += 1

if failures:
    print(f"FAILED: {failures} of {len(files)} error examples")
    sys.exit(1)
print(f"PASS: {len(files)} assembler error examples")
