"""gen_e2e.py OUTROOT RESULT_TXT: the re-measurement table (results/rfsim_e2e_2026-11-03.txt) from the driver's
summary.json and compare.py's compare.json."""
import json
import os
import re
import sys

root, dst = os.path.abspath(sys.argv[1]), sys.argv[2]
S = json.load(open(os.path.join(root, "summary.json")))
C = json.load(open(os.path.join(root, "compare.json")))
hdr = """# End-to-end rfsim runs, re-measured 2026-11-03 on the final build (snapshot cg18 = patches 0001-0006,
# v0.37.0-24-g087ce9e) and on stock v0.37.0, Apple M5, macOS 27.0.1, one run each, in this order.
# Each run is what the author's toolkit does for a board (rfsim core.run(threads=0): model build in Python, FDTD.Run
# with operator setup and time stepping, then CalcPort for S11/S21 and the line impedance); toolkit = the rfsim working
# tree of 2026-11-03 (patches/rfsim 0001-0003). The fork picks its thread count itself; on the stock library the toolkit
# falls back to 4 threads (GCPW) and 8 (SMA). Before every run the driver waited until the other processes used less
# than one core for 10 s; 'others' = their mean / max CPU during the run (100 = one core).
# GCPW line: core.gcpw_line(length=50, feed=10, f_max=2 GHz), 12 ns. SMA launch: launch.sma_launch(), 10 ns, mesh
# floor min_cell (0 = the toolkit default 0.02 mm, the published default mesh). db/hold: probe end criterion
# (off = run to max_time). Times in s: build = model build, run = FDTD.Run, post = CalcPort, total = all three.
# MC/s from openEMS's own 'Time for N iterations' line (the time loop only). thr = engine threads from the run's log
# (aN = picked by the fork's tuner, N = fixed). E_end = openEMS's field energy estimate relative to its peak at the last
# progress line of the run (dB); the energy end criterion (-50 dB) never fired.
# Compared with the full fork run of the same model (G_off, S_off; for the SMA floors that is the full run on the
# default mesh): S11 at f_ref (GCPW 640 MHz, SMA 1 GHz), max |dS11| in dB where |S11_ref| > -40 dB ('-' when S11_ref
# stays below -40 dB, as on the GCPW line) and linear over the band, max |dS21| in dB,
# dZ0 = Re Z0 - Re Z0_ref at f_ref (ohm). prefix = the port files are a byte-identical prefix of the full run's
# (runs on the same mesh only). stock = the stock full run's port files are byte-identical to the fork's full run's.
# Scripts: scripts/e2e/ (driver.py runs the set, run_one.py one run, compare.py the comparisons, gen_e2e.py this table);
# they need the toolkit (RFSIM_PATH), which is not public.
"""
cols = "name     lib   model floor   db   hold  cells_M  steps   dt_fs   build    run   post  total   MC/s thr  E_end  others   S11@fref  dS11_dB dS11_lin  dS21_dB  dZ0_ohm  prefix  stock"
lines = [hdr.rstrip("\n"), "# " + cols]


def energy_end(name):
    try:
        log = open(os.path.join(root, name + ".log"), errors="replace").read()
    except OSError:
        return float("nan")
    m = re.findall(r"Energy: ~\S+ \(\s*(-?\s*[0-9.]+)dB\)", log)
    return float(m[-1].replace(" ", "")) if m else float("nan")


def threads(name):
    try:
        log = open(os.path.join(root, name + ".log"), errors="replace").read()
    except OSError:
        return "?"
    m = re.search(r"Best performance found using (\d+) threads", log)
    if m:
        return "a" + m.group(1)
    m = re.search(r"fixed number of threads: (\d+)", log)
    return m.group(1) if m else "?"


for name, r in S.items():
    c = C.get(name, {})
    pre = c.get("prefix_of_full")
    ident = c.get("identical_to_fork_full")
    lines.append(
        f"{name:8s} {r['lib']:5s} {r['model']:5s} {float(r['floor'] or 0):.2f} {r['db']:>5s} {float(r['hold']):4.1f}"
        f"  {r.get('cells', 0)/1e6:6.3f} {r.get('steps', 0):7d} {r.get('dt_fs', 0):7.2f}"
        f" {r.get('t_build', 0):6.2f} {r.get('t_run', 0):6.1f} {r.get('t_post', 0):6.2f} {r.get('t_total', 0):6.1f}"
        f" {r.get('mcs', 0):6.0f} {threads(name):>3s} {energy_end(name):6.1f}  {r['others_mean']:3.0f}/{r['others_max']:3.0f}"
        f"  {c.get('s11_db', float('nan')):8.2f} {('       -' if c.get('ds11_db', 0) is None else format(c.get('ds11_db', float('nan')), '8.4f'))}"
        f" {c.get('ds11_lin', float('nan')):8.1e} {c.get('ds21_db', float('nan')):8.5f}"
        f" {c.get('dz0', float('nan')):+8.4f}  {('-' if pre is None else ('yes' if pre else 'NO')):6s}"
        f"  {('-' if ident is None else ('yes' if ident else 'NO'))}")
open(dst, "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
