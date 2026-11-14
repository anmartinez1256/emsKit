# patches

| folder | what it applies to | licence |
|---|---|---|
| `openems/` | 0001-0043 (`git am`, in order) on commit 7bb294f of upstream's former `gpu-engine` branch (`openems/BASE_origin_gpu-engine.txt`): 0001-0006 up to snapshot cg18 (the build installed on the author's Mac from 2026-11-04 to 2026-11-06), 0007-0016 the Metal diamond engine (snapshots cg19-cg28), 0017-0027 the CPU items of snapshot cg29, commit 78fe656 (the build installed there from 2026-11-06 to 2026-11-11), 0028 RunFDTD's energy schedule (none in a run without an end criterion), 0029-0038 the Metal diamond engine items of snapshots cg30a-cg30l, 0039 the line hooks of the cylinder extension (snapshot cg31a), commit ff2538a = cg31 (the build installed there since 2026-11-11), 0040 the opt-in tiled sweep of the multithreaded engine (snapshot cg32d, commit 0ef186b, tree d7b66f1; not installed), 0041-0043 the thread search of the multithreaded engine and the packed Debye, Lorentz and Drude line hooks (snapshots cg33a to cg33d), the fork's head 13350ca (not installed). `cumulative_vs_gpu-engine.patch` is the same change as one diff (68 files, +7685/-265); the 43 patches and the diff both give tree 211a3de (0001-0039 alone: dc4a352, the installed build) | GPL-3.0-or-later, like openEMS (`../LICENSE`) |
| `csxcad/` | 0001 (`git am`) on CSXCAD v0.7.0; `cumulative_vs_v0.7.0.patch` is the same change as one diff | LGPL-3.0-or-later, like CSXCAD (`csxcad/COPYING.LESSER`, a copy of CSXCAD's `COPYING`; the LGPLv3 adds permissions to the GPLv3 in `../LICENSE`) |

- Apply the CSXCAD patch first. The openEMS patches call `FindPropertyByCoordPriority`, which only that patch adds.
  `../BUILD.md` has the full build steps.
- Apply the openEMS patches in order: 0001-0039 for the installed build cg31 (tree
  dc4a352f915176a6e99732d921dffb667f7c7c45, that of ff2538a), all 43 for the fork's head (tree
  211a3de8300454a37bda032ecf7514db1514579b, that of 13350ca), 0001-0040 for the tiled sweep alone (tree
  d7b66f1066672597c3a37e79bac0950469a93830, that of 0ef186b), 0001-0027 for cg29 (tree 90f8c01, that of
  78fe656), or 0001-0006 for cg18 (tree f67bc0f, that of cb168f7). 0040 adds only an opt-in sweep: with its switch
  `OPENEMS_TBLOCK` unset, the engine runs the fused sweep as before. 0041-0043 change the CPU engine's defaults
  (the start of the thread search, the packed dispersive hooks), with results bit-identical to stock. Do not stop between 0001 and 0006: in the trees
  after 0003 and 0004 the multithreaded engine computes Debye materials wrongly (0005 fixes it), so do not use those
  trees, or bisect across them, on models with Debye materials. 0001-0006 were regenerated with the others on
  2026-11-05; only their subject lines changed (the numbering, `[PATCH 01/27]` then).
- The 28 patch files of that day (0001-0027 and the CSXCAD patch) were made again on 2026-11-07 from the fork's
  commits as rewritten for publication and pushed that day (the author's public identity, a `Generated-by:` trailer
  above a `Signed-off-by:` line, the same trees). In each file the first line (`From <hash> ...`, which names the
  published commit) and the trailers changed, and in 0006 also the hashes of 0001-0005 wherever its message names
  them (its list of corrections, whose heading now ends "(not reworded)", and three references to the build of
  0005), which are now the published ones; the cumulative diffs stayed the same byte for byte.
  The table in `../CHANGELOG.md` (the entry of 2026-11-07 on the fork's rewrite) maps the earlier hashes that the
  records in `../results/` made before that day give.
- All 39 openEMS patch files of that time were regenerated on 2026-11-11, when 0028-0039 were added. 0001-0027
  changed only in their subject numbering (`[PATCH nn/39]` then): their first lines name the same commits as before,
  9651fff to 78fe656. The cumulative diff was regenerated with them (before: 66 files, +6178/-256, tree 90f8c01;
  after: 68 files, +6644/-266). `git am` of the 39 patches on 7bb294f and `git apply` of that cumulative diff both
  gave tree dc4a352f915176a6e99732d921dffb667f7c7c45 (checked 2026-11-11). The CSXCAD patch did not change.
- All 40 openEMS patch files were regenerated again on 2026-11-11 (evening), when 0040 was added. 0001-0039 changed
  only in their subject numbering (`[PATCH nn/40]`): their first lines name the same commits as before, 9651fff to
  ff2538a. The cumulative diff was regenerated with them (before: 68 files, +6644/-266, tree dc4a352, which is still
  the tree after 0001-0039). `git am` of the 40 patches on 7bb294f and `git apply` of the cumulative diff both give
  tree d7b66f1066672597c3a37e79bac0950469a93830 (checked 2026-11-11). The CSXCAD patch did not change.
- All 43 openEMS patch files were regenerated again on 2026-11-13 (`git format-patch 7bb294f..13350ca`), when
  0041-0043 were added. 0001-0040 changed only in their subject numbering (`[PATCH nn/43]`): their first lines name the
  same commits as before, 9651fff to 0ef186b. 0041, 0042 and 0043 are the commits 8bcec90, c6ef5c5 and 13350ca. The
  cumulative diff was regenerated with them (before: 68 files, +7042/-265, tree d7b66f1, which is still the tree after
  0001-0040; after: 68 files, +7685/-265). `git am` of the 43 patches on 7bb294f and `git apply` of the cumulative diff
  both give tree 211a3de8300454a37bda032ecf7514db1514579b (checked 2026-11-13). The CSXCAD patch did not change.
- 0007-0016 add `--engine=metal-diamond`, which is opt-in and built only on macOS with `ENABLE_METAL`
  (`../BUILD.md`, sections 5 and 7). Besides the engine's two new files they change only friend declarations in 13
  extension headers, `ArrayENG::InitView` (`tools/arraylib/array_e.h`), the engine option in `openems.cpp` and
  `openems.h`, and one line of `FDTD/CMakeLists.txt`. 0017-0027 change the CPU side (the engines, their extensions,
  the compressed operator's index and the UPML operator setup), one topic each, every one bit-identical to stock
  v0.37.0 (`../results/cpu_items_cg29_2026-11-05.txt`).
- 0028-0039 are the commits of 2026-11-11 (`../results/metal_engine_cg31_2026-11-11.txt`, the paper's section "After
  publication"). 0028 changes `openems.cpp`: a run without an end criterion (`EndCriteria = 0`) no longer sums the
  field energy every Nyquist period; its results do not change. 0029-0038 change only the Metal diamond engine's
  `FDTD/metal/engine_metal_diamond.mm`, one step each (snapshots cg30a-cg30l); every step passed
  `../scripts/checks/diamond_check.sh` with 72 of 72 comparisons identical. 0039 changes the cylinder extension
  (`FDTD/extensions/engine_ext_cylinder.{h,cpp}`), so that a cylindrical mesh closed in alpha runs the fused sweep
  (`../scripts/cylinder_closed/cyl_closed.py`).
- 0040 is the commit of the evening of 2026-11-11 (`../results/tiled_sweep_cg32_2026-11-11.txt`): an opt-in tiled
  sweep for the multithreaded engine, `OPENEMS_TBLOCK=k` or `auto`, which runs several timesteps on one tile of
  x-lines shared by all threads (`../BUILD.md`, section 7). It changes seven files: the multithreaded engine
  (`FDTD/engine_multithread.{h,cpp}`), the y range of the update loops (`FDTD/engine_sse_compressed.{h,cpp}`), one
  new virtual function in `FDTD/extensions/engine_extension.h` (`GetMaxBlockDepth()`, default: no limit) and its
  override in the steady-state extension (`FDTD/extensions/engine_ext_steadystate.{h,cpp}`). Its results were
  identical to the fused sweep's in every test (`../scripts/tiled_sweep/check.zsh`), and with the switch unset the
  six models were identical to stock v0.37.0. It is not in the installed build.
- 0041-0043 are the commits of 2026-11-13, written on 2026-11-12 and 2026-11-13 (`../results/cpu_items_cg33_2026-11-13.txt`), none of them
  installed. 0041 changes where the multithreaded engine's thread search starts (`numThreads=0`): at every core that
  is not an efficiency core instead of at the cores of the first performance level; `OPENEMS_TUNE_START=p` restores
  the old rule (`FDTD/engine_multithread.{h,cpp}`). 0042 gives the Debye, Lorentz and Drude line hooks packed groups of
  up to four positions of one x-line, with state and coefficients in one block per group; `OPENEMS_ADE_PACKED=0` turns
  it off. 0043 puts that packed code under the GCC/clang guard with stubs for other compilers and prints one line at
  verbose 1 or above when the packing is refused. Their results were identical to stock v0.37.0 and to cg31 in every
  test (`../scripts/ade_check/ade_check2.py` and the checks of `../BUILD.md`, section 9).
- The openEMS patches apply to their base only. Upstream merged a reworked GPU engine into master (c3a956b), deleted
  the `gpu-engine` branch and restructured the engines (c0816a2); `git apply --check` of 0001 fails on master 5fecbb5
  (checked 2026-11-03). The later patches need 0001, and 0007-0043, written after that check, were not checked
  against master. `../BUILD.md` fetches the base commit by its hash. The CSXCAD patch also applies to CSXCAD master
  626b99f (checked the same way).
- The changes made in this project to the author's simulation toolkit (rfsim) are not published, since the toolkit
  itself is private; the paper's section "The modelling side" and `../CHANGELOG.md` describe them.
