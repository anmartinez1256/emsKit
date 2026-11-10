"""loop_insns.py STOCK_LIB FORK_LIB [GXX]: instruction counts of the inner z-loops of the voltage and current updates
(one iteration = the three field components of one z-vector of four cells), 2026-11-03. arm64 macOS only.
- Kernel: kb_idx.cpp next to this file, built by Apple clang (clang++) and by GCC (GXX, default g++-16) with the flags
  of gcc_vs_clang.sh (-std=c++17 -O3 -DNDEBUG) and linked with pc_sampler.cpp, then run once (KB_ONE=1, 6000 steps
  on 40 x 40 x 40) while the sampler records where the program counter is. Functions:
  Engine::Update{Voltages,Currents}_{stock,clean}.
- Libraries: STOCK_LIB and FORK_LIB, the libopenEMS.0.dylib of stock v0.37.0 and of the fork (both Apple clang):
  Engine_SSE_Compressed::Update{Voltages,Currents} (the stock loop) and ..._IJKN (the fork's rewrite).
Every function is disassembled with objdump. A compiler emits several copies of the z-loop: the loop that holds the
z-vector-0 code (lane loads or lane shifts, run once per y-line), and copies made by loop unswitching (for example
for y = 0). Listed per function: every innermost loop with 15 vector floating-point operations (one z-vector update),
its instruction count, whether it holds lane operations, and for the kernel its share of the function's samples.
The steady-state loop is the copy with the most samples (kernel) or the one without lane operations (libraries; the
clang kernel shows that this is the copy that runs). Last, clang's IR of the kernel (-S -emit-llvm): the
type-based alias analysis (TBAA) type of every vector store in each kernel function. The binaries go to
${TMPDIR:-/tmp}/emskit_loops."""
import os
import re
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
stock_lib, fork_lib = sys.argv[1], sys.argv[2]
gxx = sys.argv[3] if len(sys.argv) > 3 else "g++-16"
work = os.path.join(os.environ.get("TMPDIR", "/tmp"), "emskit_loops")
os.makedirs(work, exist_ok=True)
GRID = ["6000", "40", "40", "40"]

line = re.compile(r"^\s*([0-9a-f]+):\s+(\S+)\s*(.*)$")
branch = re.compile(r"^(b|b\.\w+|cbn?z|tbn?z)$")


def fp_op(mn, ops):
    return bool(re.match(r"^f(mla|mls|mul|add|sub)(\.4s)?$", mn)) and ".4s" in mn + ops


def lane_op(mn, ops):
    return mn.startswith(("ext", "ins", "mov.s", "dup", "zip", "uzp", "trn", "tbl")) or \
        (mn.startswith(("ld1", "st1")) and "}[" in ops.replace(" ", ""))


def loops(binary, symbol, hist=None):
    """[(instructions, lane ops, samples)] of the innermost loops with 15 vector FP operations; total samples."""
    out = subprocess.run(["objdump", "-d", "--no-show-raw-insn", f"--disassemble-symbols={symbol}", binary],
                         check=True, capture_output=True, text=True).stdout
    ins = [(int(m.group(1), 16), m.group(2), m.group(3)) for m in map(line.match, out.splitlines()) if m]
    if not ins:
        raise SystemExit(f"loop_insns.py: {symbol} not found in {binary}")
    lo, hi = ins[0][0], ins[-1][0]
    found = []
    for addr, mn, ops in ins:
        if branch.match(mn):
            t = re.findall(r"0x([0-9a-f]+)", ops.split("<")[0])
            if t and lo <= int(t[-1], 16) < addr:
                found.append((int(t[-1], 16), addr))
    res = []
    for a, b in found:
        if any((a, b) != (a2, b2) and a <= a2 and b2 <= b for a2, b2 in found):
            continue    # not innermost
        body = [(mn, ops) for addr, mn, ops in ins if a <= addr <= b]
        if sum(fp_op(mn, ops) for mn, ops in body) != 15:
            continue
        lane = sum(lane_op(mn, ops) for mn, ops in body)
        s = sum(c for x, c in hist.items() if a <= x <= b) if hist is not None else None
        ld = [ops for mn, ops in body if re.match(r"^(ldr|ldur|ldp|ld1)", mn)]
        mem = (len(ld), sum(1 for o in ld if re.match(r"^q\d+", o)), sum(1 for o in ld if "[sp" in o),
               sum(1 for mn, _ in body if re.match(r"^(str|stur|stp|st1)", mn)))
        res.append((len(body), lane, s, mem))
    total = sum(c for x, c in hist.items() if lo <= x <= hi) if hist is not None else None
    return res, total


def steady(res, sampled):
    if sampled:
        return max(res, key=lambda r: r[2])
    free = [r for r in res if r[1] == 0]
    return free[0] if len(free) == 1 else None


src = os.path.join(here, "kb_idx.cpp")
smp = os.path.join(here, "pc_sampler.cpp")
vers = {}
rows = []
for name, cxx in (("clang", "clang++"), ("gcc", gxx)):
    vers[name] = subprocess.run([cxx, "--version"], check=True, capture_output=True, text=True).stdout.splitlines()[0]
    exe = os.path.join(work, "kbs_" + name)
    f = ["-std=c++17", "-O3", "-DNDEBUG"]
    subprocess.run([cxx] + f + ["-Dmain=kb_main", "-c", src, "-o", exe + "_kb.o"], check=True)
    subprocess.run([cxx] + f + ["-c", smp, "-o", exe + "_smp.o"], check=True)
    subprocess.run([cxx, exe + "_kb.o", exe + "_smp.o", "-o", exe], check=True)
    r = subprocess.run([exe] + GRID, env=dict(os.environ, KB_ONE="1"), check=True, capture_output=True, text=True)
    hist = {}
    for l in r.stderr.splitlines():
        if l.startswith("PC "):
            _, a, c = l.split()
            hist[int(a, 16)] = int(c)
    for var in ("stock", "clean"):
        for upd in ("Voltages", "Currents"):
            fn = f"Update{upd}_{var}"
            res, tot = loops(exe, f"__ZN6Engine{len(fn)}{fn}Ejj", hist)
            rows.append((f"kernel, {name}: {fn}", res, tot, steady(res, True)))
for label, lib, suffix in (("stock v0.37.0 library", stock_lib, ""), ("fork library", fork_lib, "_IJKN")):
    for upd in ("Voltages", "Currents"):
        fn = f"Update{upd}{suffix}"
        res, _ = loops(lib, f"__ZN21Engine_SSE_Compressed{len(fn)}{fn}Ejj")
        rows.append((f"{label}: {fn}", res, None, steady(res, False)))

print("# loop_insns.py: inner z-loops (one iteration = three components of one z-vector of four cells), objdump")
print(f"# clang: {vers['clang']}")
print(f"# gcc:   {vers['gcc']}")
print(f"# kernel runs: KB_ONE=1 kb_idx {' '.join(GRID)} (steps Nx Ny Nz) under pc_sampler.cpp")
print("# per function: the steady-state loop's instructions, load instructions (of them vector loads, loads from the")
print("# stack), store instructions; then every copy: instructions [lane ops] (share of the function's samples; copies")
print("# can share addresses, so the shares can add up to more than 100 %)")
print(f"# {'function':42s} {'ins':>4s} {'ld':>3s} {'vec':>3s} {'sp':>3s} {'st':>3s}   copies")
for label, res, tot, st in rows:
    copies = "  ".join(f"{n}" + (f" [lane {ln}]" if ln else "") + (f" ({100 * s / tot:.1f} %)" if tot else "")
                       for n, ln, s, _ in res)
    n, (ld, vec, sp, sto) = (st[0], st[3]) if st else ("?", ("?",) * 4)
    print(f"{label:44s} {n:>4} {ld:>3} {vec:>3} {sp:>3} {sto:>3}   {copies}")

ll = os.path.join(work, "kb_idx.ll")
subprocess.run(["clang++", "-std=c++17", "-O3", "-DNDEBUG", "-S", "-emit-llvm", src, "-o", ll], check=True)
ir = open(ll).read()
meta = dict(re.findall(r"^(!\d+) = (.*)$", ir, re.M))


def tbaa(tag):
    m = re.match(r"!\{(!\d+), (!\d+)", meta.get(tag, ""))
    n = re.match(r'!\{!"([^"]+)"', meta.get(m.group(2), "")) if m else None
    return n.group(1) if n else "?"


print("# clang IR (-S -emit-llvm) of the kernel: TBAA type of the vector stores (whole function, z-vector 0 included)")
for var in ("stock", "clean"):
    for upd in ("Voltages", "Currents"):
        fn = f"Update{upd}_{var}"
        body = re.search(r"define [^@]*@_ZN6Engine\d+" + fn + r"Ejj\(.*?\n\}", ir, re.S).group(0)
        types = {}
        for t in re.findall(r"store <4 x float> [^\n]*?!tbaa (!\d+)", body):
            types[tbaa(t)] = types.get(tbaa(t), 0) + 1
        print(f"kernel, clang IR: {fn:22s} " + ", ".join(f"{n} vector stores of type '{k}'" for k, n in types.items()))
