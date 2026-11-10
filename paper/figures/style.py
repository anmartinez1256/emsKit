"""Shared chart style (white surface, as the page under it; validated categorical palette slots 1-6)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
SURF, INK, INK2, GRID = "#ffffff", "#0b0b0b", "#52514e", "#e6e5e1"
C = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
plt.rcParams.update({"font.size": 9, "axes.titlesize": 10, "axes.labelsize": 9, "legend.fontsize": 8,
                     "figure.facecolor": SURF, "axes.facecolor": SURF, "savefig.facecolor": SURF,
                     "axes.edgecolor": GRID, "xtick.color": INK2, "ytick.color": INK2, "text.color": INK,
                     "axes.labelcolor": INK2, "pdf.fonttype": 42})
def clean(ax, grid="y"):
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.grid(True, axis=grid, color=GRID, zorder=0); ax.set_axisbelow(True)
    ax.tick_params(length=0)
def r0(v):
    """Round half up, as the paper's tables do (276.5 -> 277)."""
    return int(v + 0.5)
def save(fig, name):
    fig.tight_layout(); fig.savefig(name + ".pdf"); fig.savefig(name + ".png", dpi=200); print("wrote", name)
