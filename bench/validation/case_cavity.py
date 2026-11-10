"""Resonant frequencies of closed PEC cavities.

rect: a 100 x 60 x 80 mm box on a uniform 2 mm mesh with a fixed time step. Two references:
  - the continuum formula f = c/2 sqrt((m/a)^2 + (n/b)^2 + (p/d)^2)   (tests the physics, ~0.1 %)
  - the exact discrete Yee dispersion relation for the same mesh and time step
      sin(w dt/2) = c dt/2 * sqrt(sum_i (2/D_i sin(k_i D_i/2))^2),  k_i = m_i pi / L_i
    which a correct engine reproduces to the precision of the peak estimate (1.5e-8 measured).
    This is the tight engine check for errors that touch the whole grid (a wrong coefficient,
    a missed or doubled update); an error confined to a few cells moves the modes far less and
    can pass. Races between threads are covered by check.sh (bit identity across thread
    counts), not here.
cyl: a 50 mm radius, 60 mm long cylinder in cylindrical coordinates with the multigrid
  (three nested alpha grids), against f = c/(2 pi) sqrt((x/R)^2 + (p pi/L)^2), x a zero of J_m
  (TM) or J_m' (TE). Exercises the cylindrical and multigrid engines: openEMS runs a cylindrical
  mesh on its cylindrical multithreaded engine (its GPU backend for gpu / gpu-reference),
  whatever VALIDATION_ENGINE says.
Every expected mode must be found; the error checks use the modes that were.
"""
import os

import numpy as np
from scipy.special import jn_zeros, jnp_zeros
from CSXCAD import ContinuousStructure
from CSXCAD.CSRectGrid import CoordinateSystem
from openEMS import openEMS

from common import C0, check, match_modes, read_probe, run, spectral_peaks

# ---------------------------------------------------------------- rectangular
A, B, D, H = 100.0, 60.0, 80.0, 2.0      # mm
F_RECT = (1.5e9, 4.2e9)
TOL_RECT_CONT = 0.002                     # continuum, relative (measured 5.5e-4: the Yee dispersion)
TOL_RECT_DISC = 1e-7                      # exact discrete Yee, relative (measured 1.55e-8; 1.89e-8 with --quick)


def rect_modes(fmin, fmax, dt=None):
    out = []
    for m in range(6):
        for n in range(6):
            for p in range(6):
                if (m > 0) + (n > 0) + (p > 0) < 2:
                    continue
                k = np.array([m * np.pi / A, n * np.pi / B, p * np.pi / D]) * 1e3
                fc = C0 / (2 * np.pi) * np.linalg.norm(k)
                if dt is None:
                    f = fc
                else:
                    s = C0 * dt / 2 * np.sqrt(np.sum((2 / (H * 1e-3) * np.sin(k * H * 1e-3 / 2))**2))
                    f = 2 / dt * np.arcsin(s) / (2 * np.pi)
                if fmin <= fc <= fmax:
                    out.append(((m, n, p), fc, f))
    out.sort(key=lambda x: x[1])
    return out


def build_rect(nrts, dt):
    fdtd = openEMS(NrTS=nrts, EndCriteria=0)
    fdtd.SetGaussExcite(2.85e9, 1.5e9)
    fdtd.SetBoundaryCond(['PEC'] * 6)
    fdtd.SetTimeStep(dt)
    csx = ContinuousStructure()
    fdtd.SetCSX(csx)
    mesh = csx.GetGrid()
    mesh.SetDeltaUnit(1e-3)
    for ax, L in zip('xyz', (A, B, D)):
        mesh.SetLines(ax, np.arange(0, L + H / 2, H))
    exc = csx.AddExcitation('exc', exc_type=0, exc_val=[1, 1, 1])
    exc.AddBox([22, 14, 26], [24, 16, 28])
    for ax, stop in zip('xyz', ([72, 42, 50], [70, 44, 50], [70, 42, 52])):
        csx.AddProbe(f'ut_{ax}', p_type=0).AddBox([70, 42, 50], stop)
    return fdtd


# ---------------------------------------------------------------- cylindrical
R, L_CYL, DR = 50.0, 60.0, 2.0            # mm
N_ALPHA_INNER, SPLITS = 16, [10.0, 20.0, 35.0]
F_CYL = (2.0e9, 4.6e9)
TOL_CYL = 0.005                           # measured 0.16 %


def cyl_modes(fmin, fmax):
    out = []
    for m in range(4):
        for p in range(4):
            for nz, x in enumerate(jn_zeros(m, 3), 1):            # TM_mnp, p >= 0
                f = C0 / (2 * np.pi) * np.hypot(x / (R * 1e-3), p * np.pi / (L_CYL * 1e-3))
                if fmin <= f <= fmax:
                    out.append((f'TM{m}{nz}{p}', f))
            if p == 0:
                continue
            for nz, x in enumerate(jnp_zeros(m, 3), 1):               # TE_mnp, p >= 1
                f = C0 / (2 * np.pi) * np.hypot(x / (R * 1e-3), p * np.pi / (L_CYL * 1e-3))
                if fmin <= f <= fmax:
                    out.append((f'TE{m}{nz}{p}', f))
    out.sort(key=lambda x: x[1])
    merged = []
    for name, f in out:                    # TE0np and TM1np are degenerate: keep one entry
        if merged and abs(f - merged[-1][1]) < 1e-6 * f:
            merged[-1] = (merged[-1][0] + '/' + name, f)
        else:
            merged.append((name, f))
    return merged


def build_cyl(nrts):
    fdtd = openEMS(NrTS=nrts, EndCriteria=0, CoordSystem=1, MultiGrid=SPLITS)
    fdtd.SetGaussExcite(3.3e9, 1.6e9)
    fdtd.SetBoundaryCond(['PEC'] * 6)
    csx = ContinuousStructure(CoordSystem=CoordinateSystem.CYLINDRICAL)
    fdtd.SetCSX(csx)
    mesh = csx.GetGrid()
    mesh.SetDeltaUnit(1e-3)
    mesh.SetLines('r', np.arange(0, R + DR / 2, DR))
    a = np.linspace(-np.pi, np.pi, N_ALPHA_INNER * 2**len(SPLITS) + 1)
    mesh.SetLines('a', a)
    mesh.SetLines('z', np.arange(0, L_CYL + DR / 2, DR))
    exc = csx.AddExcitation('exc', exc_type=0, exc_val=[1, 1, 1])
    exc.AddBox([30, a[70], 20], [32, a[71], 22])
    p0 = [36, a[23], 34]
    for ax, stop in zip('raz', ([38, a[23], 34], [36, a[24], 34], [36, a[23], 36])):
        csx.AddProbe(f'ut_{ax}', p_type=0).AddBox(p0, stop)
    return fdtd


def _peaks(sim_dir, axes, fmin, fmax):
    t = None
    spec_sum = None
    for ax in axes:
        t, v = read_probe(sim_dir, f'ut_{ax}')
        p, m = spectral_peaks(t, v / (np.abs(v).max() + 1e-300), fmin, fmax)
        # pool the peaks of all three probe orientations
        spec_sum = (p, m) if spec_sum is None else (np.r_[spec_sum[0], p], np.r_[spec_sum[1], m])
    return spec_sum


def run_case(workdir, quick=False):
    res = []
    # rectangular, fixed time step
    dt = 0.95 * H * 1e-3 / (C0 * np.sqrt(3))
    nrts = 60000 if quick else 120000
    d = os.path.join(workdir, 'cavity_rect')
    run(build_rect(nrts, dt), d)
    peaks, mags = _peaks(d, 'xyz', *F_RECT)
    modes = rect_modes(*F_RECT, dt=dt)
    found = match_modes([m[2] for m in modes], peaks, mags, window=0.004)
    ok = ~np.isnan(found)
    e_cont = np.abs(found[ok] - np.array([m[1] for m in modes])[ok]) / np.array([m[1] for m in modes])[ok]
    e_disc = np.abs(found[ok] - np.array([m[2] for m in modes])[ok]) / np.array([m[2] for m in modes])[ok]
    names = ' '.join(f'{m[0][0]}{m[0][1]}{m[0][2]}' for m, k in zip(modes, ok) if k)
    res.append(check('cavity_rect', f'modes found ({len(modes)} expected)', ok.sum(), len(modes),
                     0, kind='abs', note=names))
    res.append(check('cavity_rect', 'max rel. error vs continuum', e_cont.max() if ok.any() else np.nan, 0.0,
                     TOL_RECT_CONT, kind='abs'))
    res.append(check('cavity_rect', 'max rel. error vs exact discrete Yee', e_disc.max() if ok.any() else np.nan,
                     0.0, TOL_RECT_DISC, kind='abs', note=f'mean {e_disc.mean():.1e}' if ok.any() else 'no mode found'))
    # cylindrical with multigrid
    nrts = 40000 if quick else 80000
    d = os.path.join(workdir, 'cavity_cyl')
    run(build_cyl(nrts), d)
    peaks, mags = _peaks(d, 'raz', *F_CYL)
    modes = cyl_modes(*F_CYL)
    found = match_modes([m[1] for m in modes], peaks, mags, window=0.02)
    ok = ~np.isnan(found)
    e = np.abs(found[ok] - np.array([m[1] for m in modes])[ok]) / np.array([m[1] for m in modes])[ok]
    names = ' '.join(f'{m[0]}:{x:+.2%}' for m, k, x in zip(modes, ok, np.where(ok, (found - [m[1] for m in modes]) / [m[1] for m in modes], np.nan)) if k)
    res.append(check('cavity_cyl', f'modes found ({len(modes)} expected)', ok.sum(), len(modes), 0, kind='abs',
                     note=names))
    res.append(check('cavity_cyl', 'max rel. error vs Bessel-zero formula', e.max() if len(e) else np.nan, 0.0,
                     TOL_CYL, kind='abs'))
    return res


if __name__ == '__main__':
    import sys
    for r in run_case(sys.argv[1] if len(sys.argv) > 1 else '/tmp/val', quick='--quick' in sys.argv):
        print(r)
