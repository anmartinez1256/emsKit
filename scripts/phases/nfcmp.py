"""nf2ff check: run the far-field transform on a finished patch run dir and compare to a reference.

  python3 nfcmp.py run RUN_DIR TAG [SCALE]   -> writes nf_TAG_cuts.h5 / nf_TAG_3d.h5 (+ timings)
  python3 nfcmp.py cmp RUN_DIR TAG_REF TAG   -> max relative differences
Run each 'run' in its own process with the lib chosen by DYLD_LIBRARY_PATH / OPENEMS_NF2FF_LEGACY.
"""
import os, sys, time
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'bench'))   # the harness's models.py

mode, run_dir, tag = sys.argv[1:4]
if mode == 'run':
    if not os.path.exists(os.path.join(run_dir, 'nf2ff_E_0.h5')):   # CalcNF2FF would quietly give a zero far field
        rep = os.path.join(run_dir, 'rep0')
        sys.exit(f'nfcmp.py: no nf2ff dumps (nf2ff_E_0.h5) in {run_dir}'
                 + (f'; a bench run with --repeat keeps them in {rep}' if os.path.isdir(rep) else ''))
    from models import MODELS
    scale = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    FDTD, ports, f = MODELS['patch'](nrts=10, scale=scale, nf2ff=False)
    nf = FDTD.CreateNF2FFBox()
    f_res = [2.2e9, 2.4e9]
    t0 = time.time()
    nf.CalcNF2FF(run_dir, f_res, np.arange(-180.0, 180.0, 2.0), [0., 90.], center=[0, 0, 1e-3],
                 read_cached=False, outfile=f'nf_{tag}_cuts.h5')
    t1 = time.time()
    nf.CalcNF2FF(run_dir, f_res, np.arange(0, 182, 2.0), np.arange(0, 362, 2.0), center=[0, 0, 1e-3],
                 read_cached=False, outfile=f'nf_{tag}_3d.h5')
    t2 = time.time()
    print(f'{tag:8s} 2 cuts x 2 freq {t1-t0:6.2f} s   3D 91x181 x 2 freq {t2-t1:6.2f} s')
else:
    import h5py
    ref = sys.argv[3]; tag = sys.argv[4]
    for kind in ('cuts', '3d'):
        with h5py.File(os.path.join(run_dir, f'nf_{ref}_{kind}.h5')) as a, \
             h5py.File(os.path.join(run_dir, f'nf_{tag}_{kind}.h5')) as b:
            out = []
            for name in ('E_theta', 'E_phi', 'P_rad'):
                g = a[f'nf2ff/{name}/FD']
                worst = 0.0
                for key in g:
                    da, db = np.asarray(g[key]), np.asarray(b[f'nf2ff/{name}/FD'][key])
                    if not np.max(np.abs(da)) > 0:
                        sys.exit(f'nfcmp.py: the far field of {ref} is all zero ({name} {key}): no dumps in the run')
                    worst = max(worst, np.max(np.abs(da-db))/np.max(np.abs(da)))
                out.append(f'{name} {worst:.1e}')
            for attr in ('Dmax', 'Prad'):
                va, vb = np.asarray(a['nf2ff'].attrs[attr]), np.asarray(b['nf2ff'].attrs[attr])
                out.append(f'{attr} {np.max(np.abs(va-vb)/np.abs(va)):.1e}')
            print(f'{kind:5s} {tag} vs {ref}: max rel diff  ' + '  '.join(out))
