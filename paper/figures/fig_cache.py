"""The allocation-placement valley: single-thread speed vs cell count, PEC box nz = 20 (scripts/cache_valley/box.py,
2000 steps), with and without the allocator stagger, and stock openEMS v0.37.0.
fdtdKit: results/cache_valley_2026-11-01.txt (the installed cg16 build, 2026-11-01), columns MCs_stagger and
MCs_nostagger; OPENEMS_NO_STAGGER=1 turns the stagger off and leaves the field arrays page-aligned, as in stock openEMS.
Stock v0.37.0: results/cache_valley_stock_2026-11-03.txt (2026-11-03), column MCs_nostagger. Stock has no stagger, so
both columns of that file ran the same stock library and differ only by run-to-run noise; the figure uses one of
them."""
import numpy as np, matplotlib.pyplot as plt, os
from style import *
R = os.path.join(os.path.dirname(__file__), "..", "..", "results")
d = np.loadtxt(os.path.join(R, "cache_valley_2026-11-01.txt"))         # nx ny nz cells MCs_stagger MCs_nostagger
s = np.loadtxt(os.path.join(R, "cache_valley_stock_2026-11-03.txt"))   # same columns, stock v0.37.0
fig, ax = plt.subplots(figsize=(5.4, 3.0))
# marker shapes as a second cue besides colour
ax.plot(s[:, 3] / 1e3, s[:, 5], "-o", color=C[0], ms=4, label="stock v0.37.0", zorder=3)
ax.plot(d[:, 3] / 1e3, d[:, 4], "-s", color=C[1], ms=4, label="fdtdKit, staggered allocations", zorder=3)
ax.plot(d[:, 3] / 1e3, d[:, 5], "-^", color=C[2], ms=4.5,
        label="fdtdKit, OPENEMS_NO_STAGGER=1 (page-aligned, as in stock)", zorder=3)
ax.set_xlabel("cells, thousands (nx = ny, nz = 20, one thread, 2000 timesteps)")
ax.set_ylabel("million cells per second")
ax.set_ylim(0, 1400); ax.set_yticks(range(0, 1001, 200))   # the legend sits in the empty band above 1000
clean(ax); ax.legend(frameon=False, loc="upper right"); save(fig, "fig_cache")
