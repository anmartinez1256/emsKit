"""Thread scaling of snapshot cg14 (check.sh runs of 2026-10-29, results/*_cg14.txt, through results/summary.json: run
parse_results.py first): MC/s at 1, 4, 8, 10 threads; the auto pick marked where the run printed it (the patch tutorial's
0.7 s auto run, 1499 MC/s, ends before the search prints its choice)."""
import json, os, re, numpy as np, matplotlib.pyplot as plt
from style import *
S = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results", "summary.json")))
thr = [1, 4, 8, 10]
names = {"kgcpw": "GCPW line (0.24 M)", "ksma": "SMA launch (1.07 M)", "notch": "notch tutorial (0.27 M)",
         "patch": "patch tutorial (0.10 M)", "patch_x5": "patch x5 (7.9 M)", "notch_x3": "notch x3 (5.3 M)"}
fig, ax = plt.subplots(figsize=(6.2, 3.9))
for i, (k, nm) in enumerate(names.items()):
    e = S[k]["cg14"]; rows = e["rows"]
    at = {int(m.group(1)): v for c, v in rows.items() if (m := re.match(r"[^@]+@multithreaded:(\d+)$", c))}
    ax.plot(thr, [at[n] for n in thr], "-o", color=C[i], ms=3.5, lw=1.5, label=nm, zorder=3)
    auto = [v for c, v in rows.items() if c.endswith("@fastest")]
    if e["picked"] is not None and auto:
        ax.plot([e["picked"]], auto, marker="*", color=C[i], ms=9, mec=SURF, mew=0.8, zorder=4, ls="none")
ax.set_xticks(thr); ax.set_xlabel("engine threads (star = the automatic choice and its speed)"); ax.set_ylabel("million cells per second")
clean(ax); ax.legend(frameon=False, ncol=3, loc="upper center", bbox_to_anchor=(0.5, -0.2)); save(fig, "fig_threads")
