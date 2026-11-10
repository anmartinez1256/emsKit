"""memcheck.py N NRTS VARIANT OUTDIR: openEMS heap use per mesh node, setup peak against the running state (2026-11-03).
The per-node figures are slopes between two mesh sizes (N = 40, 52, 64), which removes the fixed part.
FDTD.Run runs in a worker thread (the wrapper releases the GIL); the main thread samples
malloc_zone_statistics(NULL) size_in_use every ~0.5 ms and records the maximum and the
values during the time loop (after 'Running FDTD engine' appears is not observable, so we
take the median of the last 40 % of the samples, when setup is long done).
VARIANT: plain (dumps disabled) | dump (one 2x2x2 E-field TD dump box, dumps enabled)
Mesh: N lines per axis (N multiple of 4: no f4vector padding), PEC box, soft E excitation."""
import os, sys, time, ctypes, threading, resource, json
import numpy as np
from CSXCAD import ContinuousStructure
from openEMS import openEMS

N, nrts = int(sys.argv[1]), int(sys.argv[2])
variant = sys.argv[3]
out = os.path.abspath(sys.argv[4])

class MStats(ctypes.Structure):
    _fields_ = [('blocks_in_use', ctypes.c_uint), ('size_in_use', ctypes.c_size_t),
                ('max_size_in_use', ctypes.c_size_t), ('size_allocated', ctypes.c_size_t)]
libc = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
libc.malloc_zone_statistics.argtypes = [ctypes.c_void_p, ctypes.POINTER(MStats)]
libc.malloc_zone_statistics.restype = None
def in_use():
    s = MStats(); libc.malloc_zone_statistics(None, ctypes.byref(s)); return s.size_in_use
def hwm():
    s = MStats(); libc.malloc_zone_statistics(None, ctypes.byref(s)); return s.max_size_in_use

FDTD = openEMS(NrTS=nrts, EndCriteria=0)
FDTD.SetGaussExcite(2e9, 1e9)
FDTD.SetBoundaryCond(['PEC'] * 6)
CSX = ContinuousStructure()
FDTD.SetCSX(CSX)
mesh = CSX.GetGrid()
mesh.SetDeltaUnit(1e-3)
for d in 'xyz':
    mesh.AddLine(d, np.arange(N, dtype=float))
exc = CSX.AddExcitation('exc', exc_type=0, exc_val=[0, 0, 1])
exc.AddBox(start=[N // 2, N // 2, N // 4], stop=[N // 2, N // 2, N // 4 + 2])
if variant == 'dump':
    dmp = CSX.AddDump('Et', dump_type=0, file_type=1)
    dmp.AddBox(start=[N // 2 - 1, N // 2 - 1, N // 2 - 1], stop=[N // 2 + 1, N // 2 + 1, N // 2 + 1])
kw = dict(engine='multithreaded', numThreads=2)
if variant == 'plain':
    kw['disable_dumps'] = True

base = in_use()
hwm0 = hwm()
samples = []
done = threading.Event()
def worker():
    FDTD.Run(out, cleanup=True, verbose=0, **kw)
    done.set()
t = threading.Thread(target=worker)
t0 = time.time()
t.start()
while not done.is_set():
    samples.append((time.time() - t0, in_use()))
    time.sleep(0.0005)
t.join()
after = in_use()
hwm1 = hwm()
v = np.array([s[1] for s in samples], float)
tt = np.array([s[0] for s in samples], float)
tail = v[int(0.6 * len(v)):]
dyld = ctypes.CDLL(None)
dyld._dyld_image_count.restype = ctypes.c_uint32
dyld._dyld_get_image_name.restype = ctypes.c_char_p
libs = [dyld._dyld_get_image_name(i).decode() for i in range(dyld._dyld_image_count())]
res = dict(N=N, nodes=N ** 3, variant=variant, nsamples=len(v), wall=float(tt[-1]) if len(tt) else 0,
           base=base, hwm0=hwm0, hwm1=hwm1, peak=float(v.max()), run_med=float(np.median(tail)), after=after,
           peak_t=float(tt[v.argmax()]), maxrss=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
           libs=[l.replace(os.path.expanduser('~'), '~') for l in libs if 'libopenEMS' in l or 'libCSXCAD' in l])
print("RESULT " + json.dumps(res))
