"""ss_box.py SIM_DIR MAX_TS THREADS [F0_GHZ [END_CRITERION]]: a Mur box with a dielectric block and a sinusoidal excitation, so the run has the
steady-state detection (it exists for every sinusoidal run) and stops by it (END_CRITERION, default 1e-2) before MAX_TS. Probes on mesh
lines; prints the probe peaks and the number of timesteps run. For the tiled sweep (OPENEMS_TBLOCK) against the fused one."""
import sys, os, re, numpy as np
from CSXCAD import ContinuousStructure
from openEMS import openEMS
sim, nrts, thr = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
f0 = float(sys.argv[4])*1e9 if len(sys.argv) > 4 else 6e9
crit = float(sys.argv[5]) if len(sys.argv) > 5 else 1e-2
FDTD = openEMS(NrTS=nrts, EndCriteria=crit)
FDTD.SetSinusExcite(f0)
FDTD.SetBoundaryCond(['MUR']*6)
CSX = ContinuousStructure(); FDTD.SetCSX(CSX)
mesh = CSX.GetGrid(); mesh.SetDeltaUnit(1e-3)
mesh.SetLines('x', np.linspace(-40, 40, 81)); mesh.SetLines('y', np.linspace(-25, 25, 51)); mesh.SetLines('z', np.linspace(-20, 20, 41))
x, y, z = mesh.GetLines('x'), mesh.GetLines('y'), mesh.GetLines('z')
CSX.AddMaterial('block', epsilon=2.6, kappa=0.02).AddBox([x[50], y[10], z[8]], [x[66], y[40], z[30]])
CSX.AddExcitation('excite', exc_type=0, exc_val=[0, 0, 1]).AddBox([x[24], y[25], z[16]], [x[24], y[25], z[24]])
CSX.AddProbe('port_ut1', 0).AddBox([x[40], y[25], z[16]], [x[40], y[25], z[24]])
CSX.AddProbe('port_ut2', 0).AddBox([x[58], y[20], z[12]], [x[58], y[20], z[26]])
CSX.AddProbe('port_ut3', 0).AddBox([x[2], y[30], z[18]], [x[2], y[30], z[22]])
CSX.AddProbe('port_ut4', 0).AddBox([x[77], y[12], z[20]], [x[79], y[12], z[20]])
sim = os.path.abspath(sim)
FDTD.Run(sim, cleanup=True, numThreads=thr, verbose=1)
for k in (1, 2, 3, 4):
    d = np.loadtxt(os.path.join(sim, 'port_ut%d' % k), comments='%')
    print('probe %d: %d samples, peak %.6e, last t %.9e' % (k, len(d), np.abs(d[:, 1]).max(), d[-1, 0]))
