"""Shared helpers for the emsKit validation suite.

Every case builds an openEMS model whose answer is known in closed form (or from an exact
discrete formula), runs it on whatever openEMS the current Python imports, and compares.
Engine and threads come from the environment so the same suite checks stock and the fork:

  VALIDATION_ENGINE   openEMS engine name (default 'fastest' = the multithreaded engine);
                      'gpu', 'gpu-reference' and 'metal-diamond' exist only in the fork (stock runs its default
                      engine for them without a message, so the engine each run reported is
                      recorded); cylindrical meshes always run the cylindrical multithreaded
                      engine, or its GPU backend for 'gpu' and 'gpu-reference'
  VALIDATION_THREADS  thread count (default 0 = openEMS default / the fork's auto count)
"""
import ctypes
import os
import re
import shutil
import sys

import numpy as np

C0 = 299792458.0
EPS0 = 8.8541878128e-12
MU0 = 4e-7 * np.pi
Z0_FREE = np.sqrt(MU0 / EPS0)
ENGINES = ('fastest', 'basic', 'sse', 'sse-compressed', 'multithreaded', 'gpu', 'gpu-reference', 'metal-diamond')
RUNS = []    # one entry per run(): run directory name, engine(s) and threads as openEMS reported them
_libc = ctypes.CDLL(None)


def engine():
    """The engine named by VALIDATION_ENGINE; an unknown name is an error, not a silent default."""
    e = os.environ.get('VALIDATION_ENGINE', 'fastest')
    if e not in ENGINES:
        raise ValueError(f"VALIDATION_ENGINE={e!r} is not an openEMS engine ({', '.join(ENGINES)})")
    return e


def tidy(s):
    """A string with the home directory written as '~' (result files carry no personal paths)."""
    return s.replace(os.path.expanduser('~'), '~') if isinstance(s, str) else s


def run(fdtd, sim_dir, verbose=0, eng=None):
    """Run in-process (like bench/runner.py), fresh directory, no dumps. openEMS's console output
    goes to SIM_DIR.log; the engine and thread count it reports are appended to RUNS. FDTD.Run
    changes into the run directory: the caller's working directory is restored afterwards."""
    sim_dir = os.path.abspath(sim_dir)
    if os.path.isdir(sim_dir):
        shutil.rmtree(sim_dir)
    os.makedirs(sim_dir)
    kw = dict(engine=eng or engine(), verbose=verbose, cleanup=True)
    nt = int(os.environ.get('VALIDATION_THREADS', '0') or 0)
    if nt:
        kw['numThreads'] = nt
    cwd, log = os.getcwd(), sim_dir + '.log'
    sys.stdout.flush()
    _libc.fflush(None)
    saved = os.dup(1)
    try:
        with open(log, 'w') as fh:
            os.dup2(fh.fileno(), 1)
            try:
                fdtd.Run(sim_dir, **kw)
            finally:
                _libc.fflush(None)
                os.dup2(saved, 1)
    finally:
        os.close(saved)
        os.chdir(cwd)
    text = open(log, errors='replace').read()
    engines = sorted(set(m or 'basic' for m in re.findall(r'^Create FDTD engine(?: \((.*)\))?\s*$', text, re.M)))
    thr = re.search(r'fixed number of threads: (\d+)', text)
    auto = re.search(r'Best performance found using (\d+) threads', text)
    multi = any('multi' in e for e in engines)     # the thread count matters to the multithreaded engines only
    RUNS.append(dict(run=os.path.basename(sim_dir), engine='; '.join(engines) or '?',
                     threads=(f'{thr[1]} (fixed)' if thr else f'{auto[1]} (auto)' if auto else '') if multi else ''))


def read_probe(sim_dir, name):
    """Time and value columns of a time-domain probe file written by openEMS."""
    d = np.loadtxt(os.path.join(sim_dir, name), comments='%')
    return d[:, 0], d[:, 1]


def dft(t, x, f):
    """Plain DFT at arbitrary frequencies, exp(-j w t) kernel (phasor convention exp(+j w t))."""
    dt = t[1] - t[0]
    return np.array([np.sum(x * np.exp(-2j * np.pi * fi * t)) * dt for fi in np.atleast_1d(f)])


def spectral_peaks(t, x, fmin, fmax, pad=16):
    """Peak frequencies of a ringing signal: Hann window, zero-padded FFT, parabolic interpolation
    on the log magnitude. Returns (freqs, magnitudes) of all local maxima in [fmin, fmax]."""
    dt = t[1] - t[0]
    n = len(x)
    w = np.hanning(n)
    nfft = 1 << int(np.ceil(np.log2(n * pad)))
    X = np.abs(np.fft.rfft((x - x.mean()) * w, nfft))
    f = np.fft.rfftfreq(nfft, dt)
    sel = np.where((f >= fmin) & (f <= fmax))[0]
    peaks, mags = [], []
    for i in sel[1:-1]:
        if X[i] > X[i - 1] and X[i] >= X[i + 1]:
            a, b, c = np.log(X[i - 1] + 1e-300), np.log(X[i] + 1e-300), np.log(X[i + 1] + 1e-300)
            den = a - 2 * b + c
            p = 0.5 * (a - c) / den if den != 0 else 0.0
            peaks.append(f[i] + p * (f[1] - f[0]))
            mags.append(X[i])
    return np.array(peaks), np.array(mags)


def match_modes(f_ref, peaks, mags, window=0.02, rel_floor=1e-3):
    """For each reference frequency, the strongest peak within +-window (relative), ignoring peaks
    below rel_floor of the strongest one. Returns array of matched frequencies (nan if none)."""
    keep = mags >= rel_floor * mags.max() if len(mags) else []
    p, m = peaks[keep], mags[keep]
    out = []
    for fr in f_ref:
        near = np.where(np.abs(p - fr) <= window * fr)[0]
        out.append(p[near[np.argmax(m[near])]] if len(near) else np.nan)
    return np.array(out)


def check(case, quantity, value, reference, tol, kind='rel', note=''):
    """One validation result. kind 'rel': |v-r|/|r| <= tol; 'abs': |v-r| <= tol; 'max': v <= r + tol."""
    value = float(value) if np.isscalar(value) or np.ndim(value) == 0 else value
    if np.isscalar(value) and np.isnan(value):
        err, ok = float('nan'), False
    else:
        if kind == 'max':                         # pass if value <= reference + tol
            err = float(value - reference)
            ok = err <= tol
        else:
            err = abs(value - reference) / abs(reference) if kind == 'rel' else abs(value - reference)
            err = float(np.max(err))
            ok = err <= tol
    return dict(case=case, quantity=quantity, value=value if np.isscalar(value) else None,
                reference=float(reference) if np.isscalar(reference) else None,
                error=err, tol=tol, kind=kind, passed=bool(ok), note=note)
