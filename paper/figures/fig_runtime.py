"""Wall time of a complete rfsim run of the two boards, timed around the toolkit's FDTD.Run call (operator setup and time
stepping; the Python model build and CalcPort are not included). Every value is the "run" column of
results/rfsim_e2e_2026-11-03.txt (measured 2026-11-03, one run each, snapshot cg18 and stock v0.37.0, meshes built
by the toolkit as it was that day): stock v0.37.0 full run (G_stock, S_stock; 4 and 8 threads, the toolkit's counts for
a stock library), fdtdKit full run with the same steps (G_off, S_off), fdtdKit with probe end -60 dB, hold 1 (G_60, S_60;
the toolkit's default until 2026-11-04), and the shortest setting tested, the toolkit's
default since 2026-11-04: probe end -60 dB, hold 0.5 (G_60h; the GCPW line has no mesh
floor) and, on the SMA launch, also the 0.05 mm mesh floor (M_05h, 0.871 M cells). Same model and Gaussian pulse in
every bar. Factor = stock time / time."""
import matplotlib.pyplot as plt
from style import *
rows = [("GCPW line, 12 ns", [76.5, 13.7, 8.6, 5.2]),        # G_stock, G_off, G_60, G_60h
        ("SMA launch, 10 ns", [562.7, 168.5, 97.6, 37.4])]   # S_stock, S_off, S_60, M_05h
lab = ["stock v0.37.0, full run", "fdtdKit cg18, full run (same steps)",
       "fdtdKit cg18, probe end -60 dB, hold 1 (toolkit default until 2026-11-04)",
       "fdtdKit cg18, default since 2026-11-04: hold 0.5 (SMA 0.05 mm floor, 0.871 M cells)"]
n, h, gap, step = len(lab), 0.2, 0.03, 1.25
fig, ax = plt.subplots(figsize=(6.2, 3.9))
for r, (nm, v) in enumerate(rows):
    yc = (len(rows) - 1 - r) * step
    for j, x in enumerate(v):
        y = yc + ((n - 1) / 2 - j) * (h + gap)
        ax.barh(y, x, height=h, color=C[j], zorder=3, label=lab[j] if r == 0 else None)
        t = f"{x:g} s" if j == 0 else f"{x:g} s ({v[0] / x:.1f}×)"
        ax.text(x * 1.08, y, t, va="center", fontsize=8, color=INK)
ax.set_xscale("log"); ax.set_xlim(3, 2000)
ax.set_yticks([(len(rows) - 1 - r) * step for r in range(len(rows))]); ax.set_yticklabels([r[0] for r in rows])
ax.set_xlabel("wall time of the run (FDTD.Run: setup and time stepping), seconds (log scale)"); clean(ax, "x")
ax.legend(frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.24), ncol=1, fontsize=7.5)
save(fig, "fig_runtime")
