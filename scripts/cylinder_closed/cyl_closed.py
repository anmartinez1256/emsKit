"""cyl_closed.py SIM_DIR NRTS THREADS [R0]: a closed cylindrical mesh (alpha all around), with r = 0 when R0 is 0, a dielectric
ring, a z-directed excitation off the axis, PEC walls except MUR at z-max; five voltage probes and one current probe, on the axis, the alpha seam
and beside it; fixed step count. The source and the probes sit on mesh lines."""
import sys, os, numpy as np
from CSXCAD import ContinuousStructure
from CSXCAD.CSRectGrid import CoordinateSystem
from openEMS import openEMS
sim, nrts, thr = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
r0 = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
FDTD = openEMS(NrTS=nrts, EndCriteria=0, CoordSystem=1)
FDTD.SetGaussExcite(1e9, 0.5e9)
FDTD.SetBoundaryCond([0, 0, 0, 0, 0, 2])
CSX = ContinuousStructure(CoordSystem=CoordinateSystem.CYLINDRICAL)
FDTD.SetCSX(CSX)
mesh = CSX.GetGrid(); mesh.SetDeltaUnit(1e-3)
mesh.SetLines('r', np.linspace(r0, 300, 61))
mesh.SetLines('a', np.linspace(-np.pi, np.pi, 73))
mesh.SetLines('z', np.linspace(-100, 100, 41))
CSX.AddMaterial('ring', epsilon=3.2, kappa=0.01).AddBox([120, -np.pi, -40], [200, np.pi, 30])
r, a, z = mesh.GetLines('r'), mesh.GetLines('a'), mesh.GetLines('z')
exc = CSX.AddExcitation('excite', exc_type=0, exc_val=[0, 0, 1])
exc.AddBox([r[12], a[41], z[16]], [r[12], a[41], z[24]])
CSX.AddProbe('port_ut1', 0).AddBox([r[30], a[25], z[18]], [r[30], a[25], z[22]])
CSX.AddProbe('port_ut2', 0).AddBox([r[0], a[0], z[14]], [r[0], a[0], z[26]])                 # on the axis when r0 = 0
CSX.AddProbe('port_ut3', 0).AddBox([r[8], a[0], z[14]], [r[8], a[0], z[26]])                 # on the alpha seam
CSX.AddProbe('port_ut4', 0).AddBox([r[1], a[70], z[20]], [r[16], a[70], z[20]])              # radial, next to the seam
CSX.AddProbe('port_ut5', 0).AddBox([r[20], a[68], z[20]], [r[20], a[71], z[20]])             # along alpha up to the seam
CSX.AddProbe('port_it1', 1).AddBox([r[20], a[69], z[19]], [r[28], a[71], z[21]])             # a current loop at the seam
FDTD.Run(os.path.abspath(sim), cleanup=True, numThreads=thr, verbose=1)
