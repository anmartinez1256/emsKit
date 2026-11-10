"""compare.py OUTROOT: S-parameter and port-file checks of the re-measurement set.

- every run against its model's full fork run (G_off, S_off): max |dS11| in dB where |S11_ref| > -40 dB, max |dS21| dB,
  dZ0 at f_ref, S11 at f_ref; for runs on the same mesh also whether the port files are a byte-identical prefix
  (same lines up to the stop) of the full run's;
- the stock full runs (G_stock, S_stock) against the fork full runs: port files byte for byte.
Writes OUTROOT/compare.json and prints a table.
"""
import glob
import json
import os
import sys

import numpy as np

root = os.path.abspath(sys.argv[1])
summ = json.load(open(os.path.join(root, "summary.json")))


def sp(name):
    return np.load(os.path.join(root, name, "sp.npz"))


def port_lines(name):
    d = {}
    for fn in sorted(glob.glob(os.path.join(root, name, "port_*"))):
        with open(fn) as fh:
            d[os.path.basename(fn)] = [l for l in fh.read().splitlines() if not l.startswith('%')]
    return d


def prefix_ok(a, b):
    """a's data lines are the first lines of b's, file by file (same set of files)."""
    A, B = port_lines(a), port_lines(b)
    if set(A) != set(B) or not A:
        return False
    return all(len(A[k]) <= len(B[k]) and A[k] == B[k][:len(A[k])] for k in A)


def identical(a, b):
    A, B = port_lines(a), port_lines(b)
    return bool(A) and set(A) == set(B) and all(A[k] == B[k] for k in A)


res = {}
for name, r in summ.items():
    ref = "G_off" if r["model"] == "gcpw" else "S_off"
    if not os.path.exists(os.path.join(root, name, "sp.npz")) or not os.path.exists(os.path.join(root, ref, "sp.npz")):
        continue
    a, b = sp(name), sp(ref)
    S, rS, f = a["S"], b["S"], a["f"]
    i = int(np.argmin(np.abs(f - (r.get("f_ref") or 1e9))))
    mask = np.abs(rS[:, 0]) > 1e-2
    d = dict(ref=ref, s11_db=float(20 * np.log10(abs(S[i, 0]))),
             ds11_db=float(np.max(np.abs(20 * np.log10(np.abs(S[mask, 0])) - 20 * np.log10(np.abs(rS[mask, 0]))))) if mask.any() else None,
             ds11_lin=float(np.max(np.abs(S[:, 0] - rS[:, 0]))),
             ds21_db=float(np.max(np.abs(20 * np.log10(np.abs(S[:, 1])) - 20 * np.log10(np.abs(rS[:, 1]))))),
             dz0=float(complex(a["Z0"][i]).real - complex(b["Z0"][i]).real), z0=float(complex(a["Z0"][i]).real))
    same_mesh = (r["model"] == "gcpw") or float(r.get("floor") or 0) == 0
    if name != ref and same_mesh:
        d["prefix_of_full"] = prefix_ok(name, ref)
    res[name] = d
for st, fk in (("G_stock", "G_off"), ("S_stock", "S_off")):
    if st in summ and fk in summ:
        res.setdefault(st, {})["identical_to_fork_full"] = identical(st, fk)
json.dump(res, open(os.path.join(root, "compare.json"), "w"), indent=1)
for name in summ:
    r, d = summ[name], res.get(name, {})
    print(f"{name:8s} cells {r.get('cells', 0)/1e6:.3f} M steps {r.get('steps')} dt {r.get('dt_fs', 0):.2f} fs "
          f"total {r.get('t_total', 0):.1f} s (run {r.get('t_run', 0):.1f}) | S11@fref {d.get('s11_db', 0):.2f} dB "
          f"dS11 {d.get('ds11_db') or 0:.4f} dB ({d.get('ds11_lin', 0):.1e} lin) dS21 {d.get('ds21_db', 0):.5f} dB dZ0 {d.get('dz0', 0):+.4f} "
          f"prefix={d.get('prefix_of_full')} identical={d.get('identical_to_fork_full')}")
