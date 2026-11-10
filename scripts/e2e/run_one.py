"""run_one.py MODEL FLOOR DB HOLD OUT: one full rfsim run, the way the author's toolkit runs a board (core.run, threads=0).

MODEL gcpw | sma; FLOOR = SMA mesh floor min_cell in mm (0 = the toolkit default); DB = 'off' or e.g. -60;
HOLD in excitation lengths. Writes OUT/ (the run dir) and OUT/result.json: cells, the time of the three phases
(model build in Python, FDTD.Run incl. operator setup, post-processing = CalcPort for S11/S21 + Z0), m.info.
openEMS's own stdout ('FDTD timestep is', 'Time for N iterations', the probe end line) goes to the caller's log.
Run with DYLD_LIBRARY_PATH=<snapshot dir> and plain python3 (no caffeinate in front: SIP strips DYLD_*).
E2E_ENGINE=<engine> (e.g. metal-diamond) passes engine= to FDTD.Run; the toolkit itself is not changed.
"""
import json
import os
import sys
import time

import numpy as np

if "RFSIM_PATH" not in os.environ:
    raise KeyError("RFSIM_PATH is not set: point it at the rfsim toolkit directory (the folder that contains rfsim/)")
sys.path.insert(0, os.environ["RFSIM_PATH"])
from rfsim.openems import core  # noqa: E402

model, floor, db, hold, out = sys.argv[1], float(sys.argv[2]), sys.argv[3], float(sys.argv[4]), os.path.abspath(sys.argv[5])
f = np.linspace(50e6, 2e9, 391)

t0 = time.perf_counter()
if model == "gcpw":
    m = core.gcpw_line(length=50.0, feed=10.0, scale=1.0, f_max=2e9, f_ref=640e6)
else:
    from rfsim.openems import launch
    m = launch.sma_launch(scale=1.0, P={"min_cell": floor} if floor > 0 else None)
if os.environ.get("E2E_ENGINE"):   # e.g. metal-diamond: core.run has no engine argument, so FDTD.Run gets it here
    class _EngineRun:
        def __init__(self, fdtd, engine):
            self._fdtd, self._engine = fdtd, engine
        def __getattr__(self, name):
            return getattr(self._fdtd, name)
        def Run(self, *args, **kw):
            kw.setdefault("engine", self._engine)
            return self._fdtd.Run(*args, **kw)
    m.fdtd = _EngineRun(m.fdtd, os.environ["E2E_ENGINE"])
t1 = time.perf_counter()
core.run(m, out, threads=0, probe_end_db=None if db == "off" else float(db), probe_end_hold=hold)
t2 = time.perf_counter()
for p in m.ports:
    p.CalcPort(out, f, ref_impedance=50)
S = np.array([p.uf_ref / m.ports[0].uf_inc for p in m.ports]).T          # (nf, 2): S11, S21 of port 1
m.ports[0].CalcPort(out, f)
Z0 = np.array(m.ports[0].Z_ref, dtype=complex)
t3 = time.perf_counter()
np.savez(os.path.join(out, "sp.npz"), f=f, S=S, Z0=Z0)
info = {k: (v if isinstance(v, (int, float, str, bool, type(None), list, dict)) else str(v)) for k, v in m.info.items()}
res = dict(model=model, floor=floor, db=db, hold=hold, cells=m.info.get("cells"), f_ref=m.f_ref,
           t_build=t1 - t0, t_run=t2 - t1, t_post=t3 - t2, t_total=t3 - t0, info=info,
           lib=os.environ.get("DYLD_LIBRARY_PATH", "(installed)"))
json.dump(res, open(os.path.join(out, "result.json"), "w"), indent=1, default=str)
print("RESULT", json.dumps({k: res[k] for k in ("model", "floor", "db", "hold", "cells", "f_ref", "t_build", "t_run", "t_post", "t_total")}))
