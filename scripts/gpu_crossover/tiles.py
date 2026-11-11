"""tiles.py OUTDIR MODEL:SCALE[:STEPS] ...: one short metal-diamond run per point (verbose=1, 100 steps) to record the GPU
engine's grid and the tile counts of the tuner's tilings (four up to patch 0037, seven since 0038; 'Engine_Metal_Diamond: ... cells ... tiles ...') in
OUTDIR/MODEL_sSCALE.txt, which analyze.py reads. Run with DYLD_LIBRARY_PATH set to the snapshot and a python3 that keeps it
(not /usr/bin/python3); RFSIM_PATH for kgcpw. The timing of these runs means nothing."""
import os, subprocess, sys
bench = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'bench')
outdir = os.path.abspath(sys.argv[1])
for spec in sys.argv[2:]:
    name, s = spec.split(':')[:2]                # MODEL:SCALE, or sweep.sh's MODEL:SCALE:STEPS
    d = os.path.join(outdir, f'{name}_s{s}')
    os.makedirs(d, exist_ok=True)
    code = f"""
import os, sys
sys.path.insert(0, {bench!r})
from models import MODELS
FDTD = MODELS['{name}'](nrts=100, scale={s})[0]
FDTD.Run({d!r}, engine='metal-diamond', verbose=1)
"""
    p = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True, cwd=d)
    lines = [l for l in (p.stdout + p.stderr).splitlines() if 'Engine_Metal_Diamond' in l or 'libopenEMS' in l]
    print(f'== {name} s{s} (exit {p.returncode})')
    for l in lines:
        print('  ' + l)
    with open(os.path.join(outdir, f'{name}_s{s}.txt'), 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
