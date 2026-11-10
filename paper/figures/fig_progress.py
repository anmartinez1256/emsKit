"""Speed-up over stock per snapshot (best thread count of each snapshot's check run), from results/summary.json (run
parse_results.py first; snapshot A comes from the A@ rows of the *_AB.txt tables). Stock: the best of the step-1 sweep for
the tutorials, one 4-thread reference run for the two boards (cg10 table for the GCPW line, cg14 for the SMA launch).
A solid line joins snapshots that were both run on a model; a dotted line bridges snapshots in which it was not run (the
boards before cg10, the GCPW line at cg11). The patch x5 point of A (1151 MC/s, 8 threads) is a row whose load figure is
invalid in its table (summary.json 'bad_load'); load can only slow a run, so it is kept."""
import json, os, numpy as np, matplotlib.pyplot as plt
from style import *
S = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results", "summary.json")))
tags = ["stock", "A", "AB", "ABCDEG", "cg2", "cg6", "cg8", "cg9", "cg10", "cg11", "cg12", "cg13", "cg14"]
STOCK = {"kgcpw": ("cg10", "stock_ref"), "ksma": ("cg14", "stock_ref")}      # the tutorials: ("step1", "best")
names = {"patch_x5": "patch x5 (7.9 M)", "notch_x3": "notch x3 (5.3 M)", "patch": "patch tutorial (0.10 M)", "notch": "notch tutorial (0.27 M)", "kgcpw": "GCPW line (0.24 M)", "ksma": "SMA launch (1.07 M)"}
fig, ax = plt.subplots(figsize=(6.6, 3.6))
for i, (k, nm) in enumerate(names.items()):
    t0, f0 = STOCK.get(k, ("step1", "best")); st = S[k][t0][f0]
    xs, ys = [], []
    for j, t in enumerate(tags):
        v = st if t == "stock" else S.get(k, {}).get(t, {}).get("best")
        if v: xs.append(j); ys.append(v / st)
    for a in range(len(xs) - 1):                       # solid between neighbours in the series, dotted across a gap
        ax.plot(xs[a:a + 2], ys[a:a + 2], color=C[i], lw=1.6 if xs[a + 1] == xs[a] + 1 else 1.0,
                ls="-" if xs[a + 1] == xs[a] + 1 else ":", zorder=3)
    ax.plot(xs, ys, "o", color=C[i], ms=3.5, label=nm, zorder=3)
    ax.text(xs[-1] + 0.2, ys[-1], nm, fontsize=7, color=INK2, va="center")   # the end marker beside it carries the colour
ax.set_xticks(range(len(tags))); ax.set_xticklabels(tags, fontsize=7.5)
ax.set_xlim(-0.3, len(tags) + 2.6); ax.set_ylabel("speed-up over stock (best thread count)"); clean(ax)
ax.axhline(1, color=INK2, lw=0.6); save(fig, "fig_progress")
