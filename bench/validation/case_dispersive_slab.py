"""Plane-wave reflection from a dispersive slab (Debye, Drude, Lorentz) against the exact
Fabry-Perot formula.

Geometry: a TEM parallel-plate channel along x (PEC walls in z, PMC walls in y, PML at both x
ends) carries an exact plane wave with E along z. A slab of thickness t fills the channel at
x = [x1, x1+t]. A voltage probe sits on the slab face x1; the incident field is taken from an
identical run without the slab, so R(f) = (V_slab - V_ref) / V_ref at the face, with no
propagation correction.

Material models (from openEMS operator_ext_*material.cpp, frequencies in Hz, exp(+jwt)):
  Debye:   eps(w) = eps_r + d_eps / (1 + j w tau)
  Drude:   eps(w) = eps_r * (1 - wp^2 / (w (w - j/tau)))                     wp = 2 pi f_plasma
  Lorentz: eps(w) = eps_r * (1 - wp^2 / (w^2 - wL^2 - j w/tau))              wL = 2 pi f_pole
This is the check that would have caught the fork's Debye bug (the multithreaded engine
dropped the Debye hooks: the slab then behaves like a plain eps_r dielectric).
The physics tolerance catches a lost or grossly wrong pole, also one shared by all engines (an
operator extension error). A hook error on a few x-lines only stays inside it, so each slab is
also run on the basic engine of the same build, and the probe of the selected engine must equal
it: within TOL_ENGINE_TOLERANT when the engine's name starts with 'gpu' (gpu, gpu-reference) or
OPENEMS_FTZ is set to anything but '' or '0' (subnormals flushed to zero), exactly otherwise
(metal-diamond without OPENEMS_FTZ too). The comparison is skipped when the selected engine is
basic.
"""
import os

import numpy as np
from CSXCAD import ContinuousStructure
from CSXCAD.CSProperties import CSPropDebyeMaterial, CSPropLorentzMaterial
from openEMS import openEMS

from common import C0, check, dft, engine, read_probe, run

MATERIALS = {
    # name: (model, eps_r, params)
    'debye': ('debye', 2.0, dict(eps_delta=6.0, eps_relax=50e-12)),
    'drude': ('drude', 1.0, dict(eps_plasma=8e9, eps_relax=100e-12)),
    'lorentz': ('lorentz', 2.0, dict(eps_plasma=6e9, eps_pole_freq=4e9, eps_relax=0.2e-9)),
}
F_LO, F_HI = 0.5e9, 9e9          # evaluation band
DX = 0.25                        # mm, propagation direction
X_MIN, X_MAX, X_SRC, X1, T = 0.0, 120.0, 20.0, 60.0, 6.0   # mm
TOL_R = 0.03                     # max |R_fdtd - R_exact| over the band (complex, absolute);
                                 # measured 0.010-0.020 at DX=0.25 mm, halving at 0.125 mm (first order)
TOL_ENGINE_TOLERANT = 1e-6       # max |v - v_basic| / max |v_basic| for the GPU engines and OPENEMS_FTZ;
                                 # measured 0 with the fork's GPU engine (quick and full) and OPENEMS_FTZ=1 (quick)


def eps_model(model, eps_r, p, f):
    w = 2 * np.pi * f
    if model == 'debye':
        return eps_r + p['eps_delta'] / (1 + 1j * w * p['eps_relax'])
    wp = 2 * np.pi * p['eps_plasma']
    if model == 'drude':
        return eps_r * (1 - wp**2 / (w * (w - 1j / p['eps_relax'])))
    wl = 2 * np.pi * p['eps_pole_freq']
    return eps_r * (1 - wp**2 / (w**2 - wl**2 - 1j * w / p['eps_relax']))


def slab_reflection(eps, f, t):
    """Normal-incidence reflection of a slab of thickness t (m) in vacuum, exp(+jwt)."""
    n = np.sqrt(eps.astype(complex))
    n = np.where(n.imag > 0, -n, n)          # decaying branch: Im(k) < 0
    g = (1 - n) / (1 + n)                    # vacuum -> slab, for E
    ph = np.exp(-2j * 2 * np.pi * f / C0 * n * t)
    return g * (1 - ph) / (1 - g**2 * ph)


def build(material, with_slab, nrts):
    fdtd = openEMS(NrTS=nrts, EndCriteria=0)
    fdtd.SetGaussExcite(5e9, 5e9)
    fdtd.SetBoundaryCond(['PML_8', 'PML_8', 'PMC', 'PMC', 'PEC', 'PEC'])
    csx = ContinuousStructure()
    fdtd.SetCSX(csx)
    mesh = csx.GetGrid()
    mesh.SetDeltaUnit(1e-3)
    mesh.SetLines('x', np.arange(X_MIN, X_MAX + DX / 2, DX))
    mesh.SetLines('y', [0, 1, 2])
    mesh.SetLines('z', [0, 1, 2])

    exc = csx.AddExcitation('plane', exc_type=0, exc_val=[0, 0, 1])
    exc.AddBox([X_SRC, 0, 0], [X_SRC, 2, 2])
    probe = csx.AddProbe('ut_face', p_type=0)
    probe.AddBox([X1, 1, 0], [X1, 1, 2])

    if with_slab:
        model, eps_r, p = MATERIALS[material]
        pset = csx.GetParameterSet()
        if model == 'debye':
            prop = CSPropDebyeMaterial(pset, name='slab', order=1, epsilon=eps_r)
        else:
            prop = CSPropLorentzMaterial(pset, name='slab', order=1, epsilon=eps_r)
        csx.AddProperty(prop)
        prop.SetDispersiveMaterialProperty(0, **p)
        prop.AddBox([X1, 0, 0], [X1 + T, 2, 2])
    return fdtd


def run_case(workdir, quick=False):
    nrts = 8000 if quick else 16000
    eng = engine()
    tolerant = eng.startswith('gpu') or os.environ.get('OPENEMS_FTZ', '') not in ('', '0')
    ref_dir = os.path.join(workdir, 'slab_ref')
    run(build(None, False, nrts), ref_dir)
    t, v_ref = read_probe(ref_dir, 'ut_face')
    f = np.linspace(F_LO, F_HI, 120)
    V_ref = dft(t, v_ref, f)
    results = []
    for name, (model, eps_r, p) in MATERIALS.items():
        d = os.path.join(workdir, f'slab_{name}')
        run(build(name, True, nrts), d)
        _, v = read_probe(d, 'ut_face')
        R = (dft(t, v, f) - V_ref) / V_ref
        R_ex = slab_reflection(eps_model(model, eps_r, p, f), f, T * 1e-3)
        err = np.abs(R - R_ex)
        # negative control: the same slab with its dispersion switched off (static eps_r only)
        R_bad = slab_reflection(np.full_like(f, eps_r, dtype=complex), f, T * 1e-3)
        sep = np.max(np.abs(R - R_bad))
        results.append(check(f'slab_{name}', 'max |R - R_exact| over 0.5-9 GHz', err.max(), 0.0, TOL_R, kind='abs',
                             note=f'mean {err.mean():.4f}; distance from non-dispersive answer {sep:.2f}'))
        if eng == 'basic':
            continue
        db = os.path.join(workdir, f'slab_{name}_basic')
        run(build(name, True, nrts), db, eng='basic')
        _, vb = read_probe(db, 'ut_face')
        dev = np.max(np.abs(v - vb)) / np.max(np.abs(vb)) if v.shape == vb.shape else np.inf
        results.append(check(f'slab_{name}', f'max |v - v_basic| / max |v_basic| ({eng} vs basic engine)', dev,
                             0.0, TOL_ENGINE_TOLERANT if tolerant else 0.0, kind='abs',
                             note='same build; ' + ('GPU engine or OPENEMS_FTZ run' if tolerant else 'must be 0')))
    return results


if __name__ == '__main__':
    import sys
    for r in run_case(sys.argv[1] if len(sys.argv) > 1 else '/tmp/val', quick='--quick' in sys.argv):
        print(r)
