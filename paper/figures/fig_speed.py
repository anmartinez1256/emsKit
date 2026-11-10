"""Stock v0.37.0 vs fdtdKit snapshot cg14, six models, from results/summary.json (run parse_results.py first).
fdtdKit: the fastest row of each model's cg14 check run (results/*_cg14.txt), i.e. its best thread count; the cg14 values
match Table tab:final and Figure fig_threads (the GCPW's cg13 run reached 1745 at 4 threads, within the run-to-run spread).
Stock: the best of the step-1 thread sweep for the four tutorial models (results/*_step1.txt); for the two boards one
4-thread reference run each (the cg10 table for the GCPW line, the cg14 table for the SMA launch). Their stock thread
count was not swept, so those two bars are not a best."""
import json, os, numpy as np, matplotlib.pyplot as plt
from style import *
S = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results", "summary.json")))
models = [("kgcpw", "GCPW line (0.24 M)"), ("ksma", "SMA launch (1.07 M)"), ("notch", "notch tutorial (0.27 M)"),
          ("patch", "patch tutorial (0.10 M)"), ("patch_x5", "patch x5 (7.9 M)"), ("notch_x3", "notch x3 (5.3 M)")]
STOCK = {"kgcpw": ("cg10", "stock_ref"), "ksma": ("cg14", "stock_ref")}      # the tutorials: ("step1", "best")
stock = [S[k][STOCK.get(k, ("step1", "best"))[0]][STOCK.get(k, ("step1", "best"))[1]] for k, _ in models]
now = [S[k]["cg14"]["best"] for k, _ in models]
fig, ax = plt.subplots(figsize=(6.4, 3.8)); y = np.arange(len(models))[::-1]; h = 0.36
ax.barh(y + h/2 + 0.01, stock, height=h, color=C[0], label="stock openEMS v0.37.0", zorder=3)
ax.barh(y - h/2 - 0.01, now, height=h, color=C[1], label="fdtdKit (snapshot cg14)", zorder=3)
for yy, v, (k, _) in zip(y + h/2 + 0.01, stock, models):
    ax.text(v + 20, yy, f"{r0(v)}" + ("  (4 threads, not swept)" if k in STOCK else ""), va="center", fontsize=7.5, color=INK2)
for yy, v, s in zip(y - h/2 - 0.01, now, stock): ax.text(v + 20, yy, f"{r0(v)}  ({v/s:.1f}x)", va="center", fontsize=7.5, color=INK)
ax.set_yticks(y); ax.set_yticklabels([nm for _, nm in models]); ax.set_xlim(0, 2700); clean(ax, "x")
ax.set_xlabel("engine speed at the best thread count, million cells per second")
ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.2), ncol=2, frameon=False); save(fig, "fig_speed")
