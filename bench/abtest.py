"""Interleaved A/B timing on a shared Mac: every round runs each config once, in turn (A B C A B C ...), so slow
changes of the background load hit all configs alike. Per config: the median and the spread of the cell rate, and
the median of its ratio to the first config within the same round (the paired ratio that cancels the drift); per run
the CPU and GPU use of the other processes during it (bench/usage.py). Every run's port probes are compared with the
first config's first run (bench.py's probe_diff): 'identical' or the max relative difference.

usage: abtest.py MODEL --scale S --nrts N --rounds R --configs CFG ... [--runs DIR] [--out FILE] [--quiet PCT]
CFG is bench.py's [LIB@]ENGINE[:THREADS][+nodumps][#NAME=VAL,...]; NAME=VAL lists may also use ';' between pairs.
--quiet PCT: before each round, wait (bench.wait_quiet) until the other processes use at most PCT % CPU and 10 %
GPU; after --quiet-max s the round runs anyway and the output says so. --redo N (with --quiet): a round in which a
run saw the others above PCT % CPU or 10 % GPU is run again, up to N times; the discarded runs are printed as
'# redo' lines and do not count. --run-redo N (with --quiet, instead of --redo): every run waits for the quiet Mac
itself and is run again, up to N times, when the others rose above the limit during it, so one loaded run does not
cost the whole round; a round whose kept runs include a loaded one says so ('# rN: kept after')."""
import argparse, os, statistics, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench, usage


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('model')
    ap.add_argument('--scale', type=float, default=1)
    ap.add_argument('--nrts', type=int, required=True)
    ap.add_argument('--rounds', type=int, default=5)
    ap.add_argument('--configs', nargs='+', required=True)
    ap.add_argument('--runs', default=os.environ.get('OPENEMS_BENCH_RUNS', '/tmp/openems_bench_runs'))
    ap.add_argument('--out')
    ap.add_argument('--quiet', type=float, default=0)
    ap.add_argument('--quiet-max', type=float, default=900)
    ap.add_argument('--redo', type=int, default=0)
    ap.add_argument('--run-redo', type=int, default=0)
    a = ap.parse_args()
    if a.run_redo and a.redo:
        ap.error('--run-redo replaces --redo; give one of them')
    cfgs = [c.replace(';', ',') for c in a.configs]
    for c in cfgs:
        bench.check_cfg(c)
    scale = int(a.scale) if a.scale == int(a.scale) else a.scale
    name = f'{a.model}_s{scale}_n{a.nrts}'
    base = os.path.join(a.runs, 'ab_' + name)
    res = {c: [] for c in cfgs}
    ref_dir, lines = None, []

    def say(s):
        print(s, flush=True)
        lines.append(s)

    say(f'# {name}  {time.strftime("%Y-%m-%d %H:%M")}  load avg {os.getloadavg()[0]:.2f}  {a.rounds} rounds, interleaved'
        + (f', each round after others <= {a.quiet:.0f} % CPU' if a.quiet else ''))
    for r in range(a.rounds):
        for attempt in range(a.redo + 1):
            if a.quiet and not a.run_redo:
                oc, busy, late = bench.wait_quiet(a.quiet, a.quiet_max)
                if late:
                    say(f'# r{r}: others still {oc:.0f} % CPU after {a.quiet_max:.0f} s ({" ".join(busy)}); the round runs anyway')
            got, out = [], []
            for i, c in enumerate(cfgs):
                d = os.path.join(base, f'c{i}', f'r{r}')
                for k in range(a.run_redo + 1):
                    if a.quiet and a.run_redo:
                        oc, busy, late = bench.wait_quiet(a.quiet, a.quiet_max)
                        if late:
                            say(f'# r{r} c{i}: others still {oc:.0f} % CPU after {a.quiet_max:.0f} s ({" ".join(busy)}); the run goes ahead')
                    x = bench.run_one(a.model, scale, a.nrts, d, c)
                    if ref_dir is None or d == ref_dir:
                        ref_dir, diff = d, 'reference'
                    else:
                        rel, zero, prob = bench.probe_diff(d, ref_dir)
                        diff = ('PROBLEM ' + '; '.join(prob)) if prob else ('identical' if rel == 0 else f'probes rel {rel:.1e}')
                    u = x['use'] or {}
                    g = (x['mcs'], u.get('cpu_other', -1), u.get('gpu_other', -1), diff)
                    line = f'r{r} c{i} {x["mcs"]:8.1f} MC/s  others cpu {u.get("cpu_other", -1):4.0f}% gpu {u.get("gpu_other", -1):3.0f}%  {diff}'
                    print(line, flush=True)
                    if a.run_redo and (g[1] > a.quiet or g[2] > 10) and k < a.run_redo:
                        lines.append('# redo ' + line)
                        say(f'# r{r} c{i}: redo {k + 1} of {a.run_redo} (the others at {g[1]:.0f} % CPU, {g[2]:.0f} % GPU during the run)')
                        continue
                    break
                got.append(g)
                out.append(line)
            loud = [g for g in got if g[1] > a.quiet or g[2] > 10] if a.quiet else []
            if loud and attempt < a.redo:
                for s in out:
                    lines.append('# redo ' + s)
                say(f'# r{r}: redo {attempt + 1} of {a.redo} (a run saw the others at {max(g[1] for g in got):.0f} % CPU, '
                    f'{max(g[2] for g in got):.0f} % GPU)')
                continue
            for c, g in zip(cfgs, got):
                res[c].append(g)
            lines.extend(out)
            if loud:
                say(f'# r{r}: kept after {a.redo or a.run_redo} redos although a run saw the others above the limit')
            break
    say(f'# summary {name}: median MC/s [min-max], median paired ratio to c0 [min-max], others cpu/gpu median, result')
    for i, c in enumerate(cfgs):
        v = [x[0] for x in res[c]]
        q = [x[0] / y[0] for x, y in zip(res[c], res[cfgs[0]])]
        cpu = statistics.median(x[1] for x in res[c])
        gpu = statistics.median(x[2] for x in res[c])
        diffs = sorted(set(x[3] for x in res[c]))
        say(f'c{i} {c:60s} {statistics.median(v):8.1f} [{min(v):.0f}-{max(v):.0f}]  x{statistics.median(q):.3f} '
            f'[{min(q):.3f}-{max(q):.3f}]  others {cpu:.0f}%/{gpu:.0f}%  {",".join(diffs)}')
    if a.out:
        with open(a.out, 'a') as fh:
            fh.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
