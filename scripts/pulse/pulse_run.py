"""pulse_run.py MODEL PULSE DB HOLD OUT: one rfsim run of a board with the toolkit's pulse (std: f0 = fc = f_max/2) or a
baseband Gaussian of half the length (base: f0 = 0, fc = f_max). The toolkit is not changed: the excitation is set on
the built model before core.run. MODEL gcpw | sma; DB = 'off' or e.g. -60; HOLD in excitation lengths of the pulse used.
Writes OUT/sp.npz (f, S = S11 and S21, Z0, inc = the incident voltage spectrum) and OUT/result.json."""
import json, os, sys, time
import numpy as np
sys.path.insert(0, os.environ["RFSIM_PATH"])
from rfsim.openems import core
model, pulse, db, hold, out = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), os.path.abspath(sys.argv[5])
if model == "gcpw":
    m = core.gcpw_line(length=50.0, feed=10.0, scale=1.0, f_max=2e9, f_ref=640e6)
else:
    from rfsim.openems import launch
    m = launch.sma_launch(scale=1.0)
f = np.linspace(50e6, m.f_max, 391)
if pulse == "base":
    m.fdtd.SetGaussExcite(0, m.f_max)
elif pulse != "std":
    raise SystemExit("PULSE is std or base")
t0 = time.perf_counter()
core.run(m, out, threads=int(os.environ.get("PULSE_THREADS", "2")), probe_end_db=None if db == "off" else float(db), probe_end_hold=hold)
t1 = time.perf_counter()
for p in m.ports:
    p.CalcPort(out, f, ref_impedance=50)
S = np.array([p.uf_ref / m.ports[0].uf_inc for p in m.ports]).T
inc = np.abs(np.array(m.ports[0].uf_inc))
m.ports[0].CalcPort(out, f)
Z0 = np.array(m.ports[0].Z_ref, dtype=complex)
np.savez(os.path.join(out, "sp.npz"), f=f, S=S, Z0=Z0, inc=inc)
info = {k: (v if isinstance(v, (int, float, str, bool, type(None), list, dict)) else str(v)) for k, v in m.info.items()}
json.dump(dict(model=model, pulse=pulse, db=db, hold=hold, f_max=m.f_max, t_run=t1 - t0, info=info), open(os.path.join(out, "result.json"), "w"), indent=1, default=str)
print("RESULT", model, pulse, db, hold, "t_run %.1f s" % (t1 - t0), {k: info.get(k) for k in ("cells", "steps", "t_end_ns", "stopped_early", "threads")})
