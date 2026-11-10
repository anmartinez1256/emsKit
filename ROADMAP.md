# fdtdKit roadmap: from "faster openEMS" toward a usable design tool

Goal: close the gaps that keep openEMS behind HFSS/CST for PCB-scale RF work, in the order that buys the most
trust and day-to-day value per hour. Effort: S = days, M = 1-3 weeks, L = a month or more (rough guesses).

## Acceptance rule for new features
The engine work used bit identity as its test: the CPU engines against stock v0.37.0, the Metal diamond engine
(`--engine=metal-diamond`) against the multithreaded CPU engine run with `OPENEMS_FTZ=1`, because Apple's GPU flushes
subnormals to zero (against stock it differs by up to 9.4e-7 relative in the port probes and 2.3e-4 dB in S11,
`results/*_cg22.txt`). New solver features have no stock reference, so:
1. **Off by default, bit-identical when off.** `check.sh` must still pass with the feature disabled, and
   `scripts/checks/diamond_check.sh` too for a feature of the Metal engine.
2. **Validated when on**, against an analytic result, a published benchmark, or a fine-mesh reference run,
   with a stated tolerance, kept as a regression test in `bench/validation/`.

## Phase 0: publish what exists (now, during the review)
| item | effort | notes |
|---|---|---|
| arXiv submission of the report | S | needs an arXiv endorsement (the repository URL is in the paper since 2026-11-06) |
| Upstream pull requests: port the engine items of patches 0001-0027 to upstream master (the CPU items of 0001-0006 and 0017-0027, the Metal diamond engine of 0007-0016) | L | the patches apply only to the pre-merge `gpu-engine` commit 7bb294f. Master has since replaced Engine_Multithread, Engine_SSE_Compressed and Operator_SSE_Compressed with Engine_ThreadPool, Engine_sse and Coeffs_SSE_Compressed (c0816a2, 2026-11-02), and the maintainer has put speed pull requests on hold until a refactoring that separates the mesh geometry from the coefficient storage is done (Discussion #495). One topic per pull request, CSXCAD part first, trailers per AI_POLICY.md, no new dependencies. A speed claim needs upstream's `benchmark/bench.py compare` table; its cases use a sinusoidal source, which the fork has run on the fused sweep since cg29 (the steady-state line hooks). The diamond engine follows the tile schedule of luikore's pull request #228, and master has a GPU engine of its own (c3a956b): ask before porting it. Check against a stock build of master. Get in touch with biergaizi, whose tiling engine overlaps |

## Phase 1: trust (needed before anyone else relies on it)
| item | effort | why |
|---|---|---|
| Validation suite, the cases still missing: GCPW Z0 vs closed-form, patch resonance, thin-wire dipole impedance, Mie-sphere RCS (nf2ff, TFSF), lumped RLC resonator, conducting-sheet loss, coax line (the first 15 checks and their runs are under "Done" below) | M | commercial tools are trusted because of validation; this is the cheapest way to earn it |
| Cross-check one board against measurement (VNA) and one against Elmer/another solver | M | turns the speed result into a usable design gate |
| A portable `check.sh` (Linux: `LD_LIBRARY_PATH`, a stock build to compare against) and a Linux run of it | M | upstream CI already builds openEMS on Linux (Debian, Ubuntu, Fedora, AlmaLinux, Alpine), macOS and FreeBSD; what is missing is the bit-identity check against stock off macOS |
| Debye/Lorentz/Drude and cylindrical models in `check.sh` itself | S | the Debye bug showed the gap. Today they run beside it: `scripts/checks/debye_check.sh`, the Drude/Lorentz, sheet and Debye boxes of `scripts/checks/diamond_check.sh`, the dispersive slabs and the cylindrical cavity of `bench/validation/`, `scripts/cylinder_multigrid/run_cyl.py`; `check.sh` runs none of them |

## Phase 2: workflow (the gap users feel every day)
| item | effort | gap closed |
|---|---|---|
| KiCad (.kicad_pcb) to CSXCAD import: layers, stack-up, vias, ports from footprints | M | CAD import; ties into the author's rfsim toolkit |
| Automatic mesh convergence: coarse/fine pair, refine until S-params change < tolerance (generalises the mesh-floor rule) | M | HFSS-style "converged" answer |
| Mesh-floor rule for every builder, not only the SMA launch | S | already listed as open in the paper |
| Parameter sweeps and optimisation (Nelder-Mead/Bayesian) with a result cache and resume | M | CST/HFSS optimiser |
| Touchstone export, Smith/TDR/far-field plots, port de-embedding as one post-processing module | S-M | post-processing parity |
| Checkpoint/restart for long runs | S | robustness |

## Phase 2b: Mac mini / Mac Studio cluster (scale by adding memory buses)
One machine is capped by one bus; each extra Mac adds its own unified memory and bandwidth. Thunderbolt 5 RDMA
(macOS 26.2+) gives a low-latency link. Paper outlook: `paper/sec_positioning.tex`, subsection "Outlook: clusters of
Apple-silicon machines".
| item | effort | notes |
|---|---|---|
| Sweep farm: dispatch parameter-study jobs to N Macs over SSH, collect results | S-M | near-linear scaling, no engine change; biggest win for design work |
| Write a domain-decomposed engine on top of the fork's fused multithreaded engine or its Metal diamond engine (one slab per rank, fused sweep or diamond blocks per rank, distributed excitation, probes, dumps and extensions) | L (new engine) | openEMS has no distributed engine to extend: upstream removed its MPI engine before v0.37.0 (commit 5261463, 2026-09-16); it had not compiled for years. With the diamond engine's K time steps per block, how a block meets the halo exchange is open. One fork has tried an x-slab split of one model across two GPUs with host-staged halo exchange (td-krzysiek, described in Discussion #495); the maintainer replied there that multi-device engines are not a priority for him |
| Halo exchange over Thunderbolt RDMA (MPI over TB bridge first, RDMA second), overlapped with the interior update | M-L | ~8 MB per interface per half step on a 1000^3 model |
| Bit-identity check: distributed run vs single-machine run | S | decomposition shouldn't change any cell's arithmetic |
| Measure on Max/Ultra chips: the CPU engine against the Metal diamond engine, and their share of the bus | S | everything so far ran on the base M5 (10 GPU cores). There the fused but unblocked GPU sweep ran at 0.85x / 1.07x the CPU's quiet-Mac best of cg18 (notch x3 / patch x5), and the diamond engine above the 2470-2590 MC/s bound of a fused sweep (cg28: notch x3 3226, patch x5 2917 MC/s); see "Done" |
| Benchmark: 2-4 machines, scaling curve and cost per cell vs a GPU workstation | M | the main number for a follow-up paper |

## Phase 3: solver capability (the hard gaps; not bit-identical by nature)
| item | effort | gap closed |
|---|---|---|
| Conformal PEC (Dey-Mittra) for curved/slanted conductors | L | staircasing error on curves, a main HFSS advantage |
| Cartesian sub-gridding (local fine mesh around vias/gaps) | L | cell count; openEMS only has cylindrical multigrid |
| Resonance extraction by harmonic inversion (Harminv-style) for high-Q structures | M | eigenmode-like answers without running to full decay |
| Surface-impedance boundary for good conductors (skin effect without meshing it) | M | loss accuracy at high frequency |

## Phase 4: the Metal engine's open items (paper section "A diamond-blocked Metal engine")
The second review's CPU items, listed here before, are measured and done (cg29, under "Done").
| item | effort | notes |
|---|---|---|
| Larger chips and other tilings | S-M | the tuner picks one of four tilings, K=3 or 4 (cg28). In the cg23 sweep (`bench.py`, the faster of two runs per setting, not paired; others' CPU 0.4-2 cores, GPU up to 15 %) K=6, K=8 and the tiles of 16 lines (16:8, 8:16, 16:16) beat no model's best setting, but the SMA launch and the patch tutorial ran best with a K=2 tiling (0.3 % and 1.2 % above the best of the four), and the SMA launch's best in the paired runs on cg24 (K=2, 6:4 tiles, x1.132 against the default; K=3 8,6 x1.065) is not among the four and was not timed after cg24 (`results/diamond_engine_cg28_tuner_2026-11-04.txt`). The M5 Pro, Max and Ultra are not measured (Phase 2b) |
| A head-to-head with luikore's engine | S | on this M5 its diamond path refused all six models (Mur faces; on the GCPW line also the conducting sheets) and ran only the variants with every Mur face replaced by PEC, on which the fork's diamond engine was not run (cg18's CPU engine was: `results/others_2026-11-04/`). luikore reports 1.3-4.2x its own unfused path on an M4 Pro and an M5 Max (uniform grid, no conducting sheets). Run both engines on the same inputs |
| GPU memory footprint | S | not measured: the shared field buffers, the four tilings' buffers while the tuner runs, the extension buffers. Only the coefficient tables are known (SMA launch: 12.4 MB packed, 1.4 + 2.1 MB split). The CPU figures of cg18 are in `results/memory_per_cell_2026-11-03.txt` |
| TFSF, the steady-state detection, the cylinder and multigrid extensions and subclasses of the dispersive extensions on the GPU | M | today TFSF, the steady-state detection and such subclasses put a model on the single-threaded CPU loops, and with `--engine=metal-diamond` a cylindrical mesh (with its multigrid) runs the cylindrical CPU engine (`BUILD.md`, section 7); every case of upstream's benchmark uses the steady-state detection |
| fp16 field storage with fp32 arithmetic | M | not started: late-run currents of 1e-6 A lie below the half-precision normal range, which ends at 6e-5 (project log), so the fields need scaling, and it cannot be bit-identical, so the validation suite would be its test |

## Phase 5: front end
| item | effort | notes |
|---|---|---|
| Command line, version 2 (`Docs/fdtdKit/PLAN.md`, sections 14 and 18): `install` and `rollback` with a typed confirmation and the UUID gate, the `accept` bundle (the full check: `check.sh` in all its configurations, the Debye check, the validation suite with two engines, the cylinder multigrid check, `diamond-check` and the six models on the Metal engine against the multithreaded engine with `OPENEMS_FTZ=1`, as run for cg29 in section 3 of `results/cpu_items_cg29_2026-11-05.txt`), `snapshot`, the cylinder multigrid check as a command of its own, multi-Mac runs | S-M | version 0.1.0 of `emskit fdtd` is under "Done"; it installs nothing |
| Native macOS app or web dashboard: model view (CSXCAD), live run monitor, results plots | L | only after phases 1-2; a GUI on an unvalidated tool hides problems |

## Done since the first version of this file (2026-11-03)
| item | snapshot | result |
|---|---|---|
| Publication of this repository (one commit, without its working history) | 2026-11-10 | pushed to github.com/anmartinez1256/emsKit on the author's word, after the two fork branches (public since 2026-11-07), the full check of a fresh build of the published patches (that day), the licence decision of 2026-11-08 (the Swift package stays under GPL-3.0-or-later; `Docs/fdtdKit/PLAN.md`, section 15) and the reviews of the command line (`CHANGELOG.md`, 2026-11-09 and 2026-11-10). `CITATION.cff` and `.zenodo.json` describe the repository for citation and for a Zenodo archive of its releases |
| Metal diamond engine, `--engine=metal-diamond` (Apple only, opt-in; patches 0007-0016) | cg19-cg28 | tile schedule after luikore's pull request #228 (no code of it is used). On the GPU: excitation and Mur (cg19), lumped RLC (cg20), UPML (cg21), Drude/Lorentz materials and conducting sheets (cg22, from then on all six models), Debye (cg23); a run-time tuner picks one of four tilings (cg28). Bit-identical to the multithreaded engine with `OPENEMS_FTZ=1` on the six models and in `scripts/checks/diamond_check.sh` (72 of 72 on cg28 and cg29); validation suite 15 of 15 (cg23, cg27). cg28, medians of 5 rounds paired against cg27 on a quiet Mac (others' CPU 0.5-1.3 cores, GPU 2-4 %): SMA launch (0.871 M cells) 1828, GCPW line 2113, notch x3 3226, patch tutorial 1764, notch tutorial 1902, patch x5 2917 MC/s (`results/diamond_engine_cg28_tuner_2026-11-04.txt`). The model has to fill the GPU: on a 61^3 Mur box the CPU at 4 threads was faster (2281 vs 2099 MC/s, cg19, single runs at a load average of 2-7). On cg29, beside stock and the CPU engine in one paired interleaved run of 4 rounds per model (others' CPU a median of 0.5-0.8 cores; the SMA launch on its 1.071 M-cell mesh): 1729-3193 MC/s, 2.87-7.40x stock at its best thread count; against the CPU engine at its best (8 threads on all six) 1.47x on patch x5, 1.46x on notch x3, 1.17x on the GCPW line, 1.00x on the SMA launch, 0.97x on the notch tutorial and 0.93x on the patch tutorial (`results/speed_cg29_2026-11-05.txt`). End to end through the toolkit with its defaults since 2026-11-04 (the SMA launch on 0.871 M cells), against cg29's CPU engine with the automatic count: GCPW line 5.6 to 4.1 s (1.37x), SMA launch 28.9 to 23.6 s (1.22x), the full runs 1.17x each, the same stop steps; medians of 2-3 interleaved rounds (the ratios: medians of the per-round ratios) on a loaded Mac (others 1.0-1.6 cores; the rounds in which both runs were clean give 1.08-1.27x) (`results/rfsim_e2e_cg29_2026-11-05.txt`) |
| Fused, unblocked GPU sweep (the diamond engine at K=1) | cg27 | notch x3 1716-1733 and patch x5 1799-1844 MC/s over the tile sizes (patch x5 1530 with 32:16 tiles; medians of 4 paired rounds, others' CPU 2.5-4 cores, GPU 3-5 %): 0.57-0.65x of K=4 (8:8) with 8:8 and 16:8 tiles (notch x3 also with 32:16), 0.54x for patch x5 with 32:16; at the best tile size 1.25-1.30x the base's unfused GPU engine and 67-75 % of the 2470-2590 MC/s bound of a fused sweep (85-90 GB/s at 49 B/cell). Temporal blocking, not the fusion alone, carries the GPU's gain (`results/fused_sweep_k1_2026-11-04.txt`) |
| Master's merged GPU engine and luikore's engine run on this M5 | 2026-11-04 | master 5fecbb5 (`--engine=gpu`, the Metal backend of c3a956b): 0.42-1.06x cg18 on the six models, level on patch x5 (1529 vs 1510) and the SMA launch (1084 vs 1019). luikore's pull request #228 (55ce11b): its diamond path refuses all six models (Mur; on the GCPW line also the sheets); on the variants of five models with every Mur face replaced by PEC, speed-only cases, it runs at 0.39-2.00x cg18; its legacy path is slower than cg18 on every model. Their GPU engines differ from stock by 1.7e-7 to 1.3e-6 relative in the probes (float rounding). Best of two runs each on a loaded Mac, rough (`results/others_2026-11-04/README.md`) |
| Steady-state detection and Debye materials on the fused sweep (patches 0021, 0022, 0026) | cg29 | line hooks for both, and the steady-state detection runs on the neighbour flags. Upstream's benchmark cases (`benchmark/cases.py` of master), paired A/B against the unfused plan: pml x1.36 at 4 threads, inhomogeneous x1.29 / x1.34 at 4 / 8, ideal x0.98 / x0.80 (recovered by the flags), dispersive x6.5 / x10.0 (`results/cpu_items_cg29_2026-11-05.txt`, section 1); cg29 against cg18 on the same cases, paired in quiet rounds (others 0.4-1.4 cores): x1.11-x1.36 on the ideal box, x1.74-x2.18 on pml and inhomogeneous, x4.25-x7.40 on dispersive (section 5) |
| The second review's engine items (paper Table "second review") and the other forks' ideas (in patches 0017-0027) | cg29 | kept: UPML y-rows (item 1; SMA launch x1.18 at 1 thread, x1.13 at 4 and 8), merged ADE for conducting sheets (item 2; GCPW line x1.041 / x1.031 at 4 / 8 threads; its uniqueness guard follows the strict-order check of upstream pull request #245, Roel Budé), neighbour flags (item 5; x1.015-x1.055 at 4 threads, x1.07-x1.29 at 8), geometry coefficient tables (item 9 in another form; SMA launch x1.067 at 8), no flag spin above the performance-core count (item 4 in part), the operator index per z-vector (patch x5 x1.12 / x1.10 at 4 / 8), the UPML coefficient setup of upstream pull request #244 (Noriaki Takashima) on the setup threads, lumped RLC slots by timestep (MrHighVoltage, Discussion #492). Dropped with their numbers: items 3, 4 (per-thread QoS split, longer spin, faster slab balancing), 6, 7 and 9's first form (split tables); item 10 not built (under 0.1 %); item 8 skipped (the diamond engine replaces the base's GPU engine). cg29 against cg18, median ratios of paired rounds (5; 4 for notch x3 at the automatic count and the SMA launch on 1.071 M cells, measured last), others 0.3-0.6 cores: x1.03-x1.23 at 4 threads, x1.13-x1.44 at 8, x1.13-x1.42 with the automatic count over the six models (the SMA launch on its 0.871 M-cell mesh); on the 1.071 M-cell mesh the SMA launch x1.37 at 8 threads and x1.38 with the automatic count (others 0.6-0.7 cores) (`results/cpu_items_cg29_2026-11-05.txt`, sections 1, 2 and 4) |
| Validation suite, first 15 checks (`bench/validation/`) | 2026-11-03 to 2026-11-05 | dispersive slabs (Debye, Drude, Lorentz; each also against the basic engine of the same build), rectangular and cylindrical (multigrid) cavities, WR-90, microstrip. 15 of 15 on stock (macOS), on cg17, cg18 and cg29 (multithreaded and fastest) and on the Metal diamond engine (cg23, cg27); 12 of 12 on stock in a Linux x86_64 virtual machine (an earlier version of the suite, before the three basic-engine checks). Negative controls, both failing the Debye check: a stock build with the two Debye hooks disabled (2 of 3; that build is not published) and patches 0001-0004 at 2 threads (4 of 6) (`results/validation_*`) |
| Command line `emskit fdtd` 0.1.0 (`Package.swift`, `Sources/`, `Tests/`, `Docs/fdtdKit/PLAN.md`) | 2026-11-05 to 2026-11-06, fixes of a code review 2026-11-09 and of a second, a third and a fourth review 2026-11-10 (on cg29) | ten commands (`info`, `load`, `bench`, `ab`, `check`, `validate`, `debye-check`, `diamond-check`, `e2e`, `run`) that run the repository's tools unchanged (`bench/bench.py`, `bench/abtest.py`, `bench/check.sh`, `bench/usage.py`, the validation suite, `scripts/checks/`, `scripts/e2e/run_one.py`) or any openEMS script (`run`), and print one JSON document per call; every speed and run time carries the other processes' CPU and GPU use; it installs nothing, and refuses every output, table, backup and run folder inside or over the installed prefix or the snapshot folder (`protected_path`, exit 2; what a `run` script writes by itself is not checked). 244 unit tests in 27 suites pass (258 tests in 28 suites with the 14 smoke runs, which passed last on 2026-11-10, before that day's later changes, which closed the reviews' open items and the findings of a third and a fourth review and of an attack on the guards); acceptance on cg29, 2026-11-10, before those changes too: `check cg29 --lite` all identical to stock v0.37.0 on the six models, `diamond-check cg29` 72 of 72, `e2e gcpw --lib cg29` finished (`Docs/fdtdKit/PLAN.md`, section 16) |
| The two fork branches published (patches 0001-0027 and the CSXCAD patch as commits) | 2026-11-07 | rewritten with the author's public identity and the `Generated-by:` / `Signed-off-by:` trailers of upstream's `AI_POLICY.md` (same trees, 90f8c01 and 902b9d6), then pushed: github.com/anmartinez1256/openEMS/tree/speed-m5-gpu (head 78fe656) and github.com/anmartinez1256/CSXCAD/tree/speed-m5 (bc854b7); `CHANGELOG.md`, 2026-11-07 |
| A fresh build of the published patches (`BUILD.md` sections 1, 4 and 5) and its full check | pub29, 2026-11-07 | `check.sh` with the two boards, every run identical to stock on the six models; the Debye check; `diamond_check.sh` 72 of 72; the six models on `metal-diamond`; the validation suite 15 of 15 at 4 threads and with the fastest engine; the cylindrical multigrid equal to stock (`results/fresh_build_pub29_2026-11-07.txt`, a loaded Mac, so only the verdicts count) |

## Not planned (from measurements in the paper)
- An unfused GPU engine on unified-memory Macs. Upstream's Metal engine as it was on the pre-merge `gpu-engine` branch
  (7bb294f) is slower than the CPU engine of cg13/cg14 on all six benchmark models, for example GCPW 1337 vs 1608 to
  1745 MC/s (the four 4-thread runs of cg13 and cg14), SMA launch 1135 vs 1385 (on its 1.071 M-cell mesh), patch
  tutorial 1055 vs 1912 (`results/kgcpw_s1_n15000_cg13.txt` and `results/*_cg14.txt`; the base's engine:
  `results/kgcpw_s1_n30000_cg12.txt`, `ksma_s1_n20000_kirch.txt`, `patch_s1_n10500_cg2.txt`). On a 201^3 box it was
  ahead of the CPU engine of the time (1638 vs 1562 MC/s at 8 threads, snapshot cg9; project log); on the 201^3 Mur
  box of 2026-11-04 it ran 1446 MC/s against 1579 for the CPU code of cg18 at 8 threads and 2775 for the diamond
  engine (loaded Mac, `results/diamond_engine_cg19_2026-11-04.txt`). The reworked engine that master merged (c3a956b)
  ran at 0.42-1.06x cg18 (under "Done"); on the variant of the notch tutorial with PEC in place of Mur (0.270 M cells)
  it reached 2374 MC/s against 2053 for cg18 at 4 threads, the faster of two runs (1.82 s; the other ran 1452 MC/s;
  others' CPU 43 % in the second before it), above the ~2000 MC/s DRAM bound of an unfused 74 B/cell sweep; whether
  its kernels fuse or the small model stays in the GPU's caches was not examined
  (`results/others_2026-11-04/notch_s1_n16000_master-nomur.txt`). A fused but unblocked GPU sweep (K=1, under "Done")
  came to about the CPU's level (0.85x / 1.07x its quiet-Mac best of cg18 on notch x3 / patch x5): temporal blocking
  is what carries the GPU's gain.
- A one-dispatch fused GPU kernel: tiles that compute their own edges overwrite values their neighbours still read,
  so it needs a second copy of both fields, and every extension would have to follow; with K=4 already above the bound
  of a fused sweep it would not make a model faster (`results/fused_sweep_k1_2026-11-04.txt`).
- Two simulations side by side (project log), and temporal blocking on the CPU: two to four time steps per sweep of
  the fork's loops gained at most 6 % even as a standalone upper bound without halos or extension hooks, against
  +10-14 % for two steps in the 2026-10-28 kernel (`scripts/kernel/kb_tb.cpp`: the stock arithmetic with its
  invariants hoisted and the 12 coefficient tables, also a fused sweep on one independent sub-grid per thread); why
  the fork's loops gain less was not examined (`results/cpu_items_cg29_2026-11-05.txt`, section 2; project log). On
  the GPU the blocking pays (the diamond engine, under "Done"). fp16 field storage is in Phase 4.
