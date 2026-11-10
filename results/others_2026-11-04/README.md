# Other openEMS GPU engines on the M5, next to emsKit (2026-11-04)

Measured on the author's Apple M5 (16 GB, macOS 27.0.1) with `scripts/others/run_others.sh`; every table line is
`bench.py` output (fixed step count, port probes and S-parameters compared with the reference run). Speeds are
million cell updates per second (MC/s, openEMS's own stepping time), best of two runs.

Builds:
- **emsKit**: snapshot cg18 (`v0.37.0-24-g087ce9e`, the final build of 2026-11-03), and stock v0.37.0 as reference.
- **master**: upstream openEMS 5fecbb5 (2026-11-02) with CSXCAD 626b99f, its CPU engine and `--engine=gpu` (the Metal
  backend of c3a956b, "backend: Metal (Apple M5)"), built with `update_openEMS.sh` into `~/opt/openEMS-master`.
- **luikore**: openEMS pull request #228 at 55ce11b (2026-09-28) with CSXCAD v0.7.0, `--engine=metal` (the diamond
  path, four time steps per block) and the same with `OPENEMS_METAL_FUSED_PIPELINE=0` (its legacy two-dispatch
  path), built with Xcode's Metal Toolchain 27B47 into `~/opt/openEMS-luikore`.

Each build ran in its own `bench.py` call with its own Python, its GPU configs compared with its own CPU engine
(`*_master.txt`, `*_luikore-*.txt`); `xcompare.py` compared every run with the stock run (`*_xcompare*.txt`).

## The six benchmark models as they are (Mur boundaries)

| model (cells) | stock | emsKit cg18 | master CPU 4 thr | master GPU | luikore legacy | luikore diamond |
|---|---|---|---|---|---|---|
| patch x5 (7.86 M) | 849 | 1 510 | 980 | 1 529 | 884 | refused |
| notch x3 (5.25 M) | 794 | 2 010 | 762 | 1 334 | 593 | refused |
| patch tutorial (0.10 M) | 278 | 1 856 | 247 | 782 | 172 | refused |
| notch tutorial (0.27 M) | 322 | 1 822 | 329 | 1 635 | 379 | refused |
| GCPW line (0.24 M), recheck | 297 | 1 634 | 237 | 1 343 | 223 | refused |
| SMA launch (0.87 M) | 256 | 1 019 | 388 | 1 084 | 414 | refused |

- luikore's diamond path refuses every model before stepping: "Metal: extension 'Mur ABC Extension' has not migrated
  to the diamond wavefront; refusing to start a legacy simulation" (the GCPW line: 'Conducting Sheet Extension').
  All six models use Mur (`run_log.txt`).
- GCPW: the main-pass row (`kgcpw_s1_n15000_*.txt`) gave emsKit 1 151 and stock 230 under load; the recheck after
  both passes (`kgcpw_s1_n15000_recheck.txt`) gave 1 634 at 4 threads and stock 297, as on 2026-11-03 (1 760 / 307),
  and master's GPU 1 343 (main pass 1 310). The table uses the recheck. emsKit's automatic thread count picked 9
  threads in the main pass and 4 in the recheck; on this model 6 threads give 1 122.
- The SMA launch is the toolkit's model as of commit 4a7e20e (2026-11-04 02:19: mesh floor 0.05 mm, 0.871 M cells),
  not the 1.071 M-cell model of the `*_cg18.txt` tables; its numbers do not compare with those.

## The same models with every Mur face replaced by PEC (`*-nomur.txt`)

`NOMUR=1`: `OPENEMS_BENCH_BC` with MUR -> PEC; PML and PEC faces stay (notch: PML_8 at both x ends; SMA: PML_8 at
z-max). Same meshes and cell counts; the GCPW line is left out (its conducting sheets are refused too).

| model | stock | emsKit cg18 | master GPU | luikore legacy | luikore diamond | diamond / emsKit |
|---|---|---|---|---|---|---|
| patch x5 | 1 119 | 1 565 | 1 635 | 1 472 | 3 128 | 2.00 |
| notch x3 | 726 | 2 003 | 1 661 | 1 381 | 3 734 | 1.86 |
| patch tutorial | 381 | 1 921 | 1 158 | 181 | 747 | 0.39 |
| notch tutorial | 395 | 2 053 | 2 374 | 469 | 3 011 | 1.47 |
| SMA launch | 292 | 1 207 | 1 204 | 484 | 1 266 | 1.05 |

## Results against stock

- emsKit cg18: identical to stock on every run of both passes (probes and S-parameters).
- master and luikore CPU engines: identical to stock, except master on the SMA launch (probes 1.5e-4 relative, S11
  3.4e-3 dB), where master's GPU engine shows the same difference: a change in master since v0.37.0, not the GPU.
- GPU engines: probes 1.7e-7 to 1.3e-6 relative to stock, S-parameters within 2.6e-4 dB (notch tutorial) and within
  3e-5 dB elsewhere. luikore's diamond and legacy paths give identical results to each other (same differences to
  stock, to the digit), as his documentation says.

## Conditions

The Mac was also used by other work: a KiCad `pcb render` loop from another session (about 950 % CPU in bursts),
Spotlight indexing the new build folders, and KirchhoffStudio. The first attempt (`run_log.txt` up to "resumed") was
stopped; the runs from 04:54 on waited for a 1-minute load below 4 and then for other processes below 100 % CPU
before each run (up to 10 min). The `others` column of each line is the CPU of other processes in the second before
the run; GPU use by other processes is not measured. From about 06:00 another session was developing a Metal engine
in the emsKit fork (`CHANGELOG.md`, snapshot cg19) and may have used the GPU during the PEC pass.
