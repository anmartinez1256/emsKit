"""compare.py DIR_A DIR_B: compare volt.f32 / curr.f32 (raw [3][x][y][z] float32) of two engines.
Exit status 0 only when both exports have the same step count and every value is identical; 1 otherwise."""
import json, os, sys
import numpy as np

if len(sys.argv) != 3:
    sys.exit(__doc__)
a, b = sys.argv[1:3]
ha = json.load(open(os.path.join(a, 'fields.json'))); hb = json.load(open(os.path.join(b, 'fields.json')))
assert ha['numLines'] == hb['numLines'], (ha, hb)
shape = (3, *ha['numLines'])
ok = ha['numTS'] == hb['numTS']
if not ok:
    print(f'different step counts: {ha["numTS"]} vs {hb["numTS"]}')
for name in ('volt', 'curr'):
    fa = np.fromfile(os.path.join(a, f'{name}.f32'), dtype=np.float32).reshape(shape)
    fb = np.fromfile(os.path.join(b, f'{name}.f32'), dtype=np.float32).reshape(shape)
    d = np.abs(fa.astype(np.float64) - fb)
    scale = np.max(np.abs(fa))
    ndiff = int(np.count_nonzero(fa != fb))
    print(f'{name}: max|a|={scale:.3e}  max|a-b|={d.max():.3e}  rel={d.max()/scale if scale else 0:.1e}  '
          f'differing elements {ndiff}/{fa.size}  (TS {ha["numTS"]} vs {hb["numTS"]})')
    if ndiff:
        ok = False
        w = np.unravel_index(np.argmax(d), shape)
        print(f'   worst at n,x,y,z={w}: {fa[w]!r} vs {fb[w]!r}')
print('BIT-IDENTICAL' if ok else 'DIFFERENT')
sys.exit(0 if ok else 1)
