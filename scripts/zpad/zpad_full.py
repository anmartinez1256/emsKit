"""Full rfsim GCPW line runs (12 ns, probe end criterion off, engine auto threads) with 17 and 20 z lines
(core.Z_MULT 0 and 4): Z0, loss, S-params, runtime. The step count is read from the run's excitation and port files;
runtime and MC/s are over the wall time of FDTD.Run (operator setup and time stepping). Run folders run_z0 and
run_z4 go next to this script. Runs with the toolkit at commit 2948d58 (the z padding of ed3ac3e, which the project-log
numbers came from, and probe_end_db) and with 2b0fd8c or later (whose padding keeps the top boundary cell, so the
20-line mesh differs at the top)."""
import os, sys
import numpy as np
if "RFSIM_PATH" not in os.environ:
    raise KeyError("RFSIM_PATH is not set: point it at the rfsim toolkit directory (the folder that contains rfsim/)")
sys.path.insert(0, os.environ["RFSIM_PATH"])
from rfsim.openems import core


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


MAX_TIME = 12e-9   # gcpw_line's default, passed explicitly: Model.max_time exists only from toolkit commit 2b0fd8c on
here = os.path.dirname(os.path.abspath(__file__))
f = np.linspace(50e6, 2e9, 391)
res = {}
for zm in (0, 4):
    core.Z_MULT = zm
    m = core.gcpw_line(length=50.0, feed=10.0, scale=1.0, f_max=2e9, f_ref=640e6, max_time=MAX_TIME)
    nz = len(m.mesh.GetLines("z"))
    run_dir = os.path.join(here, f"run_z{zm}")
    core.run(m, run_dir, threads=0, probe_end_db=0)     # the whole 12 ns (the toolkit's default stops at -60 dB)
    S, tsig = core.ports_result(m, f)
    Z0, beta = core.line_params(m, f)
    i6 = np.argmin(abs(f - 640e6)); i2 = np.argmin(abs(f - 2e9))
    s21 = 20 * np.log10(abs(S[:, 1, 0])); s11 = 20 * np.log10(abs(S[:, 0, 0]))
    alpha = -np.imag(beta) if np.iscomplexobj(beta) else np.full_like(f, np.nan)
    res[zm] = dict(nz=nz, cells=m.info["cells"], runtime=m.info["runtime_s"], ts=run_steps(run_dir, MAX_TIME)[1],
                   Z0_640=complex(Z0[i6]).real, Z0_2G=complex(Z0[i2]).real,
                   S21_640=s21[i6], S21_2G=s21[i2], S11_640=s11[i6], S11_2G=s11[i2],
                   settle=core.settle_db(tsig), S21=s21, S11=s11)
    r = res[zm]
    print(f"z_mult={zm}: {nz} z lines, {r['cells']/1e6:.3f} M cells, {r['ts']} TS, runtime {r['runtime']} s "
          f"({r['ts']*r['cells']/r['runtime']/1e6:.0f} MC/s over FDTD.Run), settle {r['settle']:.0f} dB")
    print(f"   Z0 {r['Z0_640']:.2f} ohm @640M  {r['Z0_2G']:.2f} @2G | S21 {r['S21_640']:.3f} dB @640M  {r['S21_2G']:.3f} @2G"
          f" | S11 {r['S11_640']:.1f} dB @640M  {r['S11_2G']:.1f} @2G", flush=True)
a, b = res[0], res[4]
print(f"delta 20-17 lines: Z0 {b['Z0_640']-a['Z0_640']:+.3f} ohm @640M, S21 {b['S21_640']-a['S21_640']:+.4f} dB @640M "
      f"{b['S21_2G']-a['S21_2G']:+.4f} dB @2G, max|dS21| {np.max(abs(b['S21']-a['S21'])):.4f} dB over 50M-2G, "
      f"runtime {a['runtime']:.1f} -> {b['runtime']:.1f} s")
