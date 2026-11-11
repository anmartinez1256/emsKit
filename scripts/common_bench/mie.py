#!/usr/bin/env python3
"""Backscatter of a PEC sphere against the Mie series. Model = openEMS Tutorials/RCS_Sphere.py
((c) 2016-2023 Thorsten Liebig, GPL-3.0-or-later): radius 200 mm, plane wave (total-field/scattered-field box),
PML_8, nf2ff box; cell = lambda/RES at 1 GHz.   usage: mie.py RES OUT.npz [ENGINE [THREADS]]"""
import os, sys, time, shutil, numpy as np
from scipy.special import spherical_jn as jn, spherical_yn as yn
from CSXCAD import ContinuousStructure
from openEMS import openEMS
from openEMS.physical_constants import C0, Z0
from openEMS.ports import UI_data

res, out = float(sys.argv[1]), sys.argv[2]
engine = sys.argv[3] if len(sys.argv) > 3 else 'multithreaded'
threads = int(sys.argv[4]) if len(sys.argv) > 4 else 8
out = os.path.abspath(out); sim = out + '.run'
unit, a_mm, SimBox, PW_Box = 1e-3, 200, 1200, 750
f_start, f_stop, f0 = 50e6, 1000e6, 500e6
nr = int(os.environ.get('MIE_NRTS', 0)); FDTD = openEMS(NrTS=nr, EndCriteria=0) if nr else openEMS(EndCriteria=1e-5)
FDTD.SetGaussExcite(0.5*(f_start+f_stop), 0.5*(f_stop-f_start))
FDTD.SetBoundaryCond(['PML_8']*6)
CSX = ContinuousStructure(); FDTD.SetCSX(CSX)
mesh = CSX.GetGrid(); mesh.SetDeltaUnit(unit)
mesh.SetLines('x', [-SimBox/2, 0, SimBox/2]); mesh.SmoothMeshLines('x', C0/f_stop/unit/res)
mesh.SetLines('y', mesh.GetLines('x')); mesh.SetLines('z', mesh.GetLines('x'))
CSX.AddMetal('sphere').AddSphere(priority=10, center=[0, 0, 0], radius=a_mm)
E_dir = [0, 0, 1]
pw = CSX.AddExcitation('plane_wave', exc_type=10, exc_val=E_dir)
pw.SetPropagationDir([1, 0, 0]); pw.SetFrequency(f0)
pw.AddBox([-PW_Box/2]*3, [PW_Box/2]*3)
nf2ff = FDTD.CreateNF2FFBox()
t0 = time.time()
FDTD.Run(sim, cleanup=True, engine=engine, numThreads=threads)
wall = time.time() - t0
freq = np.linspace(f_start, f_stop, 100)
ef = UI_data('et', sim, freq)
Pin = 0.5/Z0*abs(np.array(ef.ui_f_val[0]))**2
r = nf2ff.CalcNF2FF(sim, freq, 90, 180, outfile='back_nf2ff.h5')
sim_rcs = np.array([4*np.pi/Pin[i]*r.P_rad[i][0][0] for i in range(len(freq))])
a = a_mm*unit
def mie(ka, N=60):
    s = 0
    for n in range(1, N+1):
        h = jn(n, ka) - 1j*yn(n, ka); dh = jn(n, ka, True) - 1j*yn(n, ka, True)
        s += (-1)**n*(2*n+1)*(jn(n, ka)/h - (jn(n, ka) + ka*jn(n, ka, True))/(h + ka*dh))
    return abs(s)**2/ka**2
ka = 2*np.pi*freq/C0*a
ref = np.array([mie(k) for k in ka])*np.pi*a*a
et = np.loadtxt(os.path.join(sim, 'et'), comments='%')
np.savez(out, freq=freq, ka=ka, sim=sim_rcs, mie=ref, et=et, cells=mesh.GetQtyLines('x')**3, wall=wall)
db = 10*np.log10(sim_rcs/ref)
m = ka > 0.4       # below that the RCS is < -20 dB of pi a^2 and the Gaussian pulse has little energy
print(f'RES {res:g} lines/axis {mesh.GetQtyLines("x")} steps {len(et)} wall {wall:.1f} s')
print(f'error vs Mie, ka {ka[m][0]:.2f}..{ka[-1]:.2f}: mean |dB| {abs(db[m]).mean():.3f}, max |dB| {abs(db[m]).max():.3f} at ka {ka[m][abs(db[m]).argmax()]:.2f}; all points max {abs(db).max():.3f}')
shutil.rmtree(sim, ignore_errors=True)
