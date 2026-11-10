# patches

| folder | what it applies to | licence |
|---|---|---|
| `openems/` | 0001-0027 (`git am`, in order) on commit 7bb294f of upstream's former `gpu-engine` branch (`openems/BASE_origin_gpu-engine.txt`): 0001-0006 up to snapshot cg18 (the build installed on the author's Mac from 2026-11-04 to 2026-11-06), 0007-0016 the Metal diamond engine (snapshots cg19-cg28), 0017-0027 the CPU items of snapshot cg29, the fork's head 78fe656 (the build installed there since 2026-11-06). `cumulative_vs_gpu-engine.patch` is the same change as one diff (66 files, +6178/-256); the 27 patches and the diff both give tree 90f8c01 | GPL-3.0-or-later, like openEMS (`../LICENSE`) |
| `csxcad/` | 0001 (`git am`) on CSXCAD v0.7.0; `cumulative_vs_v0.7.0.patch` is the same change as one diff | LGPL-3.0-or-later, like CSXCAD (`csxcad/COPYING.LESSER`, a copy of CSXCAD's `COPYING`; the LGPLv3 adds permissions to the GPLv3 in `../LICENSE`) |

- Apply the CSXCAD patch first. The openEMS patches call `FindPropertyByCoordPriority`, which only that patch adds.
  `../BUILD.md` has the full build steps.
- Apply the openEMS patches in order: all 27 for the fork's head (cg29), or 0001-0006 for cg18 (tree f67bc0f, that of
  cb168f7). Do not stop between 0001 and 0006: in the trees after 0003 and 0004 the multithreaded engine computes
  Debye materials wrongly (0005 fixes it), so do not use those trees, or bisect across them, on models with Debye
  materials. 0001-0006 were regenerated with the others on 2026-11-05; only their subject lines changed (the
  numbering, `[PATCH 01/27]`).
- All 28 patch files were made again on 2026-11-07 from the fork's commits as rewritten for publication and pushed
  that day (the author's public identity, a `Generated-by:` trailer above a `Signed-off-by:` line, the same trees). In
  each file the first line (`From <hash> ...`, which names the published commit) and the trailers changed, and in 0006
  also the hashes of 0001-0005 wherever its message names them (its list of corrections, whose heading now ends
  "(not reworded)", and three references to the build of 0005), which are now the published ones; the cumulative
  diffs stayed the same byte for byte.
  The table in `../CHANGELOG.md` (the entry of 2026-11-07 on the fork's rewrite) maps the earlier hashes that the
  records in `../results/` made before that day give.
- 0007-0016 add `--engine=metal-diamond`, which is opt-in and built only on macOS with `ENABLE_METAL`
  (`../BUILD.md`, sections 5 and 7). Besides the engine's two new files they change only friend declarations in 13
  extension headers, `ArrayENG::InitView` (`tools/arraylib/array_e.h`), the engine option in `openems.cpp` and
  `openems.h`, and one line of `FDTD/CMakeLists.txt`. 0017-0027 change the CPU side (the engines, their extensions,
  the compressed operator's index and the UPML operator setup), one topic each, every one bit-identical to stock
  v0.37.0 (`../results/cpu_items_cg29_2026-11-05.txt`).
- The openEMS patches apply to their base only. Upstream merged a reworked GPU engine into master (c3a956b), deleted
  the `gpu-engine` branch and restructured the engines (c0816a2); `git apply --check` of 0001 fails on master 5fecbb5
  (checked 2026-11-03). The later patches need 0001, and 0007-0027, written after that check, were not checked
  against master. `../BUILD.md` fetches the base commit by its hash. The CSXCAD patch also applies to CSXCAD master
  626b99f (checked the same way).
- The changes made in this project to the author's simulation toolkit (rfsim) are not published, since the toolkit
  itself is private; the paper's section "The modelling side" and `../CHANGELOG.md` describe them.
