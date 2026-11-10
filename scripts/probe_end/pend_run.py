"""pend_run.py MODEL DB HOLD OUT [REF]: run an rfsim model (gcpw | sma) with the probe end criterion
(DB = 'off' or e.g. -60, HOLD in excitation lengths, passed through core.run) and report record length, runtime,
settle, Z0, S-params; if REF (a finished run dir) is given, the port files must be a bit-identical prefix of REF's
and the S-params are compared to REF's. The runtime is the wall time of FDTD.Run (operator setup and time stepping);
the model build and the port post-processing are not in it. Run with DYLD_LIBRARY_PATH pointing at the snapshot to
test (no caffeinate wrapper: SIP strips DYLD_* for system binaries).
The reference of scripts/sma_mesh (`pend_run.py sma off 1 s_ref`) has to be made with the toolkit at commit 2948d58:
the mesh floor (toolkit commit 2b0fd8c) moves 14 lines of the default mesh (results/sma_mesh_sweep_2026-11-01.txt)."""
import glob, os, sys
import numpy as np
if "RFSIM_PATH" not in os.environ:
    raise KeyError("RFSIM_PATH is not set: point it at the rfsim toolkit directory (the folder that contains rfsim/)")
sys.path.insert(0, os.environ["RFSIM_PATH"])
from rfsim.openems import core

model, db, hold, out = sys.argv[1:5]
ref = os.path.abspath(sys.argv[5]) if len(sys.argv) > 5 else None   # openEMS Run() chdirs into the sim dir
out = os.path.abspath(out)
f = np.linspace(50e6, 2e9, 391)
if model == "gcpw":
    m = core.gcpw_line(length=50.0, feed=10.0, scale=1.0, f_max=2e9, f_ref=640e6)
else:
    from rfsim.openems import launch
    m = launch.sma_launch(scale=1.0)
core.run(m, out, threads=0, probe_end_db=None if db == "off" else float(db), probe_end_hold=float(hold))

for p in m.ports:
    p.CalcPort(out, f, ref_impedance=50)
S = np.array([p.uf_ref / m.ports[0].uf_inc for p in m.ports]).T          # (nf, P) column of port 1
try:
    m.ports[0].CalcPort(out, f)
    Z0 = np.array(m.ports[0].Z_ref, dtype=complex)
except Exception as e:  # noqa
    Z0 = np.full(len(f), np.nan, dtype=complex)
i6 = np.argmin(abs(f - m.f_ref))
s11 = 20 * np.log10(abs(S[:, 0])); s21 = 20 * np.log10(abs(S[:, 1])) if S.shape[1] > 1 else None
# settle: worst port voltage file, last 10 % of the record vs its peak
settle = -400.0; tmax = 0
for fn in sorted(glob.glob(os.path.join(out, "port_ut*"))):
    d = np.loadtxt(fn, comments='%'); u = np.abs(d[:, 1]); n = len(u); tmax = d[-1, 0]
    settle = max(settle, 20 * np.log10(max(u[int(0.9 * n):].max(), 1e-300) / max(u.max(), 1e-300)))
print(f"RESULT {model} db={db} hold={hold}: record {tmax*1e9:.2f} ns, runtime (FDTD.Run) {m.info['runtime_s']} s, settle {settle:.0f} dB, "
      f"Z0 {Z0[i6].real:.3f} ohm, S11 {s11[i6]:.2f} dB" + (f", S21 {s21[i6]:.4f} dB" if s21 is not None else "") + f" @{m.f_ref/1e6:.0f}M")
np.savez(os.path.join(out, "sp.npz"), f=f, S=S, Z0=Z0)
if ref:
    worst = 0.0
    for fn in sorted(glob.glob(os.path.join(ref, "port_*"))):
        b = np.loadtxt(fn, comments='%'); a = np.loadtxt(os.path.join(out, os.path.basename(fn)), comments='%')
        n = min(len(a), len(b))
        worst = max(worst, float(np.max(np.abs(a[:n] - b[:n]))) if n else np.inf)
        if len(a) > len(b): worst = np.inf
    r = np.load(os.path.join(ref, "sp.npz"))
    rS = r["S"]
    mask = np.abs(rS[:, 0]) > 1e-2
    ds11 = np.max(np.abs(20*np.log10(np.abs(S[mask, 0])) - 20*np.log10(np.abs(rS[mask, 0])))) if mask.any() else 0
    msg = f"COMPARE vs {os.path.basename(ref)}: port-file prefix max|diff| {worst:.1e}, max|dS11| {np.max(np.abs(S[:,0]-rS[:,0])):.2e} ({ds11:.4f} dB where S11>-40dB)"
    if s21 is not None:
        msg += f", max|dS21| {np.max(np.abs(S[:,1]-rS[:,1])):.2e} ({np.max(np.abs(s21 - 20*np.log10(np.abs(rS[:,1])))):.5f} dB)"
    msg += f", dZ0 {Z0[i6].real - complex(r['Z0'][i6]).real:+.4f} ohm"
    print(msg)
