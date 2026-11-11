#!/usr/bin/env python3
"""Write the benchmark model of luikore's bench_metal.py (uniform 1 mm grid, PEC walls, one dielectric box, Gaussian
0-5 GHz excitation of one cell with direction (1,1,1)); no dumps (their bench strips them); plus one voltage probe.
usage: model.py OUT.xml NX NY NZ STEPS"""
import sys, numpy as np
from CSXCAD import ContinuousStructure
from openEMS import openEMS
out, cells, steps = sys.argv[1], tuple(int(v) for v in sys.argv[2:5]), int(sys.argv[5])
csx = ContinuousStructure(); fdtd = openEMS(NrTS=steps, EndCriteria=0); fdtd.SetCSX(csx)
fdtd.SetBoundaryCond(['PEC']*6); fdtd.SetGaussExcite(0, 5e9)
g = csx.GetGrid(); g.SetDeltaUnit(1e-3)
for a, n in zip('xyz', cells):
    g.SetLines(a, np.arange(n + 1, dtype=float))
c = np.asarray(cells, dtype=float)/2
csx.AddExcitation('excite', 0, [1, 1, 1]).AddBox(c, c + 1)
csx.AddMaterial('dielectric', epsilon=3.66, kappa=0.02).AddBox(np.asarray(cells)*0.2, np.asarray(cells)*0.45)
csx.AddProbe('ut1', 0).AddBox([c[0] + 6, c[1], c[2]], [c[0] + 6, c[1], c[2] + 3])
fdtd.Write2XML(out)
