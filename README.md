# fdtdKit: openEMS FDTD towards the memory ceiling of an Apple M5

fdtdKit is a performance fork of [openEMS](https://github.com/thliebig/openEMS) (the open-source EC-FDTD solver) tuned on
an Apple M5 MacBook (4 P + 6 E cores, 16 GB, one ~150 GB/s memory bus shared with the GPU), together with the benchmark
harness and the verification method used to build it. It is the FDTD kit of EMSKit, a family of electromagnetic
solvers for Apple silicon (fdtdKit, femKit for finite elements, momKit for the method of moments and sbrKit for
shooting and bouncing rays); the other three kits are developed on branches of their own and are not covered here.
fdtdKit was called emsKit until 2026-11-05, and the repository and its folder keep that name: `emsKit` in `results/`,
in the patches and in the dated entries of `CHANGELOG.md` is this same project.

To cite it: DOI [10.5281/zenodo.24118865](https://doi.org/10.5281/zenodo.24118865), which always resolves to the
latest release archived at Zenodo (release 0.1.0 of 2026-11-10 is 10.5281/zenodo.24118866); `CITATION.cff` holds the
same in machine-readable form.

For the same number of time steps, every change to the CPU engines produces results **identical bit for bit** to
stock openEMS v0.37.0 (port probes, S-parameters, HDF5 field dumps; clang builds, see `BUILD.md` section 8 for GCC).
The fork's own Metal engine for the GPU (`--engine=metal-diamond`, opt-in) gives the bits of the multithreaded CPU
engine run with `OPENEMS_FTZ=1` instead, because Apple's GPU flushes subnormal numbers to zero; against stock its port
probes differ by at most 9.4e-7 relative on the six benchmark models (`BUILD.md` section 7). A run that ends on the
energy end criterion can stop at a different step than v0.37.0: the fork's base, commit 7bb294f, contains upstream
commit eb1c5ee, which checks that criterion every Nyquist period during the first minute of a run, where v0.37.0
without `--exact-endcriteria` checks it with the progress report every 4 s of wall-clock time; up to the earlier stop
the probe files are the same.

In the speed table below (snapshot cg29 = patches 0001 to 0027, measured on 2026-11-05 with all configurations paired
in the same rounds, the other processes at a median of 0.5 to 0.8 cores), the CPU engine reaches 1.95x (patch x5) to
6.89x (patch tutorial) the cell rate of stock over the six models, each at its best thread count in the run, and 4.73x
(SMA launch, on the 1.071 M-cell mesh of the toolkit's former 0.02 mm floor) and 6.33x (GCPW line) on the author's two
real boards. The Metal diamond engine of the same build reaches 2.87x (patch x5) to 7.40x (GCPW line) stock's rate
over the same models. Against the CPU engine at its best setting, which was 8 threads on all six models, it is ahead
on patch x5 (1.47x), notch x3 (1.46x) and the GCPW line (1.17x), level on the SMA launch (1.00x) and behind on the
notch and patch tutorials (0.97x and 0.93x).

End to end, for a full simulation of each board from the author's toolkit (wall time of `FDTD.Run`: operator setup and
time stepping), at the toolkit's defaults since 2026-11-04 (toolkit commit 4a7e20e: a 0.05 mm mesh floor on the SMA
launch, which then has 0.871 M cells instead of 1.071 M, and the probe end criterion at -60 dB with a hold of 0.5
excitation lengths) a vertical SMA launch went from 562.7 s on stock to 37.4 s on cg18 (15.0x) and a 50 mm GCPW line
from 76.5 s to 5.2 s (14.7x). The stock runs went to the end of the simulated time, the SMA launch on the 1.071 M-cell
mesh, so these factors include the early stop and, on the SMA launch, the coarser mesh. With the toolkit's defaults
until 2026-11-04 (a 0.02 mm floor and a hold of 1) the factors are 5.8x (SMA) and 8.9x (GCPW); for the same number of
steps the engine alone gives 3.3x and 5.6x. Both sides model the same structure with the same Gaussian excitation, and
stock ran at the thread counts the toolkit uses for a stock library (8 and 4, the counts the tuner also picked for the
full runs). These runs were made on 2026-11-03 on a quiet Mac, one per setting, with cg18 (patches 0001 to 0006) and
stock v0.37.0 (`results/rfsim_e2e_2026-11-03.txt`).

On 2026-11-05, at the toolkit's current defaults, cg29's Metal diamond engine ran the two boards 1.22x (SMA launch,
28.9 to 23.6 s) and 1.37x (GCPW line, 5.6 to 4.1 s) faster than cg29's CPU engine with the automatic thread count, and
their full runs 1.17x faster each, with the same stop steps, S11 within 7.3e-3 dB (where it is above -40 dB) and S21
within 2.0e-4 dB (medians of the per-round ratios of 2 or 3 interleaved rounds,
`results/rfsim_e2e_cg29_2026-11-05.txt`). The Mac was loaded then: the other processes used a median of 1.0 to 1.6
cores (the rounds in which both runs stayed below the load limit give 1.08x to 1.27x), so those CPU times are no
comparison with cg18's. Paired in the same rounds on a quieter Mac (other processes on 0.3 to 0.6 cores), cg29's CPU
engine runs at 1.03 to 1.23 times cg18's rate at 4 threads, 1.13 to 1.44 times at 8 and 1.13 to 1.42 times with the
automatic count on the six models, the SMA launch on its 0.871 M-cell mesh; on the 1.071 M-cell mesh of the speed
table it gains 1.37 to 1.38 times at 8 threads and with the automatic count (others on 0.6 to 0.7 cores;
`results/cpu_items_cg29_2026-11-05.txt`, section 4).

**Status.** Reviewed before publication: four read-only reviews on 2026-11-02 by fresh instances of Claude Fable 5.1,
one of the two models that wrote the code (fixes in patch 0005), and a final review on 2026-11-03 with every finding
checked by two verifiers, the nits by one (fixes in patch 0006 and in these documents); the corrections are listed in
`CHANGELOG.md`. Of the code added since (patches 0007 to 0027), only the tiling tuner of patch 0016 had a correctness
review, on its first version (three read-only reviewers, every finding checked by two verifiers; section 5 of
`results/diamond_engine_cg28_tuner_2026-11-04.txt`); the rest rests on the checks below.
Patch 0005 fixes a wrong-result bug of the fork in Debye materials found by the pre-publication review; it does not
change any number in this README. Snapshot cg18 (patches 0001 to 0006, the build installed on the author's Mac from
2026-11-04 to 2026-11-06) passed the full check of `BUILD.md` section 9 on 2026-11-03: bit-identical to stock on all
six models, with best speeds from 2.7 % below to 1.6 % above cg14's on five of them and 8.2 % above on the GCPW line
(`results/*_cg18.txt`). Snapshot
cg29 (patches 0001 to 0027) passed it on 2026-11-05: `bench/check.sh` with eight cg29 configurations per model (1, 4,
8 and 10 threads, the automatic count, each coefficient layout forced once, the barriers instead of the neighbour
flags), every run bit-identical to stock on the six models (`results/*_cg29.txt`); the Debye check; the validation
suite, 15 of 15 both with the multithreaded engine at 4 threads and with the default engine and thread count
(`results/validation_cg29_*`); the cylindrical multigrid, 34 HDF5 datasets equal to stock; a run-mode matrix of 45
small models, 461 comparisons identical and 10 that differ only in the stop step of the energy end criterion (one
model, for the reason given in the first paragraph); `scripts/checks/diamond_check.sh`, 72 of 72; and the six models
on `metal-diamond`, bit-identical to the multithreaded engine with `OPENEMS_FTZ=1` (`results/*_cg29gpu.txt`; all of
them in section 3 of `results/cpu_items_cg29_2026-11-05.txt`). Since 2026-11-06 cg29 is the build installed on the
author's Mac. That day the command line's release build (section "Command line") checked the installed library, on a
Mac loaded by other programs, so only the verdicts count: `check --lite` all identical to stock on the six models (18
of 18 rows exact), the Debye check (its fields also identical to those of snapshot cg29), `diamond-check` 72 of 72,
the validation suite 15 of 15 with the default engine and with the multithreaded engine at 4 threads, and the GCPW
line's end-to-end run at the toolkit's defaults, stopped by the probe end criterion at step 34300 as on cg18 and cg29
before (`Docs/fdtdKit/PLAN.md`, section 16). On 2026-11-07 the 27 published patches were built from a fresh clone of
upstream's superproject as `BUILD.md` describes, and that build passed `check.sh` (every run identical to stock on
the six models), the Debye check, `diamond_check.sh` 72 of 72, the six models on `metal-diamond`, the validation
suite 15 of 15 twice and the cylindrical multigrid, on a loaded Mac (`results/fresh_build_pub29_2026-11-07.txt`).
The speed table below and the end-to-end runs come from files in
`results/`; numbers marked "project log" come from the project's working log, which is not published.

<!-- BEGIN speed table (generated by paper/figures/tables.py) -->
| model (cells) | stock v0.37.0, MC/s (threads) | fdtdKit CPU, MC/s (threads) | gain | fdtdKit GPU, MC/s | gain | GPU / CPU |
|---|---|---|---|---|---|---|
| GCPW line, conducting sheets, MUR (0.24 M) | 286 (4) | 1808 (8) | 6.33x | 2113 | 7.40x | 1.17x |
| vertical SMA launch, coaxial port, z-PML (1.07 M) | 379 (4) | 1833 (8) | 4.73x | 1829 | 4.83x | 1.00x |
| notch filter tutorial, MSL ports, PML_8 at both x ends (0.27 M) | 303 (4) | 1961 (8) | 6.56x | 1893 | 6.26x | 0.97x |
| patch antenna tutorial, nf2ff (0.10 M) | 268 (2) | 1854 (8) | 6.89x | 1729 | 6.48x | 0.93x |
| patch antenna x5 (7.86 M) | 1003 (8) | 1958 (8) | 1.95x | 2879 | 2.87x | 1.47x |
| notch filter x3 (5.25 M) | 800 (8) | 2177 (8) | 2.72x | 3193 | 3.99x | 1.46x |

(Snapshot cg29, measured on 2026-11-05 in one paired interleaved run per model, 4 rounds, `results/speed_cg29_2026-11-05.txt`: stock at 2, 4 and 8 threads, fdtdKit's multithreaded engine at 4 and 8 threads and with the automatic count, and its Metal diamond engine (`--engine=metal-diamond`), in turn, each round once the other processes used at most 1.5 cores and 10 % of the GPU, and run again, up to three times, when a run saw more; the SMA launch row comes from a re-run that repeats only the loaded runs (`--run-redo 3`). Rates are medians over the rounds, gains the median of the per-round ratios; stock and fdtdKit CPU at their best thread count in the run. The CPU runs are identical to stock bit for bit; the GPU runs differ by at most 9.4e-07 relative because the GPU flushes subnormal numbers (identical with `OPENEMS_FTZ=1` on the CPU). The SMA launch on the 1.071 M-cell mesh of the toolkit's former 0.02 mm floor. MC/s = million Yee cells updated per second.)
<!-- END speed table -->

**Where the GPU overtakes the CPU.** Above about 1.5 to 2 M cells the GPU's lead grows with the grid; below that it depends on the model. In a size sweep on 2026-11-05
(`results/gpu_crossover_cg29_2026-11-05.txt`: the patch antenna, the notch filter and the GCPW line at 25 points
(10, 6 and 9 mesh scales) from 0.10 to 7.9 M cells, 4 paired rounds each, the other processes at 0.5 to 1.3 cores) the GPU was ahead in every
round from 1.7 M cells on the notch filter, 2.4 M on the GCPW line and 2.9 M on the patch antenna, and 1.25 to 1.52x
ahead from 3.1 M cells on. Below that the two engines were within 0.89 to 1.23x of each other, and which one led
depended on the model and on the session (the patch tutorial ran 1.11x in the sweep, and in a later session 0.95 to 0.97x at the same 36 500 steps and
0.91 to 0.93x at the bench's 10 500). On small grids the GPU waits while the CPU records the probes and evaluates the dumps between short calls
and while each call's command buffers start and finish (on the patch tutorial, whose nf2ff dumps end a call every 31 steps, it is busy 73 to 82 % of the loop), its own rate
is lower (1959 MC/s over its busy time on the notch tutorial against 3239 on notch x3), and the CPU engine runs
fastest in the middle of the range, 2570 to 3003 MC/s at 0.6 to 1.9 M cells. The figure and the details are in the
paper's section "A diamond-blocked Metal engine".

About 1.13x of the patch tutorial's 6.9x in snapshot cg14's table in the paper (section "Results": 1912 MC/s against
stock's 277 at 2 threads) comes from upstream's background dump writer in the fork's base, not from the fdtdKit
patches: on 2026-11-03 the base ran that model at 308.5 MC/s and stock at 273.4 (both at their best, 2 threads; 342.2
each with the dumps off), cg18 at 1845.9 (4 threads), about 6.0x the base (best of two runs each, quiet Mac). On the
notch tutorial, the GCPW line and patch x5 the base is within noise of stock (0.98 to 1.03x; `results/*_base.txt`).
The base was not run beside cg29, so its share of the 6.9x in the table above was not measured.

**Scaling out (planned, not measured).** Because the memory bus of one machine bounds the cell rate, the way to scale
further is a Thunderbolt-connected cluster of Mac minis or Mac Studios, each adding its own unified memory and
bandwidth: parameter sweeps across machines first, then one large model split across them, which needs a
domain-decomposed engine that openEMS does not have today (see `ROADMAP.md`).

## What is in the box

| folder | content |
|---|---|
| `paper/` | the technical report (LaTeX source, figures with their scripts, PDF) and `paper/code_notes.md`, notes on each code change of patches 0001 to 0006 written from the diffs (the later patches are described in `CHANGELOG.md`, the paper and their commit messages); `paper/figures/tables.py` writes the paper's two tables of cg29 and the speed table of this README from `results/` |
| `patches/README.md` | what each patch folder applies to, in which order, and its licence |
| `patches/openems/` | the fork as 27 `git am` patches on commit 7bb294f of upstream's former `gpu-engine` branch (`BASE_origin_gpu-engine.txt`), plus one cumulative diff: 0001 to 0006 = snapshot cg18, the build installed on the author's Mac from 2026-11-04 to 2026-11-06; 0007 to 0016 = the Metal diamond engine (snapshots cg19 to cg28); 0017 to 0027 = the CPU items of snapshot cg29, the build installed there since 2026-11-06. They need the CSXCAD patch below (they do not build against a stock CSXCAD 0.7.0), and they apply to that base only: upstream has since merged a reworked GPU engine into master, deleted the branch and restructured the engines |
| `patches/csxcad/` | one patch on CSXCAD v0.7.0 (material lookups during operator setup), under LGPL-3.0-or-later like CSXCAD (`COPYING.LESSER`) |
| `bench/` | the harness: `bench.py` (in-process runs with a fixed step count, S-parameter comparison; the GPU engines and `OPENEMS_FTZ` runs are compared but marked tolerant), `check.sh` (six models, five thread settings, bit-identity against stock), `abtest.py` (paired interleaved rounds, with waits for a quiet Mac), `usage.py` (the other processes' CPU and GPU use during each run), the models |
| `bench/validation/` | a validation suite against closed-form references (dispersive slabs, a rectangular and a cylindrical cavity, a WR-90 guide, a microstrip line), with same-build engine comparisons on the dispersive slabs; its runs (`results/validation_*`): cg18, cg29 and the fresh build of the published patches of 2026-11-07 (`validation_pub29_*`) 15 of 15 each on the Mac, each with the multithreaded engine at 4 threads and with the default engine and thread count (`validation_cg29pre_*` is an earlier build of cg29's topics); the Metal diamond engine 15 of 15 on cg23 and on cg27 (its slabs equal to the basic engine; the cylindrical cavity runs on the cylindrical CPU engine); snapshot cg17 (patches 0001 to 0005) 15 of 15 with its defaults and at 8 threads (two runs made outside the project's log); stock v0.37.0 15 of 15 on the Mac and 12 of 12 on a Linux x86_64 VM (the suite's earlier version, without the engine comparisons); and two negative controls that fail their Debye checks as they should, a stock build with the Debye hooks disabled on the VM (2 of 3 checks pass) and a build of patches 0001 to 0004 (the Debye bug) on the Mac (4 of 6 pass). See `bench/validation/README.md` |
| `results/` | the benchmark tables of the project (`MODEL_sSCALE_nSTEPS_SNAPSHOT.txt`; `*_cg18.txt`, `*_cg29.txt` and `*_pub29.txt` = the full checks of cg18, cg29 and a fresh build of the published patches (`fresh_build_pub29_2026-11-07.txt`), `*_cg2Ngpu.txt` and `*_pub29gpu.txt` = the Metal diamond engine of cg20 to cg29 and of that build against the multithreaded engine with `OPENEMS_FTZ=1` (cg20 to cg22 with the base's GPU engine as well), `*_base.txt` = the fork's base against stock), the speed table above (`speed_cg29_2026-11-05.txt`), the CPU items of cg29 with their paired runs and the comparison with cg18 (`cpu_items_cg29_2026-11-05.txt`), the Metal diamond engine's snapshots and checks (`diamond_engine_*`, `diamond_check_*`, `diamond_sweep_cg21_2026-11-04.txt`), the Swift prototype's diamond mode (`diamond_swift_2026-11-04.txt`), the fused unblocked Metal sweep (`fused_sweep_k1_2026-11-04.txt`), the GPU against the CPU by grid size (`gpu_crossover_cg29_2026-11-05.txt`), other openEMS builds run beside fdtdKit (`others_2026-11-04/`), `summary.json` (the best speed per model and snapshot, from every `MODEL_sSCALE_nSTEPS_SNAPSHOT.txt` table in `results/` itself up to pub29; the tables in `others_2026-11-04/` are not in it), the end-to-end runs (`rfsim_e2e_2026-11-03.txt` of cg18 and stock, `rfsim_e2e_gpu_2026-11-04.txt` of cg23 on the GPU, `rfsim_e2e_cg29_2026-11-05.txt`), the mesh sweep, the valley sweeps and the allocator placement test (`cache_valley_*`), the GCC/clang kernel comparison and the loop counts (`kernel_*`), the correctness checks of cg18, the memory and time-step checks, the initial optimisation review, the validation runs. The `*_cg17.txt`, `*_cg19.txt`, `*_cg21.txt`, `*_cg22.txt`, `*_cg2Ngpu.txt` and `*_pub29*.txt` tables were bit-identity checks, many of them on a loaded machine, and the speeds in the `*_cg29.txt` tables are the faster of two unpaired runs of a bit-identity check; none is a speed comparison (`*_cg29pre.*` = the checks of an earlier build of cg29's topics). In `summary.json` the entry of a `*_cg2Ngpu.txt` or `*_pub29gpu.txt` table is its multithreaded row with `OPENEMS_FTZ=1`. The files that the records place in the scratchpad were the assistant session's working files and are not published |
| `scripts/` | the check and experiment scripts: standalone kernel benchmarks (with the GCC/clang comparison and the loop counts), the valley box, sweep and allocator placement test, cylindrical-multigrid check, Debye-material regression check, the Metal diamond engine's bit-identity check (`checks/diamond_check.sh` with its box and compare scripts), setup/nf2ff phase timing, probe-end check, z-padding check, SMA mesh sweep, end-to-end runs (`e2e/run_one.py` runs another engine with `E2E_ENGINE`, for example `metal-diamond`), the GPU-against-CPU size sweep (`gpu_crossover/`), the runs of other openEMS builds beside fdtdKit (`others/run_others.sh`), memory and time-step checks, HDF5 compare; `scripts/README.md` lists them |
| `swift_engine/` | a Swift + Metal FDTD kernel that runs an exported openEMS operator; bit-identical to the CPU engines on a 41^3 box, and on a 121^3 box to the SSE-based engines (sse, sse-compressed, multithreaded) with `OPENEMS_FTZ=1`, which the basic engine ignores (project log). Its diamond-blocked mode (`--diamond K`, 2026-11-04, the prototype of the Metal diamond engine) gives the same bits as cg18's multithreaded engine (with `OPENEMS_FTZ=1` on the two larger boxes) on 41^3, 121^3 and 201^3 boxes at every K tried (`results/diamond_swift_2026-11-04.txt`) |
| `Package.swift`, `Sources/`, `Tests/` | the EMSKit Swift package: `Sources/fdtdKit` and `Sources/emskit-cli` make fdtdKit's command line `emskit fdtd` (section "Command line" below; with the Python launcher `Sources/fdtdKit/Python/fdtdkit_run.py`), `Tests/fdtdKitTests` holds its tests; the other kits add their own targets to the same package. Written on 2026-11-05 (the core modules, the first commands and the Python launcher) and 2026-11-06 (the remaining commands and the tests); built, tested and acceptance-run on 2026-11-06 (`Docs/fdtdKit/PLAN.md`, section 16) |
| `BUILD.md` | how to build, install, verify and revert; the knobs; what differs from upstream |
| `ROADMAP.md` | planned work: validation, upstreaming, workflow and solver features, the cluster outline, the Metal engine's open items, version 2 of the command line; what was done since its first version, the command line 0.1.0 among it |
| `Docs/fdtdKit/PLAN.md` | the plan of the command line: its phases and acceptance runs, the facts it rests on, the commands, library identity, the child environment and the knobs, the JSON output and exit codes, load recording, stopping, distribution over several Macs, tests, and its log |

The fork is also kept as two git branches with the same changes as commits: the openEMS fork's branch
[`speed-m5-gpu`](https://github.com/anmartinez1256/openEMS/tree/speed-m5-gpu) holds the 27 commits of
`patches/openems/` on 7bb294f, and the CSXCAD fork's branch
[`speed-m5`](https://github.com/anmartinez1256/CSXCAD/tree/speed-m5) the one commit of `patches/csxcad/` on v0.7.0.

The changes made in this project to the author's simulation toolkit (rfsim) are not published, since the toolkit itself
is private; the paper's section "The modelling side" and `CHANGELOG.md` describe them. The two board models and their
rows in the speed table above can therefore be checked against `results/` but not rerun by others.

## Command line: `emskit fdtd` (fdtdKit)

**Status (2026-11-10):** built and tested with Swift 6.4.2 on macOS 27.0.1: the 244 unit tests (27 suites) pass;
with the 14 smoke runs against the real tools (suite `SmokeTests`, run only with `EMSKIT_FDTD_SMOKE=1`) there are 258
tests in 28 suites. The smoke runs and the acceptance runs on snapshot cg29 passed on 2026-11-10 (`check cg29
--lite`: all identical to stock v0.37.0 on the six models; `diamond-check cg29`: 72 of 72 comparisons identical;
`e2e gcpw --lib cg29`: the run finishes). A cloud code review of 18 of the package's 31
source files found one bug and five minor issues on 2026-11-08; all six are fixed (`CHANGELOG.md`, 2026-11-09). A
second review of all 31 files on 2026-11-09 raised 28 findings; its confirmed ones are fixed or listed
(`CHANGELOG.md`, 2026-11-10). The smoke and acceptance runs were last run before that day's later changes, which
closed the two reviews' open items, the ten findings of a third review, the six of a fourth and the three of an
attack on the guards, and passed the unit suite.
`Docs/fdtdKit/PLAN.md`, section 16, logs each run
with the other processes' load during it.

fdtdKit's command line is `emskit fdtd`, a subcommand of the `emskit` tool of the EMSKit Swift package
(`Package.swift`, `Sources/fdtdKit`; plan in `Docs/fdtdKit/PLAN.md`). It runs the verified tools of this repository
(`bench/bench.py`, `bench/abtest.py`, `bench/check.sh`, the validation suite, `scripts/checks/*.sh`,
`scripts/e2e/run_one.py`) and prints one JSON document per call on stdout; the tools' output, warnings and a summary
go to stderr.

Build (macOS 26 or later, Swift 6.2 or later): `swift build -c release`; the binary is `.build/release/emskit` (run it
from there or through a symlink; a copy elsewhere needs `--repo`). With only the Command Line Tools installed, each
build prints three linker warnings from the toolchain ("search path ... not found"). Tests:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter fdtdKitTests` (swift-testing needs
Xcode's toolchain: with only the Command Line Tools the test build can fail with "plugin for module 'TestingMacros'
not found"). The smoke runs start real simulations: add `EMSKIT_FDTD_SMOKE=1` (and `EMSKIT_FDTD_RFSIM=DIR`, the
toolkit's folder, for the rfsim runs) and use `--filter fdtdKitTests.SmokeTests --no-parallel`. They are written for
the author's Mac. They expect the snapshots `stock`, `cg18`, `cg27` and `cg29` in the default snapshot folder
(`~/opt/openEMS-dev/snap`) and a git clone of this repository, and the second run (`infoIdentities`) checks the
identities of the author's own library files (`Smoke.stock` and `Smoke.cg29` in `Tests/fdtdKitTests/SmokeTests.swift`),
so it fails on any other build.

| command | runs | passes when |
|---|---|---|
| `info` | probes only: Python, the installed library, the snapshots (sha256, build UUID, engines, knobs), running simulations | always |
| `load [--seconds S]` | `bench/usage.py` | the sampler works |
| `bench MODEL --config CFG ...` | `bench.py` | no mismatch (`--exact`: every compared run bit-identical) |
| `ab MODEL --config A --config B ...` | `abtest.py` | every config that must match is identical |
| `check SNAP ... --tag T [--lite]` | `check.sh` | all identical to stock v0.37.0 (against another reference: partial, not the acceptance) |
| `validate [--lib L] [--engine E]` | the validation suite | every check passes |
| `debye-check LIB`, `diamond-check LIB` | the two check scripts | PASS |
| `e2e gcpw\|sma [--lib L] [--engine E]` | `run_one.py`, with the toolkit's own defaults | the run finishes |
| `run SCRIPT [--lib L] [--engine E] [--threads N] -- ARGS` | any openEMS Python script; engine and threads set on every `FDTD.Run` | the script exits 0 |

Examples (`mybuild` is a folder under the snapshot directory, see `BUILD.md` section 9):

    emskit fdtd info
    emskit fdtd bench patch --config stock@multithreaded:4 --config mybuild@multithreaded:4
    emskit fdtd bench notch --config mybuild@multithreaded:4 --config mybuild@metal-diamond:0 --knob OPENEMS_FTZ=1 --exact
    emskit fdtd ab notch --scale 3 --rounds 5 --config stock@multithreaded:8 --config mybuild@multithreaded:8 --quiet 60
    emskit fdtd check mybuild --tag mybuild --lite --allow-partial
    emskit fdtd e2e gcpw --lib mybuild --engine metal-diamond
    emskit fdtd run my_board.py --lib mybuild --engine metal-diamond -- --length 50

`check` runs all six models, and `e2e` runs at all, only with the author's rfsim toolkit, which is not public
(`--rfsim DIR` or `RFSIM_PATH`, the folder that holds `rfsim/`). Without the toolkit both stop with
`rfsim_not_found` (exit 2); with `--allow-partial`, as in the example, `check` runs the other four models instead
and ends with status partial.

What it guarantees:

- Snapshot libraries reach openEMS: `DYLD_LIBRARY_PATH` is set only on the Python processes it starts (never through
  `/usr/bin/env`, a shell, `caffeinate` or `/usr/bin/python3`, which drop it), and every run shows which libraries it
  loaded.
- No hidden settings: inherited `OPENEMS_*`, `DYLD_*`, most `PYTHON*` and `Malloc*` variables are removed and listed;
  knobs are given with `--knob` or in a config and appear in the labels; the toolkit's defaults are read and recorded,
  never changed.
- Every speed and run time carries the other processes' CPU and GPU use during that run (`bench/usage.py`); a figure
  without a valid reading is not printed.
- `check` is the CPU acceptance only against the stock v0.37.0 build of all three libraries.
- Nothing is overwritten: an existing results table, `--output`, `--record` or `--out-dir` is refused unless
  `--overwrite` (the old one is kept next to it as `NAME.previous-DATE-TIME`) or `--append`.
- A command line that the parser refuses (an unknown or misspelt option, a missing value; exit 64) writes no file
  and starts nothing: its JSON document goes to stdout, also when the line holds `--output`. A usage rule found
  after parsing (bench's `--knob` rules) is reported in `--output` as usual.
- `bench`, `ab` and `e2e` do not start while another simulation has an openEMS library open, unless `--quiet PCT` or
  `--allow-concurrent` is given.
- Ctrl-C stops a simulation through openEMS's own abort flag; if the command line itself dies, its runs stop too.
- It installs nothing and changes nothing in the installed openEMS prefix (the one the Python probe finds, and
  `~/opt/openEMS`) or the snapshot folder (`--snaps`, `$OPENEMS_BENCH_SNAPS`, `~/opt/openEMS-dev/snap`): before
  anything runs, in a dry run too, every location it would write, create or rename, defaults included, is compared
  with them by file identity, so links, `..` and letter case do not hide them. A location inside one, one that would be
  renamed while it holds one, and a file a tool rewrites in place that is a hard link of a file in one are refused
  (`protected_path`, exit 2; no option overrides it). A folder that the line names as a library by its path
  (`--lib DIR`, `DIR@ENGINE`, a SNAP of `check`) is protected in the same way for that command, and so is a folder
  of the working directory that has the name of a library of the line. What a `run` script writes by itself is not
  checked.
- It opens no files.

Exit codes: 0 ok (or partial), 1 a check did not pass, 2 bad input (a protected location included), 3 not supported by
that library or Python, 4 a tool failed, 5 refused (would overwrite, another simulation running), 64 usage, 130
interrupted.

## What changed in the engine (one line each; the paper has the details)

Items 1 to 11 are in patches 0001 to 0006 (cg18), item 12 in patches 0007 to 0016 (cg19 to cg28) and items 13 to 18
in patches 0017 to 0027 (cg29, the build installed on the author's Mac since 2026-11-06, which has all eighteen).

1. Spin barriers and a per-extension hook plan: stock passes 2 + 6N condition-variable barriers per timestep for N extensions, whether or not an extension uses the hook; the fork passes a handful.
2. A rewritten inner loop: 94 to 41 instructions per loop iteration of the voltage update (95 to 42 for the currents), which updates the three field components of four cells (counted in the disassembly of the stock and the cg18 library, `results/kernel_loop_instructions_2026-11-03.txt`); in a standalone copy of the loops, on one thread, GCC 16 runs the stock loop 1.16 to 1.39x faster than Apple clang and the rewrite at about the same speed (`results/kernel_gcc_vs_clang_2026-11-03.txt`).
3. Work stealing over x-lines, slab balancing, and an automatic thread count tuned on the running simulation.
4. f4vector Mur and UPML paths, a scalar-SSE UPML path for PML slabs that do not span z, compressed UPML coefficient tables.
5. A fused E/H sweep: one pass per timestep, the H update trails the E update by one x-line (74 to 49 B per cell of modelled DRAM traffic).
6. Field dumps of the SSE engines use upstream's precomputed gather (the fork maps its entries to f4vector offsets); nf2ff plane sums as complex matrix products (one per plane and block of directions; macOS only: it uses Apple's Accelerate, other builds keep the original loop); threaded operator setup.
7. Staggered allocations against the allocation-placement valley: on one thread, models with field arrays of 2 to 4 MiB each (about 0.175 to 0.35 M cells) ran about 3.6x slower without them. The trigger is where macOS 27.0.1's allocator puts the equal-sized voltage and current arrays: 4 MiB + 16 KiB apart (arrays exactly 4 MiB or 8 MiB + 16 KiB apart run fast); the hardware mechanism was not identified, and no other allocator was measured. An offset of 256 + (2560 k mod 16128) B per large allocation avoids it (`results/cache_valley_2026-11-01.txt`, `results/cache_valley_placement_2026-11-03.txt`; stock v0.37.0 has the valley too, 2.1 to 2.2x deep, `results/cache_valley_stock_2026-11-03.txt`).
8. Line hooks for the dispersive (conducting-sheet) extension, so lossy boards use the fused sweep.
9. Packed per-operator coefficient entries (one or two cache lines instead of six).
10. Engine threads at user-initiated QoS on macOS.
11. A probe end criterion (opt-in, `OPENEMS_PROBE_END_DB`): the run stops once every port and field probe has stayed below a fraction of its peak for a hold time. On the author's boards the energy criterion stalls on the static charge that the default Gaussian pulse leaves behind (it has a DC part); upstream master later added an opt-in DC-free pulse (d686f1d, after the fork's base), which avoids the stall by changing the excitation.
12. A Metal engine for the GPU, `--engine=metal-diamond` (opt-in; macOS builds with `ENABLE_METAL`): diamond-shaped tiles that advance K timesteps per block (3 or 4, picked at run time); the tile schedule follows luikore's Metal engine ([openEMS PR #228](https://github.com/thliebig/openEMS/pull/228), GPL; no code of it is used). The fields are the engine's own arrays in shared Metal buffers, so probes, dumps and any extension left on the CPU use the same memory. On the GPU run the field updates, the excitation, Mur, lumped RLC elements, UPML, Drude/Lorentz materials with the conducting sheets and Debye materials, so all six benchmark models run there (since cg22); any other extension makes the run take the single-threaded CPU loops. A run-time tuner (patch 0016) times four tilings in the first command buffers and keeps the fastest. The results are bit-identical to the multithreaded engine run with `OPENEMS_FTZ=1`, not to stock (`BUILD.md` section 7).
13. One operator index per z-vector (four cells) instead of one per cell: about 3 B per cell less memory, and on meshes of up to 42 z lines 3 B per cell less to stream.
14. Conducting sheets: the ADE orders of a position back to back, four positions per f4vector, with a uniqueness guard that follows the strict-order check of upstream [PR #245](https://github.com/thliebig/openEMS/pull/245) by Roel Budé (unsettledroell404).
15. UPML: the scalar-SSE path four y-rows at a time for boxes that are not full-z slabs (the SMA launch's), and the UPML operator coefficients computed on the setup threads, from upstream [PR #244](https://github.com/thliebig/openEMS/pull/244) by Noriaki Takashima (nori-proto).
16. Line hooks for the steady-state detection (which every sinusoidal excitation adds) and for Debye materials, so such models, upstream's benchmark cases among them, run on the fused sweep.
17. Geometry coefficient tables: when the packed tables of item 9 would exceed 4 MB, 100 B per operator instead of 192 (of the six models only the SMA launch).
18. Neighbour flags instead of the two barriers per timestep of the fused sweep: a thread waits only for its two neighbours, the extensions read their own thread's timestep, lumped RLC takes its time slots from the timestep (as MrHighVoltage proposed in upstream [Discussion #492](https://github.com/thliebig/openEMS-Project/discussions/492)), the steady-state detection runs on the flags too, and the flag waits do not spin when the threads outnumber the performance cores; `OPENEMS_FUSED_STAT=1` prints the time split of the sweep per thread.

All items except the probe end criterion and the Metal diamond engine are on by default; the coefficient layout and
the neighbour flags with their spin depend on the model and the thread count (`BUILD.md` section 7). Most can be
switched off with environment variables (see `BUILD.md`; `OPENEMS_FUSED=0` also turns off every line hook, the
dispersive ones included, and the neighbour flags); the hook plan and spin barriers, work stealing, the Mur and UPML
vector paths (of these only the UPML y-rows of item 15 have a switch), the dump gather, the operator-setup changes
(item 15's UPML coefficients on the setup threads among them) and the line hooks of item 16 have no switch of their
own and rest on the bit-identity checks against the snapshot before them. The operator setup uses every core whatever
`numThreads` says.

## Status and licence

The fork is used daily by the author (as cg29, patches 0001 to 0027, since 2026-11-06, and as cg18, patches 0001 to
0006, from 2026-11-04 to 2026-11-06; the author's toolkit runs it with no change on its side, on the CPU engine with
the automatic thread count, and does not select the Metal diamond engine, which is in the installed build but
opt-in); it has not been submitted upstream. The patches apply only to their base:
upstream has since merged a reworked GPU engine into master (c3a956b, 2026-10-17), deleted the `gpu-engine` branch and
restructured the engines (c0816a2, 2026-11-02), so a submission means porting each item to master and checking it
against a stock build of master. Fixes made upstream after the base are not in the fork; `BUILD.md` lists them.
Upstream has put speed pull requests on hold until its operator refactoring is done
([Discussion #495](https://github.com/thliebig/openEMS-Project/discussions/495)), and other contributors have posted
overlapping work: among it luikore's diamond-blocked Metal engine
([openEMS#228](https://github.com/thliebig/openEMS/pull/228)), whose tile schedule the fork's Metal diamond engine
follows (no code of it is used), and CPU pull requests with identical results such as
[#231](https://github.com/thliebig/openEMS/pull/231), [#244](https://github.com/thliebig/openEMS/pull/244) and
[#245](https://github.com/thliebig/openEMS/pull/245); cg29 takes the UPML part of #244, follows the strict-order check
of #245 and the lumped-RLC time slots that MrHighVoltage proposed in Discussion #492 (items 15, 14 and 18 above). On
2026-11-04 upstream master's merged GPU engine and PR #228 were built and run here on the six models (on a Mac shared
with other work, so the speeds are rough): master's GPU engine ran at 0.42 to 1.06 times the speed of cg18's CPU
engine, and PR #228's diamond path refused all six models before stepping (it has not migrated their Mur boundaries,
nor the GCPW line's conducting sheets); it ran only variants with every Mur face replaced by PEC, on which the fork's
Metal diamond engine was not run, so the two diamond engines have not been compared head to head
(`results/others_2026-11-04/README.md`). The paper's section "Positioning" lists this work (the paragraph on it was
added on 2026-11-04 by Claude Opus 5.5, see `CHANGELOG.md`).

openEMS is under the GPL and CSXCAD under the LGPL, both version 3 or later. The openEMS patches are under the GPL like
the files they change, and the CSXCAD patch under the LGPL like its files (`patches/csxcad/COPYING.LESSER`); files
copied from or based on openEMS keep their upstream copyright and licence notice; the harness, the scripts (the
paper's figure scripts included), `paper/code_notes.md`, `swift_engine/` and the result files of this repository are
under GPL-3.0-or-later (`LICENSE`); the paper text and figures are CC BY 4.0 (`paper/LICENSE-CC-BY-4.0.txt`). The
Swift package of the command line (`Package.swift`, `Sources/`, `Tests/`) is under GPL-3.0-or-later: its Swift files
and its Python launcher each carry `SPDX-License-Identifier: GPL-3.0-or-later`, and `LICENSE` holds the licence text.
On 2026-11-08 the author decided that the package stays under GPL-3.0-or-later; femKit, momKit and sbrKit, which have
no code in this repository, choose their licence when they are merged and published.

The code and most of the text were generated by AI assistants (Claude, Anthropic, operated through Claude Code)
working under the author's direction, with every change verified by the benchmarks described in the paper: Claude
Opus 5.5 on 2026-10-28 until the evening (the harness and the engine work of patch 0001), Claude Fable 5.1 from then to
the early morning of 2026-11-03 (the commits of 0001-0005, whose trailers name it, and most of the first version of
these documents; the trailer of 0001 also names Claude Opus 5.5, which wrote its code), and Claude Opus 5.5
from then on: the final review of 2026-11-03, its fixes (patch 0006 and these documents) and that day's runs
(the re-measured end-to-end runs, the full check and the correctness checks of cg18, the comparison with
the fork's base, the valley placement test and stock sweep, the GCC/clang kernel comparison and the loop
counts, the memory and time-step checks and the validation runs on the Mac); on 2026-11-04 the Metal diamond
engine (patches 0007 to 0016) with its checks and the K=1 measurement; on 2026-11-05 the CPU items of cg29 (patches
0017 to 0027) with their checks and measurements, and the documentation update of that day, whose fact sheets and
edits were made by Claude Opus 5.5 agents in workflows of the same session. On 2026-11-05 the same session also ran
the GPU-against-CPU size sweep, whose rows five checkers and a skeptic (Claude Opus 5.5 agents in a read-only
workflow) then recomputed from the raw runs, checking its text as well; Claude Opus 5.5 agents in workflows of the
same session renamed the documents to fdtdKit (2026-11-05) and wrote, built, tested, reviewed and acceptance-ran the
command line `emskit fdtd` (`Package.swift`, `Sources/`, `Tests/`, `Docs/fdtdKit/PLAN.md`; 2026-11-05 and
2026-11-06); on 2026-11-06 the same session and Claude Opus 5.5 agents installed cg29 on the author's Mac and made
that day's documentation updates; on 2026-11-07 the same session rewrote the two fork branches for publication,
pushed them to the author's GitHub forks at the author's request and made that day's documentation update, with
Claude Opus 5.5 agents checking the work read-only before and after the push, and built the published patches from a
fresh clone and ran the full check on that build; later that day Claude Opus 5.5 agents in a read-only workflow audited
the copy made for publication, and on 2026-11-08 Claude Opus 5.5 agents in a workflow of the same session applied the
audit's fixes and the author's decisions of that day. The same day the author ran Claude Code's cloud code review
(`/code-review ultra`; the model of its reviewers is not shown) on 18 of the command line's 31 source files; on
2026-11-09 a separate Claude Opus 5.5 session, opened by the author in the review's copy, wrote the fixes of its six
findings. Claude Opus 5.5 agents in a read-only workflow of the main session checked them; the main session corrected
what they found (one fix had dropped a fallback; the Ctrl-C handling of another needed three small changes), added
five tests and carried all of it into the repository. From the evening of 2026-11-09 the main session ran on
Claude Fable 5.2: its agents reviewed all 31 source files in a read-only workflow, and on 2026-11-10 agents of a
second workflow fixed the confirmed findings and reviewed the fixes, twice (`CHANGELOG.md`, 2026-11-10); the main
session ran the checks. A separate Claude Opus 5.5 session in this folder wrote the
paper's paragraph on concurrent work and built and measured upstream master and PR #228 on 2026-11-04; another Claude
Opus 5.5 session wrote the work plan of 2026-11-04 (a working note that is not part of the published repository), which
the author pasted into the session that did the work; the read-only reviews and research of 2026-11-04 and 2026-11-05
ran as workflows with Claude Opus 5.5 agents. Since 2026-11-07 the fork's commits carry the author's public git
identity and name the model in a `Generated-by:` trailer above a `Signed-off-by:` line (they were rewritten for
publication that day, with the same trees). The goal, the acceptance rule, the plans and the decisions, among them the
toolkit defaults of 2026-11-04 and the publishing decisions of 2026-11-06 and 2026-11-08, were the author's.
The first versions of the paper's positioning section and of `ROADMAP.md`, the cluster sentence of the abstract, the
"Scaling out" paragraph above, and the validation suite with its two Linux runs were added on 2026-11-03 by an AI
assistant session that the project's log does not record; its model is not recorded. The suite's four runs on the
Mac, the negative control among them, came from the final review. The two runs of snapshot cg17 on the Mac
(`results/validation_cg17*`) came later that day from a Claude Opus 5.5 session in the Claude desktop app, also outside
the project's log.
Upstream's `AI_POLICY.md` asks for a `Generated-by:` line directly above a `Signed-off-by:` line, the form of the
fork's commits.

`PUBLISH.md`, `NEXT_WORK_PROMPT.md` and `CLAUDE.md`, which some records name, are the author's publishing steps, the
work plan of 2026-11-04 and the assistants' working notes; they are not part of the published repository. The
repository is published as one commit, without the history in which it was made; the hashes of this repository's own
commits that the records cite (for example 00e8f7d, 60fd4a3 and 64d19f8) name commits of that history. Hashes of
the openEMS fork in records made before 2026-11-07 (for example 1620939 and 087ce9e) are those that its commits had
before that day's rewrite for publication; the table in the `CHANGELOG.md` entry of 2026-11-07 on the fork's rewrite
maps them to the published ones (see also the note "Commit hashes" in `BUILD.md`).
