"""SMA launch mesh floor sweep, measured on 2026-11-03 with snapshot cg18 (auto threads: 8 in every run) and the
corrected merge (results/sma_mesh_sweep_2026-11-01.txt, 2026-11-03 section; the same runs as rows S_60, M_03, M_04,
M_05, S_60h and M_05h of results/rfsim_e2e_2026-11-03.txt): wall time of FDTD.Run against the largest S11 change in
dB (where |S11| > -40 dB over 50 MHz-2 GHz), both against the full run on the 0.02 mm mesh (S_off). The hollow
grey point is history: the 0.06 mm run of the first merge (2026-11-01, engine cg16, against the full run on the original
mesh; the first table of the same file); the builder refuses that floor now."""
import matplotlib.pyplot as plt
from style import *
pts1 = [(0.02, 97.6, 0.0089), (0.03, 85.7, 0.0292), (0.04, 58.0, 0.0782), (0.05, 49.5, 0.1156)]   # probe end hold 1
pts2 = [(0.02, 72.9, 0.0188), (0.05, 37.4, 0.1157)]                                            # probe end hold 0.5
hist = (0.06, 24.3, 3.292)                       # first merge, 2026-11-01, engine cg16 (history; refused now)
off1 = {0.02: (-44, -3), 0.03: (5, 4), 0.04: (5, 4), 0.05: (5, 4)}
off2 = {0.02: (5, -10), 0.05: (-42, -10)}
fig, ax = plt.subplots(figsize=(5.2, 3.2))
ax.plot([p[1] for p in pts1], [p[2] for p in pts1], "o", color=C[0], ms=6, label="probe end hold 1.0", zorder=3)
ax.plot([p[1] for p in pts2], [p[2] for p in pts2], "s", color=C[1], ms=6, label="probe end hold 0.5", zorder=3)
ax.plot([hist[1]], [hist[2]], "o", mfc="none", mec=INK2, mew=1.2, ms=6, label="first merge, cg16, 2026-11-01 (history)", zorder=3)
for f, t, e in pts1: ax.annotate(f"{f:.2f} mm", (t, e), xytext=off1[f], textcoords="offset points", fontsize=7.5, color=INK2)
for f, t, e in pts2: ax.annotate(f"{f:.2f} mm", (t, e), xytext=off2[f], textcoords="offset points", fontsize=7.5, color=INK2)
ax.annotate(f"{hist[0]:.2f} mm (refused now)", hist[1:], xytext=(6, -3), textcoords="offset points", fontsize=7.5, color=INK2)
ax.set_yscale("log"); ax.set_ylim(0.005, 6); ax.set_xlim(15, 105)
ax.set_xlabel("run time of FDTD.Run, seconds (cg18, auto threads; 2026-11-03)"); ax.set_ylabel("max |dS11| in dB where S11 > -40 dB")
ax.axhspan(0.001, 0.3, color=GRID, alpha=0.5, zorder=0, lw=0); ax.text(103, 0.2, "well under the 30 dB return-loss bench floor", fontsize=7, color=INK2, ha="right")
clean(ax); ax.legend(frameon=False, loc="upper right"); save(fig, "fig_mesh")
