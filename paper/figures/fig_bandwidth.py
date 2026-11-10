"""Effective DRAM traffic = speed x bytes per cell, against the M5's bus, for the engines measured in this project.
Bytes per cell come from the paper's traffic model, not from counters: 74 (separate E/H passes), 49 (fused sweep), 72 (the
two standalone material-table kernels, 1 B index); upstream's Metal engine and the Swift/Metal prototype are ASSUMED to move
74 B/cell (separate passes, not measured). The model counts 1 B of operator index per cell. openEMS allocates that index
with one 32-bit entry per cell and uses one per z-vector, so on meshes with few z lines the engine streams up to 4 B per
cell: the whisker on the openEMS rows is the same speed at 80 (separate passes, two index reads) and 52 B/cell (fused).
Stock and fdtdKit speeds come from results/summary.json (run parse_results.py first): stock patch x5 = the best of the
step-1 sweep (8 threads), fdtdKit = the cg14 check runs (patch x5 10 threads, notch x3 8 threads). The rows marked with a
dagger (the two standalone kernels on a 200^3 box and the two GPU engines on a 201^3 box) are from the project log, not in
results/."""
import json, os, matplotlib.pyplot as plt
from style import *
S = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results", "summary.json")))
D = "†"
rows = [("stock openEMS, 8 thr, patch x5", S["patch_x5"]["step1"]["best"], 74, 80),
        ("fdtdKit CPU, patch x5 (fused)", S["patch_x5"]["cg14"]["best"], 49, 52),
        ("fdtdKit CPU, notch x3 (fused)", S["notch_x3"]["cg14"]["best"], 49, 52),
        ("standalone CPU loop, material table " + D, 1491, 72, None), ("standalone Metal kernel, material table " + D, 1763, 72, None),
        ("upstream Metal engine, 201^3 " + D, 1638, 74, None), ("Swift/Metal prototype, 201^3 " + D, 1670, 74, None)]
fig, ax = plt.subplots(figsize=(6.9, 3.4)); ys = range(len(rows))[::-1]
for y, (nm, mc, b, bmax) in zip(ys, rows):
    gb = mc * b / 1000; ax.barh(y, gb, color=C[0] if "CPU" in nm or "stock" in nm else C[1], height=0.6, zorder=3)
    top = gb
    if bmax:
        top = mc * bmax / 1000; ax.plot([gb, top], [y, y], color=INK2, lw=1.0, zorder=4); ax.plot([top, top], [y - 0.15, y + 0.15], color=INK2, lw=1.0, zorder=4)
    ax.text(top + 1.5, y, f"{gb:.0f}" + (f"-{top:.0f}" if bmax else "") + " GB/s", va="center", fontsize=7, color=INK)
    ax.text(160, y, f"{r0(mc)} MC/s x {b}" + (f"-{bmax}" if bmax else "") + " B", va="center", fontsize=6.5, color=INK2)
ax.axvline(153, color=INK2, lw=1, ls="--"); ax.text(153, len(rows) - 0.35, "153 GB/s unified memory (vendor figure)", ha="center", fontsize=7, color=INK2,
        bbox=dict(facecolor=SURF, edgecolor="none", pad=1.5))
ax.set_yticks(list(ys)); ax.set_yticklabels([r[0] for r in rows], fontsize=7); ax.set_xlim(0, 215); ax.set_ylim(-0.6, len(rows) - 0.1)
ax.set_xlabel("effective memory traffic, GB/s (blue = CPU, orange = GPU)")
clean(ax, "x"); ax.set_xticks([0, 25, 50, 75, 100, 125, 150])
fig.text(0.01, 0.01, D + " from the project log, not in results/;  whisker: the same speed with the full 4 B/cell operator index", fontsize=6.5, color=INK2)
save(fig, "fig_bandwidth")
