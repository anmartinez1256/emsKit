"""cells.py MODEL SCALE...: mesh line counts and cells of bench/models.py models (builds the model, runs nothing)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'bench'))
from models import MODELS
name = sys.argv[1]
for s in sys.argv[2:]:
    s = float(s)
    out = MODELS[name](nrts=10, scale=s)
    FDTD = out[0]
    grid = FDTD.GetCSX().GetGrid() if hasattr(FDTD, 'GetCSX') else None
    if grid is None:
        print(name, s, 'no grid accessor'); continue
    n = [len(grid.GetLines(d)) for d in 'xyz']
    nz4 = (n[2] + 3) // 4 * 4
    print(f'{name} scale {s:g}: {n[0]}x{n[1]}x{n[2]} lines = {n[0]*n[1]*n[2]/1e6:.3f} M cells (z padded to 4 lanes: {n[0]*n[1]*nz4/1e6:.3f} M)')
