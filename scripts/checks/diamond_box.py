"""diamond_box.py: the test model of diamond_check.sh (the diamond-blocked Metal engine). A box with a dielectric slab,
a soft E excitation, optionally a delayed E excitation (--delay), a soft H excitation (--hexc) and an E excitation on
the x-min Mur plane (--murexc), lumped RLC elements (--rlc, parallel and series), Drude/Lorentz blocks (--drude), conducting sheets (--sheet), a Debye block (--debye); boundaries --bc pec | mur | mixed (MUR, PEC,
PEC, MUR, MUR, PMC) | pml (PML_8 on all six faces) | pmlmix (PML_8, MUR, PEC, PML_8, MUR, PML_8: Mur faces that cross the PML
boxes). Writes the fields after the run to OUT_DIR (OPENEMS_EXPORT_FIELDS, fork only).
  python3 diamond_box.py SIM_DIR OUT_DIR --n 41,37,30 --nrts 300 --bc mur --engine metal-diamond [--hexc] [--delay]"""
import argparse, os, sys
import numpy as np
from CSXCAD import ContinuousStructure
from openEMS import openEMS
ap = argparse.ArgumentParser()
ap.add_argument('sim_dir'); ap.add_argument('out_dir')
ap.add_argument('--n', default='41,41,41')
ap.add_argument('--nrts', type=int, default=300)
ap.add_argument('--threads', type=int, default=4)
ap.add_argument('--engine', default='multithreaded')
ap.add_argument('--bc', default='pec')
ap.add_argument('--hexc', action='store_true')
ap.add_argument('--delay', action='store_true')
ap.add_argument('--murexc', action='store_true', help='an excitation on the x-min Mur plane')
ap.add_argument('--rlc', action='store_true', help='a parallel RLC (z), a series RLC (x) and a series LC (y) lumped element')
ap.add_argument('--drude', action='store_true', help='two Drude/Lorentz blocks (eps plasma + pole + mue plasma; eps plasma only)')
ap.add_argument('--sheet', action='store_true', help='two conducting sheets (a z plane and an x plane)')
ap.add_argument('--debye', action='store_true', help='a two-pole Debye block')
a = ap.parse_args()
nx, ny, nz = [int(v) for v in a.n.split(',')]
sim = os.path.abspath(a.sim_dir); out = os.path.abspath(a.out_dir)
os.makedirs(sim, exist_ok=True); os.makedirs(out, exist_ok=True)
os.environ['OPENEMS_EXPORT_FIELDS'] = out
FDTD = openEMS(NrTS=a.nrts, EndCriteria=0)
FDTD.SetGaussExcite(2e9, 1e9)
bc = {'pec': ['PEC']*6, 'mur': ['MUR']*6, 'pml': ['PML_8']*6, 'pmlmix': ['PML_8', 'MUR', 'PEC', 'PML_8', 'MUR', 'PML_8'], 'mixed': ['MUR', 'PEC', 'PEC', 'MUR', 'MUR', 'PMC']}[a.bc]
FDTD.SetBoundaryCond(bc)
CSX = ContinuousStructure(); FDTD.SetCSX(CSX)
mesh = CSX.GetGrid(); mesh.SetDeltaUnit(1e-3)
L = 100.0
mesh.AddLine('x', np.linspace(-L/2, L/2, nx)); mesh.AddLine('y', np.linspace(-L/2*0.9, L/2*0.9, ny))
mesh.AddLine('z', np.linspace(-L/2*0.7, L/2*0.7, nz))
sub = CSX.AddMaterial('substrate', epsilon=3.38, kappa=1e-3)
sub.AddBox(priority=0, start=[-30, -30, -8], stop=[30, 30, 0])
patch = CSX.AddMetal('patch'); patch.AddBox(priority=10, start=[-16, -20, 0], stop=[16, 20, 0])
exc = CSX.AddExcitation('exc', exc_type=0, exc_val=[0, 0, 1])
exc.AddBox(start=[-6, -2, -8], stop=[-4, 2, 0])
if a.delay:
    e2 = CSX.AddExcitation('exc2', exc_type=0, exc_val=[1, 0.5, 0], delay=0.4e-9)
    e2.AddBox(start=[10, 10, 10], stop=[20, 14, 12])
if a.hexc:
    e3 = CSX.AddExcitation('exch', exc_type=2, exc_val=[0, 1, 0])
    e3.AddBox(start=[-20, 5, 5], stop=[-15, 8, 9])
if a.rlc:
    p1 = CSX.AddLumpedElement('rlc_par', ny=2, caps=True, R=100, L=5e-9, C=1e-12, LEtype=0)
    p1.AddBox(start=[6, -10, -6], stop=[6, -10, 6])
    p2 = CSX.AddLumpedElement('rlc_ser', ny=0, caps=True, R=20, L=2e-9, C=2e-12, LEtype=1)
    p2.AddBox(start=[-12, 12, 3], stop=[0, 12, 3])
    p3 = CSX.AddLumpedElement('lc_ser', ny=1, caps=True, L=1e-9, C=5e-13, LEtype=1)
    p3.AddBox(start=[20, -8, -3], stop=[20, 8, -3])
if a.drude:
    from CSXCAD.CSProperties import CSPropLorentzMaterial
    lor = CSPropLorentzMaterial(CSX.GetParameterSet(), epsilon=2.0, mue=1.0)
    lor.SetName('drude')
    lor.SetDispersionOrder(1)
    lor.SetDispersiveMaterialProperty(0, eps_plasma=4e9, eps_pole_freq=2.5e9, eps_relax=2e-10, mue_plasma=3e9, mue_relax=3e-10)
    CSX.AddProperty(lor)
    lor.AddBox(priority=5, start=[-28, -26, 2], stop=[-8, -6, 14])
    drude2 = CSPropLorentzMaterial(CSX.GetParameterSet(), epsilon=1.5)
    drude2.SetName('drude2')   # plasma only (no Lorentz pole: the other branch of the hooks)
    drude2.SetDispersionOrder(1)
    drude2.SetDispersiveMaterialProperty(0, eps_plasma=3e9, eps_relax=1e-10)
    CSX.AddProperty(drude2)
    drude2.AddBox(priority=5, start=[4, -26, 2], stop=[24, -6, 14])
if a.debye:
    from CSXCAD.CSProperties import CSPropDebyeMaterial
    deb = CSPropDebyeMaterial(CSX.GetParameterSet(), epsilon=2.5, kappa=0.0)
    deb.SetName('debye')
    deb.SetDispersionOrder(2)
    deb.SetDispersiveMaterialProperty(0, eps_delta=1.5, eps_relax=5e-11)
    deb.SetDispersiveMaterialProperty(1, eps_delta=0.7, eps_relax=2e-10)
    CSX.AddProperty(deb)
    deb.AddBox(priority=6, start=[-24, 4, -20], stop=[-4, 24, -2])
if a.sheet:
    sh = CSX.AddConductingSheet('sheet', conductivity=5.8e7, thickness=35e-6)
    sh.AddBox(priority=20, start=[2, 4, 6], stop=[28, 26, 6])
    sh.AddBox(priority=20, start=[-30, 6, -12], stop=[-30, 26, 12])
if a.murexc:
    e4 = CSX.AddExcitation('excm', exc_type=0, exc_val=[0, 1, 1])
    e4.AddBox(start=[-L/2, -5, -5], stop=[-L/2, 5, 5])
FDTD.Run(sim, cleanup=True, verbose=1, engine=a.engine, numThreads=a.threads)
