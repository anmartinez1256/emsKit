#!/usr/bin/env python3
"""Run one model in-process with FDTD.Run(), as the tutorials do.

  python3 runner.py MODEL SIM_DIR --nrts N [--scale S] [--engine E] [--threads T] [--nodumps]

Not via Write2XML + the openEMS binary: Write2XML stores primitive coordinates with ~7
significant digits but mesh lines with 15, so with openEMS v0.37.0 / CSXCAD v0.7.0 and this fork
zero-thickness boxes (e.g. the MSL port excitation plane) no longer sit on their mesh line and
are dropped as "Unused primitive" (upstream master added a drawing tolerance on 2026-10-21 that
covers this).
Before the run it prints one 'BENCH_LIB path' line per loaded openEMS library (libinfo.py);
bench.py checks them.
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from models import MODELS
from libinfo import loaded_libs

ap = argparse.ArgumentParser()
ap.add_argument('model', choices=MODELS)
ap.add_argument('sim_dir')
ap.add_argument('--nrts', type=int)
ap.add_argument('--scale', type=float, default=1.0)
ap.add_argument('--engine', default='fastest')
ap.add_argument('--threads', type=int, default=0)
ap.add_argument('--nodumps', action='store_true')
ap.add_argument('--end-crit', type=float, help='use this end criterion instead of fixed --nrts work')
a = ap.parse_args()

FDTD, _, _ = MODELS[a.model](nrts=a.nrts if a.end_crit is None else None, scale=a.scale)
if a.end_crit is not None:
    FDTD.SetEndCriteria(a.end_crit)
    if a.nrts:
        FDTD.SetNumberOfTimeSteps(a.nrts)
if os.environ.get('OPENEMS_BENCH_BC'):   # experiment: override the boundaries of any model, e.g. PML_8;PML_8;...
    FDTD.SetBoundaryCond(os.environ['OPENEMS_BENCH_BC'].split(';'))
for p in loaded_libs():
    print('BENCH_LIB', p, flush=True)
kw = dict(engine=a.engine)
if a.threads:
    kw['numThreads'] = a.threads
if a.nodumps:
    kw['disable_dumps'] = True
FDTD.Run(os.path.abspath(a.sim_dir), cleanup=True, **kw)
