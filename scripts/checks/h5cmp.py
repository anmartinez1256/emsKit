"""h5cmp.py DIR_A DIR_B: compare all datasets and attributes of the *.h5 files in two run dirs.
Exit status 0 only when both directories hold the same *.h5 files and every dataset and attribute is
equal, with the same type (NaN equal to NaN); 1 on a difference, a file found in one directory only, or no file
at all."""
import sys, os, glob
import h5py, numpy as np

def items(f):
    out = {}
    def visit(name, obj):
        attrs = {k: np.asarray(v) for k, v in obj.attrs.items()}
        data = obj[()] if isinstance(obj, h5py.Dataset) else None
        out[name] = (data, attrs)
    f.visititems(visit)
    out['/'] = (None, {k: np.asarray(v) for k, v in f.attrs.items()})
    return out

def same(x, y):
    x, y = np.asarray(x), np.asarray(y)
    if x.dtype != y.dtype:      # bit identity: a float32 and a float64 copy of the same values differ too
        return False
    try:
        return np.array_equal(x, y, equal_nan=True)
    except TypeError:           # strings and other non-numeric data
        return np.array_equal(x, y)

if len(sys.argv) != 3:
    sys.exit(__doc__)
a_dir, b_dir = sys.argv[1:3]
names = {d: {os.path.basename(p) for p in glob.glob(os.path.join(d, '*.h5'))} for d in (a_dir, b_dir)}
files = sorted(names[a_dir] & names[b_dir])
bad = 0
for fn in sorted(names[a_dir] ^ names[b_dir]):
    print(fn, 'only in', a_dir if fn in names[a_dir] else b_dir); bad += 1
nsets = 0
for fn in files:
    with h5py.File(os.path.join(a_dir, fn)) as fa, h5py.File(os.path.join(b_dir, fn)) as fb:
        ia, ib = items(fa), items(fb)
        if ia.keys() != ib.keys():
            print(fn, 'different objects:', sorted(set(ia) ^ set(ib))[:5]); bad += 1; continue
        for k in ia:
            (da, aa), (db, ab) = ia[k], ib[k]
            if (da is None) != (db is None) or (da is not None and not same(da, db)):
                print(fn, k, 'data differs'); bad += 1
            if aa.keys() != ab.keys() or any(not same(aa[x], ab[x]) for x in aa):
                print(fn, k, 'attributes differ'); bad += 1
            nsets += da is not None
print(f'{len(files)} files, {nsets} datasets, {bad} differences' + ('' if files else ': nothing compared'))
sys.exit(1 if bad or not files else 0)
