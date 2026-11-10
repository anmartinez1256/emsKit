"""run_cyl.py SIM_DIR NRTS THREADS: CylindricalWave_CC tutorial (cylindrical multigrid), fixed timesteps, an FD HDF5
dump (Ef_ra) and a TD HDF5 dump (Et_ra) in SIM_DIR. Compare two runs with scripts/checks/h5cmp.py to check one library
against another, or one thread count against another; a cylindrical mesh always runs the cylindrical multithreaded
engine, so there is no engine choice here.

Derived from openEMS python/Tutorials/CylindricalWave_CC.py, (c) 2026 Thorsten Liebig <thorsten.liebig@gmx.de>.
openEMS is free software under the GNU General Public License, version 3 or (at your option) any later version, and
comes WITHOUT ANY WARRANTY; this file is distributed under the same terms (LICENSE in emsKit). Modified for emsKit,
2026: a fixed step count instead of the end criterion, the time-domain dump written as HDF5 instead of VTK, no
post-processing or plots, command-line arguments."""
import sys, numpy as np
from CSXCAD import ContinuousStructure
from CSXCAD.CSRectGrid import CoordinateSystem
from openEMS import openEMS
sim, nrts, thr = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
unit, mesh_res, radius, split = 1e-3, 10, 2560, [80, 160, 320, 640, 1280]
height, f0, excite_offset, excite_angle = mesh_res*4, 1e9, 1300, 45
FDTD = openEMS(NrTS=nrts, EndCriteria=0, CoordSystem=1, MultiGrid=split)
FDTD.SetGaussExcite(f0, f0/2)
FDTD.SetBoundaryCond([0, 3, 0, 0, 0, 0])
CSX = ContinuousStructure(CoordSystem=CoordinateSystem.CYLINDRICAL)
FDTD.SetCSX(CSX)
mesh = CSX.GetGrid(); mesh.SetDeltaUnit(unit)
mesh.SetLines('r', [0, radius]); mesh.SmoothMeshLines('r', mesh_res)
mesh.SetLines('a', np.linspace(-np.pi, np.pi, 50 * 2**len(split) + 1))
mesh.SetLines('z', [-height/2, 0, height/2]); mesh.SmoothMeshLines('z', mesh_res)
r, a = mesh.GetLines('r'), mesh.GetLines('a')
exc = CSX.AddExcitation('excite', exc_type=1, exc_val=[0, 0, 1])
exc.AddBox([excite_offset, excite_angle/180*np.pi - 0.001, -20], [excite_offset, excite_angle/180*np.pi + 0.001, 20])
Ef = CSX.AddDump('Ef_ra', dump_type=10, file_type=1, sub_sampling=[2, 2, 2]); Ef.SetFrequency([f0])
Ef.AddBox([r[0], a[0], 0], [r[-9], a[-1], 0])
Et = CSX.AddDump('Et_ra', dump_type=0, file_type=1, sub_sampling=[4, 10, 1])
Et.AddBox([r[0], a[0], 0], [r[-9], a[-1], 0])
FDTD.Run(sim, cleanup=True, numThreads=thr)
