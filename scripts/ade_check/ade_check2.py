"""Stricter identity check of the packed ADE hooks (cg33c and later).
usage: python3 ade_check2.py NEWSNAP SIZE NRTS WORKDIR [quick] [SUMMARY=path]      (suggested: XS 3000)

What is different from ade_check.py
 1. Route: every case is built and run IN-PROCESS in a child python through FDTD.Run() (fixed NrTS, EndCriteria 0), as
    bench/runner.py does, not via Write2XML + the binary (Write2XML keeps box coordinates to ~7 digits, mesh lines to 15,
    so zero-thickness boxes can be dropped). The child gets DYLD_LIBRARY_PATH = $OPENEMS_BENCH_SNAPS/<snap> (default ~/opt/openEMS-dev/snap; this
    python3 is not SIP-protected, so it reaches the module's libraries by leaf name) and OPENEMS_EXPORT_FIELDS (fork only).
    The child's loaded libraries are listed and checked against the snapshot.
 2. Two references per case: `stock` (probes + HDF5 dumps; stock cannot export raw fields) and `cg31` (probes, dumps, fields).
    Every new-snapshot row must equal both where comparable. stock != cg31 prints a FINDING line (not a failure).
 3. "packed hooks" must appear in the log of every multithreaded run of the NEW snapshot, except OPENEMS_ADE_PACKED=0 rows
    and the `refuse` case (memory cap: it must NOT be packed there). Otherwise the row FAILS.
 4. Non-zero guard: each case prints its probe peak; a row FAILS when any probe file or the exported fields are all zero.
 5. Cases: dispersive, antenna (upstream), mixed, debye4, refuse, cyl (a cylindrical mesh with Debye + Lorentz rings).
 6. SUMMARY.txt (in WORKDIR, or the SUMMARY= argument): one line per row; exit code 0 = ALL IDENTICAL, 1 otherwise.
    `quick` = first four configs, first three cases (dispersive, mixed, refuse).
Sizes are upstream's (XS 37^3 cells ...), except that even line counts get one more line (see child()). The reference rows run at 4 threads multithreaded."""
import os, sys, subprocess, filecmp, shutil, re

# CASES_DIR: upstream's benchmark/ folder (cases.py) in the sources of upstream master 1d710c2, the $MASTER_DIR/src that
# scripts/m5pro/master/build.zsh builds from (made by `git archive`); ADE_CASES_DIR names the folder directly.
CASES_DIR = os.environ.get('ADE_CASES_DIR') or os.path.join(os.environ.get('MASTER_DIR', '.'), 'src', 'openEMS', 'benchmark')
SNAP = os.path.expanduser(os.environ.get('OPENEMS_BENCH_SNAPS', '~/opt/openEMS-dev/snap'))
BENCH_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'bench')   # libinfo.py


# ------------------------------------------------------------------------------------------------ child: build + run
def build(cases, name, size):
    np = cases.np
    if name in ('dispersive', 'antenna'):
        return getattr(cases, name)(size)
    if name == 'mixed':
        # two-order Lorentz with electric AND magnetic dispersion (order 0: Lorentz terms, order 1: Drude), a two-pole
        # Debye block, boxes that do not fill z in multiples of four (partial groups)
        FDTD, CSX = cases._setup(['MUR'] * 6)
        E = cases._uniform(CSX, size)
        lor = cases.CSPropLorentzMaterial(CSX.GetParameterSet(), order=2)
        lor.SetName('lor2')
        lor.SetDispersiveMaterialProperty(0, eps_plasma=5e9, eps_pole_freq=3e9, eps_relax=1e-9,
                                          mue_plasma=2e9, mue_pole_freq=2e9, mue_relax=2e-9)
        lor.SetDispersiveMaterialProperty(1, eps_plasma=3e9, eps_relax=3e-9, mue_plasma=1e9, mue_relax=4e-9)
        CSX.AddProperty(lor)
        lor.AddBox([-0.7*E, -0.6*E, -0.53*E], [-1, 0.75*E, 0.61*E], priority=10)
        deb = cases.CSPropDebyeMaterial(CSX.GetParameterSet(), order=2, epsilon=3)
        deb.SetName('deb2')
        deb.SetDispersiveMaterialProperty(0, eps_delta=1, eps_relax=1/(2*np.pi*4e9))
        deb.SetDispersiveMaterialProperty(1, eps_delta=0.5, eps_relax=1/(2*np.pi*9e9))
        CSX.AddProperty(deb)
        deb.AddBox([3, -0.55*E, -0.47*E], [0.66*E, 0.7*E, 0.59*E], priority=10)
        cases._dipole(CSX)
        return FDTD
    if name in ('debye4', 'refuse'):
        # debye4: a 4-pole Debye block (packed). refuse: 4 poles over ~73 % of the cells = ~131 B/cell of packed blocks,
        # far above the cap (~48 B per grid cell), so packing must be refused
        FDTD, CSX = cases._setup(['MUR'] * 6)
        E = cases._uniform(CSX, size)
        deb = cases.CSPropDebyeMaterial(CSX.GetParameterSet(), order=4, epsilon=3)
        deb.SetName(name)
        for i, (de, f) in enumerate(((1.0, 2e9), (0.7, 4e9), (0.5, 8e9), (0.3, 16e9))):
            deb.SetDispersiveMaterialProperty(i, eps_delta=de, eps_relax=1/(2*np.pi*f))
        CSX.AddProperty(deb)
        if name == 'debye4':
            deb.AddBox([3, -0.7*E, -0.6*E], [0.8*E, 0.7*E, 0.65*E], priority=10)
        else:
            deb.AddBox([-0.9*E, -0.9*E, -0.9*E], [0.9*E, 0.9*E, 0.9*E], priority=10)
        cases._dipole(CSX)
        return FDTD
    if name == 'cyl':
        FDTD, CSX = cases._setup(['PEC', 'PEC', 'PEC', 'PEC', 'MUR', 'MUR'], CoordSystem=1)
        nr, na, nz = cases.CYL_CELLS[size]
        mesh = CSX.GetGrid()
        mesh.AddLine('r', np.arange(nr))
        mesh.AddLine('a', np.linspace(-np.pi, np.pi, na + 1))
        mesh.AddLine('z', np.arange(nz) - (nz - 1) / 2)
        R = nr - 1
        Z = (nz - 1) / 2
        deb = cases.CSPropDebyeMaterial(CSX.GetParameterSet(), order=2, epsilon=3)
        deb.SetName('ringD')
        deb.SetDispersiveMaterialProperty(0, eps_delta=1, eps_relax=1/(2*np.pi*4e9))
        deb.SetDispersiveMaterialProperty(1, eps_delta=0.5, eps_relax=1/(2*np.pi*9e9))
        CSX.AddProperty(deb)
        deb.AddBox([0.4*R, -np.pi, -0.6*Z], [0.55*R, np.pi, 0.6*Z], priority=10)
        lor = cases.CSPropLorentzMaterial(CSX.GetParameterSet(), order=1)
        lor.SetName('ringL')
        lor.SetDispersiveMaterialProperty(0, eps_plasma=5e9, eps_pole_freq=3e9, eps_relax=1e-9)
        CSX.AddProperty(lor)
        lor.AddBox([0.6*R, -np.pi, -0.6*Z], [0.75*R, np.pi, 0.6*Z], priority=10)
        CSX.AddExcitation('line', exc_type=0, exc_val=[0, 0, 1]).AddBox([3, 0, -1], [3, 0, 1])
        CSX.AddProbe('et', p_type=2).AddPoint([5, 0.2, 0])
        CSX.AddProbe('ht', p_type=3).AddPoint([2, -0.3, 1])
        CSX.AddProbe('et2', p_type=2).AddPoint([0.5*R, -0.4, 0.3*Z])
        return FDTD
    raise SystemExit('unknown case ' + name)


def child(argv):
    name, size, nrts, simdir, engine, threads = argv
    sys.path.insert(0, CASES_DIR)
    import cases
    # upstream's uniform meshes are np.arange(n) - (n-1)/2: with an even line count (S = 100, M = 200) no mesh line passes
    # through the origin, the dipole at (0, 0, z) excites nothing and every field stays zero (found 2026-11-13: "Voltage
    # excitations: 0"). The check needs a source, so even counts get one more line here (S = 101, M = 201).
    cases.LINES = {k: v + 1 - v % 2 for k, v in cases.LINES.items()}
    sys.path.insert(0, BENCH_DIR)
    try:
        from libinfo import loaded_libs
    except Exception:
        loaded_libs = lambda: []
    FDTD = build(cases, name, size)
    FDTD.SetNumberOfTimeSteps(int(nrts))
    FDTD.SetEndCriteria(0)
    for p in loaded_libs():
        print('CHECK_LIB', p, flush=True)
    FDTD.Run(os.path.abspath(simdir), cleanup=True, verbose=2, engine=engine, numThreads=int(threads))


if len(sys.argv) > 1 and sys.argv[1] == '--child':
    child(sys.argv[2:])
    sys.exit(0)

# ------------------------------------------------------------------------------------------------ parent
import numpy as np

args = [a for a in sys.argv[1:] if not a.startswith('SUMMARY=')]
new, size, nrts, work = args[0], args[1], int(args[2]), os.path.abspath(args[3])
quick = len(args) > 4 and args[4] == 'quick'
summ = [a[8:] for a in sys.argv[1:] if a.startswith('SUMMARY=')]
summary_path = os.path.abspath(summ[0]) if summ else os.path.join(work, 'SUMMARY.txt')
os.makedirs(work, exist_ok=True)


def run(case, tag, snap, engine, threads, env):
    d = os.path.join(work, '%s_%s' % (case, tag))
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(os.path.join(d, 'fields'))
    e = dict(os.environ, DYLD_LIBRARY_PATH=os.path.join(SNAP, snap), OPENEMS_EXPORT_FIELDS=os.path.join(d, 'fields'), **env)
    with open(os.path.join(d, 'log.txt'), 'w') as log:
        rc = subprocess.run([sys.executable, os.path.abspath(__file__), '--child', case, size, str(nrts), d, engine,
                             str(threads)], cwd=d, stdout=log, stderr=subprocess.STDOUT, env=e).returncode
    text = open(os.path.join(d, 'log.txt'), errors='replace').read()
    ver = (re.findall(r'version (v0\.37\S*)', text) or re.findall(r'(v0\.37\.0\S*)', text) or ['?'])[0]
    libs = re.findall(r'CHECK_LIB (\S+)', text)
    libok = all(l.startswith(os.path.join(SNAP, snap) + '/') for l in libs if os.path.basename(l).startswith('libopenEMS')) \
        and any(os.path.basename(l).startswith('libopenEMS') for l in libs)
    return dict(dir=d, rc=rc, ver=ver, packed='packed hooks' in text, libok=libok,
                speed=(re.findall(r'Speed: (\S+) MCells/s', text) or ['?'])[0])


def files(d):
    out = []
    for root, _, fs in os.walk(d):
        for f in fs:
            r = os.path.relpath(os.path.join(root, f), d)
            if r == 'log.txt' or r.endswith('.xml') or r.endswith('.vtk') or r.startswith('openEMS_'):
                continue
            out.append(r)
    return sorted(out)


def same(a, b):
    """probe text files without their '%' header lines; HDF5 files dataset by dataset, bit for bit; others byte for byte"""
    if a.endswith('.h5'):
        import h5py
        da, db = {}, {}
        for fn, out in ((a, da), (b, db)):
            with h5py.File(fn, 'r') as h:
                h.visititems(lambda k, v: out.__setitem__(k, np.asarray(v).tobytes()) if isinstance(v, h5py.Dataset) else None)
        return da == db and len(da) > 0
    if filecmp.cmp(a, b, shallow=False):
        return True
    try:
        ta = [l for l in open(a) if not l.startswith('%')]
        tb = [l for l in open(b) if not l.startswith('%')]
    except UnicodeDecodeError:
        return False
    return ta == tb and len(ta) > 0


def probe_peak(d, fl):
    """max abs over the numeric columns of every probe text file; list of all-zero probe files"""
    peak, zero = 0.0, []
    for f in fl:
        if f.startswith('fields') or f.endswith('.h5'):
            continue
        rows = []
        try:
            for l in open(os.path.join(d, f)):
                if l.startswith('%') or not l.strip():
                    continue
                rows.append([float(x) for x in l.split()])
            a = np.array(rows, dtype=float)
        except (ValueError, UnicodeDecodeError):
            continue
        if a.size == 0:
            continue
        if a.ndim == 2 and a.shape[1] > 1:
            a = a[:, 1:]            # column 0 is time
        m = float(np.nanmax(np.abs(a)))
        peak = max(peak, m)
        if m == 0.0:
            zero.append(f)
    return peak, zero


def field_peak(d):
    """max abs of the exported raw fields (None when nothing exported)"""
    fd = os.path.join(d, 'fields')
    fs = [f for f in os.listdir(fd)] if os.path.isdir(fd) else []
    fs = [f for f in fs if f.endswith('.f32')]
    if not fs:
        return None
    return max(float(np.nanmax(np.abs(np.fromfile(os.path.join(fd, f), dtype=np.float32)))) if os.path.getsize(os.path.join(fd, f)) else 0.0
               for f in fs)


def ndiff(a, b, fl_a, fl_b, with_fields):
    """differing files between two run dirs; None-compat: list of names"""
    sel = lambda fl: [f for f in fl if with_fields or not f.startswith('fields')]
    sa, sb = sel(fl_a), sel(fl_b)
    diff = [f for f in sa if f not in sb or not same(os.path.join(a, f), os.path.join(b, f))]
    diff += ['(extra) ' + f for f in sb if f not in sa]
    return diff


CONFIGS = [  # tag, snap, engine, threads, env
    ('ref_stock', 'stock', 'multithreaded', 4, {}),
    ('ref_cg31', 'cg31', 'multithreaded', 4, {}),
    ('new_mt4', new, 'multithreaded', 4, {}),
    ('new_mt1', new, 'multithreaded', 1, {}),
    ('new_mt15', new, 'multithreaded', 15, {}),
    ('new_mt7', new, 'multithreaded', 7, {}),
    ('new_unfused4', new, 'multithreaded', 4, {'OPENEMS_FUSED': '0'}),
    ('new_tiled4', new, 'multithreaded', 4, {'OPENEMS_TBLOCK': '3'}),
    ('new_off4', new, 'multithreaded', 4, {'OPENEMS_ADE_PACKED': '0'}),
    ('new_ssec', new, 'sse-compressed', 1, {}),
    ('new_basic', new, 'basic', 1, {}),
]
CASELIST = ['dispersive', 'mixed', 'antenna', 'debye4', 'refuse', 'cyl']
if quick:
    CONFIGS = CONFIGS[:5]       # two references + new at 4/1/15 threads (the old script's first four configs)
    CASELIST = ['dispersive', 'mixed', 'refuse']
# optional filters for finishing a partial run: ADE_CASES=refuse,cyl  ADE_TAGS=ref_stock,ref_cg31,new_ssec (comma lists)
if os.environ.get('ADE_CASES'):
    CASELIST = [c for c in CASELIST if c in os.environ['ADE_CASES'].split(',')]
if os.environ.get('ADE_TAGS'):
    CONFIGS = [c for c in CONFIGS if c[0] in os.environ['ADE_TAGS'].split(',')]

lines = []
def out(s):
    print(s, flush=True)
    lines.append(s)

bad = 0
findings = 0
for case in CASELIST:
    R = {}
    for tag, snap, engine, threads, env in CONFIGS:
        r = run(case, tag, snap, engine, threads, env)
        d = r['dir']
        fl = files(d)
        r['files'] = fl
        pk, zero = probe_peak(d, fl)
        fk = field_peak(d)
        r['peak'] = pk
        reasons = []
        if r['rc'] != 0:
            reasons.append('rc %d' % r['rc'])
        if not fl or not any(not f.startswith('fields') for f in fl):
            reasons.append('no output files')
        if pk == 0.0 or zero:
            reasons.append('all-zero probe(s) %s' % (zero[:3] or 'all'))
        is_new = tag.startswith('new_')
        if snap != 'stock' and not (fk and fk > 0):
            reasons.append('fields all zero' if fk == 0 else 'no fields exported')
        if not r['libok']:
            reasons.append('loaded library is not the snapshot')
        # packed rule
        pk_expected = None
        if is_new and engine == 'multithreaded':
            pk_expected = not (env.get('OPENEMS_ADE_PACKED') == '0' or case == 'refuse')
            if r['packed'] != pk_expected:
                reasons.append('packed %s but expected %s' % ('yes' if r['packed'] else 'no', 'yes' if pk_expected else 'no'))
        # comparison with references
        note = ''
        if tag == 'ref_stock':
            R['stock'] = r
        elif tag == 'ref_cg31':
            R['cg31'] = r
            if 'stock' in R:
                dd = ndiff(R['stock']['dir'], d, R['stock']['files'], fl, False)
                if dd:
                    findings += 1
                    out('   *** FINDING: stock differs from cg31 on case %s: %s' % (case, dd[:4]))
                    note = ' (differs from stock: %s)' % dd[:2]
        else:
            for refname, withf in (('stock', False), ('cg31', True)):
                if refname in R and R[refname]['rc'] == 0:
                    dd = ndiff(R[refname]['dir'], d, R[refname]['files'], fl, withf)
                    if dd:
                        reasons.append('differs from %s: %s' % (refname, dd[:4]))
        ok = not reasons
        bad += 0 if ok else 1
        verdict = 'IDENTICAL' if ok and is_new else ('OK' if ok else 'FAIL: ' + '; '.join(reasons))
        out('%-10s %-13s %-6s %-26s packed %-3s peak %.4g  %s MC/s  %s%s' % (
            case, tag, snap, r['ver'], 'yes' if r['packed'] else 'no', pk, r['speed'], verdict, note))

out('ALL IDENTICAL' if bad == 0 else '%d FAIL' % bad)
if findings:
    out('(%d FINDING line(s): stock vs cg31 differ, see above; not counted as failures)' % findings)
with open(summary_path, 'w') as fh:
    fh.write('\n'.join(lines) + '\n')
sys.exit(1 if bad else 0)
