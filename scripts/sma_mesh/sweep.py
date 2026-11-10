"""sweep.py FLOOR HOLD OUT REF: full rfsim run of the SMA launch with mesh floor min_cell = FLOOR (mm) and the probe
end criterion (-60 dB, HOLD excitation lengths), compared to REF (a finished run dir with sp.npz: the full 10 ns run
on the 0.02 mm mesh, made as scripts/README.md says). Reports cells, the FDTD time step and step count (read from
the run's excitation and port files), runtime (the wall time of FDTD.Run: operator setup and time stepping),
S11/S21/Z0 at f_ref and the max differences over 50 MHz - 2 GHz. Plain python3 (no caffeinate wrapper in front: SIP
strips DYLD_*)."""
import os, sys
import numpy as np
if "RFSIM_PATH" not in os.environ:
    raise KeyError("RFSIM_PATH is not set: point it at the rfsim toolkit directory (the folder that contains rfsim/)")
sys.path.insert(0, os.environ["RFSIM_PATH"])
from rfsim.openems import core, launch


def run_steps(run_dir, max_time, probe="port_ut_1A"):
    """FDTD time step and step count of a finished run. The excitation file 'et' has one row per step (6 printed
    digits), which gives k; the probe files have one row every k steps (12 printed digits), which gives dt. A probe
    end stop lands on a probe sample; a run that reached max_time did int(max_time / dt) steps (its last sample can
    be up to k steps earlier)."""
    et = np.loadtxt(os.path.join(run_dir, "et"), comments="%", ndmin=2)
    t = np.loadtxt(os.path.join(run_dir, probe), comments="%", ndmin=2)[:, 0]
    k = int(round((t[1] - t[0]) / ((et[-1, 0] - et[0, 0]) / (len(et) - 1))))
    dt = (t[-1] - t[0]) / ((len(t) - 1) * k)
    early = t[-1] + 1.5 * k * dt < max_time
    return dt, int(round(t[-1] / dt)) if early else int(max_time / dt)


floor, hold, out, ref = float(sys.argv[1]), float(sys.argv[2]), os.path.abspath(sys.argv[3]), os.path.abspath(sys.argv[4])
if not os.path.isfile(os.path.join(ref, "sp.npz")):
    sys.exit(f"sweep.py: {ref} has no sp.npz (make the reference run first, see scripts/README.md)")
f = np.linspace(50e6, 2e9, 391)
m = launch.sma_launch(P={"min_cell": floor})
core.run(m, out, threads=0, probe_end_db=-60, probe_end_hold=hold)

for p in m.ports:
    p.CalcPort(out, f, ref_impedance=50)
S = np.array([p.uf_ref / m.ports[0].uf_inc for p in m.ports]).T          # (nf, 2): S11, S21 (coax excited)
m.ports[0].CalcPort(out, f)
Z0 = np.array(m.ports[0].Z_ref, dtype=complex)
i6 = np.argmin(abs(f - m.f_ref))
dt, nts = run_steps(out, m.max_time)
s11 = 20 * np.log10(abs(S[:, 0])); s21 = 20 * np.log10(abs(S[:, 1]))
np.savez(os.path.join(out, "sp.npz"), f=f, S=S, Z0=Z0)
r = np.load(os.path.join(ref, "sp.npz")); rS = r["S"]
mask = np.abs(rS[:, 0]) > 1e-2
ds11_db = np.max(np.abs(s11[mask] - 20 * np.log10(np.abs(rS[mask, 0]))))
ds21_db = np.max(np.abs(s21 - 20 * np.log10(np.abs(rS[:, 1]))))
dz0 = Z0[i6].real - complex(r["Z0"][i6]).real
rs11_i6 = 20 * np.log10(abs(rS[i6, 0]))
print(f"RESULT floor {floor:.2f} hold {hold}: {m.info['cells']/1e6:.3f} M cells, dt {dt*1e15:.1f} fs, {nts} TS, "
      f"runtime {m.info['runtime_s']} s | S11 {s11[i6]:.2f} dB (ref {rs11_i6:.2f}), S21 {s21[i6]:.4f} dB, Z0 {Z0[i6].real:.3f} ohm "
      f"@{m.f_ref/1e6:.0f}M | vs {os.path.basename(ref)}: max|dS11| {np.max(np.abs(S[:,0]-rS[:,0])):.2e} lin "
      f"({ds11_db:.3f} dB where S11>-40dB), max|dS21| {ds21_db:.4f} dB, dZ0 {dz0:+.3f} ohm")
