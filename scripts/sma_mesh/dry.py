"""dry.py FLOOR [FLOOR ...]: build the SMA launch with each min_cell floor, run 400 timesteps, report lines, cells,
smallest cells per axis (with positions) and the time step openEMS picks."""
import glob, os, shutil, sys
import numpy as np
if "RFSIM_PATH" not in os.environ:
    raise KeyError("RFSIM_PATH is not set: point it at the rfsim toolkit directory (the folder that contains rfsim/)")
sys.path.insert(0, os.environ["RFSIM_PATH"])
from rfsim.openems import core, launch

here = os.path.dirname(os.path.abspath(__file__))
for fl in sys.argv[1:]:
    m = launch.sma_launch(P={"min_cell": float(fl)})
    L = {a: np.array(m.mesh.GetLines(a)) for a in "xyz"}
    out = os.path.join(here, f"dry_{fl}")
    shutil.rmtree(out, ignore_errors=True)
    m.fdtd.SetNumberOfTimeSteps(400); m.fdtd.SetMaxTime(0)
    core.run(m, out, threads=4, probe_end_db=None)
    print(f"\n=== min_cell {fl}: lines x/y/z {len(L['x'])}/{len(L['y'])}/{len(L['z'])}, cells {m.info['cells']/1e6:.3f} M "
          "(dt: see the 'FDTD timestep is' line above)")
    for a in "xyz":
        d = np.diff(L[a]); i = np.argsort(d)[:6]
        print(f"  {a}: smallest cells " + ", ".join(f"{d[k]:.4f}@{L[a][k]:+.3f}" for k in sorted(i, key=lambda k: d[k])))
