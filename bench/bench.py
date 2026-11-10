#!/usr/bin/env python3
"""Time openEMS engines on a benchmark model and check that their results are bit-identical.
(Each run is a separate process: runner.py -> FDTD.Run(), like the tutorials.)

  python3 bench.py MODEL --nrts N [--scale S] [--configs CFG ...] [--tag T] [--out DIR] [--runs DIR]

CFG is [LIB@]ENGINE[:THREADS][+nodumps][#NAME=VAL,...], e.g. multithreaded:4, sse-compressed,
fastest, basic+nodumps, mybuild@multithreaded:4#OPENEMS_FUSED=0.
- LIB@ runs the libopenEMS, libCSXCAD and libnf2ff of a snapshot: the folder SNAPS/LIB, or LIB itself
  when it contains a '/'. The folder must hold libopenEMS.0.dylib, libCSXCAD.0.dylib and libnf2ff.0.dylib
  (dyld would take a missing one from the install without a message); after each run bench.py checks that
  all three were loaded from it. macOS only (DYLD_LIBRARY_PATH). Without LIB@ a run uses the libraries
  Python loads anyway (the install).
- #NAME=VAL,... sets environment variables for that run.
The first config is the reference. Every run does exactly --nrts timesteps (EndCriteria=0), so all runs
compute the same thing, and the port probe files and S-parameters of every run (every repeat, also the
reference config's own later repeats) must equal those of the reference config's first run bit for bit.
Configs on the GPU engines or with OPENEMS_FTZ set are compared but not required to match: '(tolerant)'.
Per line: the speed from openEMS's own timing; 'others NN%' = CPU used by other processes in the second
before the run (top, 100 % = one core); 'during: ...' = CPU and GPU use over the whole run of the fastest repeat, of
the bench's own processes and of all others (bench/usage.py: ps CPU time, ioreg per-process GPU time and the GPU's
Device Utilization %; a busy other process makes the speed of that line unreliable); 'probes rel' = max over the port files of max|v - v_ref| / max|v_ref|;
per S-parameter max|dS| (linear) and the max dB difference over the frequencies where |S_ref| > -40 dB.
Comparisons that have no such figure (a probe that is all zero in the reference, an S-parameter that stays
below -40 dB) are compared exactly and named in the line.
Exit status: 0 = every compared run is identical (a tolerant one may differ in value), 1 = a run failed or a
config was refused, 2 = a difference or a missing file. With --tag T the lines are also written to
OUT/MODEL_sSCALE_nNRTS_T.txt (OUT = --out, default the top-level results/ folder).
"""
import argparse, os, re, subprocess, sys, time
import numpy as np
import usage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from models import MODELS, sparams

RUNNER = os.path.join(HERE, 'runner.py')
RESULTS = os.path.join(os.path.dirname(HERE), 'results')
# LIB@ prefix: a snapshot folder SNAPS/<LIB>/ holding the three libraries, e.g. the stock v0.37.0 libraries
# as 'stock' (BUILD.md section 3); a LIB that contains '/' is the folder itself.
SNAPS = os.path.expanduser(os.environ.get('OPENEMS_BENCH_SNAPS', '~/opt/openEMS-dev/snap'))
LIBS = ('libopenEMS', 'libCSXCAD', 'libnf2ff')
ENGINES = ('fastest', 'basic', 'sse', 'sse-compressed', 'multithreaded', 'gpu', 'gpu-reference', 'metal-diamond')


def lib_dir(name):
    return os.path.abspath(os.path.expanduser(name if '/' in name else os.path.join(SNAPS, name)))


def parse_cfg(cfg):
    """[LIB@]ENGINE[:THREADS][+nodumps][#NAME=VAL,...] -> (lib, engine, threads, flag, env)."""
    spec, _, envs = cfg.partition('#')
    env = {}
    for kv in filter(None, envs.split(',')):
        k, _, v = kv.partition('=')
        env[k] = v
    lib, _, spec = spec.rpartition('@')
    eng, _, rest = spec.partition(':')
    eng, _, flag = eng.partition('+')
    threads, _, flag2 = rest.partition('+')
    return lib, eng, threads, flag or flag2, env


def check_cfg(cfg):
    """Refuse a config before anything runs: unknown engine or flag, or a LIB@ folder without the three libraries."""
    lib, eng, threads, flag, _ = parse_cfg(cfg)
    if eng not in ENGINES:   # openEMS would run its default engine without a message
        sys.exit(f'bench.py: {cfg}: unknown engine {eng!r} (one of {", ".join(ENGINES)})')
    if threads and not threads.isdigit() or flag not in ('', 'nodumps'):
        sys.exit(f'bench.py: {cfg}: expected [LIB@]ENGINE[:THREADS][+nodumps][#NAME=VAL,...]')
    if not lib:
        return
    if sys.platform != 'darwin':
        sys.exit(f'bench.py: {cfg}: LIB@ selects the libraries through DYLD_LIBRARY_PATH (macOS only); elsewhere run '
                 'the config without LIB@ and set the loader path yourself')
    d = lib_dir(lib)
    if not os.path.isdir(d):
        sys.exit(f'bench.py: {cfg}: snapshot folder {d} does not exist')
    missing = [f'{n}.0.dylib' for n in LIBS if not os.path.isfile(os.path.join(d, f'{n}.0.dylib'))]
    if missing:
        sys.exit(f'bench.py: {cfg}: {d} lacks {", ".join(missing)} (dyld would take a missing library from the '
                 'install instead)')


def is_tolerant(cfg):
    """GPU engines (gpu, metal-diamond: Apple's GPU flushes subnormals) and flushed subnormals (OPENEMS_FTZ set, not 0)
    are not bit-identical to the CPU engines without FTZ."""
    _, eng, _, _, env = parse_cfg(cfg)
    ftz = env.get('OPENEMS_FTZ', os.environ.get('OPENEMS_FTZ', ''))
    return eng.startswith('gpu') or eng == 'metal-diamond' or ftz not in ('', '0')


def check_loaded(cfg, log, want):
    """Raise unless the runner loaded all three libraries from `want` (LIB@ configs), or, without LIB@
    (want None), from outside SNAPS."""
    got = re.findall(r'^BENCH_LIB (.+)$', log, re.M)
    for n in LIBS:
        paths = [os.path.realpath(p) for p in got if os.path.basename(p).startswith(n + '.')]
        if not paths:
            raise RuntimeError(f'{cfg}: the runner did not list a loaded {n}')
        for p in paths:
            if want and not p.startswith(os.path.realpath(want) + os.sep):
                raise RuntimeError(f'{cfg}: {n} came from {p}, not from {want}: dyld could not use the file there, '
                                   'or DYLD_LIBRARY_PATH did not reach the runner (a macOS system binary such as '
                                   '/usr/bin/python3 or caffeinate drops it)')
            if not want and p.startswith(os.path.realpath(SNAPS) + os.sep):
                raise RuntimeError(f'{cfg}: without LIB@ the run should use the install, but {n} came from {p} '
                                   '(DYLD_LIBRARY_PATH set in the environment?)')


def run_one(model, scale, nrts, run_dir, cfg):
    lib, eng, threads, flag, envs = parse_cfg(cfg)
    env = dict(os.environ)
    env.update(envs)
    want = lib_dir(lib) if lib else None
    if want:
        env['DYLD_LIBRARY_PATH'] = want
    args = [sys.executable, '-u', RUNNER, model, run_dir, f'--nrts={nrts}', f'--scale={scale}',
            f'--engine={eng}']
    if threads:
        args.append(f'--threads={threads}')
    if flag == 'nodumps':
        args.append('--nodumps')
    os.makedirs(run_dir, exist_ok=True)
    t0 = time.time()
    smp = usage.Sampler()
    p = subprocess.run(args, capture_output=True, text=True, env=env)
    use = smp.stop()
    wall = time.time() - t0
    log = p.stdout + p.stderr
    with open(os.path.join(run_dir, 'openEMS.log'), 'w') as fh:
        fh.write(log)
    if p.returncode or 'Unused primitive' in log:
        raise RuntimeError(f'{cfg}: exit {p.returncode} or unused primitive\n{log[-2000:]}')
    check_loaded(cfg, log, want)
    m = re.search(r'Time for (\d+) iterations with ([\d.eE+-]+) cells : ([\d.eE+-]+) sec', log)
    best = re.search(r'Best performance found using (\d+) threads', log)
    ver = re.search(r'openEMS \w+ -- version (\S+)', log)
    nts, cells, t = int(m[1]), float(m[2]), float(m[3])
    return dict(cfg=cfg, dir=run_dir, mcs=cells*nts/t/1e6, t=t, wall=wall, nts=nts, cells=cells,
                best=int(best[1]) if best else None, version=ver[1] if ver else '?', use=use)


def others_cpu():
    """CPU % used by other processes over 1 s (top's 2nd sample), and the busiest names."""
    out = subprocess.run(['top', '-l', '2', '-s', '1', '-n', '15', '-o', 'cpu', '-stats', 'pid,cpu,command'],
                         capture_output=True, text=True).stdout
    sample = out.split('PID')[-1].splitlines()[1:]
    tot, busy = 0.0, []
    for ln in sample:
        f = ln.split(None, 2)
        if len(f) < 3 or not f[0].isdigit() or int(f[0]) == os.getpid() or f[2].startswith('top'):
            continue
        c = float(f[1])
        if not 0 <= c <= 100*os.cpu_count():  # top sometimes prints garbage for a dying process
            continue
        tot += c
        if c > 20:
            busy.append(f'{f[2].strip()[:16]}:{c:.0f}')
    return tot, busy


def wait_quiet(limit, max_wait, gpu_limit=10):
    """Sample others_cpu() every 15 s until it is <= limit and the other processes' GPU use over 2 s is <=
    gpu_limit % (bench/usage.py); after max_wait s give up (third value True)."""
    t0 = time.time()
    while True:
        c, busy = others_cpu()
        g = 0.0
        if c <= limit:
            smp = usage.Sampler()
            time.sleep(2)
            u = smp.stop()
            g = u['gpu_other'] if u else 0.0
            if g <= gpu_limit:
                return c, busy, False
            busy = busy + [f'gpu {x}' for x in u['busy']]
        if time.time() - t0 > max_wait:
            return c, busy, True
        time.sleep(15)


def read_probe(path):
    return np.loadtxt(path, comments='%', ndmin=2)


def port_files(d):
    return sorted(f for f in os.listdir(d) if f.startswith('port_'))


def probe_diff(run_dir, ref_dir):
    """Compare the port probe files with the reference's, exactly. Returns (rel, zero, problems):
    rel = max over the files of max|v - v_ref| / max|v_ref| (inf for a difference in a file whose reference
    is all zero), zero = the files whose reference is all zero, problems = missing, extra or truncated files,
    differing time columns, NaN/inf that differ in place or value (+inf against -inf, NaN against inf)."""
    ref, got = port_files(ref_dir), port_files(run_dir)
    problems = [f'missing {f}' for f in ref if f not in got] + [f'extra {f}' for f in got if f not in ref]
    if not ref:
        problems.append('no port files in the reference')
    rel, zero = 0.0, []
    for fn in ref:
        if fn not in got:
            continue
        b, a = read_probe(os.path.join(ref_dir, fn)), read_probe(os.path.join(run_dir, fn))
        if not np.any(b[:, 1:]):
            zero.append(fn)
        if a.shape != b.shape:
            problems.append(f'{fn} has {a.shape[0]} rows, the reference {b.shape[0]}')
            continue
        if np.array_equal(a, b, equal_nan=True):
            continue
        if not np.array_equal(a[:, 0], b[:, 0]):
            problems.append(f'{fn} time column differs')
        fin = np.isfinite(b[:, 1:])
        if np.any(np.isfinite(a[:, 1:]) != fin) or \
                not np.array_equal(a[:, 1:][~fin], b[:, 1:][~fin], equal_nan=True):
            problems.append(f'{fn} NaN/inf differ')
            rel = np.inf
            continue
        # finite entries only: one NaN would turn the max into NaN and hide every other difference
        scale = np.max(np.abs(b[:, 1:][fin]), initial=0.0)
        d = np.max(np.abs(a[:, 1:][fin] - b[:, 1:][fin]), initial=0.0)
        if d > 0:
            rel = max(rel, d/scale if scale > 0 else np.inf)
    return rel, zero, problems


def compare(s, ref):
    """Per S-parameter: (exact, max|dS| (linear), max dB difference); the last two over the frequencies where
    |S_ref| > -40 dB, None when there are none. exact: equal over all frequencies (NaN bins equal)."""
    out = {}
    for k in ref:
        if k == 'f':
            continue
        a, b = s[k], ref[k]
        exact = a.shape == b.shape and np.array_equal(a, b, equal_nan=True)
        if a.shape != b.shape or np.any(np.isfinite(a) != np.isfinite(b)):
            out[k] = (False, np.inf, np.inf)
            continue
        mask = np.isfinite(b) & (np.abs(b) > 1e-2)
        if not mask.any():
            fin = np.isfinite(b)
            out[k] = (exact, np.max(np.abs(a[fin]-b[fin])) if fin.any() else 0.0, None)
            continue
        out[k] = (exact, np.max(np.abs(a[mask]-b[mask])),
                  np.max(np.abs(20*np.log10(np.abs(a[mask])) - 20*np.log10(np.abs(b[mask])))))
    return out


def worst(x, y):
    """Combine two compare() results (or None) entry by entry: worst figure, exact only if both are."""
    if x is None:
        return y
    out = {}
    for k in x:
        (e1, d1, b1), (e2, d2, b2) = x[k], y[k]
        dB = [v for v in (b1, b2) if v is not None]
        out[k] = (e1 and e2, max(d1, d2), max(dB) if dB else None)
    return out


def main():
    ap = argparse.ArgumentParser(description='Time openEMS engines on a benchmark model and check that their '
                                 'results are bit-identical (see the docstring of bench.py).')
    ap.add_argument('model', choices=MODELS)
    ap.add_argument('--scale', type=float, default=1.0,
                    help='patch, notch: multiplies the mesh resolution (2 -> about 8x the cells); kgcpw, ksma: '
                         'passed to the rfsim builders, where it multiplies the cell sizes (below 1 refines; ksma '
                         'refuses a scale too coarse for its gap, such as 3)')
    ap.add_argument('--nrts', type=int, required=True)
    ap.add_argument('--configs', nargs='+', default=['multithreaded:4'])
    ap.add_argument('--tag', default='', help='also write the lines to OUT/MODEL_sSCALE_nNRTS_TAG.txt')
    ap.add_argument('--out', default=RESULTS, help='folder for the --tag file (default: the top-level results/)')
    ap.add_argument('--runs', default=os.environ.get('OPENEMS_BENCH_RUNS', '/tmp/openems_bench_runs'),
                    help='run directories (probe files, dumps, logs); default $OPENEMS_BENCH_RUNS or %(default)s')
    ap.add_argument('--no-sparams', action='store_true',
                    help='skip the S-parameter DFT (the probe comparison still runs)')
    ap.add_argument('--repeat', type=int, default=1, help='runs per config; the fastest speed is reported, '
                    'every run is compared')
    ap.add_argument('--quiet', type=float, default=0,
                    help='before each run, wait until other processes use less than this CPU %% (100 = one core)')
    ap.add_argument('--quiet-gpu', type=float, default=10,
                    help='with --quiet, also wait until other processes use at most this GPU %% (default 10)')
    ap.add_argument('--quiet-max', type=float, default=900,
                    help='give up the --quiet wait after this many seconds (the line then says so)')
    a = ap.parse_args()
    if a.model in ('kgcpw', 'ksma') and not os.environ.get('RFSIM_PATH'):
        sys.exit(f'bench.py: {a.model} needs the rfsim toolkit (not public): set RFSIM_PATH to the folder that '
                 'contains rfsim/')
    for cfg in a.configs:
        check_cfg(cfg)

    name = f'{a.model}_s{a.scale:g}_n{a.nrts}'
    base = os.path.join(os.path.abspath(a.runs), name)
    os.makedirs(base, exist_ok=True)

    rows, fails, tolerant, compared = [], [], [], []
    ref_dir, ref_s, ref_tol, s_note = None, None, False, None
    print(f'# {name}  load avg {os.getloadavg()[0]:.2f}', flush=True)
    used = set()   # run folder names: a config given twice (check.sh with SNAP = the reference) gets a second one
    for cfg in a.configs:
        lib = parse_cfg(cfg)[0]
        label = cfg.replace(lib + '@', os.path.basename(lib.rstrip('/')) + '@', 1) if '/' in lib else cfg
        sub0 = re.sub(r'[^A-Za-z0-9_.-]', '_', label.replace(':', '_t'))
        sub, i = sub0, 1
        while sub in used:   # otherwise its runs would overwrite the reference's files and compare them to themselves
            i += 1
            sub = f'{sub0}_{i}'
        used.add(sub)
        rd = os.path.join(base, sub)
        runs = []
        for k in range(a.repeat):
            other, busy, late = wait_quiet(a.quiet, a.quiet_max, a.quiet_gpu) if a.quiet else (*others_cpu(), False)
            runs.append(run_one(a.model, a.scale, a.nrts, os.path.join(rd, f'rep{k}'), cfg)
                        | {'other': other, 'busy': busy, 'late': late})
        is_ref = ref_dir is None
        if is_ref:
            ref_dir, ref_tol = runs[0]['dir'], is_tolerant(cfg)
            n = min((len(read_probe(os.path.join(ref_dir, f))) for f in port_files(ref_dir)), default=0)
            if a.no_sparams:
                s_note = 'S-params not computed (--no-sparams)'
            elif n < 2:   # CalcPort's DFT needs two samples; probes are written every Nyquist/4 steps or so
                s_note = f'S-params skipped: {n} probe sample{"" if n == 1 else "s"}, raise --nrts'
            else:
                ref_s = sparams(a.model, ref_dir, nrts=a.nrts, scale=a.scale)
        tol = ref_tol or is_tolerant(cfg)
        rel, zero, problems, sd = 0.0, set(), [], None
        for k, r in enumerate(runs):
            if is_ref and k == 0:
                continue
            r_rel, r_zero, r_prob = probe_diff(r['dir'], ref_dir)
            rel, zero = max(rel, r_rel), zero | set(r_zero)
            problems += [f'rep{k}: {p}' if a.repeat > 1 else p for p in r_prob]
            if ref_s is not None and not r_prob:
                sd = worst(sd, compare(sparams(a.model, r['dir'], nrts=a.nrts, scale=a.scale), ref_s))
        r = max(runs, key=lambda x: x['mcs'])
        line = (f'{label:28s} {r["mcs"]:8.1f} MC/s  {r["t"]:8.2f} s  '
                f'{r["nts"]} TS x {r["cells"]/1e6:.3f} MC  others {r["other"]:3.0f}%')
        if a.repeat > 1:
            line += '  runs ' + '/'.join(f'{x["mcs"]:.0f}' for x in runs)
        if r['busy']:
            line += '  busy ' + ','.join(r['busy'])
        if r['use']:
            line += '  ' + usage.fmt(r['use'])
        if r['late']:
            line += '  quiet-wait timed out'
        if r['best']:
            line += f'  (auto-picked {r["best"]} threads)'
        if is_ref:
            line += '  [ref]'
        if not is_ref or a.repeat > 1:
            compared.append(label)
            line += f'  probes rel={rel:.1e}'
            if zero:
                line += f' ({len(zero)} of {len(port_files(ref_dir))} files all zero in the reference, ' \
                        'compared exactly)'
            if problems:
                line += '  PROBLEM: ' + '; '.join(problems)
            for k, (exact, dS, dB) in (sd or {}).items():
                if dB is None:
                    line += f'  {k}: below -40 dB, compared exactly: ' + ('equal' if exact else f'max|dS|={dS:.1e}')
                else:
                    line += f'  {k}: max|dS|={dS:.1e} max dB={dB:.1e}'
                    if not exact and not dS:
                        line += ' (differs below -40 dB)'
            if s_note:
                line += '  ' + s_note
            same = rel == 0 and not problems and all(v[0] for v in (sd or {}).values())
            if tol:
                tolerant.append(label)
                line += '  (tolerant)'
                if problems:
                    fails.append(label)
            elif not same:
                fails.append(label)
        line += f'  openEMS {r["version"]}'
        print(line, flush=True)
        rows.append(line)
    if fails:
        summary = f'MISMATCH: {", ".join(fails)}'
    elif not compared:
        summary = 'NOTHING COMPARED: one config, one run'
    elif len(compared) == len(tolerant):
        summary = f'NOTHING REQUIRED TO MATCH: every compared config is tolerant ({", ".join(tolerant)})'
    else:
        n = len(compared) - len(tolerant)
        summary = f'IDENTICAL: every run of {n} config{"" if n == 1 else "s"} equals the reference' + \
            (f' ({len(tolerant)} tolerant, not required to match: {", ".join(tolerant)})' if tolerant else '')
    print(summary, flush=True)
    if a.tag:
        os.makedirs(a.out, exist_ok=True)
        fn = os.path.join(a.out, f'{name}_{a.tag}.txt')
        with open(fn, 'w') as fh:
            fh.write(f'# {name}  {time.strftime("%Y-%m-%d %H:%M")}\n' + '\n'.join(rows) + f'\n# {summary}\n')
        print(f'wrote {fn}', flush=True)
    sys.exit(2 if fails else 0)


if __name__ == '__main__':
    main()
