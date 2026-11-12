# openEMS speed fork for Apple M5: code-level notes from the diffs

Written from the diffs by an AI review agent (Claude, through Claude Code; see the paper's disclosure
section) on 2026-11-01, updated for patch 0005 on 2026-11-02 and for the final review on 2026-11-03; this
header and the snapshot names were brought up to date for patches 0007–0027 on 2026-11-05.
"I" in these notes is that agent. The section on patch 0040 (the tiled sweep) was added on 2026-11-11 by another
agent of the same kind, from that patch's diff; it does not use "I". Sources: the openEMS patches `patches/openems/0001`–`0005` and their
cumulative diff against the base 7bb294f (upstream branch `gpu-engine`) as it stood on 2026-11-02, and
`patches/csxcad/0001` against CSXCAD v0.7.0. Totals through patch 0005:
openEMS 43 files, +3098/−179 lines; CSXCAD 3 files, +9/−0. Every line count below is from that
cumulative diff; patch 0006 (snapshot cg18, section "Final review fixes") changes some of them, and the file
`patches/openems/cumulative_vs_gpu-engine.patch` now covers patches 0001–0040 (68 files, +7042/−265). Patch 0001 holds
steps 2 and 3 (items A–E, Field_Gather_SSE, the Mur line hooks; snapshots ABCDEG to cg8), 0002 cg9,
0003 cg10–cg15, 0004 cg16 and 0005 cg17. Through patch 0006 the GPU engine sources (`FDTD/engine_gpu*`,
`gpu_backend*`, `FDTD/metal`, `FDTD/hip`, `operator_gpu*`) are **not touched** by the fork, and every
GPU-engine number of the paper up to cg18 is upstream's engine running on the fork's operator/setup code.
Patches 0007–0016 (snapshots cg19–cg28) leave those sources unchanged too and add the fork's own Metal diamond
engine (`--engine=metal-diamond`, in the new files `FDTD/engine_metal_diamond.h` and
`FDTD/metal/engine_metal_diamond.mm`, with a friend declaration in 13 extension headers and small changes to
`openems.cpp`, `openems.h`, `tools/arraylib/array_e.h` and `FDTD/CMakeLists.txt`: 19 files, +1717/−1 against
cg18); patches 0017–0027 (snapshot cg29) are CPU items. These notes describe
patches 0001–0006 and, in the section "Tiled sweep of the multithreaded engine", patch 0040 (the fork's head, snapshot
cg32d; not in the installed build, which is cg31 = patches 0001–0039). They do not describe the patches between:
0028–0039 (the build cg31) are described in the `CHANGELOG.md` entry of 2026-11-11 and in the
paper's Section "After publication"; 0007–0027 are described in the `CHANGELOG.md` entries of 2026-11-04 and 2026-11-05, in
the paper's Section "A diamond-blocked Metal engine" and in its subsection "The second review's CPU items and
other contributors' ideas (cg29, patches 0017–0027)", and in their commit messages. Numbers
marked "project log" come from the unpublished log of the work, not from `results/`. The bench
models `kgcpw` (GCPW line) and `ksma` (SMA launch) are the author's two boards (`bench/models.py`); every
ksma number in these notes is on its 1.071 M-cell mesh (the toolkit's 0.02 mm mesh floor of the time; the
toolkit's default since 2026-11-04, 0.05 mm, gives 0.871 M cells).

Note on the snapshot: the cg16 snapshot used for the measurements is the committed tree minus
eight lines of verbose output in `openems.cpp` (the probe list at `verbose>1` and the per-check
trace at `verbose>2`); nothing functional differs.

Memory layout used throughout (upstream `tools/arraylib/array_e.h`, `ArrayENG<f4vector>`):
the SSE engines store each field as 4-D array (n, x, y, zv) of `f4vector` (16 B, four floats)
in **I-J-K-N order**: component stride 1, z-vector stride 3, so one (x, y, zv) holds the three
components of four cells. Cell z sits in lane `z/numVectors` of z-vector `z%numVectors`
(`numVectors = ceil(Nz/4)`), so one f4vector holds cells z, z+nvec, z+2·nvec, z+3·nvec, and
the z extent is padded to 4·nvec. A cell therefore costs 12 B per field. The compressed operator
index `m_Op_index` (`ArrayIJK<unsigned int>`) needs one 4-B entry per (x, y, zv), 1 B per cell,
but `Operator_SSE_Compressed` allocates it per (x, y, z) (`m_Op_index.Init("Op_index",
numLines)`) and every user reads only the first `numVectors` entries of a z-row. With 128-B
cache lines the engine therefore streams up to 4 B of index per cell, all of it when Nz ≤ 42
(every line of the array then holds used entries). The byte counts below use the compact 1 B
unless they say otherwise.

Environment knobs added by the fork (all read with `getenv`, none set by default). From patch
0006 on, the on/off switches (`OPENEMS_NO_PACKED_COEFF`, `OPENEMS_NO_PML_TABLE`,
`OPENEMS_NO_STAGGER`, `OPENEMS_FTZ`, `OPENEMS_NF2FF_LEGACY`, `OPENEMS_SETUP_TIMING`) act only
when set to a value other than empty or `0` (`=0` is the same as unset); through patch 0005 any
value, `0` included, switched them on.
`OPENEMS_FUSED=0`, `OPENEMS_BALANCE=0` and `OPENEMS_QOS` keep their meaning. Since patch 0006 an
empty value of any of the fork's variables counts as unset (before, an empty `OPENEMS_FUSED`,
`OPENEMS_BALANCE`, `OPENEMS_QOS`, `OPENEMS_TUNE_WINDOW_MS` or `OPENEMS_BARRIER_SPIN_US` read as 0).

| knob | default | effect |
|---|---|---|
| `OPENEMS_BARRIER_SPIN_US` | 50 | spin time of `SpinBarrier` before parking |
| `OPENEMS_FUSED` | on (`0` = off) | fused E/H sweep of the multithreaded engine |
| `OPENEMS_FUSED_BLOCK` | 1 | x-lines per fused block |
| `OPENEMS_BALANCE` | on (`0` = off) | slab re-balancing between `IterateTS` calls |
| `OPENEMS_TUNE_WINDOW_MS` | 150 | measurement window per thread count (numThreads=0) |
| `OPENEMS_QOS` | 1 | 0 off, 1 `QOS_CLASS_USER_INITIATED`, 2 `USER_INTERACTIVE` (macOS) |
| `OPENEMS_NO_PACKED_COEFF` | unset | keep the operator's 12 SoA tables (also disables IJKN + fused, see cg13) |
| `OPENEMS_NO_PML_TABLE` | unset | UPML hooks read the per-cell coefficient arrays, no table (see cg14) |
| `OPENEMS_NO_STAGGER` | unset | page-aligned allocations as before |
| `OPENEMS_FTZ` | unset | set FPCR.FZ on arm64 |
| `OPENEMS_NF2FF_LEGACY` | unset | per-cell/per-direction nf2ff loop |
| `OPENEMS_SETUP_TIMING` | unset | print operator setup phase times to stderr |
| `OPENEMS_EXPORT_OPERATOR=dir`, `OPENEMS_EXPORT_FIELDS=dir` | unset | raw binary export (failed writes reported since patch 0006) |
| `OPENEMS_PROBE_END_DB`, `OPENEMS_PROBE_END_HOLD` | unset / 1.0 | probe end criterion (an invalid value prints a warning since patch 0006) |

---

## A. SpinBarrier and the hook plan (step 2, patch 0001)

**Files.** `tools/spin_barrier.h` (new, 110 lines), `FDTD/engine_multithread.{h,cpp}`
(`BuildHookPlan`, `RunHooks`, `HookStep`, the six `Do*/Apply2*` wrappers),
`FDTD/extensions/engine_extension.h` (+47: `enum Hooks`, `GetUsedHooks()`, line-hook
virtuals, `GetCoupledLines`, and since patch 0005 `OPENEMS_HOOKS_DECLARED_BY`).

**Stock.** `Engine_Multithread::m_IterateBarrier` was a `boost::barrier` (mutex + condition
variable). Each worker thread ran per timestep: `DoPreVoltageUpdates` = for every extension
(reverse order) call its hook **then wait on the barrier**; `UpdateVoltages`; barrier;
`DoPostVoltageUpdates` (N barriers); `Apply2Voltages` (N); `DoPreCurrentUpdates` (N);
`UpdateCurrents`; barrier; `DoPostCurrentUpdates` (N); `Apply2Current` (N). That is
**2 + 6·N barriers per timestep** for N extensions (patch x5: 1 excitation, 6 Mur faces and
the lumped-RLC extension of the port's feed resistor, which stock keeps with no active cell
because its `BuildExtension` returns true: N = 8, 50 barriers; notch: 38), each costing a
kernel round trip, and thread 0 incremented `numTS` after the last hook
with no barrier before the other threads' next timestep (a benign race in practice).

**New.** `SpinBarrier` is a generation-counter barrier: arrivals `fetch_add` a counter; the
last arrival optionally increments a caller-supplied counter (used for `numTS`), resets the
count and bumps the generation under the mutex; waiters spin on the generation with `yield`
(arm) / `pause` (x86) for up to `SpinTime()` (default 50 µs, `OPENEMS_BARRIER_SPIN_US`),
checking the clock every 128 spins, and only then park on the condition variable.

```cpp
void wait(volatile unsigned int* inc=NULL)
{
    const unsigned int gen = m_generation.load(std::memory_order_acquire);
    if (m_count.fetch_add(1, std::memory_order_acq_rel) + 1 == m_numThreads)
    {
        if (inc) ++(*inc);                       // numTS, before anyone is released
        m_count.store(0, std::memory_order_relaxed);
        { std::lock_guard<std::mutex> lock(m_mutex);
          m_generation.store(gen+1, std::memory_order_release); notify = m_sleepers>0; }
        if (notify) m_cond.notify_all();
        return;
    }
    const auto stop = steady_clock::now() + SpinTime();
    for (unsigned int n=1;;++n) {
        if (m_generation.load(std::memory_order_acquire) != gen) return;
        CpuRelax();
        if ((n%128)==0 && steady_clock::now()>stop) break;
    }
    /* park on m_cond until the generation changes */
}
```

`BuildHookPlan()` (called from `changeNumThreads` after `SetNumberOfThreads`, and again
from `IterateTS` whenever `m_Eng_exts` differs from the list the plan was built for) asks
every extension `GetUsedHooks()` and builds, per hook group, a list of `{ext, barrier,
inc_numTS}` steps:

- `LEGACY_HOOKS` (the base-class default `~0u`): the hook is called and followed by a barrier,
  and a barrier is forced after the previous step: the old behaviour.
- An extension that declares the group's flag: its hook is called; **pre/post hooks of all
  declaring extensions share one barrier at the end of the group** (they only read engine
  fields per the documented contract); `PREPOST_WRITES_FIELDS` (declared by the UPML, whose
  pre/post hooks swap field and flux) restores a barrier before and after that hook;
  `Apply2*` hooks keep one barrier per extension because they write fields in priority order.
- Extensions that do not declare a group are skipped entirely (no call, no barrier).
- The last barrier of the timestep (last `APPLY_CURR` step, else last `POST_CURR`, else the
  current-update barrier via `m_IncNumTS_AtCurrBarrier`) increments `numTS` inside the
  barrier, removing the stock race.

Barriers per timestep in the unfused plan become
`2 + [any PRE_VOLT] + [any POST_VOLT] + #APPLY_VOLT + [any PRE_CURR] + [any POST_CURR] + #APPLY_CURR`
(+2 per `PREPOST_WRITES_FIELDS` hook); patch x5: 50 → 18 at snapshot A (the lumped RLC did
not declare its hooks yet), 13 from ABCDEG to cg16, 12 with patch 0005 (one apply barrier each
for the RLC, the six Mur faces and the excitation, the shared pre- and post-voltage barriers,
the two update barriers). Declared hooks at patch 0005: excitation `APPLY_VOLT|LINE_HOOKS`
(+`APPLY_CURR` only when it has current excitations; before patch 0005 always); Mur
`PRE|POST|APPLY_VOLT` (+`LINE_HOOKS` when its fast path is on); UPML
`PRE|POST_VOLT|PRE|POST_CURR|PREPOST_WRITES_FIELDS` (+`LINE_HOOKS`); lumped RLC
`PRE_VOLT|APPLY_VOLT|LINE_HOOKS`; dispersive/Lorentz by ADE orders in use (cg12); Debye
`PRE_VOLT|POST_VOLT` plus the dispersive apply groups, no line hooks (patch 0005). Every other
extension (`Engine_Ext_Cylinder`, present on cylindrical meshes closed in alpha, the
cylindrical multigrid, TFSF, steady-state detection, `Absorbing_BC`) stays on `LEGACY_HOOKS`.

**Correctness.** Hook bodies are untouched; only barriers between hooks that do not write
engine fields are removed, so every cell still sees the same operands in the same order. The
plan is rebuilt when extensions are added after `Init` (the cylindrical multigrid does this;
snapshots A/AB were wrong there before the rebuild check, as the project log records).

**Reviewer notes.** The contract "pre/post hooks do not write engine fields" is enforced by
declaration only; a third-party extension that writes fields in a pre/post hook and declares
the flags without `PREPOST_WRITES_FIELDS` would race. Spinning 50 µs per barrier burns CPU
when a thread is descheduled (the E-core/P-core wait of 7-25 % noted in the project log).

## B. `UpdateVoltages_IJKN` / `UpdateCurrents_IJKN` (step 2)

**Files.** `FDTD/engine_sse_compressed.{h,cpp}` (+262/−2 for the whole file pair, cg13 and
patch 0005 included; the IJKN loops are ~125 lines, `ShiftLanesUp/Down`, `UseIJKN`, the old
loops renamed `*_Generic`).

**Stock.** `Engine_SSE_Compressed::UpdateVoltages` computed for every (x, y, zv)
`index = Op->m_Op_index(x,y,zv)`, `linearIndex(...)` for the volt and curr arrays through the
`ArrayLib` subscript operators, then `f4_volt[v].v *= vv[0][index].v; f4_volt[v].v +=
vi[0][index].v * (c1 - c2 - c3 + c4)` for the three polarisations, with the zv=0 (voltages) or
zv=nvec-1 (currents) vector handled after the loop with an `_mm_slli_si128` lane shift (or a
scalar copy without SSE2). Apple clang gives every store through the `f4vector` union the TBAA
type 'omnipotent char' (it may alias any object), so the loop, which reads strides and table
pointers through the array objects, reloads them after every store: in the stock v0.37.0
library 94 instructions per iteration (the three components of one z-vector), 44 of them loads
(21 vector loads) and 6 stores; 95, 44 and 6 for the currents
(`results/kernel_loop_instructions_2026-11-03.txt`, counted in the copy of the loop that runs).

**New.** Same arithmetic, written against the I-J-K-N layout with all loop invariants in
local `__restrict` pointers: `v = volt + x*sx + y*sy`, `c = curr + ...`, `ip = op_idx + x*isx +
y*isy`; the three components of a z-vector are `vz[0..2]`, the next z-vector is `+3`, the x/y
neighbours `-shx`/`-shy` (0 on the first line, as stock's `(pos>0)*stride`). The coefficients
come from the packed table (`pk[ip[z]].c[0..5]`, see cg13). The z-wrap uses
`__builtin_shufflevector` with a zero vector on clang/GCC ≥ 12:

```cpp
// x-polarization (voltages), z-vector z >= 1
t = cz[2].v - cz[2-shy].v - cz[1].v + cz[1-3].v;
a = vz[0].v * k[0].v;
vz[0].v = a + k[1].v * t;
...
// z-vector 0: the z-1 neighbours are the lanes below in the last z-vector
t = c[2].v - c[2-shy].v - c[1].v + ShiftLanesUp(ce[1]).v;   // {0, a0, a1, a2}
```

`UseIJKN()` checks `stride(0)==1`, `stride(3)==3` on both arrays, equal x/y strides,
`m_Op_index.stride(2)==1` and a filled packed table; otherwise (`OPENEMS_ENGINE_NIJK` builds,
`OPENEMS_NO_PACKED_COEFF=1`) the generic loops run. Instructions per iteration: 44 at snapshot
AB (project log); in the cg18 library (which also reads the packed tables) 41 with 16
loads and 3 stores, 42 with 15 loads for the currents (same results file).

**Correctness.** Per component the stock code is two statements, `v = v*vv` then
`v = v + vi*t` with `t = (c1 - c2) - c3 + c4` evaluated left to right; the new code is
`a = v*k0; v = a + k1*t` with the identical `t`. With clang's default `-ffp-contract=on` both
forms contract the second statement to `fma(k1, t, a)` after a rounded product, so the bit
patterns agree; this was verified rather than proven (probes, S-parameters and nf2ff dumps
identical on all bench models, and against the Swift/Metal mirror of the same loop). It holds
for clang. GCC's default `-ffp-contract=fast` (every C++ mode) contracts across statements: on
aarch64, and on x86-64 when FMA is enabled, it computes `fma(v, k0, round(k1*t))` for the new
form against stock's `fma(vi, t, round(v*vv))`, so a GCC build would be correct but not
bit-identical to stock. A bit comparison under GCC needs both builds made with
`-ffp-contract=off` (upstream's Debug flags already add it). Measured in the standalone kernel
(`scripts/kernel/kb_idx.cpp`, which holds a copy of the stock loop and the rewrite; Apple clang
21 and GCC 16.2, both `-std=c++17 -O3 -DNDEBUG`, three grids, five rounds;
`results/kernel_gcc_vs_clang_2026-11-03.txt`): the stock loop's final fields are the same under
both compilers, and the rewrite equals the stock loop bit for bit under clang and differs from
it under GCC on every grid and round. A GCC build of openEMS was not made, so the effect on
whole runs was not measured.

**Compilers and speed.** Upstream's FAQ advises GCC on macOS because clang's code for the SSE
engine is slow. In the same kernel GCC's stock loop does not reload the strides and pointers
(80–82 instructions, 29 loads: the 21 vector loads, the operator index and 7 reloads of spilled
registers; `results/kernel_loop_instructions_2026-11-03.txt`), and at one thread GCC runs it
1.16–1.39× faster than Apple clang, while the rewrite runs at about the same speed with both:
the rewrite's one-thread gain in the kernel is 1.74–1.80× with both loops built by clang and
1.26–1.47× with both built by GCC. Whole runs with GCC were not measured; the paper's factors
are against the clang-built stock.

**Bytes per cell.** Unchanged versus stock: per update 12 B read + 12 B write of the updated
field, 12 B read of the other field (neighbours come from cache), 1 B of index: 37 B, so
74 B/cell/timestep for both updates (with the index as allocated, up to 4 B: 40 B and 80 B).
Item B removes instructions, not traffic.

## C. Work stealing per x-line and the automatic thread count (step 2 / step 3)

**Files.** `FDTD/engine_multithread.{h,cpp}`: `WorkRange`, `UpdateStealing`, `ResetRanges`
(unfused path); `StartThreads`, `ThreadTuner`, `RunTimesteps`, `TuneThreads`, the rewritten
`IterateTS`; `FDTD/engine_cylindermultigrid.cpp` (+15).

**Stock.** Each worker updated the fixed x-slab `[m_start, m_stop]` from
`Operator_Multithread::CalcStartStopLines` (equal line counts). With `--numThreads=0`
(the default) `Init` set `m_opt_speed=true, m_numThreads=1`, and `NextInterval()`, called from
`openEMS::RunFDTD`'s progress report (about every 4 s), added one thread per call until the
reported speed fell, then stepped back one: a 1→N ramp. In the step-1 tables
(`results/*_step1.txt`) the default was 37-41 % slower than the best fixed count on the two
large models (15-20 s runs), 22 % on the 17.5 s notch tutorial run and 8 % on the 4 s patch
tutorial.

**New (unfused path).** Per thread a cache-line padded `WorkRange {atomic<int> next; int
start, stop;}` for voltages and for currents (the last thread's current range ends one line
early, as stock's `m_stop_h`). A thread grabs lines with `fetch_add(1, relaxed)` from its own
range, then from the other threads' ranges in round-robin order; thread 0 re-arms the ranges
after the following barrier. Order of lines within one update is irrelevant (the voltage
update reads only currents and vice versa), and each line is written by exactly one thread.

**New (auto thread count).** `Init` with `m_numThreads==0` sets `m_auto_threads` and starts
at `StartThreads()` = `hw.perflevel0.physicalcpu` (the P-core count; `#ifdef __APPLE__`
`sysctlbyname`), else `(max+1)/2`. The to-do list is P+2, P+4, … (clamped to the maximum),
then P−2. Patch 0005 clamps the maximum to the number of x-lines, but only for the larger
candidates: P−2 and the start itself stay unclamped (on a model with fewer x-lines than that,
`changeNumThreads` reduces the count and the reduced count is timed again). Patch 0006 clamps
every candidate, P−2 and the start included. `IterateTS` runs, while tuning, in pieces of `window/8` timesteps (`window` =
`OPENEMS_TUNE_WINDOW_MS`, default 150 ms; first piece 4 timesteps to estimate the speed),
calling `BalanceSlabs()` and `TuneThreads()` after each piece. `TuneThreads` ignores a settle
time of 0.4·window after each thread change, accumulates ≥ window of timing, records
timesteps/s per count, drops all larger counts once a count is below 85 % of the best, and
after the coarse list tries best±1 once (`refined`); it then switches to the best count and
prints "Best performance found using N threads". The old `NextInterval` ramp is kept only for
`Engine_CylinderMultiGrid`, whose `IterateTS` runs in an iterator thread: its `Init` sets
`m_auto_threads=false, m_opt_speed=true, m_numThreads=1`, and the inner (child) engine is pinned
to one thread (`m_auto_threads=false; changeNumThreads(1)`), accessed through the existing
`friend class Engine_CylinderMultiGrid`.

**Correctness.** Thread count and line assignment do not enter the arithmetic. The split of
`IterateTS` into pieces changes only when the host loop sees control back; `numTS` is unchanged.

**History.** Work stealing and the tuner with its 150 ms windows are from item C (snapshot
ABCDEG); slab balancing followed right after ABCDEG and is in every cg snapshot; the window/8
pieces and the search order (P, P+2, …, P−2, ±1) came with cg7 and cg8.

**Reviewer notes.** The search needs ~1.5 s and costs short benches 15-25 % (project log).
Speed vs threads is not monotonic on a 4P+6E part (notch x3 at cg8: 4:1791, 5:1564, 6:1800,
7:1919, 8:2022, 9:1901 MC/s; project log), hence the coarse step of 2 and the ±1 refinement.
In the fused path work stealing is not used; load balance comes from `BalanceSlabs` (below).

## D. Mur fast path and UPML f4vector path (step 2)

**Files.** `FDTD/extensions/engine_ext_mur_abc.{h,cpp}` (+267 total, of which `SetupFast`,
`MurFast`, `Do*Fast` ≈ 130 lines), `FDTD/extensions/engine_ext_upml.{h,cpp}` (the
`SetupVectorized`, `Do*Rows`, `UPML_Blend` part ≈ 280 lines of the +722 total).

**Stock Mur.** Templated hooks (`ENG_DISPATCH_ARGS` on the engine type) loop over the face
cells (i, j) and call `eng->GetVolt(n, pos)` / `SetVolt`, which for the SSE engines compute
`f4_volt(n,x,y,z%numVectors).f[z/numVectors]` per access (two integer divisions and the 4-D
subscript). Pre: `m_volt_nyP(i,j) = V(nyP, shifted) - coeffP(i,j)*V(nyP, pos)`; Post:
`m_volt_nyP += coeffP*V(nyP, shifted)`; Apply: `V(nyP,pos) = m_volt_nyP`; likewise nyPP.

**New Mur (`m_Fast`).** `SetupFast()` (once `m_Eng` is known, from `SetNumberOfThreads`)
computes for every face cell the float index of component 0 in the f4vector array
(`4*linearIndex({0,x,y,z%nvec}) + z/nvec`) and checks that the offsets to component nyP,
component nyPP and the shifted line are the same constants for all face cells
(`m_OffsetNyP/NyPP/Shift`); if not, `m_Fast` stays false and the template path is used. The
hooks then run over the thread's row range with:

```cpp
inline void Pre(size_t k) const { const float* e = E + fi[k];
    vP[k]  = e[oP+oS]  - cP[k]  * e[oP];
    vPP[k] = e[oPP+oS] - cPP[k] * e[oPP]; }
inline void Post(size_t k) const { const float* e = E + fi[k];
    vP[k]  += cP[k]  * e[oP+oS];   vPP[k] += cPP[k] * e[oPP+oS]; }
inline void Apply(size_t k) const { float* e = E + fi[k];
    e[oP] = vP[k];  e[oPP] = vPP[k]; }
```

Same three float operations per cell and hook as the template, same coefficient arrays
(`m_Mur_Coeff_nyP/nyPP`) and save arrays (`m_volt_nyP/nyPP`), only the addressing changed.

**Stock UPML.** Templated per-cell loops over the PML box (`m_StartPos`, `m_numLines`) with
`GetVolt/SetVolt` per component and six per-cell coefficient arrays `vv, vvfo, vvfn, ii, iifo,
iifn` (`ArrayNIJK<float>`, 72 B per cell) plus `volt_flux/curr_flux`. Threads split the box's
x-lines, which for a PML slab of 8 lines means at most 8 busy threads.

**New UPML (`m_Vec`).** `SetupVectorized()` accepts only SSE engines with I-J-K-N strides and a
PML box that spans the whole z range (`m_StartPos[2]==0 && m_numLines[2]==Nz`), because only
then every f4vector of the box belongs entirely to the PML. It copies the six coefficient
arrays and both flux arrays into f4vector arrays in engine order
(`index ((x*Ny+y)*nvec+v)*3+n`, lane l = z/nvec) and builds a per-z-vector lane mask (lanes
with `l*nvec+v >= Nz` are padding). The hooks run per (x, y) row over `3*nvec` vectors; rows
are split across threads with `AssignJobs2Threads(NX*NY, ...)` instead of x-lines:

```cpp
const v4sf E = e[k].v, F = flux[k].v;
const v4sf p = -(c.vvfo.v * F);
const v4sf f = c.vv.v * E + p;
e[k].v = UPML_Blend(m_f4_LaneMask[k/3].v, F, E);   // padded lanes keep E
flux[k].v = f;
```

`UPML_Blend` is a bitwise select (`(a & m) | (b & ~m)`), guarded by `#if defined(__GNUC__) ||
defined(__clang__)` (`UPML_F4VECTOR`); MSVC builds do not compile the vector path, so from cg11
on they run every PML box on the scalar-SSE rows (`SetupScalarSSE`, not compiler-guarded).

**Correctness.** Mur: identical expressions on identical operands. UPML: the scalar template
computes `f_help = vv*V - vvfo*flux`; the vector form `p = -(vvfo*F); f = vv*E + p` pins the
contraction to "round the second product, fuse the first" for clang (`-ffp-contract=on`), which
is what clang emitted for the scalar line (verified bit-identical on the bench models and the
18-dataset cylindrical case; the choice is the compiler's, so the source alone does not prove
it). GCC's cross-statement contraction fuses `vvfo*F` instead and rounds `vv*E`, so a GCC build
would differ from stock in the last bit there (see B; no GCC build of openEMS was made). Per
cell-component the PML update touches only its own V and flux, so the loop order (rows, then
component) does not matter.

**Reviewer notes.** Non-full-z PML boxes (z-only slabs such as ksma's `PML_8`, and the two
z-face slabs of a 6-sided PML, which cover only the interior x-y region; edges and corners
belong to the full-z x and y slabs) fell back to the template until cg11. The f4vector copies
double the PML coefficient memory until cg14 frees them. Net against stock: the operator
extension keeps its scalar coefficient and flux arrays, the vector path keeps its f4vector flux
copies, and cg14 adds a table index (per cell-component on the scalar path, per z-vector
component on the vector path), so a PML cell holds more memory than in stock; the gain is in
traffic, not memory.

## E. Fused E/H sweep (step 2) with line hooks for excitation and lumped RLC

**Files.** `FDTD/engine_multithread.{h,cpp}`: `SetupFused`, `FusedTimestep`,
`FusedCurrents`, `RunLineHooks`, `BalanceSlabs`, `FusedStat`; `engine_extension.h` line-hook
virtuals and `GetCoupledLines`; `engine_ext_excitation.{h,cpp}` (+59/−8: `SortByLine`,
`*Lines`, `Impl(order, n0, n1)`, the patch-0005 `GetUsedHooks`); `engine_ext_lumpedRLC.{h,cpp}` (+110/-25: `Rotate`,
`RotateOnce`, `LineRange`, `UpdateInductorCurrents`, `*Lines`).

**Stock.** Two full passes over the grid per timestep: all voltages (all threads), barrier,
hooks, all currents, barrier. Each pass streams both fields once (74 B/cell, see B).

**New.** When every extension declares `LINE_HOOKS` (else a verbose message names the
offender and the unfused plan runs; the cylindrical multigrid prints it once since patch 0006)
and `UseIJKN()` holds, `SetupFused` partitions the x-lines
into blocks (`OPENEMS_FUSED_BLOCK` lines each, default 1; a line listed by
`GetCoupledLines()` is always in the same block as x+1; the block size is halved until there
are ≥ 4 blocks per thread) and assigns contiguous block ranges (slabs) to threads. Each thread
then runs per timestep:

```cpp
for (unsigned int b=b0; b<b1; ++b) {
    const unsigned int x0 = m_Blocks[b], x1 = m_Blocks[b+1];
    RunLineHooks(0, x0, x1);  UpdateVoltages(x0, x1-x0);          // pre-volt hooks, V
    RunLineHooks(1, x0, x1);  RunLineHooks(2, x0, x1);            // post-volt, apply-volt
    FusedCurrents((x0==start) ? x0 : x0-1, x1-1);                 // pre-curr, I, post-curr, apply-curr
}
stat.busy += elapsed; stat.lines += m_Blocks[b1]-start;
m_IterateBarrier->wait();
if (start>0) FusedCurrents(start-1, start);    // the line before the slab (its V came from the previous thread)
m_IterateBarrier->wait(&numTS);
```

The dependency argument (comment in the code): V(x) reads I(x) and I(x−1); I(x) reads V(x)
and V(x+1). After the voltages and voltage hooks of block [x0, x1) are final, the currents of
lines x0−1 … x1−2 have all their operands final and their old values are no longer needed by
any voltage of this timestep (V of lines ≥ x1 reads I(x1−1) and up, which are updated later).
The last line of each slab waits for the next thread's first block, hence the first barrier;
line NX−1 is never updated (as in stock). **Two barriers per timestep**, and the currents of a
line are updated while its voltages and the neighbouring currents are still in L1/L2, so both
fields stream once: 12+12 (V r/w) + 12+12 (I r/w) + 1 (index) = **49 B/cell** instead of 74
(52 instead of 80 with the index as allocated, see the layout note at the top).

Line hooks: `RunLineHooks(g, x0, x1)` calls `Do*Lines(x0, x1)` of the extensions declaring
group g, in the hook-plan order (pre groups reversed). The excitation sorts its entries by
x-line once (`std::stable_sort` on `Volt_index[0]`, so two entries on the same cell keep their
order), finds the entries of [x0, x1) with `lower_bound`, and runs the unchanged soft-source
body for them on the `Engine_sse` instantiation. The lumped RLC does the same with its
elements; its container rotations (`v_Vdn`, `v_Jn` shift once per timestep) are done by the
first line hook of a timestep through `RotateOnce(std::atomic<int> stamp, ...)`
(mutex + timestep stamp compared with `GetNumberOfTimesteps()`), the other threads skip it.

`BalanceSlabs()` runs after every `IterateTS` piece when `m_Balance` (default on,
`OPENEMS_BALANCE=0` off, off for one thread): once the threads have accumulated ≥ 20 ms of
sweep time on average, it estimates a cost per x-line (`busy/lines`, smoothed 0.5/0.5 with the
previous estimate), integrates it, and moves the slab boundaries to equal cumulative cost on
block boundaries, keeping them monotone and leaving at least one block per thread. This is
how P/E-core speed differences and the expensive PML lines are absorbed.

**Correctness.** Every cell sees exactly the same operands as in the unfused update: the
operand analysis above, plus the contract that a line hook touches only its own lines (and the
coupled x+1 line). Hook order per cell is unchanged (pre, update, post, apply, then the
current side), and extension priority order within a group is preserved by `m_LineHooks[g]`.
The unfused and fused builds were compared bit-identically on all models.

**Reviewer notes.** Block sizes > 1 lose the L2 reuse and were measured slower on ksma
(−14 % at 4, −26 % at 16 lines; project log), so the knob stays at 1. `*CurrentLines()` is
never called for x = NX−1 (documented in `engine_extension.h`); a future extension with real
current-side work on that line would differ from the unfused path. Fallbacks: any extension
without line hooks disables the fusion for the whole run: the `LEGACY_HOOKS` ones
(`Engine_Ext_Cylinder`, present on cylindrical meshes closed in alpha, the cylindrical
multigrid, TFSF, steady-state detection, `Absorbing_BC`) and, since patch 0005, Debye materials. So does a
missing packed table (`OPENEMS_NO_PACKED_COEFF`, or a failed allocation, through `UseIJKN`).
Through patch 0005 `SetupFused` returned silently in that case; with patch 0006 the engine says
that the fused sweep is off because there are no packed tables.

## Field_Gather_SSE (step 3)

**Files.** `FDTD/engine_field_gather.{h,cpp}` (+58), `FDTD/engine_interface_fdtd.cpp` (+6/-3).

**Stock (upstream gpu-engine).** `Field_Gather_FDTD` precomputes, per dump node and
component, four flat array indices `idx[4]` and deltas, and `Evaluate()` interpolates straight
from a flat `ArrayNIJK<float>` field. `Engine_Interface_FDTD::CreateFieldGather` only built it
when `GetBasicFieldArrays()` succeeded (GPU engine host mirror only; the basic engine also
reads node by node). The SSE engines returned
false, so every dump (nf2ff faces, field dumps) read node by node through virtual
`GetVolt/GetCurr` with the z%nvec / z/nvec arithmetic; on the patch tutorial this was ~48 % of
the run.

**New.** `Field_Gather_SSE::New` builds the basic gather (with NULL arrays), then rewrites
each entry index from the N-I-J-K flat index to a float offset into the f4vector array:

```cpp
const unsigned int z = i%N[2]; i/=N[2]; const unsigned int y = i%N[1]; i/=N[1];
const unsigned int x = i%N[0]; i/=N[0]; const unsigned int n = i;
entry.idx[m] = 4*V->linearIndex({n, x, y, z%nvec}) + z/nvec;
```

`Evaluate()` passes `(const float*)f4_volt_ptr->data()` (or curr) as source. Guards: both field
arrays < 2^32 floats and identical strides, else NULL (node-by-node fallback). Dispatch:
`if (m_Eng->GetType()==Engine::SSE)`.

**Correctness.** The same floats are read and the same upstream interpolation code runs, so
dumps are bit-identical (nf2ff HDF5 compared with `scripts/checks/h5cmp.py`, results in the
project log).

## Mur line hooks (step 3, rebuilt in cg4)

**Files.** `engine_ext_mur_abc.{h,cpp}`: the `m_Vec*/m_Sc*` tables in `SetupFast`,
`Do*VoltageUpdatesLines`, `Apply2VoltagesLines`, `GetCoupledLines` (~100 lines of the +267).
The line hooks themselves came with the fused sweep (E, snapshot ABCDEG); cg4 rebuilt them in
memory order with the vector entries below.

**Mechanism.** `SetupFast` also buckets the face cells by x-line and sorts each bucket by
float index (memory order). When the three offsets are multiples of 4 floats (whole
f4vectors, true for x- and y-faces) and four consecutive cells of a bucket occupy the four
lanes of one f4vector (`f%4==0 && FloatIndex[cells[n+3]]==f+3`: cells z, z+nvec, z+2·nvec,
z+3·nvec of an x- or y-face, not four neighbouring z cells), they become one vector entry
with lane-wise coefficient vectors `m_VecCoeffP/PP` and save vectors `m_VecP/PP`; the rest (all cells of z-faces, partial vectors) stay scalar entries
`m_Sc*`. Per line x the hooks process `m_VecStart[x]..m_VecStart[x+1]` vectors then
`m_ScStart[x]..m_ScStart[x+1]` scalars:

```cpp
const f4vector* e = E4 + m_VecIndex[g];
m_VecP[g].v  = e[oP+oS].v  - m_VecCoeffP[g].v  * e[oP].v;   // Pre, four cells at once
m_VecPP[g].v = e[oPP+oS].v - m_VecCoeffPP[g].v * e[oPP].v;
```

`GetCoupledLines` reports `min(m_LineNr, m_LineNr_Shift)` for x-faces (`m_ny==0`), so the
face line and the line it reads are swept as one block. `GetUsedHooks` adds `LINE_HOOKS` only
when `m_Fast`.

**Correctness.** Lane-wise the vector form is the scalar `a - c*b` (one fmsub per lane, the
same contraction as the scalar fast path, verified). The line hooks keep their own save arrays
(`m_VecP`, `m_ScP`) so the threaded fast path and the line path never share state.

## Setup threading and setup timing (cg9)

**Files.** `FDTD/operator.{h,cpp}` (+203/−75 with the cg12 and patch-0005 changes),
`FDTD/operator_multithread.{h,cpp}`,
`FDTD/operator_cylinder.{h,cpp}` (signature), `FDTD/extensions/operator_ext_excitation.cpp`
(+2), `FDTD/operator_sse.h` (`GetNumVectors`).

**Stock.** `Operator::CalcECOperator` ran `Calc_ECOperatorPos` for every (n, x, y, z) on one
thread through the shared `AdrOp MainOp->SetPos()`; `CalcTimestep_Var3` likewise walked all
cells with `MainOp->Shift/GetShiftedPos` (the address operator keeps state, so it is not
thread-safe); `GetDiscDelta()` recomputed a mesh delta from `discLines` on every call;
`Calc_ECPos/Calc_EffMatPos/AverageMat*/GetMaterial` took `std::vector<CSPrimitives*>` **by
value** (a copy per call, several per cell); `GetMaterial` called CSXCAD's
`GetPropertyByCoordPriority` for every (coordinate, material type), i.e. the point-in-primitive
test ran twice per coordinate (eps+kappa, mue+sigma); `Operator_Multithread::CalcECOperator`
used the user's thread count for its setup pool.

**New.**
- `Calc_ECOperatorPos` computes the linear index arithmetically
  (`pos[0] + pos[1]*Nx + pos[2]*Nx*Ny`, the value `SetPos` returns) and the loop is split into
  x-ranges over `GetNumSetupThreads()` `std::thread`s (every cell writes only its own entries).
- `CalcTimestep_Var3` is split into z-ranges; each thread keeps its own `Best {dT, n, pos}`;
  the shifted indices are computed with a clamp that reproduces `SetReflection2Cell`
  semantics; the results are combined "smaller dT wins, on a tie the smaller n, then the lower
  z-range", which is the first cell in the stock loop order (n, z, y, x).
- `Init_EC` tabulates `CalcDiscDelta()` into `m_DiscDelta[3][2]`; `GetDiscDelta` reads the
  table; `Reset()` and `SetupCSXGrid()` clear it (the latter is one of the cg12 hardenings).
- `vPrims` is passed by `const&` through the averaging chain (ABI note below).
- `GetMaterial` keeps a `thread_local` last-lookup cache keyed by the three coordinates, the
  vector's data pointer, size, first and last primitive (the first/last keys are the second
  cg12 hardening against a reused vector address); only lookups with `markAsUsed` are cached.
- `Operator_Multithread::CalcECOperator` always uses `AvailableThreads()` for the setup pool;
  the engine still gets the user's count (`m_orig_numThreads`, already in stock). So the setup
  uses every core whatever `numThreads` says (stock used the user's count); documented in
  BUILD.md, not changed.
- `Operator_Ext_Excitation::BuildExtension` skips a (y, z) line when
  `GetPrimitivesByBoundBox(-1, y, z, EXCITATION)` is empty.
- `SetupTimer` (`OPENEMS_SETUP_TIMING=1`) prints laps to stderr: Init_EC, Calc_EC (material
  averaging), CalcTimestep, InitOperator, Calc_ECOperatorPos, ApplyElectricBC, CalcPEC,
  Calc_LumpedElements, ApplyMagneticBC, and one per `BuildExtension <name>`.

**Correctness.** Pure refactoring of index arithmetic and caching; the double-precision
operator values are computed by the same code per cell. Measured (project log, not in
`results/`): patch x5 setup 4.1 → 0.9 s with 4 engine threads, that is a setup pool of 4 threads
in stock against all 10 cores in the fork.

**Reviewer notes.** Material averaging (`Calc_EC`, the `IsInside` tests) was already threaded
upstream and remains the dominant setup cost. `GetNumSetupThreads()` is 1 for the base
`Operator` (single-threaded engines keep single-threaded setup).

## nf2ff separable far-field sum (cg9)

**Files.** `nf2ff/nf2ff_calc.{h,cpp}` (+143/−9: `CalcPlaneSeparable`, branch in
`AddSinglePlane`), `nf2ff/CMakeLists.txt` (+4, `-framework Accelerate` on APPLE).

**Stock.** Per plane, per thread (x-range), per direction (θ, φ) and per cell:
`r_cos_psi = Σ (line − center)·dir`, `exp_jkr = exp(j k r_cos_psi)` (one complex exp per
cell and direction), then four complex accumulations into per-thread `complex<double>`
`Nt, Np, Lt, Lp`: cost O(N_dir × N_cells) complex exponentials (patch x5 3-D pattern: 17.9 s,
project log).

**New.** For a Cartesian plane (`MeshType==0`, unless `OPENEMS_NF2FF_LEGACY`) the phase
factor separates, `exp(jk(a(x_i−c_x) + b(y_j−c_y) + c(z_0−c_z))) = Q_i · P_j · e_z`, so the
surface integral becomes `Σ_i Q_i Σ_j P_j F_c(i,j)`. The code builds `F[6][NP][NPP]`
(J_s = n×H, M_s = −n×E components), per-direction phasor rows `P[d][j] = Δ_PP[j]·exp(jk d_PP
y_j)` and `Q[d][i] = Δ_P[i]·exp(jk d_P x_i)·exp(jk d_ny x_0)`, and for blocks of directions
(`block = max(16, min(N_dir, 2^21/(6·NP)))`) one `cblas_cgemm` `G = P · F^T`
(nd × 6NP × NPP), followed by the row dot `S_c = Σ_i Q_i G[c,i]` accumulated in
`complex<double>` and the θ/φ projections (eq. 8.23/8.24 of the original comments) added to
the plane's `Nt, Np, Lt, Lp`. `NF2FF_HAVE_CBLAS` is defined only under `__APPLE__` (Accelerate):
since patch 0005 a build without it never takes the separable path and keeps the threaded
legacy loop; the plain triple loop that stands in for `cgemm` there is compiled but
unreachable. Patch 0006 bounds the per-block work buffer (through patch 0005 the block size
was bounded through NP only, so on a face with few lines along NP the phasor buffer P,
block × NPP, grew with NPP and the number of directions) and makes the Accelerate include
build with GCC on macOS.

**Correctness: not bit-identical, by design.** Products of two complex exponentials replace
one exponential of a sum, the summation order is the BLAS kernel's, and the inner sum is in
float (stock accumulated in double per thread). The project log has a 7e-7 relative difference
against the legacy path; the legacy path in the same build is bit-identical to stock. On
cg18 (`results/correctness_cg18_2026-11-03.txt`: the patch tutorial's dumps, two cuts and
a 3-D pattern of 91 × 181 directions at two frequencies) the separable path differs from stock
by 4.5e-7–6.8e-7 of the maximum in E_θ, E_φ and P_rad, by 1.5e-7–2.5e-7 in Dmax and not at all
in Prad, and the legacy path (`OPENEMS_NF2FF_LEGACY=1`) is bit-identical to stock; CalcNF2FF of
the 3-D pattern takes 1.21 s with stock, 0.30 s with the separable path and 0.90 s with the
legacy loop of the same build. The cylindrical mesh (`MeshType==1`) keeps the legacy loop
because its phase does not separate.

**Reviewer notes.** The separable path runs on the calling thread (the nf2ff thread pool is
now only used by the legacy loop); Accelerate may parallelise `cgemm` internally.

## CSXCAD changes (cg9)

**Files.** `src/ContinuousStructure.{h,cpp}` (+7), `src/CSPropMaterial.cpp` (+2).

```cpp
CSProperties* ContinuousStructure::GetPropertyByCoordPriority(const double* coord, std::vector<CSPrimitives*> primList, ...)
{   return FindPropertyByCoordPriority(coord, primList, markFoundAsUsed, foundPrimitive); }
CSProperties* ContinuousStructure::FindPropertyByCoordPriority(const double* coord, const std::vector<CSPrimitives*>& primList, ...)
{   /* the original body: first primitive whose IsInside(coord) is true */ }
```

The by-value overload is kept and forwards, so the exported symbol and the ABI of
`libCSXCAD` are unchanged; openEMS calls the new `const&` entry from `GetMaterial` and
`CalcPEC_Range`. `CSPropMaterial::GetWeight(ParameterScalar&, coords)` returns
`ps.GetValue()` immediately when `!ps.GetMode()` (plain number, no weighting expression);
stock first computed the seven parameter values (`sqrt`, `atan2`, `asin`, `atan`) and then
`GetEvaluated()` returned `dValue` anyway when `ParameterMode==false`, so the value is
identical. Weighted materials take the old path unchanged.

## Allocator stagger against the allocation-placement valley (cg10)

**Files.** `tools/arraylib/impl/allocator.h` (+43/−6 through patch 0005; patch 0006 rewrote its
comments and the `OPENEMS_NO_STAGGER` test). Platform-independent (not Apple-guarded).

**Stock.** `ArrayLib::AlignedAllocator<T>::alloc` called `posix_memalign` (or `_mm_malloc`)
with alignment `sizeof(void*)` or the next power of two ≥ `sizeof(T)`, so the system decides
where two large arrays of the same size, the voltages and the currents, land relative to each
other (on macOS 27.0.1 large blocks start on a 16 KiB boundary).

**What is seen.** In the published PEC-box sweep (`results/cache_valley_2026-11-01.txt`,
installed cg16 build, one thread, nz = 20, 2000 steps) the boxes of 200 k–338 k cells ran at
246.8–249.5 MC/s with `OPENEMS_NO_STAGGER=1` against 881–894 MC/s staggered, while the nearest
sizes outside, 162 k and 392 k cells, ran at 891.7 and 890.7 MC/s without the stagger: about
3.6× (one more point is low without the stagger, 72 k cells at 772.2 against 948.5 MC/s; one
run, not re-measured). A finer sweep on cg18 (`results/cache_valley_placement_2026-11-03.txt`,
section 3, two rounds) gives without the stagger 239.9–240.9 MC/s at 176 720, 184 320 and
338 000 cells (field arrays of 2 120 640–4 056 000 B) and 864.9–890.5 at 162 000–172 980 cells
(1 944 000–2 075 760 B) and at 348 480–369 920 cells (4 181 760–4 439 040 B); with the stagger
867.7–899.7 at every size, so outside the valley the stagger changes nothing measurable. The
valley holds the models whose field arrays are about 2–4 MiB each: about 0.175–0.35 M cells at
12 B per cell and array (nz a multiple of 4), 4.2–8.4 MB of fields. Stock v0.37.0 has it too
(`results/cache_valley_stock_2026-11-03.txt`, the same sweep on 2026-11-03): 213.4–215.3 MC/s
at 200 k–338 k cells against 461.2–474.6 at 162 k and 392 k, 2.1–2.2× deep, at about half the
fork's speed outside it.

**What triggers it.** Section 1 of the placement file (`scripts/cache_valley/place.c`, two
consecutive `posix_memalign` blocks of S bytes, macOS 27.0.1's libmalloc): S = 1 MiB, the
second block right after the first; S = 2 031 360 B to 2 MiB, 5.94–6.0 MiB below it;
S = 2 MiB + 16 B to 3 000 000 B, 4 MiB + 16 KiB after it; S = 4 181 760 B and 4 MiB, exactly
4 MiB after it; S = 4 MiB + 16 B to 8 000 000 B, 8 MiB + 16 KiB after it. The slow openEMS
sizes are those placed 4 MiB + 16 KiB apart; exactly 4 MiB (348 480 cells) and 8 MiB + 16 KiB
(from 353 780 cells) are fast, and so are the sizes below 2 MiB. Every distance is a multiple
of 16 KiB, the fast ones included, so 16 KiB set aliasing alone does not explain the valley;
the hardware mechanism was not identified. Section 2 (`scripts/kernel/kb_idx.cpp`,
110 × 110 × 20, one thread, three rounds; the current array sits 8224 KiB, two 4 MiB + 16 KiB
steps, after the voltage array and is moved by `KB_PAD` bytes): no offset, stock loop
210–211 MC/s and rewritten loop 233–234; 256 B, 366 and 439–440; 512 B, 455–459 and 779–793;
1 KiB to 64 KiB, 16 and 32 KiB included, 457–464 and 794–819. So at this shape 512 B or more
removes the slowdown and 256 B part of it. The valley was seen with macOS 27.0.1's libmalloc
on the M5 only; other allocators place large blocks differently, so the size window, and
whether there is one, depends on the platform.

**New.** Every allocation of ≥ 256 KiB with alignment ≤ 256 B is made larger by a
per-allocation offset and the array starts that far into the block; the base pointer is stored
in the word before the array and recovered in `free` (which re-derives the same alignment and
the same `StaggerApplies` decision from `numelem*sizeof(T)`). As of patch 0006:

```cpp
static const size_t STAGGER_MIN_BYTES = 256*1024;
static const size_t STAGGER_SPAN = 16384;   // offsets from 256 B to just under 16 KiB
static const size_t STAGGER_STEP = 2560;    // consecutive large arrays move 2560 B against each other (mod the span)
inline bool StaggerApplies(size_t bytes, size_t alignment)
{
    static const bool disabled = /* OPENEMS_NO_STAGGER set, not empty and not "0"; read once */;
    return !disabled && (bytes >= STAGGER_MIN_BYTES) && (alignment <= 256);
}
inline size_t StaggerOffset(size_t bytes, size_t alignment)
{
    static std::atomic<unsigned> counter{0};
    if (!StaggerApplies(bytes, alignment)) return 0;
    const unsigned k = counter.fetch_add(1);
    return 256 + (size_t)((k * STAGGER_STEP) % (STAGGER_SPAN - 256));
}
// alloc: posix_memalign(&base, alignment, bytes + offset); buf = base + offset; if (offset) ((void**)buf)[-1] = base;
// free:  base = StaggerApplies(numelem*sizeof(T), alignment) ? ((void**)ptr)[-1] : ptr; std::free(base);
```

Offsets are 256 + (2560·k mod 16128): 256, 2816, 5376, 7936, 10496, 13056, 15616, 2048, …;
since gcd(2560, 16128) = 256 the sequence visits 63 distinct multiples of 256 B before
repeating. The offset is a multiple of 256, so the returned pointer keeps any alignment ≤ 256
(f4vector needs 16). Cost: < 16 KiB per large array. `OPENEMS_NO_STAGGER=1` disables it
(read once, `static const`; from patch 0006 on `=0` or empty counts as unset). It applies to
every `ArrayLib` array ≥ 256 KiB (fields, operator index, flux arrays), not only the two field
arrays. The allocator is a header that out-of-tree code compiles in, so the stagger is an ABI
change: together with the base's ArrayLib `m_owner` member it makes the libraries
ABI-incompatible with v0.37.0 builds, and after an install over another build both Python
modules must be rebuilt (BUILD.md).

**Correctness.** Addresses only; no arithmetic changes. Verified bit-identical on six models
and the cylindrical case.

**Reviewer notes.** The 2026-10-29 project log recorded that offsets of 16/32 KB did not help
and 256 B–4 KB did, which was read then as L1 set aliasing, and patch 0003's comments said
so; the kernel test of 2026-11-03 at 110 × 110 × 20 does not reproduce it (16 and 32 KiB remove
the slowdown like 1–8 KiB do), and patch 0006 rewrote the comments. The stagger itself is
unchanged since cg10. It is global to the process (a counter), so the offset of a given array
depends on allocation order.

## UPML scalar SSE path for non-full-z PML boxes (cg11)

**Files.** `engine_ext_upml.{h,cpp}`: `SetupScalarSSE`, `UPML_SSE_ROW_SETUP`,
`Do*SSERows` (~250 lines), `LineRows`, the `m_Sse` branches in the threaded hooks and
`Do*Lines`.

**Stock / before cg11.** A PML box that is not a full-z slab (ksma's z-only `PML_8` slab, the
two z-face slabs of a 6-sided PML) ran the template with per-cell `GetVolt/SetVolt`
(4-D subscript, `z%nvec`, `z/nvec` per access) and, in the multithreaded engine, forced the
unfused plan with barriers around each UPML hook.

**New.** For SSE engines with I-J-K-N strides, `SetupScalarSSE` precomputes per local z the
float offset inside an (x, y) row of f4vectors, `m_zoff[lz] = 12*(z%nvec) + z/nvec` (three
components × four lanes = 12 floats per z-vector), and `m_Sse=true`. The hooks iterate rows
`r = lx*NY + ly` (split across threads, and by `LineRows` for the line hooks), components n,
then z, with the field accessed as `en[zo[lz]]` and the flux/coefficient rows contiguous:

```cpp
float& V = en[zo[lz]];
const FDTD_FLOAT f_help = vv[lz] * V - vvfo[lz] * flux[lz];   // literally the template's expression
V = flux[lz];
flux[lz] = f_help;
```

`GetUsedHooks` adds `LINE_HOOKS` when `m_Vec || m_Sse`, so such models now run the fused
sweep (ksma 1 thread 202 → 405 MC/s, `results/ksma_s1_n4000_smax.txt` and
`ksma_s1_n20000_cg11.txt`). Of the test models only ksma, with its top z slab, takes this path.
The notch tutorial run with `PML_8` requested on all six faces
(`results/notch_s1_n8000_pml6.txt`, stock 173 → cg12 816 MC/s at 4 threads) does not: on its
14 z lines openEMS resets the z PML to PEC, and the four x and y slabs span the whole z range
(vector path).

**Correctness.** The expression is the template's own, on the same operands, so the compiler
contracts it the same way; each (n, z) cell-component touches only its own V and flux, so
the (n outer, z inner) order versus the template's (z outer, n inner) does not change values.
Verified bit-identical (check.sh cg11, ksma, cylinder).

## Dispersive / Lorentz line hooks and the two hardenings (cg12)

**Files.** `engine_ext_dispersive.{h,cpp}` (+150 with patch 0005), `engine_ext_lorentzmaterial.{h,cpp}`
(+97), `operator.cpp` (GetMaterial key, SetupCSXGrid clear).

**Stock.** `Engine_Ext_Dispersive` (base of `Engine_Ext_LorentzMaterial`, used by Drude/
Lorentz materials and by `AddConductingSheet`, which every lossy board of the author's
toolkit uses) implemented only the non-threaded hooks, so the multithreaded engine ran them on
thread 0 (`Engine_Extension::Apply2Voltages(int threadID)` calls the plain version when
`threadID==0`) through `GetVolt/SetVolt`, with `LEGACY_HOOKS` (every group called, 19 barriers
per timestep on the GCPW model at cg11) and no fused sweep.

**New.** `SetupLines()` (from `SetNumberOfThreads`, once `m_Eng` is set; SSE engines with
equal strides and < 2^32 floats) stable-sorts the ADE positions of every order by x, stores
their x and the float index of each component (`4*linearIndex({n,x,y,z%nvec}) + z/nvec`).
`Apply2VoltagesLines(x0,x1)` finds the position range with `lower_bound` and performs
`volt[fi] = volt[fi] - ade[i]` per component, the template's `SetVolt(GetVolt - volt_ADE)`.
The Lorentz pre-hooks do the template's three statements per component
(`lor += v_lor*ade; ade *= v_int; ade += v_ext*(volt - lor)`, or the two-statement form
without the Lorentz term). `GetUsedHooks` declares `APPLY_VOLT`/`APPLY_CURR` only when some
order has volt/curr ADEs (`AnyVoltADE/AnyCurrADE`), Lorentz adds `PRE_VOLT`/`PRE_CURR`
likewise, and `LINE_HOOKS` when `m_LinesReady`.

**Correctness.** Each ADE position owns its state arrays indexed by the original position
index `i = idx[k]`; positions on different x cannot share a cell, and positions on the same x
keep their original order under the stable sort, so even a (pathological) duplicated cell
would be updated in the stock order. Verified bit-identical on a Drude/Lorentz box (template
vs line hooks, 1 and 4 threads) and on kgcpw.

**Reviewer notes.** The threaded (non-line) hooks of these extensions are **not**
parallelised: in the unfused plan their work still runs on thread 0 (with fewer barriers). The
hardenings: `GetMaterial`'s cache key now includes the first and last primitive pointer so a
freed-and-reused vector address with different content cannot hit; `SetupCSXGrid` clears the
`m_DiscDelta` tables when a new mesh is set.

## Packed coefficient tables (cg13)

**Files.** `engine_sse_compressed.{h,cpp}`: `struct PackedCoeff`, `m_PackedV/I`,
`BuildPackedCoeffs`, `Init`, `Reset` (~45 lines), used by the IJKN loops.

**Stock.** `Operator_SSE_Compressed::CompressOperator` dedups the per-(x, y, zv) coefficient
set into 12 SoA tables `f4_vv_Compressed[3], f4_vi_Compressed[3], f4_ii_Compressed[3],
f4_iv_Compressed[3]` (each a `vector<f4vector>` of `numOps` entries) plus the 4-byte index per
z-vector. A voltage update of one z-vector needs `vv[0..2][i]` and `vi[0..2][i]`: six 16-byte
loads from six separate arrays, i.e. up to six cache lines per operator; with 69.5 k operators
(ksma; the count is from the project log) the tables are 69.5 k × 12 × 16 B = 13.3 MB and the
access pattern per table is sparse.

**New.** `Engine_SSE_Compressed::Init` copies the tables into two AoS arrays in access order:

```cpp
struct PackedCoeff { f4vector c[6]; };   // 96 B: vv0 vi0 vv1 vi1 vv2 vi2  (or ii0 iv0 ii1 iv1 ii2 iv2)
m_PackedV[i].c[2*n]   = Op->f4_vv_Compressed[n][i];
m_PackedV[i].c[2*n+1] = Op->f4_vi_Compressed[n][i];
```

so one operator costs 96 contiguous bytes (one or two cache lines). Memory: +2 × 96 B ×
numOps (+13 MB for ksma). `OPENEMS_NO_PACKED_COEFF=1` skips the build; **note that
`UseIJKN()` requires a filled packed table, so this knob also reverts the engine to the
generic loops and disables the fused sweep** (the project log describes it only as "keeps the
old tables"; the diff is stricter). The operator's own tables stay allocated (the compressed
operator's `GetVV` etc. still read them). Patch 0005 added a size test (skip the build when
192 B per operator exceed twice the field memory) and a `bad_alloc` fallback. The size test
could fire only through the z padding and then also turned off the IJKN loops and the fused
sweep, so patch 0006 removes it again: the tables are always built, as in cg16, and only a
failed allocation skips them (both tables freed; the multithreaded engine then says that the
fused sweep is off because there are no packed tables).

**Correctness.** Plain copies; the loops multiply the same floats.

**Numbers** (`results/*_cg12.txt`, `*_cg13.txt`). kgcpw 1 thread 507 → 532 MC/s; at 4 threads
the kgcpw runs of cg12–cg14 (1608–1745) lie within the run-to-run spread. ksma 4 threads
1017 → 1137 MC/s.

## Compressed UPML coefficient tables (cg14)

**Files.** `engine_ext_upml.{h,cpp}`: `struct Coef`, `struct Coef4`, `SetupCoefTable`,
`SetupCoefTable4`, `m_CoefIdx/m_CoefIdx4`, `m_CoefTable` branches in all eight row routines
(~150 lines).

**Mechanism.** The six PML coefficients of a cell component (`vv, vvfo, vvfn, ii, iifo, iifn`)
take only a few hundred distinct values (the PML profile along the PML direction times the
materials). `SetupCoefTable` (scalar path) maps every (row, n, z) to an index into a table of
distinct 6-float sets via a `std::map<Key,unsigned>` with `memcmp` ordering
(`Coef` = 24 B, index 4 B per cell-component); `SetupCoefTable4` does the same per
(x, y, z-vector, n) for the f4vector path (`Coef4` = 96 B) and then frees the six f4vector
coefficient copies (`vector().swap`). The row loops read `tab[ix[k]]` instead of six arrays:
per cell-component the stock paths streamed 24 B of coefficients across the four hooks; the
table path streams a 4-B index per hook (re-read per hook: 12 B per cell for the three
components on the scalar path, 3 B on the vector path) and hits the table in cache.
`OPENEMS_NO_PML_TABLE=1` keeps the hooks on the per-cell arrays; `verbose>1` prints the number
of distinct sets.

**Correctness.** The table entries are the exact floats of the arrays (bitwise keys), used in
the identical expressions. Verified: check.sh cg14 (`results/*_cg14.txt`: the six models at
1, 4, 8 and 10 threads and auto, all bit-identical); from the project log, the cylinder and the
notch run with `PML_8` requested on all six faces (four full-z x and y slabs on its 14 z
lines, so the vector path only; see cg11).

**Memory.** The operator extension keeps its six per-cell coefficient arrays (as in stock) and
the vector path keeps its f4vector flux copies, so with the index a PML cell holds more memory
than in stock; cg14 lowers the traffic, not the memory.

**Numbers** (`results/*_cg13.txt`, `*_cg14.txt`). Bandwidth-side only: ksma 4 threads
1137 → 1241 MC/s, notch x3 8 threads 2022 → 2099; single thread unchanged.

## QoS class for the engine threads (cg15)

**File.** `engine_multithread.cpp`, `thread::operator()` (+12), `#ifdef __APPLE__`,
`<pthread/qos.h>`. Immediately after `Denormal::Disable()` each worker calls
`pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0)` (`OPENEMS_QOS` unset or 1),
`QOS_CLASS_USER_INTERACTIVE` (2), or nothing (0). Stock worker threads ran at
`QOS_CLASS_DEFAULT`, which lets macOS park them on E-cores or deprioritise them behind
foreground apps. Scheduling only; probes bit-identical. Measured in a separate session (project
log, not in `results/`): ksma 8 threads 1304-1385 → 1409 MC/s, 4 threads unchanged. The cg14
runs in `results/`, without QoS, already reach 1385 (ksma, 8 threads), so the gain is within
the run-to-run spread of a shared machine.

## Probe end criterion (cg16) and the `--disable-dumps` fix

**Files.** `openems.cpp` `RunFDTD` (+70), `Common/processintegral.{h,cpp}` (+19),
`Common/processfields_fd.cpp` (+1).

**Stock.** A run stops at `NrTS` (max timesteps) or when the field energy estimate falls below
`endCrit` relative to its maximum. v0.37.0 evaluates the energy at the progress report, about
every 4 s of wall time (every Nyquist period with `--exact-endcriteria`). The gpu-engine base
(upstream commit eb1c5ee, not in v0.37.0) evaluates it every Nyquist period during the first
60 s of wall time and at the progress report after that. So a run of the base, and of the fork,
can stop at a different step than the same run on v0.37.0; for the same number of steps the
results are bit-identical. On open structures the pulse's static charge keeps the energy up: at
the end of the full runs of `results/rfsim_e2e_2026-11-03.txt` (column `E_end`) it is still
−11.1 dB of its peak on the SMA launch (stock and fdtdKit) and −13.8 dB (stock) or −14.9 dB
(fdtdKit) on the GCPW line, so the energy criterion (−50 dB) never fires and the author's runs
always went to the time limit, although the port signals fall below −80 dB much earlier: the
−80 dB probe-end runs of the same file stop after 47 040 of 94 217 steps (GCPW) and 106 113 of
182 622 (SMA).

**New.** `ProcessIntegral::Process()` now tracks, over its `NrInt` result rows,
`m_lastAbs = max_n |m_Results[n]|` and the running `m_peakAbs` (reset in `InitProcess`).
In `RunFDTD`, if `OPENEMS_PROBE_END_DB` is set to a negative value and the excitation is
Gaussian (`GetExciteType()==0`): `probeHoldTS = hold × GetLength()` of the excitation signal
(`OPENEMS_PROBE_END_HOLD`, default 1.0), `endProbes` = every enabled `ProcessIntegral`
(voltage/current integration, field probes), `probeEndThr = 10^(dB/20)`. After each
`PA->Process()` (code as of patch 0005):

```cpp
std::map<std::string,double> kindPeak;                       // per GetProcessingName()
for (pi : endProbes) kindPeak[kind] = max(kindPeak[kind], pi->GetPeakAbs());
double worst = 0;
bool allSeen = true;                                          // since patch 0005
for (pi : endProbes) {
    double ref = max(pi->GetPeakAbs(), 1e-6*kindPeak[kind]);  // a dead probe is measured against 1e-6 of its kind's peak
    if (pi->GetPeakAbs()<=0) allSeen = false;                 // the wavefront has not reached it yet
    if (ref>0) worst = max(worst, pi->GetLastAbs()/ref);
}
if (!allSeen || worst>probeEndThr || ts<excitationLength) probeHoldStart = ts;
else if (ts-probeHoldStart >= probeHoldTS) probeEnd = true;
```

`probeEnd` joins the `while` condition; the end message reports the stop point and the
energy level. The test runs at the processing cadence (`step = PA->Process()`), and
`m_lastAbs` is the probe's latest sample at its own interval. The hold restarts at every
test at which the excitation is still running, a probe is above the threshold, or (since
patch 0005) a probe is still exactly zero; the run stops at the first test at which the
hold has lasted `probeHoldTS` steps. Numerical precursors make a far probe non-zero, with
values that count as settled, some time before the pulse arrives there (the gap grows with
the distance), so the hold must be longer than the longest one-way delay from the excitation
to a probe. Without the variable
the loop is the stock loop (bench runs with fixed `NrTS` are untouched; cg15 vs cg16
bit-identical).

**Patch 0006** changes four things. (a) The excitation counts as running until its signal
length plus the largest excitation delay: the voltage and current entries of every grid,
including the inner grids of a cylindrical multigrid, and the TFSF propagation delay
(before, only the signal length counted). (b) A mode-match probe counts with its mode
amplitude only, not with its purity (its second result row, which stays near 1 while any
field is there). (c) A probe that is still exactly zero keeps holding the run, but once every
other probe has settled, a one-time notice names it. (d) An invalid `OPENEMS_PROBE_END_DB`
or `OPENEMS_PROBE_END_HOLD` value prints a warning.

**Correctness.** The time-domain port files of an early-stopped run are a bit-identical prefix
of the full run's; frequency-domain results differ only through the shorter record. Measured on
2026-11-03 against the full runs (`results/rfsim_e2e_2026-11-03.txt`; column `prefix` = yes for
every probe-end run on the 0.02 mm mesh, the toolkit's default then, with 1.071 M cells for the SMA launch): at
−60 dB / hold 1, S21 moves by at most 8.0e-4 dB
on the GCPW line and 2.3e-4 dB on the SMA launch over the band, with 2.07×
(GCPW, 94 217 / 45 570) and 1.76× (SMA, 182 622 / 103 831) fewer timesteps. These runs were
made with cg18, so they include patch 0006. Its changes (a) and (b) can move the stop point
only of models with excitation delays, a TFSF source or mode-match probes; both boards stop at
the same step as with cg16 (GCPW 45 570, project log; SMA 103 831, the 0.02 mm row of the
2026-11-01 sweep in `results/sma_mesh_sweep_2026-11-01.txt`).

**`--disable-dumps` fix.** `ProcessFieldsFD::PostProcess` returns when `Enabled==false`
(`InitProcess` allocated nothing, so the stock code dereferenced unallocated FD fields).

## OPENEMS_FTZ (arm64 flush-to-zero)

**File.** `tools/denormal.h` (+15). `Denormal::Disable()` is called in the `Engine_sse`
constructor (on the thread that creates the engine) and by every multithread worker. The
basic engine never calls it, so only the engines built on `Engine_sse` (sse, sse-compressed,
multithreaded, cylindrical) flush; `OPENEMS_FTZ` has no effect on `--engine=basic`
(documented, not changed). Stock: `#if BOOST_ARCH_X86` sets MXCSR FTZ|DAZ, otherwise nothing,
so arm64 engines keep subnormals (Apple cores have no subnormal penalty). New
`#elif defined(__aarch64__)`: if `OPENEMS_FTZ` is set (since patch 0006: to a value other
than empty or 0), `mrs/msr fpcr` with bit 24 (FZ) set. Through patch 0005 the creating thread
(for example the Python interpreter's) kept FZ after the run; since patch 0006 the engine
gives that thread its previous FZ bit back when it is destroyed on that thread (the other FPCR
bits are left as they are). Opt-in because it changes
results at the 1e-43 level (project log: first at TS ~50, 3e-7 relative by TS 600 on the 121³
test); with it these engines match Apple's GPU, which flushes subnormals: the Swift/Metal
prototype on the 121³ box, and upstream's GPU engine on the notch tutorial over 3000 steps
(multithreaded at 2 threads and sse-compressed: probes and S11 identical; 3.2e-7 relative in
the probes without the flag; `results/notch_s1_n3000_ftzgpu.txt`).

## OPENEMS_EXPORT_OPERATOR / OPENEMS_EXPORT_FIELDS

**Files.** `openems.cpp` (`RawWrite`, `ExportOperatorRaw`, `ExportFieldsRaw`, ~115 lines,
calls in `SetupFDTD` just before `CreateEngine()` and in `RunFDTD` after the loop, before
`PA->PostProcess()`), `operator_ext_excitation.h` (+5 const accessors `GetVoltIndex/Dir/
Amp/Delay`), `operator_sse.h` (`GetNumVectors`).

Operator export needs the compressed SSE operator (else a message, nothing written) and writes
little-endian binaries: `op_index.u32` [x][y][zv]; `vv/vi/ii/iv.f32` [3][numOps][4 lanes];
`exc_index.u32` [3][count], `exc_dir.u32`, `exc_delay.u32`, `exc_amp.f32` (voltage entries
only), `exc_signal.f32`; `header.json` (numLines, numVectors, numOps, dT at 17 digits, counts,
signal period, the extension names, a layout string). Field export reads
`GetVolt/GetCurr(n, pos)` for every cell of any engine into `volt.f32 / curr.f32` [3][x][y][z]
plus `fields.json` (numTS). Both cover one grid (not the inner grids of a cylindrical
multigrid). These feed the standalone Swift/Metal engine and its raw comparisons; they do not
affect a run. Through patch 0005 only a binary file that could not be opened was reported; a
failed write and the two JSON files were not checked, and the closing message always said the
export was done. Since patch 0006 every failed write is reported and the closing message then
says the export is incomplete; the comments on the export were corrected.

## async_writer (dropped)

Not part of the published patches. It exists only in the unpublished, uncommitted step-2 tree
on v0.37.0 (item G of the step-2 snapshot ABCDEG; `tools/async_writer.h` 61 lines, `.cpp` 79
lines, with changes to `Common/processfields_td.{h,cpp}`, `Common/processing.cpp`,
`tools/CMakeLists.txt`): one background thread with a bounded byte budget that
ran the HDF5 time-domain dump writes in order so the engine threads did not wait for file
I/O. Upstream `gpu-engine` already has `AsyncDumps` (`ProcessFieldsFD::FinishAsync` is visible
in the diff context), so the item was dropped when the work moved onto that base.

---

## Review fixes (cg17, patch 0005, 2026-11-02)

Found by a further AI-assisted read-only correctness review of the branch before publication (patch 0006's message
corrects the "independent" of 0005's); the four earlier patches are unchanged, patch 0005 holds these:

- **Debye materials lost their dispersion in the multithreaded engine** (`FDTD/extensions/engine_ext_debyematerial.*`).
  `Engine_Ext_DebyeMaterial` (in upstream since v0.37.0, unchanged on the gpu-engine base) implements `DoPreVoltageUpdates` / `DoPostVoltageUpdates`
  but inherited `Engine_Ext_Dispersive::GetUsedHooks()` = `APPLY_VOLT | LINE_HOOKS`, so the hook plan never called its
  Pre/Post hooks and `SetupFused` even accepted it for the fused sweep: a Debye cell ran as its base material while the
  single-threaded engines (which call every hook) were right. The test set (Drude/Lorentz, conducting sheets) had no Debye
  material. Fix: Debye declares `(DispersiveHooks() & ~LINE_HOOKS) | PRE_VOLT | POST_VOLT` (its Pre/Post hooks only read engine
  fields and write the extension's own state; the poles are applied by the inherited `Apply2Voltages`; no line hooks, so the
  fused sweep is off with it). Structural guard: `OPENEMS_HOOKS_DECLARED_BY(Class)` (`engine_extension.h`, a `typeid` test) at
  the start of every `GetUsedHooks()` override returns `LEGACY_HOOKS` for any subclass that does not override it itself, so a
  declaration can never be inherited again; `Engine_Ext_Dispersive::DispersiveHooks()` is the non-virtual base set that
  `Engine_Ext_LorentzMaterial` and Debye build on. Check: `scripts/checks/debye_check.sh` (60x60x20 Debye box, 600 steps):
  before the fix the largest voltage difference between the multithreaded and the sse-compressed engine was 37 % of the peak
  voltage, and 187 108 of 216 000 voltage values differed; after it basic, sse-compressed and multithreaded are bit-identical
  and the single engine is unchanged against cg16 (rerun with 2 threads during the final review; the output is not in
  `results/`).
- **Probe end criterion arming** (`openems.cpp` RunFDTD): a probe the wavefront had not reached yet (peak still 0) contributed
  nothing and counted as settled, so a model whose one-way delay exceeds the hold could stop before its far port saw the pulse
  (S21 = 0 with a normal "criterion reached" message). The hold now restarts while any probe is still exactly zero
  (`allSeen`); a non-Gaussian excitation with the knob set prints a notice instead of silently ignoring it. This catches
  only a probe that is exactly zero: the numerical precursor gives a far probe tiny non-zero values, which count as settled,
  some time before the pulse arrives, so the hold must still be longer than the longest one-way delay. The GCPW stop point
  is unchanged (45570 steps, bit-identical port-file prefix; project log).
- **`Operator::GetMaterial()` cache key**: the per-thread last-lookup cache (coordinates, primitive-vector address, size,
  first/last primitive) could in principle survive into a later setup of the same process whose freed properties were
  reallocated at the same addresses. A setup generation (`static std::atomic<unsigned> s_SetupGeneration`, bumped in
  `CalcECOperator`) is part of the key now.
- **`Engine_Ext_Excitation`** declares `APPLY_CURR` only when it has current excitations: one barrier per timestep less in the
  unfused plan for the usual voltage excitation.
- **Auto thread tuner** (`engine_multithread.cpp` Init/TuneThreads): the larger candidates (start+2, +4, …) are clamped to
  the number of x-lines (`changeNumThreads` already reduced the count, but those candidates were then timed again as the
  reduced count). start−2 and the start itself stay unclamped until patch 0006.
- **nf2ff** (`nf2ff_calc.cpp`): the separable path is used only with Apple's Accelerate (`NF2FF_HAVE_CBLAS` is defined only
  under `__APPLE__`); other builds keep the threaded legacy loop instead of the single-threaded scalar fallback that was
  compiled there, so that fallback is no longer reachable.
- **Packed coefficient tables** (`engine_sse_compressed.cpp` BuildPackedCoeffs): skipped with a message when 192 B per
  operator would exceed twice the field memory, or on `bad_alloc` (SoA tables and generic loops then, i.e. stock speed,
  instead of an aborted setup). The side effect of `OPENEMS_NO_PACKED_COEFF` (generic loops, unfused) is unchanged and stays
  documented. Patch 0006 removes the size test again (next section).
- Cleanups: `SetupTimer` moved below the includes in `operator.cpp`; unused `<chrono>`/`<cstdlib>` dropped from
  `operator_sse_compressed.cpp`; the NX-1 current-hook invariant stated in `engine_extension.h`.
- Not changed in patch 0005, documented in BUILD.md: the staggered allocator is an ABI change for out-of-tree code;
  `OPENEMS_FTZ` also sets FPCR.FZ on the creating thread (restored at teardown since patch 0006); GCC's default
  `-ffp-contract=fast` contracts the new expressions differently from stock (correct, not bit-identical). Patch 0005's
  BUILD.md named only x86 with FMA for the GCC case; it applies to every arm64 build as well (next section).

## Final review fixes (cg18, patch 0006, 2026-11-03)

A final review before publication led to patch 0006 (snapshot cg18). The five earlier patches
are unchanged and their commit messages are not rewritten; the message of 0006 lists their
corrections. The line counts in these notes stop at patch 0005.

- **Packed coefficient tables** (`engine_sse_compressed.cpp`): the size test of patch 0005 is
  removed. It could fire only through the z padding, and when it fired it also turned off the
  IJKN loops and the fused sweep, so a model with a graded material (nearly one operator per
  z-vector) and a z line count that is not a multiple of 4 ran on the generic loops, unfused.
  The tables are always built, as in cg16. Only a failed allocation skips them, with
  both tables freed; the multithreaded engine then says that the fused sweep is off because
  there are no packed tables.
- **On/off knobs**: they act only when set to a value other than empty or `0` (`=0` is the same
  as unset): `OPENEMS_FTZ`, `OPENEMS_NO_STAGGER`, `OPENEMS_NO_PACKED_COEFF`,
  `OPENEMS_NO_PML_TABLE`, `OPENEMS_NF2FF_LEGACY`, `OPENEMS_SETUP_TIMING` and the other switches
  that were tested only for presence. `OPENEMS_FUSED=0`, `OPENEMS_BALANCE=0` and
  `OPENEMS_QOS=0/1/2` keep their meaning. An empty value of any of the fork's variables now
  counts as unset; before, an empty `OPENEMS_FUSED`, `OPENEMS_BALANCE`, `OPENEMS_QOS`,
  `OPENEMS_TUNE_WINDOW_MS` or `OPENEMS_BARRIER_SPIN_US` read as 0 (no fused sweep, no slab
  balancing, the default QoS, a zero tuning window, no spinning).
- **Probe end criterion**: the four changes (a)-(d) in the probe end section above (excitation
  delay, mode-match amplitude only, a notice for a probe that is still zero, a warning for an
  invalid value).
- **Auto thread tuner**: every candidate is clamped to the number of x-lines, start−2 and the
  start itself included.
- **`OPENEMS_FTZ`**: the thread that creates the engine gets its previous flush-to-zero bit
  back when the engine is destroyed on that thread. It still has no effect on `--engine=basic`
  (documented, not changed).
- **Cylindrical multigrid**: its fused-sweep line is printed once per level engine (each level
  engine printed it twice before, from several threads at once).
- **nf2ff**: the per-block work buffer of the separable path is bounded.
- **Portability**: the Accelerate include builds with GCC on macOS; the spin barrier's `yield`
  is guarded for 32-bit ARM.
- **Large meshes**: a mesh whose node count overflows the 32-bit array sizes is refused with a
  clear error: above 2^32/3 ≈ 1.43e9 nodes when arrays with three components over the whole
  mesh are needed, as with field dumps or an nf2ff box, and above 2^32 ≈ 4.29e9 otherwise.
- **Raw export**: failed writes are reported and the comments are corrected (export section
  above).
- **Comments**: code comments are corrected.
- **Version string**: the build is reconfigured so that the library reports its real git
  revision (the cg16 and cg17 libraries both call themselves v0.37.0-19-g0893f50).

**Verification of cg18** (2026-11-03, quiet machine). `bench/check.sh cg18
cg18`: the six models at 1, 4, 8 and 10 threads and the automatic choice, two runs each, every
run bit-identical to stock v0.37.0 in probes and S-parameters (`results/*_cg18.txt`).
`results/correctness_cg18_2026-11-03.txt`: the Debye box (`scripts/checks/debye_check.sh`,
4 threads) bit-identical across basic, sse-compressed and multithreaded and against cg17 (0 of
216 000 values differ per array); the cylindrical multigrid example (CylindricalWave_CC,
1.37 M cells, 1500 steps, 4 threads, an FD and a TD dump) against stock: 2 files, 34 datasets,
0 differences (the earlier checks of this kind had 18 datasets, from a different run length);
nf2ff of the patch tutorial: cg18 equals cg17 bit for bit, cg18 with `OPENEMS_NF2FF_LEGACY=1`
equals stock bit for bit, and the separable path is within 4.5e-7–6.8e-7 of stock (nf2ff
section). The validation suite (`bench/validation/run_validation.py`): 15 of 15 with the
multithreaded engine at 4 threads and with the default engine and thread count
(`results/validation_cg18_mt4.md`, `validation_cg18_fastest.md`; stock v0.37.0 on the same Mac
15 of 15, `validation_stock-v0.37.0_macos.md`). The probe-end stop steps and port-file prefixes
on cg18 (GCPW 45 570 steps): the Correctness paragraph of the probe end section above, which
cites `results/rfsim_e2e_2026-11-03.txt`.

Documented in BUILD.md, not changed:

- The operator setup (`Operator_Multithread`) uses every core, whatever `--numThreads` says.
- With GCC's default contraction (`-ffp-contract=fast`, in every C++ mode, on every arm64 build
  and on x86-64 built with FMA) the rewritten loops round a different product than stock, so a
  GCC build would be correct but not bit-identical. Measured in the standalone kernel only
  (`results/kernel_gcc_vs_clang_2026-11-03.txt`): the stock loop gives the same bits under Apple
  clang and GCC 16, the clang-built rewrite equals it, the GCC-built rewrite does not. A GCC
  build of openEMS was not made (BUILD.md section 8). For a bit-for-bit comparison under GCC,
  build stock and fork with the same explicit `-ffp-contract=off` (the Debug build already sets
  it). clang matches stock.
- The base's energy end-criterion schedule (upstream eb1c5ee, in gpu-engine, not in v0.37.0)
  checks the criterion every Nyquist period in the first 60 s of wall time, so a run can stop
  at a different step than on v0.37.0; for the same number of steps the results are
  bit-identical.
- Upstream fixes made after the base are not in the fork, among them 367a63f (flush to zero
  only during the run, for every engine), 54a4c60 (setup and run errors caught instead of
  terminating), d1fef7c (no excitation before its delay) and 0212258c3 (correct sizes and
  counts for large meshes).
- The libraries are not ABI-compatible with v0.37.0 builds (the base's ArrayLib `m_owner`
  member and the staggered allocator); after any install over another build, both Python
  modules must be rebuilt.
- The five earlier commit messages are not rewritten.

## Tiled sweep of the multithreaded engine (cg32d, patch 0040, 2026-11-11)

Written from the diff of patch 0040 alone (commit 0ef186b on ff2538a = cg31); the line counts are that patch's.
The sweep is opt-in: `OPENEMS_TBLOCK=k` or `auto` turns it on, and with the variable unset, empty or `0` the
engine runs the fused sweep of item E as before. The installed build (cg31, patches 0001–0039) does not have it.

**Files.** `FDTD/engine_multithread.cpp` (+345/−6) and `.h` (+33): `TileCacheBytes`, `SetupTiled`, `TiledRun`,
`TileHookShare`, `BalanceTiled`, `struct TileTask`, and the members `m_Tiled`, `m_TileK`, `m_TileW`,
`m_TilePlan`, `m_TileCum`, `m_TileHooksAll`, `m_TiledMsg`. `FDTD/engine_sse_compressed.cpp` (+19/−9) and `.h`
(+6/−2): `UpdateVoltagesY`, `UpdateCurrentsY`, and a y range in the two IJKN templates.
`FDTD/extensions/engine_extension.h` (+4): `GetMaxBlockDepth()`.
`FDTD/extensions/engine_ext_steadystate.cpp` (+6) and `.h` (+3): its override. Seven files, +416/−17.

**Before (cg31).** The fused sweep gives every thread a slab of x-lines and passes over the whole grid once
per timestep. On a grid larger than the cache both fields come from memory once per timestep (49 B/cell,
item E).

**New: the idea.** A block of k timesteps runs on one tile of x-lines before the engine moves to the next
tile, and all threads work in that same tile, each on its share of the y lines. A tile is then read from
memory once per k timesteps. The comment in `engine_multithread.h` names the model: upstream master's `cpu`
engine, one cache-sized tile for all threads. None of its code is used.

**New: the y-range loops (`engine_sse_compressed`).** `UpdateVoltages_IJKN_T` and `UpdateCurrents_IJKN_T` take
`y0, y1`; their y loops run `for (y=y0; (y<y1) && (y<ny); ++y)` for the voltages and
`(y<y1) && (y+1<ny)` for the currents (the last y line has no current update, as before). The loop bodies
are untouched. `UpdateVoltagesY` / `UpdateCurrentsY(startX, numX, y0, y1)` pick the geometry or the packed
coefficient tables as the old entry points did, and `UpdateVoltages_IJKN` / `UpdateCurrents_IJKN` now call
them with the whole range `[0, numLines[1])`, so the fused sweep runs the same code as before.

**New: the task plan (`SetupTiled`).** `SetupFused` clears `m_Tiled` at its start and calls
`SetupTiled(coupled)` at its end, so the tiled sweep exists only where the fused sweep does, and the plan is
rebuilt whenever `SetupFused` runs again (after a change of the thread count). With depth K and tile width W
(at least 2K+1 x-lines) the tile edges are 0, W, 2W, …, NX; a last tile shorter than 2K+1 lines joins the
one before. `m_TilePlan[d]` holds the tasks of a block of d timesteps for d = 1 … K, so the rest of a call
that is shorter than K has a plan of its own depth. A task is `TileTask {volt, x0, x1, ts}`: the voltages or
the currents of the x-lines [x0, x1) at timestep `ts` of the block. For a tile [a, b) and t = 0 … d−1 the
plan has the voltages on [a+t, b−t) and the currents on [a+t, b−t−1); at a domain edge the range does not
shrink (from 0, to NX for the voltages and NX−1 for the currents, since the currents of the last x-line are
never updated). After the tiles, for every inner edge c and t = 0 … d−1, come the voltages on [c−t, c+t)
(none at t = 0) and the currents on [c−t−1, c+t): the wedges between the tiles. Every range has the operands
of its timestep final when it runs: V(x) reads I(x) and I(x−1), I(x) reads V(x) and V(x+1), as in item E.

**New: running it (`TiledRun`).** A worker thread whose engine has `m_Tiled` calls `TiledRun(threadID,
m_iterTS)` in place of the per-timestep loop. Its y lines [y0, y1) come from the shares `m_TileCum`
(cumulative, in 1/65536). For every task it runs the hook stage before it (next paragraph), then
`UpdateVoltagesY` or `UpdateCurrentsY(x0, x1−x0, y0, y1)`, then waits at `m_IterateBarrier`; after the last
task of the call one more hook stage follows. The barriers do not count timesteps here: for the hooks of a
stage the thread sets its own `t_TS` (the thread-local timestep of the `TS_LOCAL` hooks of cg29) to the
call's first timestep plus the task's place in the call, and `RunTimesteps` adds the call's n to `numTS`
afterwards, as it does for the neighbour flags. The flags themselves are not used by the tiled sweep. The time and the x-y lines of the
updates go into `m_FusedStat[threadID]`.

**New: hook stages on all threads (`TileHookShare`).** A stage runs the Post and Apply line hooks of the
task before (hook groups 1, 2 or 4, 5) at that task's timestep, then the Pre hooks of the task after (group
0 or 3) at its own. When no extension has such a hook the stage and its barrier are skipped; otherwise the
stage ends at the barrier too. `TileHookShare` cuts the x-lines of the two tasks (one interval, or two with
a gap) once into one share per thread, at the same `m_TileCum` shares as the y lines. The upper cut of one
thread is the lower cut of the next (same formula), so the shares cover every line once. A cut between the
lines 0 and 1 moves up by one and a cut between NX−2 and NX−1 down by one, so a pair that a hook may couple
stays on one thread. All hooks of an x-line therefore run on one thread, in the order of a one-thread
sweep; the hooks of other lines do not depend on them (the line hook contract in `engine_extension.h`). No
extension was changed for this. `OPENEMS_TBLOCK_HOOKS=0` gives thread 0 all lines of every stage (a
diagnostic; the other threads only wait).

**New: shares (`BalanceTiled`).** Every task ends at a barrier, so the slowest share sets the pace, and a
thread on an efficiency core is slower. Where the fused sweep calls `BalanceSlabs` (after every `IterateTS`
piece, with `m_Balance`), the tiled sweep calls `BalanceTiled`: once the threads have 20 ms of update time
each on average, a thread's new share is halfway between its old share and its part of the summed speeds
(x-y lines per second), not below a quarter of the equal share, and every thread keeps one y line at least.
The shares stay as they are when a thread has no measurement or the grid has fewer y lines than threads.
`OPENEMS_BALANCE=0` keeps them equal. The shares start equal after every `SetupTiled`.

**New: `auto` (`TileCacheBytes`).** The cache: `hw.perflevel0.l2cachesize` on macOS (the L2 cache that the
performance cores share), then `hw.l3cachesize`; elsewhere `sysconf` for the level-3 and then the level-2
cache where the C library defines them; 0 when unknown. One x-line of both fields is
`24·Ny·4·numVectors` bytes (six floats a cell, z padded to whole vectors). With 90 % of the cache as the
budget: no tiling when the whole grid fits ("the fields fit the cache"); else the deepest K ≤ 8 whose 2K+1
lines fit; no tiling when that K is below 2 ("two timesteps of a tile do not fit the cache") or when the
cache size is not known. When NX has no room for two tiles of that depth (NX/2 < 2K+1), K is lowered to
(NX/2−1)/2, in integer arithmetic; only when that is below 2, which means NX < 10, is there no tiling ("too
few x-lines for two tiles"). The tile is then widened to
⌈200000/(Ny·Nz)⌉ lines (200 000 cells), but not past the budget and not past NX/2. With a set k and no
width the tile is 2k+1 lines; `OPENEMS_TBLOCK_W=n` sets the width in both cases, raised to 2K+1 if smaller.

**Depth cap (`GetMaxBlockDepth`).** New virtual of `Engine_Extension`, default `~0u` (no limit).
`SetupTiled` takes the smallest value over the extensions, at least 1, also for a set k.
`Engine_Ext_SteadyState` returns its signal period (`m_TS_period`, at least 1): a block then holds one
evaluation step at most, and the lines that run ahead write into the third period of the records that cg29
gave it. No other extension overrides it.

**Refusals.** With a message at `verbose>0` (printed once per text), and the fused sweep then runs: an
extension without `TS_LOCAL` in `GetUsedHooks()`; a coupled x-line (`GetCoupledLines`) other than 0 and
NX−2, because only at the two domain edges, where a tile does not shrink, are both lines of a pair in one
task at one timestep; and fewer x-lines than two tiles (2W > NX, compared in 64 bits). A value of
`OPENEMS_TBLOCK` that is not `auto` and that `atoi` does not read as a positive number leaves the sweep off
without a message.

**Correctness.** The arithmetic of a cell is the IJKN loop body of item B, unchanged; only the order in
which lines and timesteps are visited changes, and the plan gives every update the operands that the
unfused update has. The hooks keep their per-line order as described above. Checked, not proved
(`results/tiled_sweep_cg32_2026-11-11.txt`, `scripts/tiled_sweep/check.zsh`): against the fused sweep of
cg31 the probes of six models are identical in 30 of 30 comparisons at 2 threads and 36 of 36 at 3, 4, 8 and
10 threads (k 2 to 7 and `auto`, set widths, `OPENEMS_TBLOCK_HOOKS=0`, `OPENEMS_BALANCE=0`); the raw fields
of a closed cylinder at 2, 8 and 10 threads; a sinusoidal run that stops by the steady-state criterion
(period 87 steps) with the same stop step, 17 580, probes and raw fields for k = 4, 5, 8 and 19 at 1 to 10
threads; the Debye box with k = 3 and 4; and, with the variable unset, the reduced check against stock
v0.37.0, 18 of 18 rows on six models. The same library files passed the same checks on an M5 Pro at 5 to 15
threads. A read-only review before the commit (three reviewers, each finding handed to a second reader)
found no result defect and two faults that the commit already has fixed: the balance could leave a thread
at zero y lines for the rest of a run (hence the one-line minimum), and a depth of 2^30 or more passed the
two-tile test (hence the 64-bit compare).

**Numbers** (same record; Apple M5, macOS 27.2.1, three paired rounds, median MC/s, other processes a
median of 9 % of one core; fused = cg31, tiled = cg32d with `auto`). Patch x5 (7.86 M cells): fused 1841 at
4 threads and 2138 at 8, tiled 2305 at 4, 1872 at 8, 1881 at 10. PEC box of 16.8 M cells: 1648 and 1867,
tiled 2289, 1995, 1995. Against the fused sweep at 8 threads the best tiled setting is at 1.08× and 1.23×
on these two and at 0.92× (PEC box, 2.95 M), 0.85× (PML cube, 8.0 M), 0.81× (notch x3) and 0.71× (ksma on
its 0.871 M-cell mesh) on the others. Hook stages on one thread at 4 threads: patch x5 2044 instead of
2305, notch x3 1499 instead of 1861, PML cube 617 instead of 1138. Measured against equal shares at 8
threads: within 3 % on every model. Under heavy load from other programs (5.6 other cores busy) the tiled
sweep at 8 to 10 threads fell to 28–600 MC/s where the fused sweep at 4 threads held 730–1570.

**Reviewer notes.** The sweep pays only on large grids with little extension work, and most at the
performance-core count (at 8 and 10 threads only the 16.8 M-cell box stays ahead of the fused sweep at 8:
1995 against 1867), and a barrier per task does not survive a loaded machine; hence opt-in. kgcpw fits the
cache, so `auto` leaves it on the fused sweep. A tile holds every y and z line of its x-lines, so a grid
whose five x-lines exceed the budget cannot be tiled at all (a 400³ cube on the M5). On an M5 Pro (5 + 10
cores, macOS 27.2.1; a set of its own, `results/m5pro_tiled_sweep_2026-11-12.txt`, three paired rounds at 5,
10 and 15 threads, all 162 runs identical) the sweep led only on the PEC box of 16.8 M cells (4752 against
3326 MC/s, 1.43×, both at 15 threads) and ran 0.41–0.97× the fused sweep's best on the other five models,
where the fused sweep gains up to 15 threads and the tiled sweep peaks at 10, although the standalone kernel
(`scripts/kernel/kb_tile.cpp`) gains 1.21× at 15 threads there; the verdict stays opt-in. Not measured: the
sweep against upstream master's `cpu` engine in one paired run, and what the engine loses against the
kernel at many threads. Not built: a choice between the two sweeps at run time.

## Numbers checked against the code

- Barriers per timestep: stock `2 + 6·N_ext` (`boost::barrier`; 50 on patch x5 with N_ext = 8,
  38 on notch); unfused plan
  `2 + [PRE_VOLT] + [POST_VOLT] + #APPLY_VOLT + [PRE_CURR] + [POST_CURR] + #APPLY_CURR`
  (+2 per `PREPOST_WRITES_FIELDS` hook, +1-2 per legacy extension); fused sweep exactly 2.
- `SpinBarrier`: default spin 50 µs (`OPENEMS_BARRIER_SPIN_US`), clock checked every 128 spins,
  `yield` on arm, `pause` on x86.
- Hook flags: `PRE_VOLT=1, POST_VOLT=2, APPLY_VOLT=4, PRE_CURR=8, POST_CURR=16, APPLY_CURR=32,
  PREPOST_WRITES_FIELDS=64, LINE_HOOKS=128, LEGACY_HOOKS=~0u`.
- Auto threads: start = `hw.perflevel0.physicalcpu` (Apple) or `(max+1)/2`; candidates
  start+2, +4, … ≤ max (max clamped to the number of x-lines since patch 0005), then start−2
  (if start > 2), then best±1; start−2 and the start itself are clamped to the number of
  x-lines too since patch 0006; window 150 ms
  (`OPENEMS_TUNE_WINDOW_MS`), settle 0.4·window, larger counts dropped below 0.85·best,
  `IterateTS` pieces of window/8, first piece 4 timesteps.
- Fused blocks: default 1 line (`OPENEMS_FUSED_BLOCK`), halved until ≥ 4 blocks per thread;
  balancing after ≥ 20 ms average busy time per thread, cost smoothing 0.5.
- Field layout: I-J-K-N, component stride 1, z-vector stride 3; cell z = lane z/nvec of
  z-vector z%nvec, z padded to 4·nvec; 12 B per cell per field. Operator index: 4 B per
  z-vector are read (1 B per cell), but it is allocated with 4 B per cell (x, y, z) and only
  the first nvec entries of each z-row are used, so up to 4 B per cell are streamed (all of it
  when Nz ≤ 42).
- Traffic: unfused 37 B/cell per update, 74 B/cell/timestep; fused 49 B/cell/timestep, all
  with the compact 1-B index; with the index as allocated 40, 80 and up to 52 B.
- `PackedCoeff` = 6 × 16 B = 96 B per operator per update side; +2·96·numOps bytes
  (+13.3 MB for ksma's 69.5 k operators, a project-log count). Stock SoA tables: 12 × 16 B × numOps.
- UPML tables: `Coef` 24 B, `Coef4` 96 B, index 4 B per cell-component (scalar) or per
  (x, y, z-vector, n) (vector); stock per-cell coefficients 72 B.
- UPML scalar SSE offset: `m_zoff[lz] = 12*(z%nvec) + z/nvec`.
- Mur vector run test: offsets multiples of 4 floats and `FloatIndex[cells[n+3]] == f+3` with
  `f%4==0`.
- Allocator: threshold 256 KiB, alignment ≤ 256 B, offset `256 + (k·2560) mod 16128`
  (span 16384 − 256), 63 distinct offsets (gcd(2560, 16128) = 256), base pointer stored at
  `((void**)buf)[-1]`.
- FTZ: FPCR bit 24.
- Probe end: threshold `10^(dB/20)` on amplitude, hold `OPENEMS_PROBE_END_HOLD × GetLength()`
  timesteps (default 1.0), dead-probe floor `1e-6 ×` the kind's peak, kinds =
  `GetProcessingName()` ("voltage integration", "current integration", field probe names),
  Gaussian excitation only (`GetExciteType()==0`); the hold restarts at every check while
  `ts < GetLength()` (since patch 0006: the length plus the largest excitation delay), while a
  probe is above the threshold and, since patch 0005, while a probe is still exactly zero.
- nf2ff block size `max(16, min(N_dir, 2^21/(6·NP)))` through patch 0005 (patch 0006 bounds
  the per-block work buffer); `cgemm` dimensions nd × 6·NP × NPP; since patch 0005 the
  separable path is used only with Apple's Accelerate (`NF2FF_HAVE_CBLAS`, defined only under
  `__APPLE__`), other builds keep the threaded legacy loop.
- `Field_Gather_SSE` and the dispersive/Mur fast paths require the field arrays to have fewer
  than 2^32 floats (indices are `unsigned int`). Since patch 0006 a mesh beyond the 32-bit
  array sizes is refused at setup (above 2^32/3 ≈ 1.43e9 nodes when three-component arrays over
  the whole mesh are needed, as with field dumps or an nf2ff box; above 2^32 ≈ 4.29e9 otherwise).
- Setup timing laps: Init_EC, Calc_EC, CalcTimestep, InitOperator, Calc_ECOperatorPos,
  ApplyElectricBC, CalcPEC, Calc_LumpedElements, ApplyMagneticBC, BuildExtension <name>.
- Line counts (numstat of the cumulative diff through patch 0005, without 0006): engine_multithread.cpp +470/−45,
  engine_ext_upml.cpp +668, engine_ext_mur_abc.cpp +241, engine_sse_compressed.cpp +242/−2,
  operator.cpp +193/−70, openems.cpp +192/−1, nf2ff_calc.cpp +139/−9, engine_ext_dispersive.cpp +130,
  engine_ext_lorentzmaterial.cpp +93, engine_ext_lumpedRLC.cpp +87/−24, spin_barrier.h +110,
  engine_ext_excitation.cpp +46/−6, allocator.h +43/−6, engine_field_gather.cpp +38,
  engine_extension.h +47, denormal.h +15, engine_ext_debyematerial.cpp +10, CSXCAD +9.

## Open questions

1. Instructions per iteration of item B: the stock 94 / 95 and cg18's 41 / 42 are measured
   (`results/kernel_loop_instructions_2026-11-03.txt`); the 44 of snapshot AB is from the
   project log. The MC/s numbers come from `results/` or the project log, not from the code;
   they cannot be re-derived from the diff.
2. Bit-identity of the UPML f4vector path and of the IJKN loops rests on the compiler's
   contraction choice matching the scalar/stock code; it was verified by comparison for clang
   (`-ffp-contract=on`), not forced in source (no `fma()` calls, no `#pragma STDC FP_CONTRACT`).
   The final review showed the GCC case: with its default `-ffp-contract=fast` (every aarch64
   build, x86-64 with FMA) GCC turns the IJKN update into fma(v, k0, round(k1·t)) where stock
   computes fma(vi, t, round(v·vv)), and in the UPML vector rows it fuses a different product
   than stock. In the standalone kernel the GCC-built rewrite is not bit-identical to the
   GCC-built stock loop, while the stock loop gives the same bits under both compilers
   (`results/kernel_gcc_vs_clang_2026-11-03.txt`); a GCC build of openEMS was not made.
   BUILD.md documents this and `-ffp-contract=off` for both builds. Explicit `fma()` in both
   paths would remove the dependence on the compiler.
3. The hook contract (pre/post hooks never write engine fields unless
   `PREPOST_WRITES_FIELDS`) is declarative; I did not audit every upstream extension that
   stays on `LEGACY_HOOKS` (TFSF, steady-state detection, cylinder, multigrid, `Absorbing_BC`) for whether it
   could safely declare hooks.
4. In the fused sweep the first-timestep rotation stamps of the lumped RLC start at −1 and
   compare against `GetNumberOfTimesteps()`; I did not check how `Reset()`/re-`Init()` of an
   engine (a second run in the same process) interacts with these stamps.
5. Closed: `OPENEMS_NO_PACKED_COEFF=1` disables the IJKN loops and the fused sweep as a side
   effect (through `UseIJKN()`); the paper (engine section) and BUILD.md now say so.
6. Closed: `Operator_Multithread`'s setup pool always uses `AvailableThreads()`, so the setup
   uses every core whatever `--numThreads` says (stock used the user's count there).
   Behavioural, not numerical; documented in BUILD.md, not changed.
7. The nf2ff 7e-7 relative difference is the project log's measurement on one pattern; a
   stored comparison now exists for the patch tutorial on cg18 (4.5e-7–6.8e-7,
   `results/correctness_cg18_2026-11-03.txt`). I did not find a stored comparison for
   cylindrical meshes (they use the legacy path, so none needed).
8. `operator_sse_compressed.cpp` gained `<chrono>`, `<cstdlib>`, `<iostream>` includes with no
   code using them in the diff through patch 0004 (leftover from a timing experiment). Patch 0005 dropped the
   unused `<chrono>` and `<cstdlib>`.
