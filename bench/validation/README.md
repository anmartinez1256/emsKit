# Validation suite: openEMS against closed-form and exact references

`check.sh` proves the fork computes the same thing as stock openEMS. This suite checks that the
thing computed is right: every case has an answer known in closed form, or from an exact discrete
formula, and a tolerance set from measured margins. It runs on any openEMS (stock or fork, any
engine), and it is the acceptance test for new features that have no stock reference
(ROADMAP.md, "Acceptance rule").

```sh
cd bench/validation
python3 run_validation.py                       # all cases; writes results/validation_<date>.json/.md
python3 run_validation.py --quick               # shorter slab and cavity runs
python3 run_validation.py --cases slab cavity   # a subset
# the openEMS that Python loads (the install, unless DYLD_LIBRARY_PATH / LD_LIBRARY_PATH is set):
VALIDATION_ENGINE=multithreaded VALIDATION_THREADS=4 python3 run_validation.py --tag fork_mt4
DYLD_LIBRARY_PATH=~/opt/openEMS-dev/snap/stock python3 run_validation.py --tag stock   # a saved snapshot
```
Exit status is non-zero if any check fails. Needs numpy and scipy. `--work DIR` (default
`/tmp/emskit_validation`) holds the run directories and each run's openEMS output (`RUN.log`);
`--out DIR` changes where the result files go.

`VALIDATION_ENGINE` takes the openEMS engine names (`fastest`, `basic`, `sse`, `sse-compressed`,
`multithreaded`, and in the fork `gpu`, `gpu-reference`, `metal-diamond`); any other name is refused.
Stock openEMS runs its default engine for the three fork names without a message, and so does a fork
build without Metal for `metal-diamond` (BUILD.md section 7), so the result files record the engine
that each run reported, next to the libraries that were loaded. Cylindrical meshes (`cavity_cyl`)
always run the cylindrical multithreaded engine, or its GPU backend for `gpu` and `gpu-reference`,
whatever `VALIDATION_ENGINE` says. The result files write the home directory as `~` and carry no host
name.

## Cases

| case | reference | tolerance | stock v0.37.0 (Linux VM, engine fastest) | what it catches |
|---|---|---|---|---|
| `slab_debye`, `slab_drude`, `slab_lorentz`: plane wave on a dispersive slab in a TEM parallel-plate channel | (a) exact Fabry-Perot reflection with openEMS's own material formulas (read from `operator_ext_*material.cpp`); (b) the same slab on the basic engine of the same build | (a) max \|R - R_exact\| <= 0.03 over 0.5-9 GHz; (b) probe identical (1e-6 for `gpu` and `gpu-reference` and with `OPENEMS_FTZ` set; `metal-diamond` is held to 0, and gave 0 on cg23 and cg27) | (a) 0.010 / 0.020 / 0.015, halving with the cell size | (a) a lost or grossly wrong dispersive pole, also one that all engines share; (b) an engine hook error, even on a few x-lines only (skipped when the engine is `basic`) |
| `cavity_rect`: 100 x 60 x 80 mm PEC box, uniform 2 mm mesh, fixed time step | (a) continuum mode frequencies; (b) the **exact discrete Yee dispersion relation** for that mesh and time step | every mode found; (a) 0.2 %; (b) **1e-7** | 7 of 7 modes; (a) 0.055 %; (b) **1.5e-8** (the fork with `--quick`: 1.89e-8) | (b) is the tight engine check for errors that touch the whole grid: a wrong coefficient, a missed or doubled update. An error in a few cells moves the modes far less and can pass; races between threads are covered by `check.sh` (bit identity across thread counts), not here |
| `cavity_cyl`: cylinder of radius R = 50 mm and length L = 60 mm, cylindrical coordinates, three-level multigrid | Bessel-zero mode formula (TM and TE) | every mode found; 0.5 % | 6 of 6 modes; 0.16 % | the cylindrical and multigrid engines |
| `wr90`: WR-90 guide, TE10 port, PML ends | beta = sqrt(k0^2 - (pi/a)^2) from the phase between two probes; port S11 | beta 0.5 %; S11 < -30 dB | 0.09 %; -54 dB | waveguide port, PML |
| `msl`: 0.6 mm strip on 0.254 mm, eps_r 3.66 (openEMS notch tutorial without the stub), fixed 12000 steps | Hammerstad-Jensen Z0 and eps_eff | Z0 2 %, eps_eff 1 % | 0.003 %, 0.13 % | MSL port extraction, Mur/PML, mesh thirds rule (a physics check; HJ's stated accuracy is 0.2 % for eps_eff) |

The stock column is `results/validation_stock-v0.37.0_linux-sandbox.md`. That run is older than the
basic-engine comparison (b) of the slab case and than the present cavity tolerances (it let one mode
go missing and allowed 1e-6 for (b)), and its `msl` case still ran to the energy end criterion; with
the fixed 12000 steps, stock and the fork both give Z0 = 47.6688 ohm and eps_eff = 2.87956 (errors
0.003 % and 0.13 %, as before).

Full run: about 3 minutes on the Linux virtual machine of the stock column (stock v0.37.0, case
times in that file); the cavity case takes most of it, and the time scales with the engine speed.

These runs on the author's Mac (Apple M5, macOS 27.0.1) passed 15 of 15: stock v0.37.0
(`results/validation_stock-v0.37.0_macos.md`); cg18, patches 0001-0006, with the multithreaded engine
at 4 threads and with the fastest engine (`validation_cg18_mt4`, `validation_cg18_fastest`,
2026-11-03); the Metal diamond engine on cg23 and cg27 (`validation_cg23_metal`,
`validation_cg27_metal`, 2026-11-04: the three slabs equal the basic engine exactly, without
`OPENEMS_FTZ`, and the cylindrical cavity runs on the cylindrical CPU engine); cg29, patches
0001-0027 (the fork's head until 2026-11-11), at 4 threads and with the fastest engine (`validation_cg29_mt4`,
`validation_cg29_fastest`, 2026-11-05; the slabs again equal the basic engine); and a fresh
build of the patches published on 2026-11-07, 0001-0027 (snapshot pub29, `results/fresh_build_pub29_2026-11-07.txt`) in the
same two ways (`validation_pub29_mt4`, `validation_pub29_fastest`, 2026-11-07; the slabs equal the
basic engine; `$PUBCHECK` in them stands for that build's scratch folder). The
`validation_cg29pre_*` files are an earlier build of cg29's CPU items (2026-11-04).

## Negative control

The fork's Debye bug, fixed in patch 0005, made the multithreaded engine skip the Debye material
hooks. A build of patches 0001-0004 reproduces it, and the slab case fails on it (`$SNAP` = a folder
with the three libraries of that build, made as in BUILD.md section 9):
```sh
VALIDATION_ENGINE=multithreaded VALIDATION_THREADS=2 DYLD_LIBRARY_PATH=$SNAP \
  python3 run_validation.py --cases slab --tag negative-control_patches-0001-0004_mt2
```
`slab_debye` **fails at 0.425 (tolerance 0.03)**, its note reports "distance from non-dispersive
answer 0.00" (the slab behaves exactly like a plain dielectric), and the multithreaded probe differs
from the basic engine's by 0.598 of its peak; Drude and Lorentz pass both checks
(`results/validation_negative-control_patches-0001-0004_mt2.md`). In the project's snapshots the bug
came in with the line hooks of the dispersive extensions inside patch 0003: the slab case passes on
cg11 and fails on cg12. Had this suite existed, the bug would have been caught at that commit
rather than in the pre-publication review. An earlier control, made on a stock v0.37.0 build whose
two public Debye hooks return early, gave the same 0.425
(`results/validation_negative-control_debye-hooks-disabled.md`); that modified build is not
published.

## Adding a case
A case module exposes `run_case(workdir, quick=False)` returning a list of `common.check(...)`
results; register it in `CASES` in `run_validation.py`. Set the tolerance from a measured run with
a margin, and show convergence (halve the cell size, the error should shrink at the expected order).
Good next cases: Mie-sphere RCS (nf2ff, TFSF), thin-wire dipole impedance, lumped RLC resonator,
conducting-sheet loss against a closed-form surface impedance, and a coax line (`CoaxialPort`).
