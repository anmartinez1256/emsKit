#!/usr/bin/env python3
"""Interleaved runs of three openEMS binaries (luikore's pull request 228, the fork, upstream master) on luikore's model.
usage: compare3.py LUIKORE_BIN FORK_BIN MASTER_BIN OUT_DIR"""
import os, re, subprocess, sys, statistics, time, numpy as np
theirs, fork, master, out = sys.argv[1], sys.argv[2], sys.argv[3], os.path.abspath(sys.argv[4])
here = os.path.dirname(os.path.abspath(__file__))
CFG = [('luikore metal', theirs, ['--engine=metal']), ('luikore mt-8', theirs, ['--engine=multithreaded', '--numThreads=8']),
       ('master gpu', master, ['--engine=gpu']), ('master cpu-8', master, ['--engine=cpu', '--numThreads=8']),
       ('master mt-8', master, ['--engine=multithreaded', '--numThreads=8']),
       ('fdtdKit metal-diamond', fork, ['--engine=metal-diamond']), ('fdtdKit mt-8', fork, ['--engine=multithreaded', '--numThreads=8']),
       ('fdtdKit mt-10', fork, ['--engine=multithreaded', '--numThreads=10'])]
def others():
    p = subprocess.run(['ps', '-A', '-o', '%cpu='], capture_output=True, text=True).stdout.split()
    return sum(float(v) for v in p)
def quiet(limit=150, maxwait=180):
    t0 = time.time()
    while others() > limit and time.time() - t0 < maxwait:
        time.sleep(10)
for cells, steps in [((192, 160, 96), 3000), ((256, 256, 256), 1000)]:
    tag = 'x'.join(map(str, cells)) + f'_n{steps}'
    d = os.path.join(out, tag); os.makedirs(d, exist_ok=True)
    xml = os.path.join(d, 'model.xml')
    subprocess.run([sys.executable, os.path.join(here, 'model.py'), xml, *map(str, cells), str(steps)], check=True, stdout=subprocess.DEVNULL)
    res = {n: [] for n, _, _ in CFG}; probes = {}; notes = {}
    for r in range(3):
        for i, (name, binary, args) in enumerate(CFG):
            quiet(); o = others()
            rd = os.path.join(d, f'c{i}_r{r}'); os.makedirs(rd, exist_ok=True)
            env = {k: v for k, v in os.environ.items() if not k.startswith('DYLD_')}   # each binary loads its own library
            p = subprocess.run([binary, xml, *args], cwd=rd, capture_output=True, text=True, env=env)
            log = p.stdout + p.stderr; open(os.path.join(rd, 'log.txt'), 'w').write(log)
            m = re.search(r'Time for (\d+) iterations with ([\d.e+]+) cells : ([\d.e+-]+) sec', log)
            if p.returncode or not m:
                print(f'{tag} r{r} {name}: FAILED rc={p.returncode}: {log.strip().splitlines()[-1] if log.strip() else ""}', flush=True); continue
            mcs = int(m[1])*float(m[2])/float(m[3])/1e6; res[name].append(mcs)
            lib = re.search(r'version (\S+)', log); notes.setdefault(name + ' version', lib[1] if lib else '?')
            notes[name] = '; '.join(l.strip() for l in log.splitlines() if re.search(r'diamond|has no GPU|falling back|legacy', l, re.I))[:160]
            f = os.path.join(rd, 'ut1')
            if os.path.exists(f) and name not in probes:
                probes[name] = np.loadtxt(f, comments='%')
            print(f'{tag} r{r} {name:22} {mcs:8.1f} MC/s   all processes before the run {o:4.0f} % cpu', flush=True)
    ref = probes.get('fdtdKit mt-8')
    print(f'# {tag}: median MC/s [min-max], probe vs fdtdKit mt-8')
    for name, _, _ in CFG:
        v = res[name]
        if not v: print(f'# {name:22} no result'); continue
        pr = probes.get(name); diff = 'no probe'
        if ref is not None and pr is not None:
            diff = 'shape differs' if pr.shape != ref.shape else ('identical' if np.array_equal(pr, ref) else f'rel {abs(pr[:,1]-ref[:,1]).max()/abs(ref[:,1]).max():.1e}')
        print(f'# {name:22} {statistics.median(v):8.1f} [{min(v):.0f}-{max(v):.0f}]  {diff}  {notes.get(name + " version", "")}  {notes.get(name, "")}', flush=True)
