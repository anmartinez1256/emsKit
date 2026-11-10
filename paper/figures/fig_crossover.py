"""GPU against CPU by grid size, snapshot cg29 (results/gpu_crossover_cg29_2026-11-05.txt, the size sweep of 2026-11-05).
Top row: the metal-diamond engine's speed over the multithreaded engine's at its faster thread count (8 at every point),
the median of the paired rounds and their range. Bottom row: the medians in MC/s with the range over the rounds, and the
GPU's rate over its busy time alone (cells x steps / GPU busy, from the OPENEMS_DIAMOND_TIMING=1 runs): the gap between
that line and the GPU's own is the time the GPU waits for the CPU."""
import os, re, sys, matplotlib.pyplot as plt
from style import *
F = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results",
                                                       "gpu_crossover_cg29_2026-11-05.txt")
NUM = r"x?([\d.]+) \[([\d.]+)-([\d.]+)\]"
rows = {}
for line in open(F):
    if not line.startswith("# | ") or "| cells " in line:
        continue
    c = [x.strip() for x in line[3:].strip().strip("|").split("|")]
    model = c[0].rsplit(" s", 1)[0]
    rng = lambda k: tuple(map(float, re.match(NUM, c[k]).groups()))
    rows.setdefault(model, []).append(dict(cells=float(c[1].split()[0]), cpu=max((rng(3), rng(4)), key=lambda v: v[0]),
                                           gpu=rng(5), ratio=rng(6), only=float(c[10]) if c[10] != "-" else None))
names = {"patch antenna": "patch (Mur, nf2ff dumps)", "notch filter": "notch filter (PML)", "GCPW line": "GCPW line (sheets, Mur)"}
models = [m for m in names if m in rows]
fig, axs = plt.subplots(2, len(models), figsize=(6.8, 4.5), sharex=True, sharey="row", squeeze=False,
                        gridspec_kw={"height_ratios": [1, 1.7]})


def whiskers(ax, x, v, col, **kw):
    med, lo, hi = zip(*v)
    ax.errorbar(x, med, yerr=[[a - b for a, b in zip(med, lo)], [b - a for a, b in zip(med, hi)]], color=col, marker="o",
                ms=3.2, elinewidth=0.8, capsize=0, zorder=3, **kw)


for j, m in enumerate(models):
    pts = sorted(rows[m], key=lambda d: d["cells"]); x = [d["cells"] for d in pts]
    top, ax = axs[0][j], axs[1][j]
    top.axhline(1, color=INK2, lw=0.7, zorder=1)
    whiskers(top, x, [d["ratio"] for d in pts], INK, lw=1.3)
    top.set_title(names[m], fontsize=8.5, color=INK); clean(top)
    whiskers(ax, x, [d["cpu"] for d in pts], C[0], lw=1.6, label="CPU, multithreaded engine (8 threads)")
    whiskers(ax, x, [d["gpu"] for d in pts], C[1], lw=1.6, label="GPU, metal-diamond engine")
    xo = [d["cells"] for d in pts if d["only"]]; yo = [d["only"] for d in pts if d["only"]]
    ax.plot(xo, yo, ls=":", color=C[1], lw=1.4, label="GPU over its busy time only", zorder=2)
    ax.set_xscale("log"); ax.set_xticks([0.1, 0.3, 1, 3]); ax.set_xticklabels(["0.1", "0.3", "1", "3"]); ax.set_xlim(0.08, 9)
    ax.minorticks_off(); ax.set_xlabel("million cells"); clean(ax)
axs[0][0].set_ylabel("GPU / CPU"); axs[1][0].set_ylabel("million cells per second")
h, l = axs[1][0].get_legend_handles_labels(); o = sorted(range(len(l)), key=lambda i: ("CPU" not in l[i], "busy" in l[i]))
fig.legend([h[i] for i in o], [l[i] for i in o], frameon=False, ncol=3, loc="lower center", fontsize=7.5)
fig.tight_layout(rect=(0, 0.05, 1, 1))              # style.save without its tight_layout: the legend sits below the panels
fig.savefig("fig_crossover.pdf"); fig.savefig("fig_crossover.png", dpi=200); print("wrote fig_crossover")
