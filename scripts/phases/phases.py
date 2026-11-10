"""Time the non-engine phases of an openEMS job: python model build (CSXCAD), FDTD.Run setup
(operator creation, dump init, end processing) and the post-processing (CalcPort, CalcNF2FF).

  python3 phases.py MODEL SCALE RUN_DIR_WITH_DUMPS
RUN_DIR_WITH_DUMPS is a finished bench run (its port and nf2ff dump files are reused).
"""
import os, re, sys, time, io, contextlib
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'bench'))   # the harness's models.py
from models import MODELS

model, scale = sys.argv[1], float(sys.argv[2])
run_dir = os.path.abspath(sys.argv[3])   # FDTD.Run changes into its own directory
tmp = os.path.join(os.path.dirname(os.path.abspath(__file__)), f'tmp_{model}_{scale:g}')

t0 = time.time()
if model == 'patch':
    FDTD, ports, f = MODELS[model](nrts=10, scale=scale, nf2ff=False)
    nf = FDTD.CreateNF2FFBox()
else:
    FDTD, ports, f = MODELS[model](nrts=10, scale=scale)
t_build = time.time() - t0

t0 = time.time()
buf = io.StringIO()
# openEMS prints from C++; capture via a pipe on fd 1
r, w = os.pipe()
saved = os.dup(1); os.dup2(w, 1)
try:
    FDTD.Run(tmp, cleanup=True, engine='multithreaded', numThreads=4)
finally:
    os.dup2(saved, 1); os.close(w)
log = os.read(r, 1 << 20).decode()
t_run = time.time() - t0
m = re.search(r'Time for (\d+) iterations with ([\d.eE+-]+) cells : ([\d.eE+-]+) sec', log)
t_eng = float(m[3])
cells = float(m[2])

t0 = time.time()
for p in ports:
    p.CalcPort(run_dir, f, ref_impedance=50)
t_port = time.time() - t0

print(f'{model} x{scale:g}  {cells/1e6:.2f} MC  build(CSXCAD py) {t_build:.2f} s  '
      f'Run(10 TS) {t_run:.2f} s of which engine {t_eng:.2f} -> setup+end {t_run-t_eng:.2f} s  '
      f'CalcPort {t_port:.2f} s')

if model == 'patch':
    f_res = 2.4e9
    theta = np.arange(-180.0, 180.0, 2.0)
    t0 = time.time()
    nf.CalcNF2FF(run_dir, f_res, theta, [0., 90.], center=[0, 0, 1e-3], read_cached=False, verbose=0,
                 outfile='nf2ff_2cuts.h5')
    t_cuts = time.time() - t0
    t0 = time.time()
    nf.CalcNF2FF(run_dir, f_res, np.arange(0, 182, 2.0), np.arange(0, 362, 2.0), center=[0, 0, 1e-3],
                 read_cached=False, verbose=0, outfile='nf2ff_3d.h5')
    t_3d = time.time() - t0
    print(f'   nf2ff: 2 cuts (360 pts) {t_cuts:.2f} s   3D (91x181) {t_3d:.2f} s')
