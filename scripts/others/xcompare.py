#!/usr/bin/env python3
"""Compare the port probes and S-parameters of runs from different builds with one reference run.
(bench.py compares only the runs of one call, which all use one build's Python modules.)

  python3 xcompare.py MODEL --nrts N [--scale S] REF_DIR RUN_DIR [RUN_DIR ...]

REF_DIR and every RUN_DIR are run folders written by bench.py (.../CONFIG/rep0). The S-parameters of all folders
are computed with the modules this interpreter imports (the model is rebuilt for its ports), so every folder is
evaluated the same way. Per run, bench.py's figures: probes rel = max over the port files of
max|v - v_ref| / max|v_ref|, and per S-parameter max|dS| (linear) and the max dB difference over the frequencies
where |S_ref| > -40 dB. A missing folder (a run that failed) is named and skipped.
"""
import argparse, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'bench'))
from bench import probe_diff, compare
from models import MODELS, sparams

ap = argparse.ArgumentParser()
ap.add_argument('model', choices=MODELS)
ap.add_argument('--nrts', type=int, required=True)
ap.add_argument('--scale', type=float, default=1.0)
ap.add_argument('ref')
ap.add_argument('runs', nargs='+')
a = ap.parse_args()

ref_s = sparams(a.model, a.ref, nrts=a.nrts, scale=a.scale)
print(f'# {a.model}_s{a.scale:g}_n{a.nrts}  reference {a.ref}', flush=True)
for d in a.runs:
    label = os.path.relpath(d, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(d)))))
    if not os.path.isdir(d):
        print(f'{label:60s} MISSING (the run failed or was not made)', flush=True)
        continue
    rel, zero, problems = probe_diff(d, a.ref)
    line = f'{label:60s} probes rel={rel:.1e}'
    if zero:
        line += f' ({len(zero)} files all zero in the reference)'
    if problems:
        line += '  PROBLEM: ' + '; '.join(problems)
    else:
        for k, (exact, dS, dB) in compare(sparams(a.model, d, nrts=a.nrts, scale=a.scale), ref_s).items():
            if exact:
                line += f'  {k}: identical'
            elif dB is None:
                line += f'  {k}: below -40 dB, max|dS|={dS:.1e}'
            else:
                line += f'  {k}: max|dS|={dS:.1e} max dB={dB:.1e}'
    print(line, flush=True)
