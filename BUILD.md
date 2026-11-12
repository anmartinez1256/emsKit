# Building and installing fdtdKit's openEMS

Tested on macOS 27.0.1 (Apple M5, 16 GB) with Apple clang 21, CMake 4.4, Homebrew's boost 1.92, cgal 6.2, hdf5 2.2 and
vtk 9.7, and Python 3.14.6. On 2026-11-03 the commands of sections 1 and 4 were run on a fresh clone with patches 0001
to 0005 (they gave the trees of the fork's commits), both routes of section 5 and the Python step of section 6 on
those trees into empty prefixes, and the stock build of section 3 (second route) on another fresh clone; sections 2
and 9 were not run in that test. After patch 0006 was added, `git am` of 0001 to 0006 onto the base was repeated: it
gives tree f67bc0f, the tree of cb168f7 (snapshot cg18). On 2026-11-05 `git am` of the 27 patches then in
`patches/openems/` (0001 to 0027) and `git apply` of the regenerated cumulative diff both gave tree 90f8c01, the tree
of the fork's head of that day (78fe656, snapshot cg29). The build routes were not repeated with 0006 or the later
patches until 2026-11-07: that day sections 1, 4 and 5 (the script route, with `--python`) ran on a fresh clone with
the 27 patches into an empty prefix, and that build passed the checks of section 9
(`results/fresh_build_pub29_2026-11-07.txt`). On 2026-11-11, with twelve patches more (0028 to 0039), `git am` of the
39 patches then in `patches/openems/` and `git apply` of the regenerated cumulative diff both gave tree dc4a352, the
tree of ff2538a (snapshot cg31). That evening patch 0040 was added: `git am` of the 40 patches now in
`patches/openems/` and `git apply` of the cumulative diff both give tree d7b66f1, the tree of the fork's head
(0ef186b). The build from a fresh clone was not repeated with the patches after 0027.
Snapshot cg18 (0001 to 0006) reports `v0.37.0-24-g087ce9e`, passed the check of section 9 on 2026-11-03
(`results/*_cg18.txt`) and was the build installed on the author's Mac from 2026-11-04 to 2026-11-06; snapshot cg29
passed that check on 2026-11-05 (`results/*_cg29.txt`) and was the installed build from 2026-11-06 to 2026-11-11. It
was put in place without the routes of section 5, after a backup of the prefix: only two files changed, the snapshot's
`libopenEMS` (with the prefix's install name and rpath, re-signed) and cg29's `include/openEMS/openems.h`; `libCSXCAD`
and `libnf2ff` there already had cg29's bytes. The Python modules stayed upstream's v0.37.0 binding (section 6: this
affects SAR, not FDTD runs or nf2ff). Snapshot cg31 (0001 to 0039) reports `v0.37.0-57-gff2538a` and is the installed
build since 2026-11-11 (`results/metal_engine_cg31_2026-11-11.txt`). Section 9 lists the checks that passed from the
two installs. Patch 0040 (the fork's head 0ef186b, snapshot cg32d) is not installed: it adds only the opt-in tiled
sweep of section 7, and with its switch unset the engine runs the fused sweep as before
(`results/tiled_sweep_cg32_2026-11-11.txt`). Other platforms are
untested. The fork is meant to build wherever openEMS v0.37.0 builds (for GCC see section 8); its platform-dependent
parts are guarded: thread QoS (`#ifdef __APPLE__`), the starting point of the automatic thread count (the P-core count
from `sysctl` on macOS, half the available hardware threads elsewhere), the default spin of the neighbour-flag waits
(none above the P-core count, which only macOS reports here), the separable nf2ff path (`NF2FF_HAVE_CBLAS`, wired only
to Apple's Accelerate; other builds keep the original loop), the opt-in flush-to-zero (`OPENEMS_FTZ`, any
`__aarch64__`), the Metal diamond engine (`OPENEMS_WITH_METAL`, macOS only; section 7) and the cache size that
`OPENEMS_TBLOCK=auto` reads (`hw.perflevel0.l2cachesize` on macOS; elsewhere the level-3 or level-2 cache from
`sysconf` where the C library defines it; without a figure `auto` keeps the fused sweep).

What the fork is built on:

- **openEMS:** commit 7bb294f of upstream's `gpu-engine` branch (2026-10-12, `patches/openems/BASE_origin_gpu-engine.txt`),
  that is v0.37.0 plus 18 upstream commits, plus the 40 fdtdKit patches: 0001 to 0006 (snapshot cg18 after 0006, the
  build installed on the author's Mac from 2026-11-04 to 2026-11-06), 0007 to 0016 (the Metal diamond engine,
  snapshots cg19 to cg28), 0017 to 0027 (the CPU items of snapshot cg29: commit 78fe656, `git describe --tags`
  v0.37.0-45-g78fe656, the build installed there from 2026-11-06 to 2026-11-11), 0028 to 0039 (2026-11-11: 0028
  drops the energy estimates of a run without an end criterion, 0029 to 0038 speed up the Metal diamond engine,
  snapshots cg30a to cg30l, and 0039 gives the cylinder extension line hooks; snapshot cg31: commit ff2538a,
  `git describe --tags` v0.37.0-57-gff2538a, the build installed there since 2026-11-11; sections 7 to 9, and the
  paper's section "After publication") and 0040 (2026-11-11, evening: the opt-in tiled sweep of the multithreaded
  engine, sections 7 and 9; snapshot cg32d: the fork's head 0ef186b, `git describe --tags` v0.37.0-58-g0ef186b, not
  installed). The 39 patches up to 0039 make the installed build, all 40 the fork's head. Upstream has since
  merged a reworked GPU engine into master (c3a956b) and deleted the branch, so section 4 fetches the base commit by its
  hash. The patches apply to this base only; master has restructured the engines since (c0816a2).
- **CSXCAD:** v0.7.0 plus one patch. The openEMS patches call the `FindPropertyByCoordPriority` it adds, so they do not
  compile against a stock or packaged CSXCAD 0.7.0.
- **Commit hashes:** the fork's commits were rewritten for publication on 2026-11-07, with the author's public
  identity, the `Generated-by:` and `Signed-off-by:` trailers that upstream's `AI_POLICY.md` asks for, and the same
  trees, and the two branches were pushed that day (section 1). This file, `patches/README.md` and the record of the
  fresh build of 2026-11-07 give the published hashes (the openEMS head of that day, 78fe656, and the CSXCAD commit
  bc854b7); the records in `results/` made before 2026-11-07 and the entries of `CHANGELOG.md` dated before then give
  the earlier ones (the head was 1620939), and the table in the `CHANGELOG.md` entry of 2026-11-07 on the fork's
  rewrite maps them. The thirteen commits of 2026-11-11 (72a6492 to ff2538a on 78fe656, and 0ef186b on ff2538a, the
  head now) were made with that identity and those trailers and were not rewritten. The version strings in the
  records (`v0.37.0-NN-g` and a hash, section 5) are not changed either: they name the commit at which a build
  folder was configured, for the fork's commits up to cg29 one from before the rewrite (074a687, in the string of
  cg29, is on no branch), for the fresh build of 2026-11-07 the commit that its own `git am` made (1d091c7), for cg31
  its own commit (ff2538a), and for cg32d that commit too, not its own (section 5).
- **The dependencies of that time:** CSXCAD v0.7.0 and this openEMS still need CGAL and VTK, which upstream master dropped
  on 2026-10-21. Use the superproject at tag v0.37.0, whose scripts match, not today's upstream install instructions.

## 1. Sources

```sh
EMSKIT=/path/to/emsKit                  # this repository
PREFIX=$HOME/opt/openEMS                # install prefix (upstream's default; read section 3 before reusing one)
git clone --recursive --branch v0.37.0 https://github.com/thliebig/openEMS-Project.git
cd openEMS-Project
```
The commands below run in `openEMS-Project`. Its submodules are now at stock openEMS v0.37.0 and CSXCAD v0.7.0.

The fork is also kept as two git branches with the same changes as commits:
https://github.com/anmartinez1256/openEMS/tree/speed-m5-gpu (the 40 commits of `patches/openems/` on 7bb294f) and
https://github.com/anmartinez1256/CSXCAD/tree/speed-m5 (the one commit of `patches/csxcad/` on v0.7.0). The steps
below use the patch files of this repository.

## 2. Dependencies

```sh
./scripts/install_deps.sh --install --disable-gui --python
```
On macOS this installs `cmake boost hdf5 cgal vtk` and, for `--python`, Homebrew's Python packages; on Linux the
distribution's packages (`--check` lists what is missing without installing). TinyXML is no longer in Homebrew:
`update_openEMS.sh` builds it from source on macOS (network access to SourceForge and GitHub needed). fparser comes from
the superproject's `fparser` submodule.

## 3. Save a stock reference first

The install overwrites what is in `$PREFIX`, and the checks of section 9 compare against a stock build.

- If `$PREFIX` holds an upstream v0.37.0 install, keep a copy of the whole prefix (section 10 restores it) and save its
  three libraries as the snapshot `stock` (`-L` copies the file behind each symlink):
  ```sh
  cp -a "$PREFIX" "$PREFIX.stock-v0.37.0"
  mkdir -p ~/opt/openEMS-dev/snap/stock
  for l in libopenEMS libCSXCAD libnf2ff; do cp -L "$PREFIX/lib/$l.0.dylib" ~/opt/openEMS-dev/snap/stock/; done
  ```
- Otherwise build stock now, from this clone before the patches are applied, into a prefix of its own (with its own
  Python modules in `$HOME/opt/openEMS-stock/venv`), and save its libraries the same way:
  ```sh
  ./update_openEMS.sh "$HOME/opt/openEMS-stock" --disable-GUI --python --python-venv-mode venv
  mkdir -p ~/opt/openEMS-dev/snap/stock
  for l in libopenEMS libCSXCAD libnf2ff; do cp -L "$HOME/opt/openEMS-stock/lib/$l.0.dylib" ~/opt/openEMS-dev/snap/stock/; done
  ```
  Keep `--python` with macOS's `/bin/bash` 3.2: without it the v0.37.0 script stops at once with
  `PYTHON_ARGS[*]: unbound variable`. `--python-venv-mode venv` keeps an active virtual environment out of it.

Installing the fork into a prefix of its own (for example `PREFIX=$HOME/opt/fdtdKit`) leaves an existing install alone.
`~/opt/openEMS-dev/snap/` is where `bench/bench.py` looks for a snapshot given by name (`OPENEMS_BENCH_SNAPS` changes
the folder; a snapshot given as a path with a `/` in it is used as it is).

## 4. Apply the patches

```sh
git -C CSXCAD checkout -b speed-m5 v0.7.0
git -C CSXCAD am "$EMSKIT"/patches/csxcad/0001-*.patch
BASE=$(cat "$EMSKIT"/patches/openems/BASE_origin_gpu-engine.txt)
git -C openEMS fetch origin "$BASE" && git -C openEMS checkout -b speed-m5-gpu "$BASE"
git -C openEMS am "$EMSKIT"/patches/openems/0*.patch
```
No upstream branch holds the base any more; GitHub serves it by its hash. If that fetch fails, the fork's branch
`speed-m5-gpu` has the base: it is the parent of patch 0001, the first of the 40 commits that the branch adds to it.
Fetch the branch and go on as above (if the `git am` line ran already, run `git -C openEMS am --abort` first):
```sh
git -C openEMS fetch https://github.com/anmartinez1256/openEMS.git speed-m5-gpu
git -C openEMS checkout -b speed-m5-gpu "$BASE"
git -C openEMS am "$EMSKIT"/patches/openems/0*.patch
```
`git am` needs a git identity (`git config user.name` and `user.email`). With the 40 openEMS patches
`git -C openEMS rev-parse 'HEAD^{tree}'` prints d7b66f1066672597c3a37e79bac0950469a93830, the tree of the fork's head
(0ef186b, snapshot cg32d). How many patches to apply: all 40 for the fork's head, or 0001 to 0039 for the build
installed on the author's Mac since 2026-11-11. The two differ only by patch 0040, the opt-in tiled sweep of the
multithreaded engine (section 7); with its switch unset the engine runs the fused sweep as before. The pattern
`00[0-3]?-*.patch` in place of `0*.patch` stops after 0039 at snapshot cg31, the installed build (tree
dc4a352f915176a6e99732d921dffb667f7c7c45, that of ff2538a). The two patterns
`00[01]?-*.patch` and `002[0-7]-*.patch`, in this order in place of `0*.patch`, stop after 0027 at snapshot cg29, the
build installed there from 2026-11-06 to 2026-11-11 (tree 90f8c01f2724cee04437d1da064a37cadb36132e, that of
78fe656), and `000[1-6]-*.patch` stops at snapshot cg18, the build installed there from 2026-11-04 to 2026-11-06 (tree
f67bc0f1bcf8482cc00f6c8bf027c443836ba864, that of cb168f7). The commit hashes differ from the
fork's, because `git am` makes new commits. The `cumulative_vs_*.patch` files hold the same changes as one diff each,
for `git apply` or reading (applied to the base, the openEMS one gives the same tree as the 40 patches).
The changes made in this project to the author's simulation toolkit (rfsim) are not published, since the toolkit itself
is private; the paper's section "The modelling side" and `CHANGELOG.md` describe them.

## 5. Build and install

Upstream's script builds TinyXML (on macOS), fparser and the checked-out, now patched, CSXCAD and openEMS into one
prefix, and with `--python` the two Python modules (section 6). It runs no git command, so it builds the trees as they
are:
```sh
rm -rf CSXCAD/python/build openEMS/python/build     # a stale Python build would be reused, see section 6
./update_openEMS.sh "$PREFIX" --disable-GUI --python
```
Without Homebrew's Python packages (section 2) the script's dependency check names them as missing and says that it
did not pass; the build goes on, and with `--python` the two modules go into the active virtual environment or, with
none active, into `$PREFIX/venv` (section 6), where pip installs the packages they need. So it went on 2026-11-07
(`results/fresh_build_pub29_2026-11-07.txt`). The validation suite of section 9 needs scipy in that environment as
well.
The same steps by hand (after a change to the sources only the last two lines are needed):
```sh
mkdir -p downloads build-tinyxml "$PREFIX"
./scripts/build_tinyxml.sh --build-dir "$PWD/build-tinyxml" --install-dir "$PREFIX"
cmake -S fparser -B build-fparser -DCMAKE_INSTALL_PREFIX="$PREFIX" && cmake --build build-fparser -j8 && cmake --install build-fparser
cmake -S CSXCAD -B build-csxcad -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" -DFPARSER_ROOT_DIR="$PREFIX" -DCMAKE_BUILD_TYPE=Release && cmake --build build-csxcad -j8 && cmake --install build-csxcad
cmake -S openEMS -B build-openems -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" -DFPARSER_ROOT_DIR="$PREFIX" -DCSXCAD_ROOT_DIR="$PREFIX" -DCMAKE_BUILD_TYPE=Release && cmake --build build-openems -j8 && cmake --install build-openems
```
`FPARSER_ROOT_DIR` and `CSXCAD_ROOT_DIR` are not optional: without them openEMS finds `fparser.hh` only by accident,
through TinyXML's include directory. On macOS with CMake 3.16 or newer `ENABLE_METAL` is on by default: it builds the
Metal backend of the base's GPU engine and the fork's Metal diamond engine (`--engine=metal-diamond`, section 7),
defines `OPENEMS_WITH_METAL` and links the Metal and Foundation frameworks. `-DENABLE_METAL=OFF` builds neither, and
other systems never have them.
The library reports `git describe --tags --always` of the openEMS tree as its version (`v0.37.0-58-g...` with the 40
patches, `v0.37.0-57-g...` with 0001 to 0039, `v0.37.0-45-g...` with 0001 to 0027, `v0.37.0-24-g...` with 0001 to
0006, the hash of your own `git am` commit; a clone without tags gives the bare
hash), taken when cmake configures: configure after applying the patches, and configure again after changing the tree.
The author's development build directories were not configured again at every commit, so the later snapshots'
libraries report an older string, and the `results/` tables print it: cg19 v0.37.0-24-g087ce9e, cg20
v0.37.0-25-g315acee, cg21 to cg28 (and the preliminary `*_cg29pre.txt` build) v0.37.0-26-gcd80d8c, cg29
v0.37.0-44-g074a687 (an earlier form of patch 0026; the code is that of 78fe656; the installed library reported it
too from 2026-11-06 to 2026-11-11). cg31, the installed build since 2026-11-11, reports its own commit,
v0.37.0-57-gff2538a. Snapshot cg32d (patch 0040, the fork's head 0ef186b) was built in the folder configured for
cg31, so it reports cg31's string too; a build configured at the fork's head reports v0.37.0-58-g0ef186b. The two
libraries differ in their bytes and in their knob names (cg32d has the three `OPENEMS_TBLOCK` names of section 7).
The libraries now in the author's cg19 and cg20 snapshot folders were replaced after those tables
were made and report their own commits instead, v0.37.0-25-g315acee and v0.37.0-26-gcd80d8c
(`Docs/fdtdKit/PLAN.md`, F7), which `emskit fdtd info` prints. The file name of a table, not that string, names its
snapshot.

## 6. Python modules and the ABI

The libraries are not ABI-compatible with v0.37.0 builds. The base's GPU-engine commit (bf30fa4) added a member to
ArrayLib's `ArrayBase`, which changes the layout of every class that holds a field array (`SAR_Calculation`, whose
setters are inline, among them) without a new SOVERSION; and the fork's staggered allocator
(`tools/arraylib/impl/allocator.h`) keeps the base pointer in the word before every block of 256 KiB or more, so arrays
allocated by this library must be freed by it. After every install over another build, in either direction, rebuild
both Python modules from the same source trees, from clean build directories (setuptools does not notice changed headers
in `$PREFIX/include` and would keep the old extension):
```sh
rm -rf CSXCAD/python/build openEMS/python/build
./scripts/build_python.sh --cpp-install-dir "$PREFIX"
```
`build_python.sh` installs into the active virtual environment, or creates `$PREFIX/venv` (`--python-venv-mode` and
`--python-venv-dir` change that). By hand: `pip install .` in `CSXCAD/python` and then in `openEMS/python`, with both
`CSXCAD_INSTALL_PATH=$PREFIX` and `OPENEMS_INSTALL_PATH=$PREFIX` set for both (the openEMS module's build also builds the
CSXCAD package it needs). Modules installed outside a virtual environment, with `pip install --user` (on macOS under
`~/Library/Python`), are replaced only by `--python-venv-mode disable` with no virtual environment active, which
installs that way again; otherwise they stay, and `python3` imports them whenever the virtual environment is not
active. `update_openEMS.sh` passes the same `--python-venv-*` options on.

Without the rebuild, SAR goes wrong. v0.37.0 modules on the fork's libraries make `openEMS.sar_calculation` ignore the
averaging mass (it returns the local SAR) and then abort; modules built against the fork's headers give a wrong SAR on
stock libraries without any error, and so does the fork-built `bin/sar_calc`, which MATLAB/Octave's `CalcSAR.m` runs.
FDTD runs and nf2ff are not affected.

## 7. Knobs (environment variables)

All optimisations of the CPU engines are on by default, some of them chosen by the model or the thread count (the
coefficient layout, the neighbour flags and their spin; see their rows); the probe end criterion, the tiled sweep of
the multithreaded engine (`OPENEMS_TBLOCK`, patch 0040) and the Metal diamond engine (all three below) are opt-in.
The switches written `=1` below act when set to any value other than empty or `0` (since
patch 0006; up to patch 0005 any value, `0` included, switched them). `OPENEMS_FUSED`, `OPENEMS_BALANCE`,
`OPENEMS_QOS`, `OPENEMS_FLAGS`, `OPENEMS_PML_YVEC`, `OPENEMS_ADE_MERGED` and `OPENEMS_TBLOCK_HOOKS` read their value
as a number, and so do the seven Metal diamond switches written `=0` (`OPENEMS_DIAMOND_MERGE`, `_MURMERGE`, `_EVEN`,
`_FASTIDX`, `_TGFLAG`, `_PML4` and `_PML3`: on unless the number is 0);
`OPENEMS_COEF` and `OPENEMS_DIAMOND_COEF` read a word. `OPENEMS_TBLOCK` reads the word `auto` or a number, the depth
k (`0`, or any other value that is not a number above 0, leaves the tiled sweep off), and `OPENEMS_TBLOCK_W` a number
above 0 (any other value means the default width). For every `OPENEMS_*` variable that the fork's own code reads
(the knobs below), an empty value is the same as an unset one (since patch 0006; before, an empty `OPENEMS_FUSED`,
`OPENEMS_BALANCE`, `OPENEMS_QOS`, `OPENEMS_TUNE_WINDOW_MS` or `OPENEMS_BARRIER_SPIN_US` read as 0). The rule does not
apply to the harness's `OPENEMS_BENCH_*` variables of section 9, nor to the `OPENEMS_HIP_*` variables of the base's
HIP backend (HIP builds only, unchanged by the fork and not listed here; an empty `OPENEMS_HIP_FUSED_STEP`, for
example, turns its fused step off). `OPENEMS_FTZ`, `OPENEMS_NO_STAGGER`, `OPENEMS_NF2FF_LEGACY`,
`OPENEMS_SETUP_TIMING`, `OPENEMS_BARRIER_SPIN_US` and `OPENEMS_FUSED_STAT` are read once per process, the others at
every run. Some items have no switch: the hook plan and the spin barriers, work stealing, the Mur and UPML vector paths
(the whole-grid hooks use them too; of these only the UPML y-rows of patch 0019 have one, `OPENEMS_PML_YVEC`), the dump
gather of the SSE engines, the operator-setup changes (among them patch 0020's UPML coefficients on the setup threads,
from upstream PR #244 by Noriaki Takashima) and the line hooks of the steady-state detection, of Debye materials and
of the cylinder extension (patches 0021, 0022 and 0039; `OPENEMS_FUSED=0` turns them off with every other line hook).
They rest on the bit-identity checks against the snapshot before them. Patch 0028 has none either (section 8, "Energy
end criterion"), nor have two of the Metal diamond engine's changes of 2026-11-11 (below).

| variable | effect |
|---|---|
| `OPENEMS_FUSED=0` | separate E and H sweeps instead of the fused sweep; the extensions then run their whole-grid hooks, and no line hook (the dispersive ones included) is used, nor are the neighbour flags |
| `OPENEMS_FUSED_BLOCK=k` | x-lines per fused block (default 1; halved while there are fewer than four blocks per thread) |
| `OPENEMS_FLAGS=0` | the two barriers per timestep of the fused sweep instead of the neighbour flags (patch 0025). With the flags a thread waits only for its two neighbours, so neighbouring threads can be up to one timestep apart (threads t and t+k up to k). They are used with the fused sweep and two or more threads when every extension of the model declares `TS_LOCAL` (section 8), otherwise the barriers are; at verbose level 1 and above the engine's line about the fused sweep says "neighbour flags" when they are used, or names the extension that is not `TS_LOCAL` |
| `OPENEMS_FLAGS_SPIN_US=us` | how long a wait for a neighbour flag spins before the thread sleeps, for any thread count (patch 0027). Unset: no spin when the threads outnumber the performance cores of an Apple CPU (4 on the M5: some threads then run on efficiency cores, the waits for them are long, and a spinning thread takes a core from the others); up to that count, and on other CPUs, the spin time of `OPENEMS_BARRIER_SPIN_US` |
| `OPENEMS_FUSED_STAT=1` | print the time split of the fused sweep per thread (the sweep, the two waits and the line before the slab, in ms, with the share of the waits) when the thread count changes and when the engine stops (patch 0024; a diagnostic) |
| `OPENEMS_BALANCE=0` | no slab re-balancing between threads; in the tiled sweep (`OPENEMS_TBLOCK`) every thread keeps an equal share of the y lines, and of the x-lines of a hook stage, instead of a share that follows its measured speed |
| `OPENEMS_TBLOCK=k` | the tiled sweep of the multithreaded engine (patch 0040; opt-in): k timesteps on one tile of x-lines, shared by all threads, before the next tile, so a tile comes from memory once per k timesteps. `auto` takes the deepest k up to 8 whose tile of 2k+1 x-lines fits the cache the threads share, and keeps the fused sweep when the fields fit that cache or two timesteps of a tile do not. Unset or `0`: the fused sweep. Results are identical. On the M5, at 4 threads, it was ahead of the fused sweep's best setting on two of six models, large grids with little extension work, and behind on the other four; at 8 or 10 threads it was behind the fused sweep at 8 threads on every model but a 16.8 M-cell box (`results/tiled_sweep_cg32_2026-11-11.txt`). On an M5 Pro (5 + 10 cores, at 5, 10 and 15 threads) it was ahead only on that box and behind on the other five (`results/m5pro_tiled_sweep_2026-11-12.txt`). Refused with a message when an extension cannot be blocked or the grid has fewer x-lines than two tiles |
| `OPENEMS_TBLOCK_W=n` | the tiled sweep's tile width in x-lines, at least 2k+1. Default: 2k+1 with a set k; with `auto` wide enough for a tile of at least 200000 cells, within the cache size and half of the x-lines |
| `OPENEMS_TBLOCK_HOOKS=0` | the tiled sweep runs the extensions' line hooks on one thread instead of all (a diagnostic; slower) |
| `OPENEMS_NO_STAGGER=1` | page-aligned field arrays (the allocation-placement valley comes back) |
| `OPENEMS_OP_INDEX_PER_CELL=1` | the operator index with one entry per cell, as before patch 0017, instead of one per f4vector (four cells); on meshes of up to 42 z lines the unused entries shared the cache lines of the used ones, so the engines streamed 4 B of index per cell instead of 1 B (kept to compare) |
| `OPENEMS_NO_PACKED_COEFF=1` | the operator's 12 SoA coefficient tables instead of the packed or geometry tables of `OPENEMS_COEF`; the IJKN loops and the fused sweep need one of these, so this also brings back the generic loops and the unfused sweep (an "old engine" switch). Otherwise one of the two is always built (patch 0006 removed the size test of 0005); only a failed allocation of the packed tables leaves none, with a message that the generic loops run and the multithreaded engine does not fuse its sweep |
| `OPENEMS_COEF=packed` or `geom` | the coefficient layout of the IJKN loops and the fused sweep (patch 0023): `packed` holds an operator's six coefficient f4vectors per update in access order (192 B per operator), `geom` only its vi and iv terms and the 16-bit indices of its vv and ii triplets in tables of the distinct triplets (100 B per operator plus 48 B per distinct triplet). Unset: `geom` when the packed tables would exceed 4 MiB (more than 21845 operators: of the six benchmark models only the SMA launch), else `packed`; any other value means `packed`. `geom` falls back to `packed`, without a message, above 65535 distinct triplets or when its allocation fails |
| `OPENEMS_BARRIER_SPIN_US=50` | spin time of the spin barrier before a thread parks; also the spin of the neighbour-flag waits up to the performance-core count (`OPENEMS_FLAGS_SPIN_US`) |
| `OPENEMS_TUNE_WINDOW_MS=150` | measurement window per thread count when `numThreads=0` |
| `OPENEMS_NO_PML_TABLE=1` | per-cell UPML coefficient arrays instead of the compressed table; this also turns off the UPML y-rows of `OPENEMS_PML_YVEC`, which need the table |
| `OPENEMS_PML_YVEC=0` | the scalar SSE path of the UPML (boxes that are not full-z slabs, such as the SMA launch's) row by row instead of four y-rows at a time (patch 0019) |
| `OPENEMS_ADE_MERGED=0` | the line hooks of the dispersive materials run their orders one after the other instead of back to back per position, four positions at a time (patch 0018). The merged form applies when every order with voltage (or current) ADEs has the same positions, already in x order, as the two orders of a conducting sheet have, and lists each position once (a check that follows the strict-order check of upstream PR #245 by Roel Budé); `verbose>1` prints the merged orders |
| `OPENEMS_QOS=0`, `1` or `2` | engine thread QoS on macOS: 0 leaves the default class, 1 user-initiated (the default), 2 user-interactive |
| `OPENEMS_FTZ=1` | flush subnormals to zero (arm64 only). It sets FPCR.FZ wherever the engine runs its subnormal setup: on the thread that creates an engine of the SSE family (sse, sse-compressed, multithreaded, cylindrical, metal-diamond) and in the multithreaded workers; the basic engine never flushes. Results then match a GPU that flushes subnormals and are no longer bit-identical to stock (notch tutorial, 3000 steps: the multithreaded engine at 2 threads and the sse-compressed engine with it gave the base's GPU engine's probes and S11 bit for bit, `results/notch_s1_n3000_ftzgpu.txt`; the Metal diamond engine below is bit-identical to the multithreaded engine run with it). Since patch 0006 the creating thread (Python's, for example) gets its previous state back when the engine is destroyed there. On x86 the engines set MXCSR FZ and DAZ as stock v0.37.0 does, whatever this variable says, and do not restore them, so after a run the Python thread's own float arithmetic and a later basic-engine run in the same process flush too (CMake `-DENABLE_FLUSH_TO_ZERO=OFF` turns it off; upstream's later fix 367a63f is not in the fork) |
| `OPENEMS_NF2FF_LEGACY=1` | the original nf2ff loop; builds without Apple's Accelerate always use it |
| `OPENEMS_SETUP_TIMING=1` | print operator-setup phase times |
| `OPENEMS_EXPORT_OPERATOR=dir`, `OPENEMS_EXPORT_FIELDS=dir` | write the compressed operator (just before the engine is created) or the engine's final fields (after the run) as raw little-endian files plus JSON, for swift_engine/ and the field comparison of `scripts/checks/diamond_check.sh`; the operator export needs the compressed operator (sse-compressed, multithreaded or metal-diamond engine); `dir` must exist; one grid only, and only the voltage excitation entries; since patch 0006 every failed write is reported, and an empty value exports nothing |
| `OPENEMS_PROBE_END_DB=-60`, `OPENEMS_PROBE_END_HOLD=1` | probe end criterion, see below |
| `OPENEMS_DIAMOND_K=k` | metal-diamond (see below): timesteps per diamond block (default 4, at least 1). When it or `OPENEMS_DIAMOND_TILE` is set, one tiling runs and the tuner is off; without a tile the mountains and valleys are then 2k cells wide |
| `OPENEMS_DIAMOND_TILE=M,V` or `M:V` | metal-diamond: the widths of the mountain and valley tiles in x and y, M at least 2K-1 (otherwise ignored with a message); fixes one tiling, as `OPENEMS_DIAMOND_K` does |
| `OPENEMS_DIAMOND_TUNE=n` | metal-diamond: the first command buffers of a run take the tuner's tilings in turn, n timed buffers each (default 4); then the tiling with the least GPU time per timestep runs and the others are released. Four tilings up to patch 0037: K=4 with 8,8 or 12,8 tiles and K=3 with 8,6 or 6,6 (patch 0016; 532 to 623 timesteps of tuning on the six models, `results/diamond_engine_cg28_tuner_2026-11-04.txt`); since patch 0038 also K=4 with 10,6 and 9,2 tiles and K=5 with 12,8, in two stages: a tiling more than 6 % behind the fastest after two timed buffers is not timed further. `0`: K=4 with 8,8 tiles, no tuning. The fields do not depend on the tiling: every value gets the same operations in the same order |
| `OPENEMS_DIAMOND_TG=n` | metal-diamond: threads per tile; default the largest power of two from 256 to 1024 that is at most 3/5 of a mountain's f4vectors (M·M·z-vectors), and 256 below that; never more than the Metal pipeline allows; `0` is the default |
| `OPENEMS_DIAMOND_BATCH=n` | metal-diamond: timesteps per Metal command buffer (default 64, at least 1, in whole blocks of K steps; half as many while the tuner runs) |
| `OPENEMS_DIAMOND_TIMING=1` or `2` | metal-diamond: 1 prints the tuner's choice and, when the engine is destroyed, its setup time, timesteps, MC/s on the GPU, IterateTS calls, command buffers, GPU busy time and the tiling; 2 also times the four phases of a block (MM, MV, VM, VV; one command buffer per phase, so the run is slower) and fixes one tiling |
| `OPENEMS_DIAMOND_COEF=packed` or `split` | metal-diamond: the coefficient layout on the GPU (patch 0015). `packed`: six f4vectors per operator and update, in access order; `split`: one table of the distinct f4vectors (vv and ii first, at most 1024 of them) and per operator and update one uint4 of indices (the three vi or iv terms, and the three vv or ii terms in 10 bits each). Unset: `split` when the packed coefficients of a block of 16x16 columns average more than 32 KB (of the six models the SMA launch, the GCPW line and the patch tutorial; `results/diamond_engine_cg24_cg27_2026-11-04.txt`), else `packed`; any other value means `packed`. `split` falls back to `packed`, without a message, above 1024 distinct vv and ii f4vectors |
| `OPENEMS_DIAMOND_MERGE=0` | metal-diamond: four dispatches per block. Default (unset or `1`): three, the mountain x valley and valley x mountain tiles in one dispatch, which do not depend on each other (patch 0030; the GCPW line 5-6 % and the notch tutorial about 10 % faster in paired rounds on a loaded machine). The per-phase timing of `OPENEMS_DIAMOND_TIMING=2` keeps four |
| `OPENEMS_DIAMOND_MURMERGE=0` | metal-diamond: every Mur face behind its own barrier in each stage. Default: consecutive faces of one axis in the Apply order share a barrier, and where a tile's faces are all on one axis Post and Apply go in one pass (patches 0029 and 0032) |
| `OPENEMS_DIAMOND_EVEN=0` | metal-diamond: a call of n timesteps runs blocks of K, K, .., rest. Default: the rest is spread over blocks of nearly equal depth, 4, 3, 3 for 10 steps at K=4 (patch 0029) |
| `OPENEMS_DIAMOND_FASTIDX=0` | metal-diamond: the index arithmetic of the kernel as before patch 0031: a branch for the z neighbour of the first and last z-vector and divisions by the tile widths. Default: a select, and multiplications by reciprocals that the host computes (patches 0031, 0032, 0034; on an M5 with macOS 27.0.1 the GPU's own `0xffffffff / 3` is wrong) |
| `OPENEMS_DIAMOND_TGFLAG=0` | metal-diamond: the pipeline is not told that a threadgroup is a whole number of SIMD groups (patch 0031; no measurable difference) |
| `OPENEMS_DIAMOND_PML4=0` | metal-diamond: every UPML box a float at a time. Default: the boxes with every z line (the x and y slabs) a z-vector at a time (patch 0033; a cube with a 10-cell PML on six faces 36 % faster at 1 M cells and 17 % at 8 M, paired rounds on a loaded machine) |
| `OPENEMS_DIAMOND_PML3=0` | metal-diamond: the other UPML boxes (the z slabs) a float at a time. Default: the three components of a cell at a time, when the coefficient sets fit 16-bit indices (patch 0035; the SMA launch 7 % faster) |
| `OPENEMS_DIAMOND_CAND=n` | metal-diamond: the tuner takes only the first n of its seven tilings (`4`: those of patch 0016); `0` or unset: all seven (patch 0038) |

**Probe end criterion.** `OPENEMS_PROBE_END_DB` is a negative number of dB; unset, empty or `0` leaves the criterion
off. `OPENEMS_PROBE_END_HOLD` is the hold in excitation lengths (default 1, `0` = no hold). Since patch 0006 a value
that is not a finite number, a positive dB value or a negative hold prints a warning (the criterion stays off, or the
hold is 1). It needs a Gaussian excitation and at least one probe; otherwise a notice is printed and the criterion is
ignored. The run then stops once every enabled probe (port voltages and currents, field probes, and mode-match probes by
their mode amplitude, not their purity) has stayed below that fraction of its own peak for the hold time. The test runs
whenever the probes are processed, and the hold starts again at every test at which the excitation is still running (its
signal length plus the largest excitation delay), a probe is above the threshold, or a probe is still exactly zero. Such
a probe holds the run: one that never sees a signal (on a conductor, for example) keeps it going to its end, and once
all the others have settled a notice names it. The numerical precursor of the pulse makes a far probe slightly non-zero
shortly before the pulse arrives, so the hold must be longer than the longest one-way delay in the model. A probe whose
peak is below 1e-6 of the largest peak among probes of its kind is measured against that floor. The port files of an
early-stopped run are a bit-identical prefix of the full run's. `verbose>1` lists the probes, `verbose>2` traces each
test. (Patch 0006 added the excitation delay, the mode-match rule, the notice and the warnings.) A probe with a stop
time (`SetStopTime` of its CSXCAD probe box, `stopTS` in openEMS's `Processing`) is not processed after that time, so
its last value stays frozen; if that value is above the threshold, the criterion cannot fire and the run goes to its
maximum time (the early stop is lost; the results are not affected).

The author's rfsim toolkit (not public), which sets these variables around `FDTD.Run`, differs on purpose:
`RFSIM_PROBE_END_HOLD=0` gives a warning and the default hold, and `probe_end_hold=0` raises `ValueError`, because a
hold of 0 can stop a run on the precursor; an invalid `RFSIM_PROBE_END_DB` falls back to -60 dB with a warning. The
default hold was 1 until 2026-11-04 and is 0.5 since toolkit commit 4a7e20e of that day, which also raised the SMA
launch's mesh floor from 0.02 to 0.05 mm (0.871 M cells instead of 1.071 M); `RFSIM_PROBE_END_HOLD=1` and
`RFSIM_MIN_CELL=0.02` give the old values.

**The tiled sweep.** Patch 0040 (the fork's head; not in cg31, the installed build) gives the multithreaded engine a
second sweep, opt-in through `OPENEMS_TBLOCK`. The fused sweep passes over the whole grid once per timestep. The
tiled sweep runs k timesteps on one tile of x-lines before it moves on, and all threads work in that tile, each on
its share of the y lines, with one spin barrier per task, so a tile is read from memory once per k timesteps. A task
is the update of the voltages or of the currents on one range of x-lines at one timestep of the block. The
extensions' line hooks run in stages between two updates, on all threads, and every hook of an x-line on one thread.
The design follows the `cpu` engine of upstream master (one cache-sized tile shared by all threads); none of its
code is used. The tiled sweep is set up only where the fused sweep is, so `OPENEMS_FUSED=0` turns it off too. It is
refused, with a message at verbose level 1 and above, when an extension of the model does not declare `TS_LOCAL`
(section 8), when an extension couples two x-lines other than the first two or the last two, or when the grid has
fewer x-lines than two tiles; the run then keeps the fused sweep. An extension can bound the depth
(`Engine_Extension::GetMaxBlockDepth()`; the steady-state detection allows one signal period). The results were
identical to the fused sweep's in every test (section 9). Speed on the Apple M5 (4 performance and 6 efficiency
cores) under macOS 27.2.1, 2026-11-11, three paired rounds with the other processes at a median of 9 % of one core:
against the fused sweep at its best thread count, which was 8, the tiled sweep at its best, which was 4 threads, ran
1.08 times as fast on patch x5 (7.86 M cells) and 1.23 times on a PEC box of 16.8 M cells (the harness model
`lbox`), and 0.92, 0.85, 0.81 and 0.71 times on the same box at 2.95 M cells, a PML cube of 8.0 M (the harness model
`cube`), notch x3 and the SMA launch. At 8 or 10 threads it was behind the fused sweep at 8 threads on every model
but the 16.8 M box, and under heavy load from other programs it fell far behind the fused sweep (one barrier per
task). The GCPW line fits the cache, so `auto` keeps the fused sweep there. So it paid only on large grids with
little extension work, and most at the performance-core count: time it against the fused sweep before relying on it
(`results/tiled_sweep_cg32_2026-11-11.txt`). On a second machine, an Apple M5 Pro Mac mini (5 Super and 10
Performance cores, macOS 27.2.1; a set of its own, compared only with itself), 2026-11-12, three paired rounds at 5,
10 and 15 threads: on five of the six models the fused sweep gained x1.4 to x2.1 from 5 to 15 threads, while the
tiled sweep peaked at 10, so the tiled sweep's best was 0.41 to 0.97 times the fused sweep's best on those five; on
the PEC box of 16.8 M cells, where the fused sweep stays nearly flat from 5 to 15 threads (2986 to 3326 MC/s), the
tiled sweep ran 4752 at 15 threads, 1.43 times the fused sweep's best (`results/m5pro_tiled_sweep_2026-11-12.txt`).
The verdict there is the same: opt-in.

**The Metal diamond engine.** Patches 0007 to 0016 (snapshots cg19 to cg28) add `--engine=metal-diamond`
(`FDTD.Run(sim_path, engine='metal-diamond')` from Python; `FDTD/engine_metal_diamond.h`,
`FDTD/metal/engine_metal_diamond.mm`), and patches 0029 to 0038 (2026-11-11, snapshots cg30a to cg30l) make it faster
with the same fields. Most of their changes have a switch among the rows above; the dispersive materials updated
three components of a cell at a time (0036) and the offsets and counts of the extension data as constants of the
kernel (0037) have none (`results/metal_engine_cg31_2026-11-11.txt`; the paper's section "After publication"). The
engine is opt-in: the default engine stays the multithreaded CPU engine. The build
installed on the author's Mac has it since 2026-11-06 (cg29, and since 2026-11-11 cg31; cg18, installed there from
2026-11-04 to 2026-11-06, did not), and the author's toolkit does not select it. It needs a build with `ENABLE_METAL`
on macOS (section 5);
without it the name is unknown and the run uses the default engine without a message (section 8). It was run only on
the Apple M5 under macOS 27.0.1. The engine advances K timesteps at a time (by default 3, 4 or 5, picked at run time
among seven tilings; up to patch 0037 3 or 4, among four) in
diamond-shaped tiles (the tile schedule follows luikore's Metal engine, openEMS PR #228, GPL; no code of it is used).
The fields are the engine's own f4vector arrays in shared Metal buffers, in N-I-J-K order, so the probes, the dumps and
any extension left on the CPU use the same memory; probes and dumps run on the CPU between the `IterateTS` calls. On
the GPU run the field updates, the excitation (voltages and currents, with their delays), Mur, lumped RLC elements,
UPML (boxes that do not overlap), Drude/Lorentz materials with the conducting sheets, and Debye materials (these two
only as exactly their classes, not as subclasses); all six benchmark models run on the GPU since cg22. Any other
extension (TFSF, the steady-state detection, a subclass of a dispersive extension) prints
`Engine_Metal_Diamond: the extension "NAME" has no GPU version here, running the CPU loops`, and the whole run then
takes the single-threaded generic loops of the sse-compressed engine on the same memory: correct, but slow. The same
happens without a Metal device, when the shared memory cannot be allocated or the kernel does not compile, for
overlapping UPML boxes (each with a message) and past the limits of section 8. A cylindrical mesh always runs the
cylindrical CPU engine. The results are bit-identical to the multithreaded engine run with `OPENEMS_FTZ=1` (on every
model and box of the checks in section 9), not to stock: Apple's GPU flushes subnormals to zero, and the kernels do
the CPU engines' operations in the same order (with `fma()` where clang contracts on arm64, and Metal's fast math
off). For identical dumps set `OPENEMS_FTZ=1` for both runs, because the dumps are computed on the CPU thread that
created the engine (`results/diamond_engine_cg20_2026-11-04.txt`). Without `OPENEMS_FTZ`, against stock v0.37.0 (`results/*_cg22.txt`),
the port probes differ by 1.7e-7 to 9.4e-7 relative, S11 by at most 2.3e-4 dB (notch tutorial) and S21 by at most
9.4e-5 dB. The base's GPU engine (`--engine=gpu`) also gave the FTZ CPU engine's bits on all six models
(`results/*_cg22gpu.txt`). The knobs are the `OPENEMS_DIAMOND_*` rows above; section 9 has the checks.

## 8. What differs from stock v0.37.0 besides the fork's speed-ups

- **The base's own changes.** 7bb294f carries upstream's unreleased changes after v0.37.0 (its `CHANGELOG.md`,
  "Unreleased"): the GPU engine (`--engine=gpu`, and `--engine=gpu-reference` on the CPU), `python -m openEMS.compare`,
  a fix for a Python option passed as `False`, an aborted run that reports the abort, field dumps written on
  background threads (on the GPU engine from a snapshot of the fields; a time-domain dump keeps its HDF5 file open, see
  below), the operator and engine memory freed at the end of the run, faster reading of time-domain dumps, and the
  `ENABLE_METAL` / `ENABLE_HIP` options. The background dump writer is a speed change of its own on dump-heavy models:
  on the patch tutorial, whose nf2ff box writes time-domain dumps, the base alone runs 1.13 to 1.18x faster than stock
  at 1 to 4 threads (with the dumps off both run at 342.2 MC/s at 2 threads), so part of fdtdKit's factor on that model
  comes from the base (about 1.13x of snapshot cg14's 6.9x in the paper's section "Results", 1912 MC/s against
  stock's 277 at 2 threads; the base was not run beside cg29); on the notch tutorial, the GCPW line and patch x5 the
  base is within noise of stock (0.98 to 1.03x). The base library was measured with the stock libCSXCAD and libnf2ff
  (`results/*_base.txt`, 2026-11-03).
- **Energy end criterion.** The base checks it every Nyquist period during the first 60 s of wall-clock time and after
  that with the progress report (upstream eb1c5ee); v0.37.0 checks it only with the progress report, every 4 s, unless
  `--exact-endcriteria` is given. A run that ends on the energy criterion can therefore stop at a different step than
  v0.37.0 (one that meets it within the first minute stops where v0.37.0 stops with `--exact-endcriteria`); up to the
  earlier stop the probe files are the same. Bit identity holds for the same number of time steps, and the harness
  always runs a fixed number (`EndCriteria=0`). In the run-mode matrix of cg29 (45 small models, section 3 of
  `results/cpu_items_cg29_2026-11-05.txt`) this was the only difference, 10 of 471 comparisons, all on one 0.7 s model
  that ends on the energy criterion: stock runs to its limit of 1496 steps, every cg29 configuration stops at step 255,
  and the 64 probe lines up to there equal the first 64 of stock's 375. Since patch 0028 a run without an end
  criterion (`EndCriteria=0` from Python, a fixed number of time steps) makes no energy estimate every Nyquist
  period, as in v0.37.0, unless `--exact-endcriteria` is given; its energy is estimated with the progress report only.
  Each estimate is one pass of one thread over both fields while the engine waits (4 to 6 % of the time stepping of
  the Metal diamond engine on 3 to 17 M cells at a Nyquist period of 51 steps; the paper's section "After
  publication"). The results of a run do not change, and a run with an end criterion is checked as before; so is a
  model file with `endCriteria` 0 run by the `openEMS` program, which then takes its default of -60 dB.
- **Time-domain HDF5 dumps** (from the base, unchanged by the fork). A time-domain dump, the one of a time-domain
  nf2ff box too, keeps its file open until the run ends (`Common/processfields_td.cpp`, `SetKeepOpen(true)`; upstream
  master 5fecbb5 does so too), where v0.37.0 opens and closes it for every dump and keeps every completed step. A run
  that is killed (SIGKILL, SIGTERM, a second Ctrl-C, a crash) therefore leaves such a file with no readable time step;
  one Ctrl-C or an `ABORT` file in the run directory stops the run cleanly. Frequency-domain dumps are not affected.
  While the file is open, its HDF5 metadata cache grows with every dumped step (an nf2ff box holds 12 such files); the
  memory is freed when the run ends. The base's background writer (`Common/async_dumps.h`) queues up to 64
  time-domain dumps, each with its own copy of the field on the CPU engines (only the GPU engine has field snapshots;
  upstream master c3a956b keeps one pending task per dump). The results are correct in every case; the memory only
  matters when the writer falls behind (large dumps every step, slow storage).
- **Compilers.** Bit identity was established with Apple clang on arm64. GCC contracts `a*b + c` across statements by
  default (`-ffp-contract=fast`): on every aarch64 build, and on x86-64 when FMA is enabled (`-mfma`, `-march=x86-64-v3`
  or `haswell` and newer, `-march=native`), it fuses the other product than stock in the IJKN loops and the UPML
  f4vector rows, so such a GCC build is correct but can differ from a GCC-built stock in the last bit. For a bit
  comparison under GCC, build stock and fork with the same `-ffp-contract=off` (upstream's Debug build type sets it; or
  pass `-DCMAKE_CXX_FLAGS=-ffp-contract=off` to both), or use clang. The fork was not built as a whole with GCC; the
  review compiled single files with g++-16 on macOS. In the standalone kernel (the stock and the rewritten loops of
  `scripts/kernel/kb_idx.cpp`, one thread, arm64; `results/kernel_gcc_vs_clang_2026-11-03.txt`), Homebrew GCC 16.2
  with the same flags as Apple clang 21 (`-std=c++17 -O3 -DNDEBUG`) runs the stock loop 1.16 to 1.39x faster and the
  rewritten loop at about the same speed, so there the rewrite gains 1.26 to 1.47x over a GCC-built stock loop against
  1.74 to 1.80x over a clang-built one. Apple clang reloads the stock loop's strides and table pointers after its
  vector stores, GCC does not (`results/kernel_loop_instructions_2026-11-03.txt`). The stock loop gives the same bits
  under both compilers; the GCC-built rewrite does not match the GCC-built stock loop bit for bit (the contraction
  above). Stock was not built as a whole with GCC either, so the factors in this repository are against stock built
  with Apple clang, the default compiler on macOS. `CMakeLists.txt` asks for C++11, but VTK 9.7's `VTK::CommonCore`
  requires C++17, so CMake compiles the openEMS library with `-std=gnu++17` (nf2ff, which does not use VTK, stays at
  `gnu++11`); `FDTD/operator.cpp`, upstream's file too, does not compile with g++-16 at `gnu++11` against VTK 9.7. Since
  patch 0006 nf2ff includes only `<vecLib/cblas.h>` on macOS, because GCC cannot parse the Accelerate umbrella header.
  The Metal kernels of the diamond engine reproduce Apple clang's contraction on arm64 (an explicit `fma()` where clang
  fuses, no other contraction), so the identity of section 7 is with clang-built CPU engines.
- **Setup threads.** The operator setup uses every core whatever `numThreads` says (stock used the requested count for
  part of it); several single-thread runs side by side therefore overlap their setup on all cores.
- **Mesh size.** The array sizes and indices inherited from upstream are 32-bit. Since patch 0006 a mesh too large for
  them is refused at setup with an error that names the limit: about 1.43e9 nodes (2^32/3) with field dumps, nf2ff
  boxes, conducting sheets, the debug material or operator dumps, or the basic or GPU engine (arrays over the whole mesh
  with three components), about 4.29e9 (2^32) otherwise. Before 0006 such a mesh overran its arrays; upstream widened
  the sizes after the base (0212258). The Metal diamond engine has limits of its own: more than 65535 lines in x or y,
  2^32 or more floats per field array, or 2^32 or more words of extension data send it to the CPU loops with a message
  (section 7); more than 32 Mur faces or UPML boxes, or more than 65535 lumped-RLC or dispersive extensions, do so
  without one.
- **Engine extensions** must declare their own hooks (`GetUsedHooks()` with `OPENEMS_HOOKS_DECLARED_BY`); a subclass
  that does not gets every hook called (the stock behaviour) and runs the unfused plan. This closed the Debye-material
  bug of patch 0005. Since patch 0025 an extension whose line hooks keep no state shared by x-lines from one timestep
  to the next, and read the timestep only through `GetNumberOfTimesteps()`, also declares `TS_LOCAL`; the neighbour
  flags (`OPENEMS_FLAGS`, section 7) are used only when every extension of the model does. In the fork the excitation,
  the Mur and UPML vector paths, lumped RLC elements (which since then take their state slots from the timestep, as
  MrHighVoltage proposed in upstream Discussion #492), the dispersive materials, the steady-state detection (since
  patch 0026, while its period is longer than twice the thread count) and the cylinder extension
  (`Engine_Ext_Cylinder`, since patch 0039, which made its two Post hooks line hooks: a cylindrical mesh closed in
  alpha, with or without r = 0, no longer falls back to the unfused plan because of it) declare it; TFSF, the
  absorbing boundary (`Engine_Ext_Absorbing_BC`) and the cylindrical multigrid extension declare no hooks and keep
  the unfused plan. Since patch 0040 `Engine_Extension` also has the virtual function `GetMaxBlockDepth()`: how many
  timesteps the line hooks of a `TS_LOCAL` extension may run in one block of the tiled sweep (section 7; default: no
  limit; the steady-state detection returns one signal period). The Metal
  diamond engine takes the dispersive materials only as exactly `Engine_Ext_LorentzMaterial` or
  `Engine_Ext_DebyeMaterial` (`typeid`), so a subclass of either runs the CPU loops there.
- **The Metal diamond engine** (`--engine=metal-diamond`, opt-in; section 7) is not bit-identical to stock: it gives
  the bits of the multithreaded engine run with `OPENEMS_FTZ=1`, and on the six benchmark models its port probes
  differ from stock's by at most 9.4e-7 relative (`results/*_cg22.txt`). Extensions without a GPU version, and models
  past its limits, run on the single-threaded CPU loops.
- **Upstream fixes after the base** that the fork does not have (all on upstream master): 367a63f (flush-to-zero during
  the run only, for every engine), 54a4c60 (errors of the setup and the run are caught instead of terminating, which
  ends a Python session), d1fef7c (no excitation before its delay has expired: delayed step and custom excitations),
  0212258 (sizes and counts for large meshes), c971899 (an unknown `--engine` value is an error; in the fork it silently
  runs the default multithreaded engine, so `engine='metal'` runs the CPU, and so does `engine='metal-diamond'` on a
  build without `ENABLE_METAL`), ec4d2db (an invalid command-line option is reported instead of terminating), dd72017
  (`Write2XML` fails instead of crashing on an incomplete setup), 7badca4 (time steps limited to INT_MAX), 5c8053e (a
  SAR dump keeps no second copy of the frequency-domain fields), d6bdf08 (an abort message), 6bb955d and 53a4264 (GPU
  and HIP backends), d686f1d (an opt-in DC-free Gaussian pulse), and db68e62 with CSXCAD 4a2d385 (a drawing
  tolerance taken from the mesh, which can change stock results on master: a port to master needs a stock reference
  built from master).
- **Commit messages.** The message bodies of patches 0001 to 0005 are kept as committed (the rewrite of 2026-11-07
  changed their trailers only); the message of 0006 lists their corrections. Two are missing there, both in 0003's
  message: its speed figures (GCPW line 299 -> 1736 MC/s at 4 threads, SMA launch 437 -> 1240) are against stock
  v0.37.0, not against the patch before it (0003's own step on the GCPW line was 448-505 -> 1608-1745 MC/s at 4
  threads; results tables and project log); and its "six-sided PML model" is the notch tutorial with `PML_8` on every
  face, on whose 14 z lines openEMS resets the z PML to PEC, so the PML was on the four x and y faces
  (`results/notch_s1_n8000_pml6.txt`, section 9).

## 9. Verifying a build against stock

`bench/check.sh TAG SNAP` runs the six benchmark models at 1, 4, 8, 10 and automatic threads against the stock snapshot
and prints the engine speed and the largest difference of the port probes and S-parameters, which must be 0. Both
snapshots are folders with `libopenEMS.0.dylib`, `libCSXCAD.0.dylib` and `libnf2ff.0.dylib`: `stock` from section 3,
and the build under test, for example from the install (with the Python modules importable, e.g. after
`source "$PREFIX/venv/bin/activate"`):
```sh
mkdir -p ~/opt/openEMS-dev/snap/mybuild
for l in libopenEMS libCSXCAD libnf2ff; do cp -L "$PREFIX/lib/$l.0.dylib" ~/opt/openEMS-dev/snap/mybuild/; done
"$EMSKIT"/bench/check.sh t1 mybuild
```
or from the build directories (`build-openems/libopenEMS.0.dylib`, `build-openems/nf2ff/libnf2ff.0.dylib`,
`build-csxcad/src/libCSXCAD.0.dylib`). dyld takes a library that is missing from a snapshot folder from the install
instead, without a message, so `bench.py` refuses a snapshot folder that lacks one of the three files. `check.sh` and
`bench.py` exit non-zero on a difference or a missing file, and a comparison that has no relative figure (a probe that
is all zero in the reference, an S-parameter that stays below -40 dB) is compared exactly and named in the line. The
tables are written to `results/MODEL_sSCALE_nSTEPS_TAG.txt`. The two real-board models (`kgcpw`, `ksma`) import the
author's rfsim toolkit, which is not public, from the directory named by `RFSIM_PATH`; when it is unset `check.sh`
skips them and its last line says PARTIAL, and `bench.py` stops with a message. The four tutorial models need only
openEMS. `LITE=1` runs a reduced set (4, 8 and automatic threads, one run each, no wait for a quiet Mac),
`QUIET_MAX=s` limits the wait for a quiet Mac (default 900 s per run), and `EXTRA="cfg ..."` adds configs in the
form `[LIB@]ENGINE[:THREADS][+nodumps][#NAME=VAL,...]` of `bench.py`. Configs on the GPU engines (`gpu`,
`gpu-reference`, `metal-diamond`) or with `OPENEMS_FTZ` set are compared and marked `(tolerant)`, but a difference
there does not fail the check (when the reference is such a config, every config is).

The Metal diamond engine is checked against the multithreaded engine run with `OPENEMS_FTZ=1` (section 7), on a build
with `ENABLE_METAL`. `scripts/checks/diamond_check.sh SNAP_DIR` runs nine boxes (PEC, Mur, PML and mixed walls, with
delayed and soft excitations, lumped elements, conducting sheets, Drude/Lorentz and Debye blocks) at K = 1, 2, 3, 4
and 8, with an odd tile, thread and batch setting and with the tuner, and compares the exported final fields value by
value (72 of 72 identical on cg28, on cg29, on every snapshot of 2026-11-11 from cg30a to cg31a and on the installed
cg31). On the six benchmark models, with the step counts of `check.sh`:
```sh
OPENEMS_FTZ=1 python3 "$EMSKIT"/bench/bench.py notch --nrts 16000 \
  --configs mybuild@multithreaded:4 mybuild@metal-diamond:0
```
Every config of such a call is tolerant, so its exit status and last line (`NOTHING REQUIRED TO MATCH`) say nothing
about identity: read `probes rel=0.0e+00` and `max|dS|=0.0e+00` in the metal-diamond line (`results/*_cg29gpu.txt`:
0 on all six models).

Other checks: `scripts/checks/debye_check.sh SNAP_DIR [REF_SNAP_DIR]` (a Debye box on the basic, sse-compressed and
multithreaded engines, final fields compared bit for bit), `scripts/cylinder_multigrid/run_cyl.py` with
`scripts/checks/h5cmp.py` (cylindrical multigrid, HDF5 dumps), `scripts/cylinder_closed/cyl_closed.py` (the check of
patch 0039: a cylindrical mesh closed in alpha, with r = 0 or without, run for a fixed number of steps; its probe
files and the final fields exported with `OPENEMS_EXPORT_FIELDS` are compared between two libraries, between thread
counts and between the fused sweep and `OPENEMS_FUSED=0`), `scripts/tiled_sweep/check.zsh NEW REF [T1 T2 T3 T4]` (the
check of patch 0040: the tiled sweep of snapshot NEW against the fused sweep of snapshot REF at four thread counts,
on the probes of the harness models `patch`, `notch`, `lbox` and `cube`, and of the two boards when `RFSIM_PATH` is
set, on the raw fields of the closed cylinder and of a sinusoidal run that stops by the steady-state criterion,
`scripts/tiled_sweep/ss_box.py`, and on the Debye check; exit status 0 only when every comparison is identical), and
the validation suite in `bench/validation/`
(closed-form references; see its README). On 2026-11-03 cg18 passed the Debye check, the cylindrical multigrid
comparison and the validation suite
(`results/correctness_cg18_2026-11-03.txt`, `results/validation_cg18_*`). On 2026-11-05 cg29 passed `check.sh` with
eight configs per model (1, 4, 8, 10 and automatic threads, each coefficient layout forced once and the barriers
instead of the neighbour flags; `results/*_cg29.txt`), the Debye check, the cylindrical multigrid comparison (34
datasets, 0 differences), the validation suite (15 of 15 at 4 threads and with the fastest engine,
`results/validation_cg29_*`) and the two GPU checks above (section 3 of `results/cpu_items_cg29_2026-11-05.txt`).
On 2026-11-06, with cg29 installed, the release build of the command line `emskit fdtd` (`README.md`, section
"Command line") checked the installed library, on a Mac loaded by other programs, so only the verdicts count:
`check --lite` all identical to stock (18 of 18 rows exact on the six models), the Debye check with snapshot cg29 as the
reference (all identical), `diamond-check` 72 of 72, the validation suite 15 of 15 with the fastest engine and at 4
threads, and the GCPW line's end-to-end run, stopped by the probe end criterion at step 34300 as before
(`Docs/fdtdKit/PLAN.md`, section 16). On 2026-11-07 a build of the 27 patches published then (0001 to 0027) from a
fresh clone (sections 1, 4 and 5, snapshot `pub29`) passed `check.sh` with `RFSIM_PATH` set (every run on the six models identical to
stock, `results/*_pub29.txt`), the Debye check (its fields also identical to those of snapshot cg29),
`diamond_check.sh` 72 of 72, the six models on `metal-diamond` (`results/*_pub29gpu.txt`), the validation suite 15
of 15 at 4 threads and with the fastest engine (`results/validation_pub29_*`) and the cylindrical multigrid (34
datasets equal to stock's), on a Mac loaded by other programs, so again only the verdicts count
(`results/fresh_build_pub29_2026-11-07.txt`). On 2026-11-11 the twelve patches to cg31 were checked snapshot by
snapshot (`results/metal_engine_cg31_2026-11-11.txt`): `diamond_check.sh` 72 of 72 after every step; on cg30l (0001
to 0038) `emskit fdtd check --lite` all identical to stock (18 rows on the six models), the Debye check, the
validation suite on the Metal diamond engine (15 of 15) and the GCPW line's end-to-end run on that engine; for patch
0039 the closed cylinder (five probes on the axis and the alpha seam equal to stock's and to cg30l's, the exported
fields bit-identical to cg30l's, at 1, 4, 8 and 10 threads and with `OPENEMS_FUSED=0`) and the cylindrical multigrid
comparison (18 datasets, 0 differences against cg29). With cg31 installed, `check --lite` on the installed library
was again all identical to stock (18 rows on the six models), the Debye check passed, the two end-to-end runs stopped
at the steps of cg29 (GCPW line 34300, SMA launch 50320) and `diamond_check.sh` on the installed library gave 72 of
72. These were the reduced runs of `check` (`--lite`). The same day snapshot cg32d (0001 to 0040) passed the checks
of `scripts/tiled_sweep/check.zsh` against cg31 on the M5: with `OPENEMS_TBLOCK` set, the probes of six models (30 of
30 sets at 2 threads, 36 of 36 at 3, 4, 8 and 10), the raw fields of the closed cylinder, the steady-state run (the
same stop step, probes and raw fields) and the Debye check were identical to the fused sweep's; with the variable
unset, `check --lite` was all identical to stock (18 rows on the six models). The same library files gave the same
verdicts on an Apple M5 Pro Mac mini at 5 to 15 threads (`results/tiled_sweep_cg32_2026-11-11.txt`). On that machine
(macOS 27.2.1) the same evening, 2026-11-11, `check --lite` on the installed library (cg31) and on cg32d was all
identical to stock (18 of 18 rows each), the validation suite passed 15 of 15 with the fastest engine and on
`metal-diamond`, `diamond-check` gave 72 of 72 and the Debye check passed; in its speed set of 2026-11-12 every CPU
run gave its reference run's probes and the GPU runs were within 1e-6 relative
(`results/m5pro_speed_set_2026-11-12.txt`, `results/m5pro_tiled_sweep_2026-11-12.txt`). The build from
a fresh clone was not repeated with the 39 or the 40 patches. `scripts/README.md` lists the scripts.

Harness knobs: `OPENEMS_BENCH_RUNS=dir` puts the run directories (probe files, dumps, logs) somewhere other than
`/tmp/openems_bench_runs` (`check.sh` and `step1.sh` export it); `OPENEMS_BENCH_SNAPS=dir` is the folder of named
snapshots (default `~/opt/openEMS-dev/snap`); `STOCK=name` (or a path) names the stock snapshot that `check.sh`
compares against and `step1.sh` measures (default `stock`); `OPENEMS_BENCH_BC="PML_8;PML_8;MUR;MUR;PEC;MUR"`
overrides the boundary conditions of any model (an experiment knob in `runner.py`). On the notch tutorial's 14 z lines
`PML_8` x6 gives PML on the four x and y faces only (openEMS resets a PML that does not fit to PEC, here both z faces);
a six-sided test needs at least 17 z lines. `bench.py --quiet PCT` waits before each run until the other processes use
less than PCT % CPU (100 = one core) and at most `--quiet-gpu` % of the GPU (default 10), for at most `--quiet-max`
seconds (default 900). Each line shows the CPU and GPU use of the bench's own and of all other processes during the run
(`during: ...`, from `bench/usage.py`); a busy other process makes that line's speed unreliable. `bench/abtest.py`
runs configs interleaved in rounds (A B C A B C ...) and prints each one's median rate and its paired ratio to the first
config, which cancels slow changes of the load; the paired A/B tables of the results files of 2026-11-04 and
2026-11-05 come from it. Two scripts take variables of their own: `scripts/e2e/run_one.py` passes `E2E_ENGINE` (for
example `metal-diamond`) to `FDTD.Run` as its engine, and `scripts/others/run_others.sh` takes `NOMUR=1` (every Mur
face replaced by PEC through `OPENEMS_BENCH_BC`), `ONLY="name ..."`, `QUIET` and `QUIET_MAX` (defaults 100 % and
90 s) besides `MASTER_PY` and `LUIKORE_PY`.

The bench harness (`bench.py`, `check.sh`, `step1.sh`) is macOS-only as written: `bench.py` reads the load of other
processes with `top -l` and selects a snapshot's libraries with `DYLD_LIBRARY_PATH` (it refuses such a `LIB@` config on
other systems), and `check.sh` / `step1.sh` are zsh scripts built on such configs. macOS strips `DYLD_*` from the
environment of system binaries such as `/bin/zsh`, `/bin/bash` and `caffeinate`, so a `DYLD_LIBRARY_PATH` set in your
shell does not reach a script started through them: the scripts that test a snapshot take its folder as an argument and
set the variable themselves, and `caffeinate` must not be put in front of `python3` (`scripts/sma_mesh/batch.sh` and
`scripts/cache_valley/valley_sweep.sh` start it beside the run instead: `(caffeinate -i -w $$ &)`).

## 10. Reverting

The install replaces more than the libraries: `bin/openEMS`, `bin/nf2ff`, `bin/sar_calc`, the headers under
`include/openEMS` and `include/CSXCAD`, and the files under `share/` (the MATLAB/Octave scripts among them). To revert,
put back the prefix saved in section 3 and rebuild the Python modules against it from clean build directories of the
stock trees (section 6), unless they live in `$PREFIX/venv` and came back with the saved prefix:
```sh
mv "$PREFIX" "$PREFIX.fdtdKit" && mv "$PREFIX.stock-v0.37.0" "$PREFIX"
```
Or install stock builds of openEMS v0.37.0 and CSXCAD v0.7.0 over it from an unpatched clone, which with `--python`
also rebuilds the Python modules (into the active virtual environment, or `$PREFIX/venv`; for modules installed with
`pip install --user` see section 6):
```sh
rm -rf CSXCAD/python/build openEMS/python/build
./update_openEMS.sh "$PREFIX" --disable-GUI --python
```
Copying only the three libraries back leaves the fork's headers and binaries in the prefix: Python modules built
against those headers, and the fork's `bin/sar_calc`, then give a wrong SAR on the stock libraries without an error.
