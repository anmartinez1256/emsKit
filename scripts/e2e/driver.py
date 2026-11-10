"""driver.py LIBDIR_FORK LIBDIR_STOCK OUTROOT [NAME ...]: run the re-measurement set one by one on a quiet Mac.

Each run is a subprocess `python3 run_one.py ...` with DYLD_LIBRARY_PATH set to the fork or the stock snapshot.
Before a run it waits until the other processes use less than one core (10 s window, at most 30 min, then runs
anyway and flags it); during the run it samples the other processes' CPU every second. Parses openEMS's stdout
('Time for N iterations with C cells : T sec', 'FDTD timestep is', 'probe end criterion reached') and writes
OUTROOT/summary.json + prints one line per run. Names select a subset (default: all, in the order below).
"""
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
fork, stock, root = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])
RUNS = [  # name, lib, model, floor, db, hold
    ("G_off", "fork", "gcpw", 0, "off", 1), ("G_60", "fork", "gcpw", 0, "-60", 1), ("G_80", "fork", "gcpw", 0, "-80", 1),
    ("G_60h", "fork", "gcpw", 0, "-60", 0.5), ("G_stock", "stock", "gcpw", 0, "off", 1),
    ("S_off", "fork", "sma", 0, "off", 1), ("S_60", "fork", "sma", 0, "-60", 1), ("S_80", "fork", "sma", 0, "-80", 1),
    ("S_60h", "fork", "sma", 0, "-60", 0.5),
    ("M_03", "fork", "sma", 0.03, "-60", 1), ("M_04", "fork", "sma", 0.04, "-60", 1), ("M_05", "fork", "sma", 0.05, "-60", 1),
    ("M_05h", "fork", "sma", 0.05, "-60", 0.5),
    ("S_stock", "stock", "sma", 0, "off", 1),
]
want = set(sys.argv[4:])
os.makedirs(root, exist_ok=True)
summ_path = os.path.join(root, "summary.json")
summary = json.load(open(summ_path)) if os.path.exists(summ_path) else {}


def others_cpu(own):
    """%CPU of every process outside our own process group (100 = one core)."""
    out = subprocess.run(["ps", "-A", "-o", "pgid=,%cpu="], capture_output=True, text=True).stdout
    tot = 0.0
    for line in out.splitlines():
        p = line.split()
        if len(p) == 2 and int(p[0]) != own:
            tot += float(p[1])
    return tot


def wait_quiet(own, limit=100.0, window=10, max_wait=1800):
    t0 = time.time(); ok = 0
    while time.time() - t0 < max_wait:
        c = others_cpu(own)
        ok = ok + 1 if c < limit else 0
        if ok >= window:
            return True, time.time() - t0
        time.sleep(1)
    return False, time.time() - t0


own = os.getpgid(0)
for name, lib, model, floor, db, hold in RUNS:
    if want and name not in want:
        continue
    out = os.path.join(root, name)
    log = os.path.join(root, name + ".log")
    quiet, waited = wait_quiet(own)
    env = dict(os.environ, DYLD_LIBRARY_PATH=fork if lib == "fork" else stock)
    t0 = time.time()
    p = subprocess.Popen([sys.executable, os.path.join(HERE, "run_one.py"), model, str(floor), db, str(hold), out],
                         stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env)
    samples = []
    while p.poll() is None:
        time.sleep(1)
        samples.append(others_cpu(own))
    wall = time.time() - t0
    txt = open(log).read()
    r = dict(name=name, lib=lib, model=model, floor=floor, db=db, hold=hold, rc=p.returncode, wall=wall,
             quiet_before=quiet, waited_s=round(waited), others_mean=sum(samples) / max(1, len(samples)),
             others_max=max(samples) if samples else 0)
    m = re.search(r"Time for (\d+) iterations with ([\d.e+]+) cells : ([\d.e+]+) sec", txt)
    if m:
        r.update(steps=int(m.group(1)), cells=float(m.group(2)), t_loop=float(m.group(3)))
        r["mcs"] = r["cells"] * r["steps"] / r["t_loop"] / 1e6
    m = re.search(r"FDTD timestep is: ([\d.e+-]+) s", txt)
    if m:
        r["dt_fs"] = float(m.group(1)) * 1e15
    r["probe_end_fired"] = "probe end criterion reached" in txt
    m = re.search(r"RESULT (\{.*\})", txt)
    if m:
        r.update(json.loads(m.group(1)))
    summary[name] = r
    json.dump(summary, open(summ_path, "w"), indent=1)
    print(f"{name:8s} rc={r['rc']} steps={r.get('steps')} dt={r.get('dt_fs', 0):.2f} fs loop={r.get('t_loop', 0):.1f} s "
          f"run={r.get('t_run', 0):.1f} total={r.get('t_total', 0):.1f} s {r.get('mcs', 0):.0f} MC/s "
          f"others {r['others_mean']:.0f}%/{r['others_max']:.0f}% quiet={quiet} waited {r['waited_s']} s", flush=True)
print("DRIVER DONE")
