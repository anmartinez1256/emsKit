"""box.py NX NY NZ NRTS THREADS OUT_DIR: PEC box with a dielectric slab and one soft excitation, uniform 1 mm mesh.
Prints the engine speed. Used to test how the mesh shape (thin z) affects the CPU engine."""
import os, sys
import numpy as np
from CSXCAD import ContinuousStructure
from openEMS import openEMS

nx, ny, nz, nrts, thr = map(int, sys.argv[1:6])
out = os.path.abspath(sys.argv[6])
FDTD = openEMS(NrTS=nrts, EndCriteria=0)
FDTD.SetGaussExcite(2e9, 1e9)
FDTD.SetBoundaryCond(['PEC']*6)
CSX = ContinuousStructure()
FDTD.SetCSX(CSX)
mesh = CSX.GetGrid()
mesh.SetDeltaUnit(1e-3)
mesh.AddLine('x', np.arange(nx)); mesh.AddLine('y', np.arange(ny)); mesh.AddLine('z', np.arange(nz))
sub = CSX.AddMaterial('substrate', epsilon=3.38, kappa=1e-3)
sub.AddBox(priority=0, start=[0, 0, 0], stop=[nx-1, ny-1, min(4, nz-1)])
if os.environ.get('DRUDE'):   # a Drude/Lorentz block (eps plasma + pole, mue plasma) to exercise the dispersive extension
    from CSXCAD.CSProperties import CSPropLorentzMaterial
    lor = CSPropLorentzMaterial(CSX.GetParameterSet(), epsilon=2.0, mue=1.0)
    lor.SetName('drude')
    lor.SetDispersionOrder(1)
    lor.SetDispersiveMaterialProperty(0, eps_plasma=4e9, eps_pole_freq=2.5e9, eps_relax=2e-10, mue_plasma=3e9, mue_relax=3e-10)
    CSX.AddProperty(lor)
    lor.AddBox(priority=5, start=[nx//4, ny//4, min(5, nz-1)], stop=[nx//2, ny//2, min(9, nz-1)])
    drude2 = CSPropLorentzMaterial(CSX.GetParameterSet(), epsilon=1.5)
    drude2.SetName('drude2')   # plasma only (no Lorentz pole: the other branch of the hooks)
    drude2.SetDispersionOrder(1)
    drude2.SetDispersiveMaterialProperty(0, eps_plasma=3e9, eps_relax=1e-10)
    CSX.AddProperty(drude2)
    drude2.AddBox(priority=5, start=[nx//2+2, ny//4, min(5, nz-1)], stop=[3*nx//4, ny//2, min(9, nz-1)])
if os.environ.get('DEBYE'):   # a two-pole Debye block (2026-11-02: a review found its Pre/Post hooks skipped by the multithreaded engine)
    from CSXCAD.CSProperties import CSPropDebyeMaterial
    deb = CSPropDebyeMaterial(CSX.GetParameterSet(), epsilon=2.5, kappa=0.0)
    deb.SetName('debye')
    deb.SetDispersionOrder(2)
    deb.SetDispersiveMaterialProperty(0, eps_delta=1.5, eps_relax=5e-11)
    deb.SetDispersiveMaterialProperty(1, eps_delta=0.7, eps_relax=2e-10)
    CSX.AddProperty(deb)
    deb.AddBox(priority=5, start=[nx//4, ny//4, min(5, nz-1)], stop=[nx//2, ny//2, min(9, nz-1)])
exc = CSX.AddExcitation('exc', exc_type=0, exc_val=[0, 0, 1])
exc.AddBox(start=[nx//2, ny//2-1, 0], stop=[nx//2+1, ny//2+1, min(4, nz-1)])
FDTD.Run(out, cleanup=True, engine=os.environ.get('ENG','multithreaded'), numThreads=thr)
