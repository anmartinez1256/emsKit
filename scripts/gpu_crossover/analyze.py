"""analyze.py XDIR: the GPU/CPU size sweep (sweep.sh) as the rows of results/gpu_crossover_cg29_2026-11-05.txt.

Per point (model, scale): cells (openEMS's 'FDTD simulation size' line), the medians [min-max] of the CPU at 8 and 4
threads and of the GPU, the paired GPU / CPU-best ratio (per round: GPU over the faster CPU config of the point, by
median), the time split of the GPU runs with OPENEMS_DIAMOND_TIMING=1 (c3; per round, then the median): GPU busy, the
gaps inside IterateTS (encoding, commit, waits), the time outside IterateTS (probes, dumps, the main loop on the CPU),
the GPU-only rate (cells x steps / busy), steps per IterateTS call, the tiling chosen; the other processes' CPU and GPU
use (median [max] over the rounds used); the rounds used. A round 'kept after' its redos with a loaded run is left out
when at least two clean rounds remain (otherwise every round is used and the row says how many were loaded).
The crossover per model: where the median ratio passes 1, interpolated linearly in log(cells) between the two points
that bracket it."""
import glob, math, os, re, statistics as st, sys
import numpy as np

X = sys.argv[1]
RUN = re.compile(r'^r(\d+) c(\d+)\s+([\d.]+) MC/s\s+others cpu\s+(-?\d+)% gpu\s+(-?\d+)%\s+(.*)$')
TIM = re.compile(r'Engine_Metal_Diamond: setup ([\d.e+-]+) s, (\d+) timesteps in ([\d.e+-]+) s = ([\d.e+-]+) MC/s on the GPU; '
                 r'(\d+) IterateTS calls \(([\d.e+-]+) steps each\), (\d+) command buffers, GPU busy ([\d.e+-]+) s, span ([\d.e+-]+) s; '
                 r'K=(\d+) tiles (\d+),(\d+)( \(still tuning\))?')
SIZE = re.compile(r'FDTD simulation size: (\d+)x(\d+)x(\d+) --> ([\d.e+]+) FDTD cells')
TILES = re.compile(r'K=(\d) tiles (\d+),(\d+) \(x (\d+)\+(\d+), y (\d+)\+(\d+), (\d+) threads per tile\)')
NAMES = {'patch': 'patch antenna', 'notch': 'notch filter', 'kgcpw': 'GCPW line'}
LOOP = re.compile(r'Time for (\d+) iterations with ([\d.e+-]+) cells : ([\d.e+-]+) sec')
FLT_MIN = 1.1754944e-38      # the smallest normal float32; Apple's GPU flushes anything below it to zero


def read_probe(fn):
    return np.atleast_2d(np.loadtxt(fn, comments='%'))


def gpu_probe_check(base, used):
    """The GPU runs' port files (c2, c3, every round used) against the CPU reference c0/r0, as bench.py's probe_diff
    (max|v - v_ref| / max|v_ref| per file), but files whose reference peak is subnormal are kept apart: the wave has
    not reached that port yet, the CPU carries values below FLT_MIN and the GPU flushes them to zero, so the per-file
    ratio is 1 by construction. Returns (max rel over the other files, {file: (ref peak, max |gpu|)} of the subnormal ones)."""
    ref_dir = os.path.join(base, 'c0', 'r0')
    files = sorted(f for f in os.listdir(ref_dir) if f.startswith('port_'))
    rel, sub = 0.0, {}
    for c in (2, 3):
        for r in used:
            d = os.path.join(base, f'c{c}', f'r{r}')
            for fn in files:
                b, a = read_probe(os.path.join(ref_dir, fn)), read_probe(os.path.join(d, fn))
                if a.shape != b.shape:
                    rel = math.inf
                    continue
                peak = np.max(np.abs(b[:, 1:]))
                if 0 < peak < FLT_MIN:
                    g = float(np.max(np.abs(a[:, 1:])))
                    sub[fn] = (float(peak), max(g, sub.get(fn, (0, 0))[1]))
                    continue
                dd = np.max(np.abs(a[:, 1:] - b[:, 1:]))
                if dd > 0:
                    rel = max(rel, dd / peak if peak > 0 else math.inf)
    return rel, sub


def med(v):
    return st.median(v)


def rng(v, f='{:.0f}'):
    return f'{f.format(med(v))} [{f.format(min(v))}-{f.format(max(v))}]'


def tiles_of(model, scale):
    """Tile counts per tiling from tiles.py's verbose run of the point (tiles/MODEL_sS.txt), if present."""
    fn = os.path.join(X, 'tiles', f'{model}_s{scale}.txt')
    if not os.path.exists(fn):
        return {}
    out = {}
    for m in TILES.finditer(open(fn).read()):
        K, M, V, xm, xv, ym, yv, tg = map(int, m.groups())
        out[(K, M, V)] = dict(per_dispatch=(xm * ym, xv * yv), tg=tg)   # MM (fewest) and VV (most) tiles per dispatch
    return out


rows = []
for fn in sorted(glob.glob(os.path.join(X, 'out', '*.txt'))):
    name = os.path.basename(fn)[:-4]
    model, s, n = re.match(r'(\w+?)_s([\d.]+)_n(\d+)$', name).groups()
    runs, loud, redo = {}, set(), 0
    for line in open(fn):
        if line.startswith('# redo '):
            redo += 1
            continue
        m = re.match(r'^# r(\d+): kept after', line)
        if m:
            loud.add(int(m[1]))
            continue
        m = RUN.match(line.strip())
        if m:
            r, c = int(m[1]), int(m[2])
            runs.setdefault(c, {})[r] = (float(m[3]), int(m[4]), int(m[5]), m[6].strip())
    if len(runs) < 4:
        print(f'# {name}: incomplete ({sorted(runs)} configs), skipped', file=sys.stderr)
        continue
    every = sorted(set.intersection(*(set(runs[c]) for c in runs)))
    used = [r for r in every if r not in loud]
    if len(used) < 2:
        used = every
    nloud = len([r for r in used if r in loud])
    base = os.path.join(X, 'runs', f'ab_{name}')
    cells = None
    m = SIZE.search(open(os.path.join(base, 'c0', 'r0', 'openEMS.log')).read())
    if m:
        cells = float(m[4])
    cpu8 = [runs[0][r][0] for r in used]
    cpu4 = [runs[1][r][0] for r in used]
    gpu = [runs[2][r][0] for r in used]
    gput = [runs[3][r][0] for r in used]
    best = 0 if med(cpu8) >= med(cpu4) else 1
    ratio = [runs[2][r][0] / runs[best][r][0] for r in used]
    split = []
    for r in used:
        log = open(os.path.join(base, 'c3', f'r{r}', 'openEMS.log')).read()
        t = TIM.search(log)
        if not t:
            continue
        steps, run_s, calls, spc, busy = int(t[2]), float(t[3]), int(t[5]), float(t[6]), float(t[8])
        lt = LOOP.search(log)                                  # openEMS's own time for the time-stepping loop
        loop = float(lt[3]) if lt else steps * cells / (runs[3][r][0] * 1e6)
        split.append(dict(busy=busy / loop, gaps=(run_s - busy) / loop, outside=max(0.0, loop - run_s) / loop,
                          idle_call=(loop - busy) / calls * 1e3, work_call=busy / calls * 1e3,
                          gpu_only=steps * cells / busy / 1e6, spc=spc, tiling=(int(t[10]), int(t[11]), int(t[12])),
                          tuning=bool(t[13])))
    oc = [runs[c][r][1] for c in runs for r in used]
    og = [runs[c][r][2] for c in runs for r in used]
    diffs = sorted(set(runs[c][r][3] for c in (0, 1) for r in used))
    gdiff = [runs[c][r][3] for c in (2, 3) for r in used]
    rel = [float(x.split()[-1]) for x in gdiff if x.startswith('probes rel')]
    grel, gsub = gpu_probe_check(base, used)
    picks = []                                   # the tuner's choice in each TIMING run used, most frequent first
    for x in split:
        if x['tiling'] not in picks:
            picks.append(x['tiling'])
    picks.sort(key=lambda t: -sum(1 for x in split if x['tiling'] == t))
    npick = {t: sum(1 for x in split if x['tiling'] == t) for t in picks}
    tmap = tiles_of(model, s)
    rows.append(dict(model=model, scale=s, nrts=int(n), cells=cells, cpu8=cpu8, cpu4=cpu4, gpu=gpu, gput=gput, best=best,
                     ratio=ratio, split=split, oc=oc, og=og, used=len(used), every=len(every), nloud=nloud, redo=redo,
                     cpu_diffs=diffs, gpu_rel=max(rel) if rel else 0.0, gpu_other=[x for x in gdiff if not x.startswith('probes rel') and x != 'identical'],
                     picks=picks, npick=npick, tmap=tmap, grel=grel, gsub=gsub))

rows.sort(key=lambda d: (list(NAMES).index(d['model']), d['cells']))
hdr = ['model', 'cells', 'steps', 'CPU 8 thr', 'CPU 4 thr', 'GPU', 'GPU / CPU best', 'GPU busy', 'gaps', 'outside',
       'GPU-only', 'steps/call', 'GPU ms/call', 'idle ms/call', 'tiling', 'tiles/dispatch', 'others', 'rounds']
table = [hdr]
for d in rows:
    sp = d['split']
    picks, tmap = d['picks'], d['tmap']
    one = len(picks) == 1
    tiling_txt = ', '.join(f"K={t[0]} {t[1]},{t[2]}" + ('' if one else f" x{d['npick'][t]}") for t in picks)
    tiles_txt = ', '.join(f"{tmap[t]['per_dispatch'][0]}-{tmap[t]['per_dispatch'][1]} x {tmap[t]['tg']}" if t in tmap else '-'
                          for t in picks)
    table.append([
        f"{NAMES[d['model']]} s{d['scale']}", f"{d['cells'] / 1e6:.3f} M", str(d['nrts']),
        rng(d['cpu8']) + (' *' if d['best'] == 0 else ''), rng(d['cpu4']) + (' *' if d['best'] == 1 else ''), rng(d['gpu']),
        'x' + rng(d['ratio'], '{:.3f}'),
        f"{100 * med([x['busy'] for x in sp]):.0f} %" if sp else '-',
        f"{100 * med([x['gaps'] for x in sp]):.0f} %" if sp else '-',
        f"{100 * med([x['outside'] for x in sp]):.0f} %" if sp else '-',
        f"{med([x['gpu_only'] for x in sp]):.0f}" if sp else '-',
        f"{med([x['spc'] for x in sp]):.0f}" if sp else '-',
        f"{med([x['work_call'] for x in sp]):.2f}" if sp else '-',
        f"{med([x['idle_call'] for x in sp]):.2f}" if sp else '-',
        (tiling_txt + (' (tuning)' if any(x['tuning'] for x in sp) else '')) if picks else '-',
        tiles_txt or '-',
        f"{med(d['oc']) / 100:.1f} [{max(d['oc']) / 100:.1f}] / {med(d['og']):.0f} [{max(d['og'])}] %",
        (f"{d['used']}" if d['used'] == d['every'] else f"{d['used']} of {d['every']}") + (f", {d['nloud']} loaded" if d['nloud'] else '')
        + (f", redo {d['redo']}" if d['redo'] else ''),
    ])
w = [max(len(r[k]) for r in table) for k in range(len(hdr))]
for r in table:
    print('# | ' + ' | '.join(x.ljust(w[k]) for k, x in enumerate(r)) + ' |')

print('#')
for model in NAMES:
    pts = [(d['cells'], med(d['ratio'])) for d in rows if d['model'] == model]
    if not pts:
        continue
    cross = []                                   # every change of side between neighbouring sizes, log-linear in cells
    for (c0, q0), (c1, q1) in zip(pts, pts[1:]):
        if (q0 - 1) * (q1 - 1) < 0:
            t = (1 - q0) / (q1 - q0)
            cross.append((c0, c1, math.exp(math.log(c0) + t * (math.log(c1) - math.log(c0))), 'up' if q1 > q0 else 'down'))
    k = len(pts)
    while k > 0 and pts[k - 1][1] > 1:            # pts[k:] = the largest sizes, all with the GPU ahead
        k -= 1
    nm, lst = NAMES[model], ', '.join(f"{'GPU ahead' if u == 'up' else 'CPU ahead'} above ~{x / 1e6:.2f} M (between {a / 1e6:.3f} and {b / 1e6:.3f} M)" for a, b, x, u in cross)
    if k == 0:
        print(f'# crossover {nm}: the GPU is faster at every size measured ({pts[0][0] / 1e6:.3f}-{pts[-1][0] / 1e6:.3f} M cells)')
    elif k == len(pts):
        print(f'# crossover {nm}: the GPU is not faster at the largest size measured ({pts[-1][0] / 1e6:.3f} M cells)'
              + (f'; crossings: {lst}' if cross else ''))
    else:
        x = cross[-1][2]
        print(f'# crossover {nm}: the GPU is faster at every size from {pts[k][0] / 1e6:.3f} M cells up (measured to '
              f'{pts[-1][0] / 1e6:.3f} M); the last crossing is at about {x / 1e6:.2f} M cells, between {pts[k - 1][0] / 1e6:.3f} '
              f'(x{pts[k - 1][1]:.3f}) and {pts[k][0] / 1e6:.3f} M (x{pts[k][1]:.3f}), log-linear between the two medians'
              + (f'; all crossings: {lst}' if len(cross) > 1 else ''))
for model in NAMES:
    pts = [d for d in rows if d['model'] == model]
    k = len(pts)
    while k > 0 and min(pts[k - 1]['ratio']) > 1:     # pts[k:] = the largest sizes, the GPU ahead in every round used
        k -= 1
    if pts:
        print(f"# every round {NAMES[model]}: " + (f"the GPU ahead in every round used at every size from {pts[k]['cells'] / 1e6:.3f} M cells "
              f"(x{min(min(d['ratio']) for d in pts[k:]):.3f} or more); the next smaller point {pts[k - 1]['cells'] / 1e6:.3f} M: "
              f"x{med(pts[k - 1]['ratio']):.3f} [{min(pts[k - 1]['ratio']):.3f}-{max(pts[k - 1]['ratio']):.3f}]" if k < len(pts) else
              "not ahead in every round at the largest size"))
bad = [f"{NAMES[d['model']]} s{d['scale']} {','.join(d['cpu_diffs'])}" for d in rows
       if set(d['cpu_diffs']) - {'identical', 'reference'}]
print('# checks: CPU runs that differ from the CPU reference (8 threads, round 0): ' + '; '.join(bad) if bad else
      '# checks: every CPU run (4 and 8 threads, every round) identical to the CPU reference (8 threads, round 0)')
print(f"# GPU port probes against the CPU reference (8 threads, round 0; no FTZ in either), every GPU run used: max "
      f"{max(d['grel'] for d in rows):.1e} relative (bench.py's per-file max|v - v_ref| / max|v_ref|) over the files whose "
      "reference peak is a normal float")
for d in rows:
    if d['gsub']:
        print(f"#   {NAMES[d['model']]} s{d['scale']}: " + ', '.join(f"{f} (CPU peak {p:.1e}, GPU peak {g:.1e})" for f, (p, g) in sorted(d['gsub'].items()))
              + ": subnormal on the CPU because the wave has not reached the port in this run; the GPU flushes subnormals"
              " to zero, so bench.py's ratio is 1 there by construction")
print(f"# bench.py's own figure, all files: max {max(d['gpu_rel'] for d in rows):.1e} relative"
      + ('; other results: ' + '; '.join(f"{d['model']} s{d['scale']}: {','.join(d['gpu_other'])}" for d in rows if d['gpu_other'])
         if any(d['gpu_other'] for d in rows) else ''))
print('# TIMING=1 vs plain GPU (c3/c2, median of the per-point medians): x'
      f"{med([med(d['gput']) / med(d['gpu']) for d in rows]):.3f} [{min(med(d['gput']) / med(d['gpu']) for d in rows):.3f}-"
      f"{max(med(d['gput']) / med(d['gpu']) for d in rows):.3f}]")
