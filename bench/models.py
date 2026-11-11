"""Benchmark models for openEMS engine timing.

build_patch and build_notch are taken from the openEMS python/Tutorials (v0.37):
Simple_Patch_Antenna.py, (c) 2015-2023 Thorsten Liebig <thorsten.liebig@gmx.de>, and
MSL_NotchFilter.py, (c) 2016-2023 Thorsten Liebig. openEMS is free software under the GNU General
Public License, version 3 or (at your option) any later version, and comes WITHOUT ANY WARRANTY;
this file is distributed under the same terms (see LICENSE). Modified for emsKit, 2026: the run
control and `scale` described below, and the two board models, which build on the author's rfsim
toolkit (not public; RFSIM_PATH).

Each build_*() returns (FDTD, ports, freq). Geometry, mesh, excitation and boundaries are
the tutorial's; only the run control differs: `nrts` fixes the number of timesteps
(EndCriteria=0) so every engine does identical work and S-parameters are comparable.
`scale` means different things per model: patch and notch divide the cell size by it (scale=2 ->
~8x cells) to get a bandwidth-bound size; kgcpw and ksma pass it to the rfsim builders unchanged,
which multiply their cell sizes by it (scale < 1 refines; ksma refuses a scale too coarse for its
gap, such as 3).
"""
import os
import numpy as np
from CSXCAD import ContinuousStructure
from openEMS import openEMS
from openEMS.physical_constants import C0, EPS0


def build_patch(nrts=None, scale=1.0, nf2ff=True):
    """Simple_Patch_Antenna.py: lumped port, MUR boundaries, nf2ff box (td dumps)."""
    patch_width, patch_length = 32, 40
    substrate_epsR = 3.38
    substrate_kappa = 1e-3 * 2*np.pi*2.45e9 * EPS0*substrate_epsR
    substrate_width = substrate_length = 60
    substrate_thickness = 1.524
    substrate_cells = int(round(4*scale))
    feed_pos, feed_R = -6, 50
    SimBox = np.array([200, 200, 150])
    f0, fc = 2e9, 1e9

    FDTD = openEMS(NrTS=int(nrts), EndCriteria=0) if nrts else openEMS(NrTS=30000, EndCriteria=1e-4)
    FDTD.SetGaussExcite(f0, fc)
    FDTD.SetBoundaryCond(['MUR']*6)
    CSX = ContinuousStructure()
    FDTD.SetCSX(CSX)
    mesh = CSX.GetGrid()
    mesh.SetDeltaUnit(1e-3)
    mesh_res = C0/(f0+fc)/1e-3/20/scale

    mesh.AddLine('x', [-SimBox[0]/2, SimBox[0]/2])
    mesh.AddLine('y', [-SimBox[1]/2, SimBox[1]/2])
    mesh.AddLine('z', [-SimBox[2]/3, SimBox[2]*2/3])

    patch = CSX.AddMetal('patch')
    start = [-patch_width/2, -patch_length/2, substrate_thickness]
    stop = [patch_width/2, patch_length/2, substrate_thickness]
    patch.AddBox(priority=10, start=start, stop=stop)
    FDTD.AddEdges2Grid(dirs='xy', properties=patch, metal_edge_res=mesh_res/2)

    substrate = CSX.AddMaterial('substrate', epsilon=substrate_epsR, kappa=substrate_kappa)
    start = [-substrate_width/2, -substrate_length/2, 0]
    stop = [substrate_width/2, substrate_length/2, substrate_thickness]
    substrate.AddBox(priority=0, start=start, stop=stop)
    mesh.AddLine('z', np.linspace(0, substrate_thickness, substrate_cells+1))

    gnd = CSX.AddMetal('gnd')
    start[2] = 0
    stop[2] = 0
    gnd.AddBox(start, stop, priority=10)
    FDTD.AddEdges2Grid(dirs='xy', properties=gnd)

    start = [feed_pos, 0, 0]
    stop = [feed_pos, 0, substrate_thickness]
    port = FDTD.AddLumpedPort(1, feed_R, start, stop, 'z', 1.0, priority=5, edges2grid='xy')
    mesh.SmoothMeshLines('all', mesh_res, 1.4)
    if nf2ff:
        FDTD.CreateNF2FFBox()
    return FDTD, [port], np.linspace(max(1e9, f0-fc), f0+fc, 401)


def build_notch(nrts=None, scale=1.0):
    """MSL_NotchFilter.py: two MSL ports, PML_8 at both x ends, MUR at the y faces and z-max, PEC at z-min."""
    unit = 1e-6
    MSL_length, MSL_width = 50000, 600
    substrate_thickness, substrate_epr = 254, 3.66
    stub_length = 12e3
    f_max = 7e9

    FDTD = openEMS(NrTS=int(nrts), EndCriteria=0) if nrts else openEMS()
    FDTD.SetGaussExcite(f_max/2, f_max/2)
    FDTD.SetBoundaryCond(['PML_8', 'PML_8', 'MUR', 'MUR', 'PEC', 'MUR'])
    CSX = ContinuousStructure()
    FDTD.SetCSX(CSX)
    mesh = CSX.GetGrid()
    mesh.SetDeltaUnit(unit)
    resolution = C0/(f_max*np.sqrt(substrate_epr))/unit/50/scale
    third_mesh = np.array([2*resolution/3, -resolution/3])/4

    mesh.AddLine('x', 0)
    mesh.AddLine('x', MSL_width/2+third_mesh)
    mesh.AddLine('x', -MSL_width/2-third_mesh)
    mesh.SmoothMeshLines('x', resolution/4)
    mesh.AddLine('x', [-MSL_length, MSL_length])
    mesh.SmoothMeshLines('x', resolution)

    mesh.AddLine('y', 0)
    mesh.AddLine('y', MSL_width/2+third_mesh)
    mesh.AddLine('y', -MSL_width/2-third_mesh)
    mesh.SmoothMeshLines('y', resolution/4)
    mesh.AddLine('y', (MSL_width/2+stub_length)+third_mesh)
    mesh.AddLine('y', [-15*MSL_width, 15*MSL_width+stub_length])
    mesh.SmoothMeshLines('y', resolution)

    mesh.AddLine('z', np.linspace(0, substrate_thickness, int(round(4*scale))+1))
    mesh.AddLine('z', 3000)
    mesh.SmoothMeshLines('z', resolution)

    substrate = CSX.AddMaterial('RO4350B', epsilon=substrate_epr)
    start = [mesh.GetLine('x', 0), mesh.GetLine('y', 0), 0]
    stop = [mesh.GetLine('x', -1), mesh.GetLine('y', -1), substrate_thickness]
    substrate.AddBox(start, stop)

    port = [None, None]
    pec = CSX.AddMetal('PEC')
    portstart = [-MSL_length, -MSL_width/2, substrate_thickness]
    portstop = [0, MSL_width/2, 0]
    port[0] = FDTD.AddMSLPort(1, pec, portstart, portstop, 'x', 'z', excite=-1,
                              FeedShift=10*resolution, MeasPlaneShift=MSL_length/3, priority=10)
    portstart = [MSL_length, -MSL_width/2, substrate_thickness]
    portstop = [0, MSL_width/2, 0]
    port[1] = FDTD.AddMSLPort(2, pec, portstart, portstop, 'x', 'z',
                              MeasPlaneShift=MSL_length/3, priority=10)

    start = [-MSL_width/2, MSL_width/2, substrate_thickness]
    stop = [MSL_width/2, MSL_width/2+stub_length, substrate_thickness]
    pec.AddBox(start, stop, priority=10)
    return FDTD, port, np.linspace(1e6, f_max, 1601)


RFSIM_DIR = os.environ.get('RFSIM_PATH', '')   # the rfsim toolkit directory (the folder that contains rfsim/)


def _import_rfsim(name):
    """Import rfsim.openems.<name> from RFSIM_PATH with a clear error when the toolkit is not available."""
    import importlib, sys
    if not RFSIM_DIR:
        raise RuntimeError("set RFSIM_PATH to the rfsim toolkit directory (the kgcpw and ksma models need it)")
    if RFSIM_DIR not in sys.path:
        sys.path.insert(0, RFSIM_DIR)
    try:
        return importlib.import_module(f'rfsim.openems.{name}')
    except ImportError as e:
        raise RuntimeError(f"cannot import rfsim.openems.{name} from RFSIM_PATH={RFSIM_DIR!r}: {e}") from e


def _rfsim_model(m, nrts):
    """Fix the run length of an rfsim Model like the tutorials above (nrts steps, no end criterion)."""
    if nrts:
        m.fdtd.SetNumberOfTimeSteps(int(nrts))
        m.fdtd.SetEndCriteria(0)
        m.fdtd.SetMaxTime(0)
    return m.fdtd, m.ports, np.linspace(50e6, 2e9, 391)


def build_kgcpw(nrts=None, scale=1.0):
    """rfsim core.gcpw_line: 50 mm GCPW line, conducting-sheet copper, MSL ports, MUR (PEC at z-min), Ef_plane dump."""
    core = _import_rfsim('core')
    return _rfsim_model(core.gcpw_line(length=50.0, feed=10.0, scale=scale, f_max=2e9, f_ref=640e6), nrts)


def build_ksma(nrts=None, scale=1.0):
    """rfsim launch.sma_launch: vertical SMA launch, coaxial + MSL port, MUR, PEC at z-min, PML_8 at z-max only."""
    launch = _import_rfsim('launch')
    return _rfsim_model(launch.sma_launch(scale=scale), nrts)


def build_cube(nrts=None, scale=1.0):
    """Free-space cube after the gprMax benchmark models (bench_100x100x100 .. bench_800x800x800 of gprMax's
    tests/benchmarking): N x N x N cells of 1 mm, a z-directed dipole (one excited cell edge) at the centre, a
    10-cell PML on all six faces. N = round(100 * scale). One voltage probe beside the source, so runs can be compared."""
    n = int(round(100*scale))
    FDTD = openEMS(NrTS=int(nrts), EndCriteria=0) if nrts else openEMS(NrTS=3000, EndCriteria=1e-5)
    FDTD.SetGaussExcite(1e9, 0.9e9)
    FDTD.SetBoundaryCond(['PML_10']*6)
    CSX = ContinuousStructure()
    FDTD.SetCSX(CSX)
    mesh = CSX.GetGrid()
    mesh.SetDeltaUnit(1e-3)
    lines = np.arange(n + 1, dtype=float)
    for d in 'xyz':
        mesh.SetLines(d, lines)
    c = float(n//2)
    exc = CSX.AddExcitation('dipole', exc_type=0, exc_val=[0, 0, 1])
    exc.AddBox([c, c, c], [c, c, c + 1])
    probe = CSX.AddProbe('port_ut1', 0)
    probe.AddBox([c + 5, c, c], [c + 5, c, c + 3])
    return FDTD, [], np.linspace(1e8, 1.9e9, 201)


MODELS = {'patch': build_patch, 'notch': build_notch, 'kgcpw': build_kgcpw, 'ksma': build_ksma, 'cube': build_cube}


def sparams(name, sim_path, nrts=None, scale=1.0):
    """Rebuild the model (deterministic) and read S11 (and S21) from a finished run dir."""
    _, ports, f = MODELS[name](nrts=nrts, scale=scale)
    for p in ports:
        p.CalcPort(sim_path, f, ref_impedance=50)
    s = {'f': f, 'S11': ports[0].uf_ref/ports[0].uf_inc}
    if len(ports) > 1:
        s['S21'] = ports[1].uf_ref/ports[0].uf_inc
    return s
