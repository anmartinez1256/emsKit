"""Test model for the Swift/Metal engine: PEC box, dielectric slab with a metal patch, soft E-field excitation.
Only the excitation extension is active, so the exported operator fully describes the run.

  python3 model.py SIM_DIR --n 61 --nrts 300 [--threads 4] [--engine multithreaded]     (--n must be odd)
Writes the raw operator to SIM_DIR/op and the CPU engine's fields after the run to SIM_DIR/fields_cpu
(our openEMS fork: OPENEMS_EXPORT_OPERATOR / OPENEMS_EXPORT_FIELDS).
"""
import argparse, os, sys
import numpy as np
from CSXCAD import ContinuousStructure
from openEMS import openEMS

ap = argparse.ArgumentParser()
ap.add_argument('sim_dir')
ap.add_argument('--n', type=int, default=41, help='mesh lines per axis (odd, so z=0 is a mesh line)')
ap.add_argument('--nrts', type=int, default=300)
ap.add_argument('--threads', type=int, default=4)
ap.add_argument('--engine', default='multithreaded')
ap.add_argument('--no-export', action='store_true')
a = ap.parse_args()
if a.n % 2 == 0:
    sys.exit('--n must be odd (the patch sits on z=0)')

sim = os.path.abspath(a.sim_dir)
os.makedirs(sim, exist_ok=True)
if not a.no_export:
    for d in ('op', 'fields_cpu'):
        os.makedirs(os.path.join(sim, d), exist_ok=True)
    os.environ['OPENEMS_EXPORT_OPERATOR'] = os.path.join(sim, 'op')
    os.environ['OPENEMS_EXPORT_FIELDS'] = os.path.join(sim, 'fields_cpu')

FDTD = openEMS(NrTS=a.nrts, EndCriteria=0)
FDTD.SetGaussExcite(2e9, 1e9)
FDTD.SetBoundaryCond(['PEC']*6)
CSX = ContinuousStructure()
FDTD.SetCSX(CSX)
mesh = CSX.GetGrid()
mesh.SetDeltaUnit(1e-3)
L = 100.0  # mm box
lines = np.linspace(-L/2, L/2, a.n)
mesh.AddLine('x', lines); mesh.AddLine('y', lines); mesh.AddLine('z', lines)

sub = CSX.AddMaterial('substrate', epsilon=3.38, kappa=1e-3)
sub.AddBox(priority=0, start=[-30, -30, -5], stop=[30, 30, 0])
patch = CSX.AddMetal('patch')
patch.AddBox(priority=10, start=[-16, -20, 0], stop=[16, 20, 0])
exc = CSX.AddExcitation('exc', exc_type=0, exc_val=[0, 0, 1])
exc.AddBox(start=[-6, -2, -5], stop=[-4, 2, 0])

FDTD.Run(sim, cleanup=False, verbose=0, engine=a.engine, numThreads=a.threads)
