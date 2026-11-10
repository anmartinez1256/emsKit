"""Transmission lines against closed-form references.

wr90: WR-90 rectangular waveguide (a = 22.86 mm, b = 10.16 mm), TE10 launched by a
  waveguide port, PML termination. beta(f) from the phase between two voltage probes 30 mm
  apart, against beta = sqrt(k0^2 - (pi/a)^2); and the port's S11, which measures how well
  the PML absorbs (a broken PML or boundary path shows up as a reflection).
msl: 50-ohm-class microstrip (w = 0.6 mm, h = 0.254 mm, eps_r = 3.66, zero-thickness strip;
  the geometry of openEMS's MSL notch tutorial without the stub). The MSL ports extract the
  line impedance and beta from their probes; compared with Hammerstad-Jensen (quasi-static;
  stated accuracy 0.2 % for eps_eff, so about 0.1 % for Z0 = Z0_air / sqrt(eps_eff)).
  Evaluated at 1-3 GHz, where dispersion changes eps_eff by 0.005 / 0.020 / 0.045 % at
  1 / 2 / 3 GHz (Getsinger estimate). FDTD with a staircase strip edge typically lands within
  1-3 %, so this is a physics check, not an engine check. A fixed 12000 steps (no end
  criterion), so where the run stops does not depend on the build.
Both run the same with --quick.
"""
import os

import numpy as np
from CSXCAD import ContinuousStructure
from openEMS import openEMS

from common import C0, Z0_FREE, check, dft, read_probe, run

# ---------------------------------------------------------------- WR-90
WG_A, WG_B, WG_LEN, WG_RES = 22.86, 10.16, 150.0, 0.5
WG_X1, WG_X2 = 60.0, 90.0
F_WG = (8e9, 12e9)
TOL_BETA = 0.005                  # measured 0.09 % on stock v0.37.0 (14000 steps)
MAX_S11_DB = -30.0                # measured -54.055 dB on stock v0.37.0


def build_wr90(nrts):
    fdtd = openEMS(NrTS=nrts, EndCriteria=0)
    fdtd.SetGaussExcite(10e9, 4e9)
    fdtd.SetBoundaryCond(['PML_8', 'PML_8', 'PEC', 'PEC', 'PEC', 'PEC'])
    csx = ContinuousStructure()
    fdtd.SetCSX(csx)
    mesh = csx.GetGrid()
    mesh.SetDeltaUnit(1e-3)
    mesh.SetLines('x', np.arange(0, WG_LEN + WG_RES / 2, WG_RES))
    mesh.SetLines('y', np.linspace(0, WG_A, 47))          # a/2 is a mesh line
    mesh.SetLines('z', np.linspace(0, WG_B, 21))
    port = fdtd.AddRectWaveGuidePort(0, [10, 0, 0], [15, WG_A, WG_B], 'x', WG_A * 1e-3, WG_B * 1e-3, 'TE10', 1)
    for name, x in (('ut_x1', WG_X1), ('ut_x2', WG_X2)):
        csx.AddProbe(name, p_type=0).AddBox([x, WG_A / 2, 0], [x, WG_A / 2, WG_B])
    return fdtd, port


# ---------------------------------------------------------------- microstrip
MSL_W, MSL_H, MSL_ER, MSL_LEN = 600.0, 254.0, 3.66, 25000.0     # um
F_MSL = (1e9, 3e9)
TOL_Z0, TOL_EEFF = 0.02, 0.01     # measured 0.003 % and 0.13 %; HJ's stated accuracy is 0.2 % (eps_eff)


def hammerstad_jensen(w, h, er):
    u = w / h
    a = 1 + np.log((u**4 + (u / 52)**2) / (u**4 + 0.432)) / 49 + np.log(1 + (u / 18.1)**3) / 18.7
    b = 0.564 * ((er - 0.9) / (er + 3))**0.053
    eeff = (er + 1) / 2 + (er - 1) / 2 * (1 + 10 / u)**(-a * b)
    fu = 6 + (2 * np.pi - 6) * np.exp(-(30.666 / u)**0.7528)
    z01 = Z0_FREE / (2 * np.pi) * np.log(fu / u + np.sqrt(1 + (2 / u)**2))
    return z01 / np.sqrt(eeff), eeff


def build_msl():
    f_max = 7e9
    fdtd = openEMS(NrTS=12000, EndCriteria=0)
    fdtd.SetGaussExcite(f_max / 2, f_max / 2)
    fdtd.SetBoundaryCond(['PML_8', 'PML_8', 'MUR', 'MUR', 'PEC', 'MUR'])
    csx = ContinuousStructure()
    fdtd.SetCSX(csx)
    mesh = csx.GetGrid()
    mesh.SetDeltaUnit(1e-6)
    res = C0 / (f_max * np.sqrt(MSL_ER)) / 1e-6 / 50
    third = np.array([2 * res / 3, -res / 3]) / 4                 # thirds rule at the strip edges
    mesh.AddLine('x', [-MSL_LEN, 0, MSL_LEN])
    mesh.SmoothMeshLines('x', res)
    mesh.AddLine('y', 0)
    mesh.AddLine('y', MSL_W / 2 + third)
    mesh.AddLine('y', -MSL_W / 2 - third)
    mesh.SmoothMeshLines('y', res / 4)
    mesh.AddLine('y', [-15 * MSL_W, 15 * MSL_W])
    mesh.SmoothMeshLines('y', res)
    mesh.AddLine('z', np.linspace(0, MSL_H, 5))
    mesh.AddLine('z', 3000)
    mesh.SmoothMeshLines('z', res)
    sub = csx.AddMaterial('substrate', epsilon=MSL_ER)
    sub.AddBox([-MSL_LEN, -15 * MSL_W, 0], [MSL_LEN, 15 * MSL_W, MSL_H])
    pec = csx.AddMetal('PEC')
    ports = [
        fdtd.AddMSLPort(1, pec, [-MSL_LEN, -MSL_W / 2, MSL_H], [0, MSL_W / 2, 0], 'x', 'z', excite=-1,
                        FeedShift=10 * res, MeasPlaneShift=MSL_LEN / 3, priority=10),
        fdtd.AddMSLPort(2, pec, [MSL_LEN, -MSL_W / 2, MSL_H], [0, MSL_W / 2, 0], 'x', 'z',
                        MeasPlaneShift=MSL_LEN / 3, priority=10),
    ]
    return fdtd, ports


def run_case(workdir, quick=False):
    res = []
    # WR-90
    d = os.path.join(workdir, 'wr90')
    fdtd, port = build_wr90(14000)  # the slow near-cutoff tail needs it: 1.4 % at 3000 steps, 0.4 % ripple at 8000, 0.09 % at 14000
    run(fdtd, d)
    f = np.linspace(*F_WG, 81)
    t, v1 = read_probe(d, 'ut_x1')
    _, v2 = read_probe(d, 'ut_x2')
    ph = np.unwrap(-np.angle(dft(t, v2, f) / dft(t, v1, f)))     # < pi at 8 GHz for 30 mm
    beta = ph / ((WG_X2 - WG_X1) * 1e-3)
    beta_ex = np.sqrt((2 * np.pi * f / C0)**2 - (np.pi / (WG_A * 1e-3))**2)
    res.append(check('wr90', 'max rel. error of beta, 8-12 GHz', np.max(np.abs(beta / beta_ex - 1)), 0.0,
                     TOL_BETA, kind='abs'))
    port.CalcPort(d, f)
    s11 = 20 * np.log10(np.abs(port.uf_ref / port.uf_inc))
    res.append(check('wr90', 'max S11 (dB) of the PML-terminated guide', s11.max(), MAX_S11_DB, 0.0,
                     kind='max', note='pass if below the reference'))
    # microstrip
    d = os.path.join(workdir, 'msl')
    fdtd, ports = build_msl()
    run(fdtd, d)
    f = np.linspace(*F_MSL, 41)
    ports[0].CalcPort(d, f)
    z0_ex, eeff_ex = hammerstad_jensen(MSL_W, MSL_H, MSL_ER)
    z0 = np.real(ports[0].Z_ref).mean()
    eeff = np.mean((np.real(ports[0].beta) * C0 / (2 * np.pi * f))**2)
    res.append(check('msl', f'Z0 (ohm) vs Hammerstad-Jensen {z0_ex:.2f}', z0, z0_ex, TOL_Z0))
    res.append(check('msl', f'eps_eff vs Hammerstad-Jensen {eeff_ex:.4f}', eeff, eeff_ex, TOL_EEFF))
    return res


if __name__ == '__main__':
    import sys
    for r in run_case(sys.argv[1] if len(sys.argv) > 1 else '/tmp/val', quick='--quick' in sys.argv):
        print(r)
