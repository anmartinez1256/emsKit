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

In the speed table below (snapshot cg29 = patches 0001 to 0027, measured on the M5 on 2026-11-05 with all
configurations paired in the same rounds, the other processes at a median of 0.5 to 0.8 cores; a second machine, an
M5 Pro, has its own set further down), the CPU engine reaches 1.95x (patch x5) to
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
`CHANGELOG.md`. Of the code added since (patches 0007 to 0043), two parts had a correctness review with verifiers: the tiling tuner
of patch 0016, on its first version (three read-only reviewers, every finding checked by two verifiers; section 5 of
`results/diamond_engine_cg28_tuner_2026-11-04.txt`), and the tiled sweep of patch 0040, before its commit (three
read-only reviewers, each finding handed to a second reader; `results/tiled_sweep_cg32_2026-11-11.txt`). Patches
0041 to 0043 (2026-11-12 and 2026-11-13) were planned and reviewed by Claude Fable 5.2 and checked as described below. The rest
rests on the checks below.
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
them in section 3 of `results/cpu_items_cg29_2026-11-05.txt`). From 2026-11-06 to 2026-11-11 cg29 was the build
installed on the author's Mac. On 2026-11-06 the command line's release build (section "Command line") checked the
installed library, on a Mac loaded by other programs, so only the verdicts count: `check --lite` all identical to
stock on the six models (18 of 18 rows exact), the Debye check (its fields also identical to those of snapshot
cg29), `diamond-check` 72 of 72, the validation suite 15 of 15 with the default engine and with the multithreaded
engine at 4 threads, and the GCPW line's end-to-end run at the toolkit's defaults, stopped by the probe end criterion
at step 34300 as on cg18 and cg29 before (`Docs/fdtdKit/PLAN.md`, section 16). On 2026-11-07 the 27 patches
published then (0001 to 0027) were built from a fresh clone of upstream's superproject as `BUILD.md` describes, and
that build passed `check.sh` (every run identical to stock on the six models), the Debye check, `diamond_check.sh`
72 of 72, the six models on `metal-diamond`, the validation suite 15 of 15 twice and the cylindrical multigrid, on a
loaded Mac (`results/fresh_build_pub29_2026-11-07.txt`). Since 2026-11-11 the build installed on the author's Mac is cg31
(patches 0001 to 0039). Its checks of that day are not the full check of `BUILD.md` section 9: each of its steps
(snapshots cg30a to cg30l and cg31a) passed `diamond_check.sh`, 72 of 72; the snapshot of patches 0001 to 0038 passed
`check --lite` (all identical to stock on the six models, 18 of 18 rows), the Debye check, the validation suite on
the Metal diamond engine (15 of 15) and the GCPW line's end-to-end run on that engine; for patch 0039, a closed
cylindrical mesh gave stock's probes and the same raw fields with and without the fused sweep and at 1, 4, 8 and 10
threads, and the cylindrical multigrid tutorial 18 datasets equal to cg29's; and the installed library passed
`check --lite` (18 of 18 rows), the Debye check, `diamond_check.sh` 72 of 72 and both boards' end-to-end runs at the
toolkit's defaults, which stopped at the same steps as with cg29, 34300 (GCPW line) and 50320 (SMA launch)
(`results/metal_engine_cg31_2026-11-11.txt`). Patch 0040 (0ef186b, the fork's head from the evening of 2026-11-11 until the commits of 2026-11-13)
is not installed. It adds an opt-in tiled sweep to the multithreaded engine (item 22 below). Its snapshot cg32d gave
the fused sweep's results in every test of `scripts/tiled_sweep/check.zsh`, and with the switch unset `check --lite`
was all identical to stock on the six models, 18 of 18 rows (`results/tiled_sweep_cg32_2026-11-11.txt`).
Patches 0041 to 0043, the fork's head since 2026-11-13 (13350ca), are not installed either. 0041 changes where the
automatic thread count starts its search, 0042 packs the Debye, Lorentz and Drude line hooks and 0043 hardens that code (items
23 and 24 below). Their snapshots cg33a to cg33d gave stock's results in every check of 2026-11-13, on the M5 Pro under
macOS 27.2.1 and with the Mac loaded by other programs, so only the verdicts count: `scripts/ade_check/ade_check2.py`, which
compares the probes, the HDF5 dumps and the raw fields of six kinds of dispersive model against stock and against cg31 at
four thread counts, unfused, tiled, packing off, sse-compressed and basic, 66 of 66 rows at 37 lines and 3000 steps and every
row at 101 lines and 600 steps (a 1 M-cell grid with a source on the mesh; the closed-cylinder case at 1500 steps); `check
--lite` 18 of 18 rows, the Debye check, `diamond-check` 72 of 72, the validation suite 15 of 15 on the fastest engine and on the
multithreaded engine at 15 threads, six models in eight configurations (48 of 48 identical to stock), the tiled-sweep check and
the cylindrical multigrid (43 datasets, 0 differences; `results/cpu_items_cg33_2026-11-13.txt`, section 1).
On a second machine, an Apple M5 Pro Mac mini under macOS 27.2.1, the same library files passed on the evening of
2026-11-11: `check --lite` on the installed library and on cg32d (all identical to stock, 18 of 18 rows each), the
validation suite 15 of 15 with the default engine and on `metal-diamond`, `diamond-check` 72 of 72 and the Debye
check (`results/m5pro_speed_set_2026-11-12.txt`).
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

**A later build.** The table above was not measured again. cg31 (patches 0028 to 0039, 2026-11-11) raised the rates
of the Metal diamond engine: in four paired rounds on a quiet Mac it ran at 1.09 times cg29's rate on the GCPW line
(2118 to 2307 MC/s), 1.14 times on the SMA launch (1854 to 2108, on its 0.871 M-cell mesh, not the table's), 1.08
times on the patch tutorial (1753 to 1887), 1.53 times on the notch tutorial (1904 to 2907), 1.07 times on patch x5
(2901 to 3100) and 1.15 times on notch x3 (3210 to 3702). That table, with cg31's CPU engine beside it, is in the
paper's section "After publication" and in `results/metal_engine_cg31_2026-11-11.txt`. On the benchmark model of
luikore's Metal engine, with three builds interleaved, cg31's Metal engine ran 3981 and 3309 MC/s at 3.0 M and
17.0 M cells and luikore's 3952 and 2829 (`results/engines_on_luikore_model_2026-11-11.txt`).

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

**A second machine: an M5 Pro Mac mini (a set of its own).** Every speed above was measured on the M5 MacBook Air.
On 2026-11-12 the same library files, cg31 (patches 0001 to 0039) and stock v0.37.0, were measured on a Mac mini with
an Apple M5 Pro (5 "Super" cores sharing one L2 of 16 MiB, 10 "Performance" cores with two L2 of 8 MiB, 24 GB, macOS
27.2.1), in a night queue of that machine with no other measured job beside them. These numbers are compared only
with each other, never with the M5's. STREAM Triad gives 256 GB/s with the five Super cores and 259 GB/s with all 15.
Five interleaved rounds per model (`bench/abtest.py`; the other processes mostly at 0.2 to 0.4 cores, beside the
notch tutorial and patch x5 at 1.15 and 1.27), medians; the stock column and the gain were corrected on 2026-11-13 (note below the table):

| model (cells) | stock v0.37.0, MC/s (threads) | fdtdKit CPU, MC/s (15 threads) | gain | fdtdKit GPU, MC/s | GPU / CPU |
|---|---|---|---|---|---|
| GCPW line (0.24 M) | 305 (4) | 4123 | 14.06x | 4085 | 0.99x |
| vertical SMA launch (0.87 M) | 472 (5) | 4307 | 9.33x | 3916 | 0.91x |
| notch filter tutorial | 343 (5) | 4111 | 12.45x | 4836 | 1.18x |
| notch filter x3 (5.25 M) | 1164 (10) | 4931 | 4.27x | 7140 | 1.45x |
| patch antenna tutorial | 270 (2) | 2633 | 9.67x | 2901 | 1.10x |
| patch antenna x5 (7.86 M) | 1488 (10) | 3857 | 2.73x | 6511 | 1.69x |

(Corrected on 2026-11-13. The fdtdKit columns are those of 2026-11-12: the fork's CPU engine (cg31's multithreaded engine)
at 5, 10 and 15 threads and with the automatic count, fastest at 15 on all six, and its GPU engine
(`--engine=metal-diamond`), 5 interleaved rounds. The stock column and the gain are from 2026-11-13: stock measured at 1,
2, 3, 4, 5, 10 and 15 threads (3 interleaved rounds, half the steps of the speed table, cg31 at 15 threads in the same
rounds, the other processes mostly at 20 to 60 % of one core, in two runs at 171 and 182 %), the best of the seven
counts shown with its thread count; the gain is the median over the rounds of cg31's rate at 15 threads over stock's best
in the same round, 14.06x [13.86 to 14.52], 9.33x [9.29 to 9.63], 12.45x [12.43 to 12.92], 4.27x [4.20 to 4.31], 9.67x
[9.66 to 9.99] and 2.73x [2.71 to 2.76], with cg31's rates of those rounds (4287, 4431, 4258, 4944, 2615 and 4050 MC/s),
not the quotient of the two medians printed here. The first version of this table took stock's best from runs at 5 and 10
threads only (283, 449, 270, 1124, 152 and 1406 MC/s) and gave gains of 14.6x, 9.6x, 15.2x, 4.39x, 17.3x and 2.74x, up to
17.3x where the table now has 14.06x at most; stock needs a thread count of its own per model, and on the small grids it
slows down with threads (the patch tutorial: 270 MC/s at 2 threads, 36 at 15), and it runs slower at 10 threads than at 5 on
four of the six models. GPU / CPU is the Metal engine over the fork's best fixed count of 2026-11-12 and did not change.
The CPU runs are identical to stock bit for bit; the GPU runs differ by at most 9.4e-7 relative.)

End to end through the author's toolkit at its defaults (the engine picks the threads, the probe end at -60 dB with a hold
of 0.5, the SMA launch on its 0.05 mm mesh floor; wall time of `FDTD.Run`; the stock runs are those of 2026-11-12, at the
toolkit's fallback thread counts, 4 for the GCPW line and 8 for the SMA launch, since stock has no automatic count):

| board | stock v0.37.0 | fdtdKit CPU (cg31) | fdtdKit GPU (cg31) |
|---|---|---|---|
| GCPW line | 75.8 s (94217 steps, to max_time) | 2.8 s (34300 steps, probe end), 27x | 2.4 s (34300 steps), 32x |
| vertical SMA launch | 281.2 s (118475 steps, to max_time) | 11.0 s (50320 steps, probe end), 25.6x | 11.2 s (50320 steps), 25.1x |

On the M5 Pro the two boards therefore finish end to end 25 to 32 times sooner than on stock v0.37.0 at the toolkit's
defaults, and the factor has three parts: stock has no probe-end criterion, and the fork's stops these runs after 2.7 and 2.4
times fewer steps (GCPW line, SMA launch); the faster engine supplies the rest; and the 32 is the opt-in Metal engine on
the GCPW line, where the CPU engine reaches 27 (the SMA launch gains 25.6x and 25.1x). In the GCPW run the engine's own thread choice ran at 3281 MC/s against 4123 at 15 fixed threads: on a
run of a few seconds its search costs about 20 %. The CPU engine runs notch x3, patch x5 and the GCPW line fastest at
15 threads (7.0x, 5.1x and 7.5x their rate on one thread); the allocation-placement valley is still there under
macOS 27.2.1 (the GCPW line at one thread 563 MC/s, 191 without the stagger); without the neighbour flags the engine
runs notch x3 9 to 13 % slower. The tiled sweep of patch 0040 led the fused sweep only on a PEC box of 16.8 M cells
(1.43x) and stays opt-in. All of it is in `results/m5pro_speed_set_2026-11-12.txt`, in
`results/m5pro_tiled_sweep_2026-11-12.txt` and in the paper's section on the M5 Pro; the scripts are in
`scripts/m5pro/`.

**A later CPU build (patches 0041 to 0043, the fork's head 13350ca; not installed), on the M5 Pro, 2026-11-12 and
2026-11-13** (`results/cpu_items_cg33_2026-11-13.txt`; a set of its own; every run of the fork's builds in these comparisons gave its reference run's probes; the other
processes at 20 to 37 % of one core in the first night, in the second at 17 to 29 % in the GCPW runs; the figures are medians
of paired interleaved rounds). The automatic thread count (patch 0041, 4 rounds) gave 0.97 to 1.00 of 15 fixed threads on the
GCPW line (34300 steps), the SMA launch (50320), notch x3 (2000) and patch x5 (1200), where cg31's search gave 0.81, 0.96,
0.82 and 0.87 of them; with `OPENEMS_TUNE_START=p` the new build gave 0.81, 0.98, 0.81 and 0.86, cg31's behaviour. The packed
Debye, Lorentz and Drude line hooks (patch 0042; upstream's `bench.py`, interleaved against cg31, 3 repeats, fixed thread
counts) ran 1.94 times as fast on the `dispersive` case of 1 M cells at 5 threads and 1.90 times at 15, and 2.11 times on
the case of 8 M cells at 5 threads and 1.14 times at 15; the `antenna` case gained 1.10 and 1.08 times at 1 M cells (the
second inside the spread) and 1.06 and 1.03 times at 8 M (the second inside the spread). On the GCPW board, whose conducting
sheets run packed (1793 groups), nothing changed (34300 steps, 15 threads, 4 rounds: cg31 4201.5 MC/s, cg33d 4190.4, x0.998
[0.995 to 1.002], and with `OPENEMS_ADE_PACKED=0` 4194.7, x0.998 [0.987 to 1.013]).

**Against master's CPU engine (M5 Pro, 2026-11-13).** Upstream's master has a new `cpu` engine of its own (1d710c2); it blocks
in time, with one cache-sized tile shared by all threads and several timesteps per pass, and is not bit-identical to
v0.37.0. Upstream's `benchmark/bench.py` ran master's `cpu` engine (A) and the fork's multithreaded engine (cg33d, B) run
for run, 3 repeats, the other processes at a median of 20 % of one core, on the meshes of 101 and 201 lines (see the
note below: with upstream's own even counts the cases ideal, PML and dispersive have no source). Fork over master, B/A, at 5 / 10 /
15 threads, medians:

| case | 1 M cells (S) | 8 M cells (M) |
|---|---|---|
| ideal | 1.42 / 2.20 / 2.52 | 1.02 / 1.03 / 1.09 |
| PML | 1.61 / 2.16 / 2.42 | 0.93 / 1.07 / 1.14 |
| dispersive | 0.96 / 1.30 / 1.45 | 0.73 / 0.70 / 0.54 |

(Rates, master / fork in MC/s at 5 / 10 / 15 threads: ideal S 2293 / 3258, 2338 / 5138, 2524 / 6346; ideal M 2869 / 2932,
3568 / 3690, 3671 / 3985; PML S 1023 / 1651, 1135 / 2454, 1297 / 3133; PML M 1763 / 1630, 2139 / 2283, 2238 / 2561;
dispersive S 1400 / 1343, 1601 / 2080, 1679 / 2436; dispersive M 1771 / 1296, 2201 / 1540, 2460 / 1338. The spread of the
three repeats was 0.8 to 6.5 %, except 12.4 % for dispersive S at 10 threads.) The fork is ahead at 1 M cells (except
dispersive at 5 threads, level), level to 14 % ahead at 8 M cells on the ideal and PML cases (0.93 times on PML at 5 threads), and behind master on the 8 M
dispersive case, at 0.54 to 0.73 of master's rate (the fork peaks at 10 threads there, and its setup of that case takes 2.5
to 5.5 times master's); this is the open CPU item in `ROADMAP.md`, and the tiled sweep does not close it: on the 8 M ideal
case `OPENEMS_TBLOCK=auto` gained 8, 22 and 15 % over the fused sweep at 5, 10 and 15 threads (3183, 4450 and 4569 against
2954, 3647 and 3969 MC/s) and every tiled variant was slower on the 8 M dispersive case (`auto` by 19, 27 and 44 %). Master's
probes differ from the fork's, which equal stock's bit for bit, by 5e-6 to 3e-5 relative on these cases. In the run of the
night before (cg31, cases with their own sources) the ratios were 1.56 / 2.18 / 2.43 (inhomogeneous, 1 M), 0.98 / 1.11 / 1.19
(8 M), 1.41 / 1.90 / 2.18 (antenna, 1 M), 0.92 / 1.04 / 1.14 (8 M), 1.53 / 2.15 / 2.57 (cylindrical, 1 M) and 1.04 / 1.17 / 1.30
(8 M), and master's probes differed by 3e-7 to 1e-5.

**Upstream's benchmark cases without a source.** In upstream master 1d710c2, `benchmark/cases.py` builds its uniform meshes as
`arange(n) - (n-1)/2`. With an even number of lines (the sizes S and M of `bench.py`, 100 and 200 lines; 37 and 311 are odd)
no mesh line passes through the origin, so the dipole that the cases `ideal`, `pml` and `dispersive` put at (0, 0, z) excites
nothing (openEMS prints "Voltage excitations: 0") and those runs have all fields zero; `inhomogeneous`, `antenna` and
`cylindrical` have sources of their own. The speeds that this repository quotes for those three cases at S and M (the
common benchmarks of 2026-11-10 and the runs of 2026-11-12) are therefore speeds on zero fields, and their "probes
identical" says nothing. A control on 2026-11-13 gave rates equal to those with a source within the spread of the runs (M,
15 threads, master / fork in MC/s: ideal 3870 / 4071 without and 3671 / 3985 with a source; dispersive 2437 / 1344 without
and 2460 / 1338 with), so the rates stand; the identity of the fork's engine on these cases rests on the 37-line size and on
the 101-line runs of `scripts/ade_check/ade_check2.py`. The table above and the runs of 2026-11-13 use 101 and 201 lines. The
finding has not been reported upstream yet.

**Scaling out (planned, not measured).** On large grids the memory bus of one machine bounds the cell
rate (on the M5 Pro only the largest grid measured, a PEC box of 16.8 M cells, was held back by it: the fused sweep scales
to 15 threads on every other model and reaches 5602 MC/s at 15 threads on a box of 2.95 M cells), and the way to scale
further is a Thunderbolt-connected cluster of Mac minis or Mac Studios, each adding its own unified memory and
bandwidth: parameter sweeps across machines first, then one large model split across them, which needs a
domain-decomposed engine that openEMS does not have today (see `ROADMAP.md`).

## What is in the box

| folder | content |
|---|---|
| `paper/` | the technical report (LaTeX source, figures with their scripts, PDF) and `paper/code_notes.md`, notes on each code change of patches 0001 to 0006 and of patches 0040 to 0043 written from the diffs (patches 0007 to 0039 are described in `CHANGELOG.md`, the paper and their commit messages); `paper/figures/tables.py` writes the paper's two tables of cg29 and the speed table of this README from `results/` |
| `patches/README.md` | what each patch folder applies to, in which order, and its licence |
| `patches/openems/` | the fork as 43 `git am` patches on commit 7bb294f of upstream's former `gpu-engine` branch (`BASE_origin_gpu-engine.txt`), plus one cumulative diff: 0001 to 0006 = snapshot cg18, the build installed on the author's Mac from 2026-11-04 to 2026-11-06; 0007 to 0016 = the Metal diamond engine (snapshots cg19 to cg28); 0017 to 0027 = the CPU items of snapshot cg29, the build installed there from 2026-11-06 to 2026-11-11; 0028 to 0039 = the first twelve commits of 2026-11-11 (0028 the energy schedule of a run without an end criterion, 0029 to 0038 the Metal diamond engine, 0039 line hooks for the cylinder extension), which make cg31, the build installed there since 2026-11-11; 0040 = the opt-in tiled sweep of the multithreaded engine, committed that evening (snapshot cg32d; not installed); 0041 to 0043 = the thread search from every non-efficiency core and the packed dispersive line hooks with their hardening, written on 2026-11-12 and 2026-11-13 and committed on 2026-11-13 (snapshots cg33a to cg33d, the fork's head 13350ca; not installed). They need the CSXCAD patch below (they do not build against a stock CSXCAD 0.7.0), and they apply to that base only: upstream has since merged a reworked GPU engine into master, deleted the branch and restructured the engines |
| `patches/csxcad/` | one patch on CSXCAD v0.7.0 (material lookups during operator setup), under LGPL-3.0-or-later like CSXCAD (`COPYING.LESSER`) |
| `bench/` | the harness: `bench.py` (in-process runs with a fixed step count, S-parameter comparison; the GPU engines and `OPENEMS_FTZ` runs are compared but marked tolerant), `check.sh` (six models, five thread settings, bit-identity against stock), `abtest.py` (paired interleaved rounds, with waits for a quiet Mac), `usage.py` (the other processes' CPU and GPU use during each run), the models (`models.py`: the six benchmark models and two that only the harness runs, not `emskit fdtd`: `cube`, the free-space cube of the common benchmarks, in the records of 2026-11-10 and 2026-11-11, and `lbox`, the benchmark model of luikore's engine, in the records of 2026-11-11) |
| `bench/validation/` | a validation suite against closed-form references (dispersive slabs, a rectangular and a cylindrical cavity, a WR-90 guide, a microstrip line), with same-build engine comparisons on the dispersive slabs; its runs (`results/validation_*`): cg18, cg29 and the fresh build of 2026-11-07 of the patches published then, 0001 to 0027 (`validation_pub29_*`), 15 of 15 each on the Mac, each with the multithreaded engine at 4 threads and with the default engine and thread count (`validation_cg29pre_*` is an earlier build of cg29's topics); the Metal diamond engine 15 of 15 on cg23 and on cg27 (its slabs equal to the basic engine; the cylindrical cavity runs on the cylindrical CPU engine); snapshot cg17 (patches 0001 to 0005) 15 of 15 with its defaults and at 8 threads (two runs made outside the project's log); stock v0.37.0 15 of 15 on the Mac and 12 of 12 on a Linux x86_64 VM (the suite's earlier version, without the engine comparisons); and two negative controls that fail their Debye checks as they should, a stock build with the Debye hooks disabled on the VM (2 of 3 checks pass) and a build of patches 0001 to 0004 (the Debye bug) on the Mac (4 of 6 pass). See `bench/validation/README.md` |
| `results/` | the benchmark tables of the project (`MODEL_sSCALE_nSTEPS_SNAPSHOT.txt`; `*_cg18.txt`, `*_cg29.txt` and `*_pub29.txt` = the full checks of cg18, cg29 and a fresh build of the patches published on 2026-11-07, 0001 to 0027 (`fresh_build_pub29_2026-11-07.txt`), `*_cg2Ngpu.txt` and `*_pub29gpu.txt` = the Metal diamond engine of cg20 to cg29 and of that build against the multithreaded engine with `OPENEMS_FTZ=1` (cg20 to cg22 with the base's GPU engine as well), `*_base.txt` = the fork's base against stock), the speed table above (`speed_cg29_2026-11-05.txt`), the CPU items of cg29 with their paired runs and the comparison with cg18 (`cpu_items_cg29_2026-11-05.txt`), the Metal diamond engine's snapshots and checks (`diamond_engine_*`, `diamond_check_*`, `diamond_sweep_cg21_2026-11-04.txt`), the Swift prototype's diamond mode (`diamond_swift_2026-11-04.txt`), the fused unblocked Metal sweep (`fused_sweep_k1_2026-11-04.txt`), the GPU against the CPU by grid size (`gpu_crossover_cg29_2026-11-05.txt`), other openEMS builds run beside fdtdKit (`others_2026-11-04/`), four common benchmarks on cg29 (upstream's `benchmark/bench.py`, STREAM, a free-space cube, the Mie sphere; `common_benchmarks_2026-11-10.txt`), the Metal diamond engine's items of cg31 with the final table against cg29, the closed-cylinder check and the install checks (`metal_engine_cg31_2026-11-11.txt`), luikore's Metal engine, upstream master and cg31 on luikore's benchmark model (`engines_on_luikore_model_2026-11-11.txt`; with cg29 the night before, `luikore_compare_cg29_2026-11-11.txt`), the test of a shorter excitation pulse on the two boards (`pulse_test_2026-11-11.txt`), the opt-in tiled sweep of the multithreaded engine (patch 0040) against the fused sweep, with its checks and its timing on the M5 (`tiled_sweep_cg32_2026-11-11.txt`), the fork on a second machine, an M5 Pro Mac mini, a set of its own (bandwidth, the kernels, the thread sweep, the speed table, the valley, the switches and the two boards end to end, `m5pro_speed_set_2026-11-12.txt`; the tiled sweep there, `m5pro_tiled_sweep_2026-11-12.txt`), the CPU items of patches 0041 to 0043 on the M5 Pro with their identity checks, the corrected stock baseline and master's `cpu` engine beside the fork (`cpu_items_cg33_2026-11-13.txt`), `summary.json` (the best speed per model and snapshot, from every `MODEL_sSCALE_nSTEPS_SNAPSHOT.txt` table in `results/` itself up to pub29; the tables in `others_2026-11-04/` are not in it), the end-to-end runs (`rfsim_e2e_2026-11-03.txt` of cg18 and stock, `rfsim_e2e_gpu_2026-11-04.txt` of cg23 on the GPU, `rfsim_e2e_cg29_2026-11-05.txt`), the mesh sweep, the valley sweeps and the allocator placement test (`cache_valley_*`), the GCC/clang kernel comparison and the loop counts (`kernel_*`), the correctness checks of cg18, the memory and time-step checks, the initial optimisation review, the validation runs. The `*_cg17.txt`, `*_cg19.txt`, `*_cg21.txt`, `*_cg22.txt`, `*_cg2Ngpu.txt` and `*_pub29*.txt` tables were bit-identity checks, many of them on a loaded machine, and the speeds in the `*_cg29.txt` tables are the faster of two unpaired runs of a bit-identity check; none is a speed comparison (`*_cg29pre.*` = the checks of an earlier build of cg29's topics). In `summary.json` the entry of a `*_cg2Ngpu.txt` or `*_pub29gpu.txt` table is its multithreaded row with `OPENEMS_FTZ=1`. The files that the records place in the scratchpad were the assistant session's working files and are not published |
| `scripts/` | the check and experiment scripts: standalone kernel benchmarks (with the GCC/clang comparison and the loop counts), the valley box, sweep and allocator placement test, cylindrical-multigrid check, Debye-material regression check, the Metal diamond engine's bit-identity check (`checks/diamond_check.sh` with its box and compare scripts), setup/nf2ff phase timing, probe-end check, z-padding check, SMA mesh sweep, end-to-end runs (`e2e/run_one.py` runs another engine with `E2E_ENGINE`, for example `metal-diamond`), the GPU-against-CPU size sweep (`gpu_crossover/`), the runs of other openEMS builds beside fdtdKit (`others/run_others.sh`), the common benchmarks (`common_bench/`), the runs on luikore's benchmark model (`luikore_compare/`), the closed-cylinder check (`cylinder_closed/`), the pulse test (`pulse/`), the tiled sweep's check and timing scripts (`tiled_sweep/`), the stages of the M5 Pro set and the slots of 2026-11-12 and 2026-11-13 (`m5pro/`, with `m5pro/master/`: the build of upstream master and the wrappers that let `bench.py` run it beside the fork), the identity check of the packed dispersive hooks (`ade_check/`), memory and time-step checks, HDF5 compare; `scripts/README.md` lists them |
| `swift_engine/` | a Swift + Metal FDTD kernel that runs an exported openEMS operator; bit-identical to the CPU engines on a 41^3 box, and on a 121^3 box to the SSE-based engines (sse, sse-compressed, multithreaded) with `OPENEMS_FTZ=1`, which the basic engine ignores (project log). Its diamond-blocked mode (`--diamond K`, 2026-11-04, the prototype of the Metal diamond engine) gives the same bits as cg18's multithreaded engine (with `OPENEMS_FTZ=1` on the two larger boxes) on 41^3, 121^3 and 201^3 boxes at every K tried (`results/diamond_swift_2026-11-04.txt`) |
| `Package.swift`, `Sources/`, `Tests/` | the EMSKit Swift package: `Sources/fdtdKit` and `Sources/emskit-cli` make fdtdKit's command line `emskit fdtd` (section "Command line" below; with the Python launcher `Sources/fdtdKit/Python/fdtdkit_run.py`), `Tests/fdtdKitTests` holds its tests; the other kits add their own targets to the same package. Written on 2026-11-05 (the core modules, the first commands and the Python launcher) and 2026-11-06 (the remaining commands and the tests); built, tested and acceptance-run on 2026-11-06 (`Docs/fdtdKit/PLAN.md`, section 16) |
| `BUILD.md` | how to build, install, verify and revert; the knobs; what differs from upstream |
| `ROADMAP.md` | planned work: validation, upstreaming, workflow and solver features, the cluster outline, the engines' open items, version 2 of the command line; what was done since its first version, the command line 0.1.0, the build of 2026-11-11 (cg31), the tiled sweep of patch 0040 and the set measured on an M5 Pro among it |
| `Docs/fdtdKit/PLAN.md` | the plan of the command line: its phases and acceptance runs, the facts it rests on, the commands, library identity, the child environment and the knobs, the JSON output and exit codes, load recording, stopping, distribution over several Macs, tests, and its log |

The fork is also kept as two git branches with the same changes as commits: the openEMS fork's branch
[`speed-m5-gpu`](https://github.com/anmartinez1256/openEMS/tree/speed-m5-gpu) holds the 43 commits of
`patches/openems/` on 7bb294f (head 13350ca; the installed build cg31 is its commit ff2538a, the 39th, four before the head),
and the CSXCAD fork's branch
[`speed-m5`](https://github.com/anmartinez1256/CSXCAD/tree/speed-m5) the one commit of `patches/csxcad/` on v0.7.0.

The changes made in this project to the author's simulation toolkit (rfsim) are not published, since the toolkit itself
is private; the paper's section "The modelling side" and `CHANGELOG.md` describe them. The two board models and their
rows in the speed table above can therefore be checked against `results/` but not rerun by others.

## Command line: `emskit fdtd` (fdtdKit)

**Status (2026-11-10):** built and tested with Swift 6.4.2 on macOS 27.0.1: the 244 unit tests of that day (27
suites) passed; with the 14 smoke runs against the real tools (suite `SmokeTests`, run only with
`EMSKIT_FDTD_SMOKE=1`) there were 258 tests in 28 suites (259 since 2026-11-11, see below). The smoke runs and the
acceptance runs on snapshot cg29 passed on 2026-11-10 (`check cg29
--lite`: all identical to stock v0.37.0 on the six models; `diamond-check cg29`: 72 of 72 comparisons identical;
`e2e gcpw --lib cg29`: the run finishes). On 2026-11-11, after the knob registry grew to 38 names and cg31 was
installed, the unit suite passed again; the smoke runs were not repeated that day. That evening the registry grew to
41 names, with the three switches of the tiled sweep (patch 0040), and one unit test for them was added: there were
then 245 unit tests, and 259 tests in 28 suites with the smoke runs. The unit suite passed on that tree the same
evening, under macOS 27.2.1 (245 run, the 14 smoke tests skipped); the smoke and acceptance runs were not repeated. On
2026-11-13 the registry grew to 43 names (`OPENEMS_TUNE_START`, `OPENEMS_ADE_PACKED`; patches 0041 and 0042), with one more
unit test and the library row of snapshot cg33: 260 tests in 28 suites with the smoke runs. That day the 246 unit tests
passed, and so did the three smoke tests that start no simulation (version, the library identities of `info`, refusals
and plans); the other eleven smoke tests and the acceptance runs were not repeated.
A cloud code review of 18 of the package's 31 source files found one bug and five minor issues on 2026-11-08; all
six are fixed (`CHANGELOG.md`, 2026-11-09). A
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

Items 1 to 11 are in patches 0001 to 0006 (cg18), item 12 in patches 0007 to 0016 (cg19 to cg28), items 13 to 18 in
patches 0017 to 0027 (cg29), items 19 to 21 in patches 0028 to 0039 (cg31, the build installed on the author's Mac
since 2026-11-11, which has these twenty-one), item 22 in patch 0040 and items 23 and 24 in patches 0041 to 0043 (the
fork's head 13350ca; not installed).

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
12. A Metal engine for the GPU, `--engine=metal-diamond` (opt-in; macOS builds with `ENABLE_METAL`): diamond-shaped tiles that advance K timesteps per block (3, 4 or 5, picked at run time); the tile schedule follows luikore's Metal engine ([openEMS PR #228](https://github.com/thliebig/openEMS/pull/228), GPL; no code of it is used). The fields are the engine's own arrays in shared Metal buffers, so probes, dumps and any extension left on the CPU use the same memory. On the GPU run the field updates, the excitation, Mur, lumped RLC elements, UPML, Drude/Lorentz materials with the conducting sheets and Debye materials, so all six benchmark models run there (since cg22); any other extension makes the run take the single-threaded CPU loops. A run-time tuner (patch 0016) times its tilings in the first command buffers and keeps the fastest: seven tilings in two stages since patch 0038 (item 20), four before. The results are bit-identical to the multithreaded engine run with `OPENEMS_FTZ=1`, not to stock (`BUILD.md` section 7).
13. One operator index per z-vector (four cells) instead of one per cell: about 3 B per cell less memory, and on meshes of up to 42 z lines 3 B per cell less to stream.
14. Conducting sheets: the ADE orders of a position back to back, four positions per f4vector, with a uniqueness guard that follows the strict-order check of upstream [PR #245](https://github.com/thliebig/openEMS/pull/245) by Roel Budé (unsettledroell404).
15. UPML: the scalar-SSE path four y-rows at a time for boxes that are not full-z slabs (the SMA launch's), and the UPML operator coefficients computed on the setup threads, from upstream [PR #244](https://github.com/thliebig/openEMS/pull/244) by Noriaki Takashima (nori-proto).
16. Line hooks for the steady-state detection (which every sinusoidal excitation adds) and for Debye materials, so such models, upstream's benchmark cases among them, run on the fused sweep.
17. Geometry coefficient tables: when the packed tables of item 9 would exceed 4 MB, 100 B per operator instead of 192 (of the six models only the SMA launch).
18. Neighbour flags instead of the two barriers per timestep of the fused sweep: a thread waits only for its two neighbours, the extensions read their own thread's timestep, lumped RLC takes its time slots from the timestep (as MrHighVoltage proposed in upstream [Discussion #492](https://github.com/thliebig/openEMS-Project/discussions/492)), the steady-state detection runs on the flags too, and the flag waits do not spin when the threads outnumber the performance cores; `OPENEMS_FUSED_STAT=1` prints the time split of the sweep per thread.
19. No Nyquist-period energy estimates in a run without an end criterion (patch 0028): the fork's base summed the field energy on one thread every Nyquist period during the first minute of every run, the engine waiting, which was 4 to 6 % of the Metal diamond engine's loop on a benchmark model of 3 to 17 M cells with a Nyquist period of 51 steps; a run with `EndCriteria = 0` (a fixed number of steps) now estimates the energy with the progress report only, as v0.37.0 does (`--exact-endcriteria` still asks for the schedule), and its results do not change.
20. The Metal diamond engine's items of 2026-11-11 (patches 0029 to 0038): three dispatches per block instead of four, Mur faces of one axis behind one barrier, UPML a z-vector at a time on the x and y slabs and three components of a cell at a time on the z slabs, dispersive materials three components at a time, index arithmetic without run-time divisions, the extension data's offsets and counts as constants of the kernel, and a tuner of seven tilings in two stages (it adds K=4 with 10,6 and 9,2 tiles and K=5 with 12,8). The fields do not change: every step passed `scripts/checks/diamond_check.sh` with 72 of 72 comparisons identical, and on the benchmark models every probe of cg31's Metal runs equals cg29's. The rates are in the paragraph "A later build" above.
21. Line hooks for the cylinder extension (patch 0039), so a cylindrical mesh that is closed in alpha runs the fused sweep with the neighbour flags: 1857 and 1891 MC/s before, 2503 and 2553 after, at 8 threads on a closed cylinder of 61 x 72 x 41 lines with r = 0 (`results/metal_engine_cg31_2026-11-11.txt`); the cylindrical multigrid stays on the unfused plan.
22. An opt-in tiled sweep for the multithreaded engine (patch 0040, `OPENEMS_TBLOCK=k` or `auto`): k timesteps on one cache-sized tile of x-lines before the next tile, all threads in the same tile, so a tile comes from memory once per k timesteps; the design follows upstream master's `cpu` engine (no code of it is used), and the results are identical to the fused sweep's. On the M5 under macOS 27.2.1 (three paired rounds, other processes at a median of 9 % of one core), its best setting, at 4 threads, against the fused sweep's best, at 8: 1.08 times on patch x5 (2305 against 2138 MC/s) and 1.23 times on a PEC box of 16.8 M cells (the harness model `lbox`, the benchmark model of luikore's engine; 2289 against 1867), but 0.92 times on the same box at 2.95 M cells, 0.85 on a PML cube of 8.0 M (the harness model `cube`), 0.81 on notch x3 and 0.71 on the SMA launch. At 8 or 10 threads it is behind the fused sweep at 8 threads on every model but the 16.8 M box, and under heavy load from other programs it falls far behind; the GCPW line fits the cache, so `auto` keeps the fused sweep there. Hence opt-in, not a default (`results/tiled_sweep_cg32_2026-11-11.txt`; its three switches are in `BUILD.md` section 7). On the M5 Pro (a set of its own, 2026-11-12, `results/m5pro_tiled_sweep_2026-11-12.txt`, at 5, 10 and 15 threads) it led only on the 16.8 M-cell box, 1.43 times the fused sweep's best (4752 against 3326 MC/s, both at 15 threads), and ran 0.41 to 0.97 times the fused sweep's best on the other five models; on those five the fused sweep gains up to 15 threads, while the tiled sweep peaks at 10.
23. The thread search of `numThreads=0` starts at every core that is not an efficiency core (patch 0041): up to patch 0040 it started at the cores of the first performance level (`hw.perflevel0`: 5 on the M5 Pro, 4 on the M5) and went up in steps of 2, which on the M5 Pro, where the fused sweep scales to all 15 cores, took 8 timing windows on notch x3 (5 7 9 11 13 15 3 14 15) and cost 4 to 19 % of a short run; now it starts at every core whose performance level is not named "Efficiency" (15 on the M5 Pro; 4 on the M5, whose second level is the efficiency one, so nothing changes there), steps down by 2 for as long as each step is the fastest so far and then tries one thread either side of the best (notch x3: 15 13 14, three windows). On the M5 Pro the automatic count gave 0.97 to 1.00 of 15 fixed threads on the four models measured, against 0.81 to 0.96 before; `OPENEMS_TUNE_START=p` restores the old rule (`BUILD.md` section 7; `results/cpu_items_cg33_2026-11-13.txt`, section 2).
24. Packed line hooks for the Debye, Lorentz and Drude materials (patches 0042 and 0043): the positions of a dispersive extension are put in groups of up to four positions of one x-line (so no group is shared by two threads), and the state and coefficients of a group sit in one block of memory instead of about fifteen separate arrays; four positions are updated at a time with the same floating-point operations per position in the same order as the one-position loops, so the results do not change. Only the multithreaded engine packs (the other CPU engines keep the old paths on Cartesian meshes and serve as independent references in the checks), and not when the blocks would need more than twice the field memory, in which case one line at verbose 1 or above says so (the limit counts all dispersive extensions of one engine together); the packed code is under the GCC/clang guard, with stubs for other compilers, since its vector types are a GNU extension. A Debye cell cost about 39 ns on one thread before and a Lorentz cell about 14 ns (rough figures on a loaded machine, not results). Against cg31 upstream's `dispersive` case runs 1.9 times as fast at 1 M cells and 2.1 (5 threads) and 1.14 times (15 threads) at 8 M, the author's GCPW board, whose conducting sheets run packed, is unchanged, and `OPENEMS_ADE_PACKED=0` turns the packing off (`results/cpu_items_cg33_2026-11-13.txt`, sections 2 and 3).

All items except the probe end criterion, the Metal diamond engine (items 12 and 20) and the tiled sweep (item 22) are
on by default; the
coefficient layout and the neighbour flags with their spin depend on the model and the thread count (`BUILD.md`
section 7). Most can be switched off with environment variables (see `BUILD.md`; `OPENEMS_FUSED=0` also turns off
every line hook, the dispersive ones included, and the neighbour flags); the hook plan and spin barriers, work
stealing, the Mur and UPML vector paths (of these only the UPML y-rows of item 15 have a switch), the dump gather, the
operator-setup changes (item 15's UPML coefficients on the setup threads among them), the line hooks of items 16 and
21 and the change of item 19 have no switch of their own and rest on the bit-identity checks against the snapshot
before them. Items 23 and 24 are on by default and have a switch each (`OPENEMS_TUNE_START=p`, `OPENEMS_ADE_PACKED=0`). Within the Metal diamond engine the changes of item 20 are on by default, with eight switches
(`OPENEMS_DIAMOND_MERGE`, `_MURMERGE`, `_EVEN`, `_FASTIDX`, `_TGFLAG`, `_PML4`, `_PML3` and `_CAND`; the dispersive
materials' pass and the kernel constants have none). The operator setup uses every core whatever `numThreads` says.

## Status and licence

The fork is used daily by the author (as cg31, patches 0001 to 0039, since 2026-11-11, as cg29, patches 0001 to 0027,
from 2026-11-06 to 2026-11-11, and as cg18, patches 0001 to 0006, from 2026-11-04 to 2026-11-06; the author's toolkit
runs it with no change on its side, on the CPU engine with the automatic thread count, and does not select the Metal
diamond engine, which is in the installed build but opt-in); it has not been submitted upstream. The patches apply
only to their base:
upstream has since merged a reworked GPU engine into master (c3a956b, 2026-10-17), deleted the `gpu-engine` branch and
restructured the engines (c0816a2, 2026-11-02), so a submission means porting each item to master and checking it
against a stock build of master. Fixes made upstream after the base are not in the fork; `BUILD.md` lists them.
Upstream has put speed pull requests on hold until its operator refactoring is done
([Discussion #495](https://github.com/thliebig/openEMS-Project/discussions/495)), and other contributors have posted
overlapping work: among it luikore's diamond-blocked Metal engine
([openEMS#228](https://github.com/thliebig/openEMS/pull/228)), whose tile schedule the fork's Metal diamond engine
follows (no code of it is used), and CPU pull requests with identical results such as
[#231](https://github.com/thliebig/openEMS/pull/231), [#244](https://github.com/thliebig/openEMS/pull/244) and
[#245](https://github.com/thliebig/openEMS/pull/245); since cg29 the fork takes the UPML part of #244, follows the
strict-order check of #245 and the lumped-RLC time slots that MrHighVoltage proposed in Discussion #492 (items 15, 14
and 18 above). On
2026-11-04 upstream master's merged GPU engine and PR #228 were built and run here on the six models (on a Mac shared
with other work, so the speeds are rough): master's GPU engine ran at 0.42 to 1.06 times the speed of cg18's CPU
engine, and PR #228's diamond path refused all six models before stepping (it has not migrated their Mur boundaries,
nor the GCPW line's conducting sheets); it ran only variants with every Mur face replaced by PEC, on which the fork's
Metal diamond engine was not run (`results/others_2026-11-04/README.md`). The two diamond engines were first compared
head to head on 2026-11-11, on the benchmark model of luikore's engine (a uniform grid with PEC walls, one dielectric
box and a point excitation), with luikore's build (55ce11b), upstream master (1d710c2) and cg31 interleaved on a
quiet Mac: at 3.0 M and 17.0 M cells cg31's Metal diamond engine ran 3981 and 3309 MC/s, luikore's Metal engine 3952
and 2829, master's `gpu` engine 1638 and 1566, master's new `cpu` engine at 8 threads 1872 and 1933, cg31's
multithreaded engine 2371 and 1659 (the better of 8 and 10 threads) and master's 1246 and 1055 (8 threads)
(`results/engines_on_luikore_model_2026-11-11.txt`; the paper's section "After publication"). The conditions of that
comparison: the model file's `endCriteria="0"` made the programs of the fork and of master use the default -60 dB criterion,
so both estimated the field energy every Nyquist period during the first minute while luikore's build did not (a cost the
record measured for the Metal engine only), and the thread counts were not tuned alike (the fork's multithreaded engine
at the better of 8 and 10 threads, master's `cpu` engine at 8 only), so the fork's 1.27 times master's `cpu` engine at 3.0
M cells (2371 against 1872 MC/s) is not a like-for-like ratio; the paired run of 2026-11-13 above, with equal thread counts
and a source on the mesh, is the comparison to read. It is one model, a regular grid without boundary work; luikore's diamond
path still refuses the six benchmark models, so on those the two engines have not been compared. The tiled sweep of patch
0040 (item 22 above) came after that run and has not been run beside master's `cpu` engine; the fused sweep was, on the
M5 Pro on 2026-11-13 (the section above). The paper's section "Positioning" lists the other contributors' work (the
paragraph on it was added on 2026-11-04 by Claude Opus 5.5, see `CHANGELOG.md`).

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
session ran the checks. On 2026-11-10 the main session (Claude Fable 5.2) also ran the four common benchmarks, whose
numbers a read-only checker recomputed, and on 2026-11-11, after four read-only reviewers had looked for the engines'
bottlenecks, each followed by a checker that tried to refute its findings (agents of a workflow of the same session,
on the same model), it wrote the twelve commits of cg31 (patches 0028 to 0039, whose trailers name Claude Fable 5.2)
with their checks and measurements, ran the three-build comparison on luikore's model (the first side-by-side, with
cg29, the author ran) and the pulse test, installed cg31 at the author's word and made that day's documentation
update with agents of the same model. The tiled sweep of that evening (patch 0040, whose trailer names Claude Fable
5.2) has its checks, the read-only review before its commit and its timing in
`results/tiled_sweep_cg32_2026-11-11.txt`. On 2026-11-12 the main session, on Claude Opus 5.5 from the night
before, ran the set of the M5 Pro Mac mini in a night queue on that machine (the tiled sweep's timing and stages A to E
of `scripts/m5pro/`, which it had written that evening on Claude Fable 5.2) and wrote its two records; agents in a
workflow of the same session (Claude Opus 5.5) wrote the paper's section on it and
brought the other documents up to date, and two read-only checkers and a fixer (agents again) checked that text
against the two records and corrected it. On 2026-11-12 and 2026-11-13 the code of patches 0041 to 0043 (the thread search, the packed dispersive line hooks and their
hardening) was written by Claude Opus 5.5, the hardening of patch 0043 by an Opus 5.5 subagent, and planned and reviewed by
Claude Fable 5.2; the check script `ade_check2.py` was
written by a Claude Sonnet subagent; the documents of 2026-11-13 (this README, `BUILD.md`, `CHANGELOG.md`, the paper and the
others) were brought up to date by Claude Sonnet subagents directed and checked by Claude Fable 5.2. The commit trailers of the
three fork commits name Claude Opus 5.5 (`Generated-by:`) above the author's `Signed-off-by:`. A separate Claude Opus 5.5 session in this folder wrote the
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
