# openEMS CPU speed review on the M5 — what is left beyond the CLAUDE.md plan

Reviewer: Fable (subagent), 2026-10-28. Read-only review of openEMS v0.37.0 at
`~/opt/src/openEMS-Project/openEMS` and the installed `~/opt/openEMS/lib/libopenEMS.0.37.0.dylib`.
No openEMS runs were made. Two standalone microbenchmarks were compiled and run in
(scratch dir)
(`barrier_bench.cpp`, `kernel_bench.cpp`; total CPU time well under 30 s, run while other sessions
used 14-55 % of the machine, so absolute numbers carry ±10 % noise).

Baseline from CLAUDE.md step 1 (not re-measured): patch x5 (7.86 MCells, 6x MUR, nf2ff) 1041 MC/s with
8 threads, 1006 with 4; notch x3 (5.25 MCells, PML_8 at both x ends) 845 / 693; patch tutorial
(0.104 MCells) 277 at 2 threads; notch tutorial (0.270 MCells) 318 at 4 threads.

**Notes (2026-11-03, final review; the review text below is unchanged):**
- Barrier counts. In stock v0.37.0 the patch model has 8 extensions, not 7: the R-only lumped RLC extension stays
  with 0 cells, because its `BuildExtension` returns true (end of `operator_ext_lumpedRLC.cpp:BuildExtension`), so
  `operator.cpp:1062-1070` does not remove it. The patch model therefore has 2 + 6 x 8 = 50 barriers per time step,
  not 44 (sections 0 row A, 1.3, 2, 3, 4.A and 5 item 4). The 44-barrier microbenchmarks understate stock's barrier
  cost a little. The notch count (38) is right. Checked with a 20-step stock run of the patch tutorial at 2 threads,
  which lists the lumped RLC load (0 active cells), the six Mur faces and the excitation.
- "CLAUDE.md" (the plan, step 1) means the project's working notes, which are not published. The step-1 numbers are
  in `results/*_step1.txt`.
- "(scratch dir)" and section 7: `barrier_bench.cpp`, `kernel_bench.cpp` and `mesh_dims.py` are not in this
  repository. `scripts/kernel/kb_idx.cpp` is a later version of `kernel_bench.cpp` (the same loops, more options).

---------------------------------------------------------------------------------------------------

## 0. Ranked result (best gain per unit of effort first)

| # | Change | Effort | Patch x5 (7.86 MC) | Tutorial-size models | Bit-identical? | Plan step |
|---|--------|--------|--------------------|----------------------|----------------|-----------|
| A | Barrier diet: 44 (38) barriers/TS → 4-10, spin-then-park barrier instead of `boost::barrier` | ~1 day, `engine_multithread.cpp` + a "hook implemented" mask per extension | +13-15 % at 8 thr, +5 % at 4 thr | +60-100 % (and 8-10 threads stop being slower than 2) | yes (keep hook order at Mur edges) | 2 (new item) |
| B | Rewrite the two inner loops of `engine_sse_compressed.cpp`: hoist invariants, pointer walking, one store per component | ~1 day; the verified code is in `kernel_bench.cpp` | +3-9 % (bandwidth-bound) | +50-80 % (compute-bound): 1.8x single-thread, measured | yes (measured, memcmp) | 2 |
| C | Scheduling: dynamic x-chunks over all 10 cores, main thread as a worker, kill the 1→N thread ramp of `numThreads=0` | ~0.5 day | +5 % over static at 8 thr; default-engine users +40-60 % (615 → ~1000) | +15-25 % over static (dynamic adapts to P/E cores and other load) | yes | 2 |
| D | Vectorize/de-divide the Mur-ABC and UPML engine paths (f4vector lanes, no `z%numVectors`, `z/numVectors`), split PML work by rows not x-lines | 2-3 days | +5 % (Mur ≈ 6 % of TS time at 8 thr) | patch +25 %, notch tutorial +40-60 % (PML ≈ 45 % of its instructions); notch x3 +15-25 % | yes if the per-cell arithmetic is kept (fmul+fmls/fmla order), else S-params equal to ~1e-7 | 2 (new item) |
| G | Take dumps/probes off the critical path: CalcField on the workers, HDF5 write on a helper thread | 1-2 days | +1 % | tutorial patch +20 % now, +40-60 % once A-D make the TS 5x shorter | yes | new |
| E | Fused E/H sweep (one pass per timestep, H lags E by one x-plane; = temporal blocking with k=1) | 1-2 weeks: new engine class, per-plane extension hooks | +30-45 % on top of A-D (DRAM 74 → 49 B/cell) | ~0 | yes in principle (same ops, same operands) | 4 → should move up |
| H | fp16 field storage, fp32 math | 2-4 days (CPU: `fcvtl/fcvtn`; GPU: native half) | up to +60-90 % if still bandwidth-bound | 0 | NO; noise floor ~-60 dB, check S21 stopband of the notch | 4 |
| F | Metal engine at the same 72-74 B/cell | weeks | ≈ +5 % over the fixed CPU engine (GPU 127 GB/s vs CPU 125 GB/s measured here) | negative unless every per-TS hook is on the GPU | yes | 3 → demote |
| – | uint8/uint16 operator index | hours | < 1 % | < 1 % | yes | 2 (drop) |
| – | `-mcpu=apple-m4`, LTO, `-ffast-math`, huge pages, FTZ | hours | 0 % (verified for -mcpu: identical instruction stream) | 0 % | fast-math/FTZ: no | 2 (drop) |

Expected combined effect of A+B+C+D on this machine (estimate, see §3): patch x5 1041 → ~1600 MC/s,
notch x3 845 → ~1450-1500, patch tutorial 277 → ~1000-1300 (then G), notch tutorial 318 → ~1000.
Then E: patch x5 → ~2200-2400.

---------------------------------------------------------------------------------------------------

## 1. Verified facts (file:line or asm)

### 1.1 Data layout and per-timestep traffic

* Field arrays are `ArrayLib::ArrayENG<f4vector>` with **I-J-K-N** strides: component is innermost,
  `stride = {1, Ny*nvec*3, nvec*3, 3}` (`tools/arraylib/array_e.h:56-60`). One f4vector = 4 cells
  along z (`engine_sse.cpp:40`: `numVectors = ceil(Nz/4)`), so one (x,y,zvec) position is a 48-byte
  triple (Ex,Ey,Ez) and the z-inner loop walks memory with a 48 B stride, perfectly sequential.
* Per f4vector the E update reads 3 volt + 9 distinct curr vectors (3 at (x,y), 2 at z-1 = previous
  48 B, 2 at y-1, 2 at x-1), writes 3 volt, loads 1 uint32 index and 6 table entries
  (`engine_sse_compressed.cpp:82-116`). With the y-1 line (2 KB) in L1 and the x-1 plane
  (441 KB per array for patch x5, 94 KB for notch x3; `mesh_dims.py`) in L2, DRAM traffic per
  timestep is 2 phases x (48 read + 48 read + 48 write) = 288 B per 4 cells = 72 B/cell, plus the
  4-byte index read twice = 2 B/cell: **74 B/cell**, as CLAUDE.md says. Measured ceiling of this
  layout on this machine (kernel_bench, 8 threads): 1689 MC/s = 125 GB/s.
* Mesh dimensions of the four bench models (computed from the CSXCAD grid, no simulation):

  | model | Nx,Ny,Nz | MCells | numVectors | z-slots | padding |
  |---|---|---|---|---|---|
  | patch x1 | 49, 47, 45 | 0.104 | 12 | 48 | 6.2 % |
  | patch x5 | 209, 209, 180 | 7.863 | 45 | 180 | 0 % |
  | notch x1 | 235, 82, 14 | 0.270 | 4 | 16 | 12.5 % |
  | notch x3 | 689, 224, 34 | 5.247 | 9 | 36 | 5.6 % |

  The notch tutorial's z-inner loop has 3 iterations plus the z-wrap special case per (x,y) line.

### 1.2 The generated inner loop (installed dylib, `otool -tV -p __ZN21Engine_SSE_Compressed14UpdateVoltagesEjj`)

The z-loop of `UpdateVoltages` is 0x5a870-0x5a9e4 = **94 instructions per f4vector triple**
(12 vector cell-components, 4 Yee cells). `UpdateCurrents` (0x5ac1c-0x5ad94) is the same size.
Mix per iteration:

* 15 NEON arithmetic: 3 `fmul.4s`, 3 `fmla.4s`, 9 `fsub/fadd.4s` -- this is the minimum; fp-contract
  is already on (clang default), so the FP side is fine and `-mcpu` cannot help.
* 21 `ldr q` vector loads, **6 `str q` stores (3 redundant: `*=` is stored, then `+=` stores again)**.
* **~22 scalar reloads per iteration** that should be loop-invariant: `this->Op` is reloaded 6 times
  (`ldr x5, [x0, #0x78]` at 0x5a870, 0x5a8e4, 0x5a924, 0x5a944, 0x5a984, 0x5a9a0), each of the six
  table base pointers is reloaded through it (`ldr x21, [x5, #0x240]`, `[x22, #0x288]`,
  `[x21, #0x258]`, `[x22, #0x2a0]`, `[x20, #0x270]`, `[x20, #0x2b8]`), the `m_Op_index` strides
  (`[x5, #0x220/#0x224/#0x228]`), the field array pointers and strides (`ldp x21, x19, [x0, #0x68]`,
  `[x19, #0x38..0x40]`), and `numVectors` (`ldr w5, [x0, #0x60]`) at the loop bottom.
  Cause: every store goes through the `f4vector` union, and clang gives union accesses the
  may-alias-anything TBAA tag, so after each `str q` the compiler must assume `Op`, the vector
  headers and the strides changed. Each coefficient is therefore at the end of a 3-deep dependent
  load chain (Op → vector.begin → entry) that restarts after every store.
* 8 `mul/madd` to rebuild the linear index from strides each iteration, 6 `ubfiz` (32-bit unsigned
  indices zero-extended to 64-bit on every address), ~14 add/sub.

Excerpt (x-component, one of three per iteration):

```
5a870  ldr  x5, [x0, #0x78]        ; this->Op            (reloaded every iteration)
5a874  ldr  x6, [x5, #0x238]       ; m_Op_index.m_ptr
5a878  ldr  w7, [x5, #0x220]       ; m_Op_index.stride[0]
5a87c  mul  w7, w7, w1
5a880  ldr  w19,[x5, #0x224]       ; stride[1]
5a884  ldr  w20,[x5, #0x228]       ; stride[2]
5a888  madd w7, w19, w17, w7
...
5a8a8  ldr  w6, [x6, w7, uxtw #2]  ; index
5a8bc  ldr  x21,[x5, #0x240]       ; f4_vv_Compressed[0].begin
5a8c4  ldr  q0, [x21, x5]          ; vv
5a8cc  ldr  q1, [x9, x21]          ; volt
5a8d4  fmul.4s v0, v0, v1
5a8d8  str  q0, [x9, x21]          ; store #1 (the *=)
5a8e4  ldr  x22,[x0, #0x78]        ; this->Op again
5a8f4  ldr  x22,[x22, #0x288]      ; f4_vi_Compressed[0].begin
...
5a91c  fmla.4s v0, v1, v2
5a920  str  q0, [x9, x21]          ; store #2 (the +=)
```

Single-thread consequence (kernel_bench, patch-x5 grid): 485-488 MC/s = 10 ns = ~44 cycles per
iteration for 188 instructions (E+H), i.e. IPC ≈ 4.3 -- the core is instruction-bound, not
memory-bound, at 29 GB/s. The hoisted version of the same arithmetic (`UpdateVoltages_clean`,
181 instructions for the whole function including the z=0 path) runs at 878-882 MC/s single-threaded,
bit-identical.

`-O3` rebuild of `engine_sse_compressed.cpp` alone reproduces the dylib exactly (237 instructions
in `UpdateVoltages`, same mix); adding `-mcpu=apple-m4` gives an identical instruction stream
(`engine_sse_compressed_O3.s` vs `engine_sse_compressed_m4.s` in the scratchpad: no diff in the
opcode histogram). CMake Release flags are the defaults (`CMakeLists.txt:4-7`, no `-march/-mcpu`).

### 1.3 Threading

* Worker loop `engine_multithread.cpp:325-368`: per timestep `DoPreVoltageUpdates`, update,
  barrier, `DoPostVoltageUpdates`, `Apply2Voltages`, `DoPreCurrentUpdates`, update, barrier,
  `DoPostCurrentUpdates`, `Apply2Current`. Each of the six hook dispatchers does
  `m_IterateBarrier->wait()` **after every extension, whether or not that extension implements the
  hook** (`engine_multithread.cpp:226-285`). Barriers per timestep = 2 + 6 x N_ext.
  * patch (6 Mur faces, `openems.cpp:401-412`, + excitation `openems.cpp:1237`; the lumped-port R is
    handled by `Operator::Calc_LumpedElements`, the LumpedRLC extension drops R-only elements in
    `BuildExtension` and is removed at `operator.cpp:1062-1070`): N_ext = 7 → **44 barriers/TS**.
  * notch (2 UPML x-slabs from `Create_UPML`, `operator_ext_upml.cpp:128-144`; 3 Mur; excitation):
    N_ext = 6 → **38 barriers/TS**. Of the 36 extension barriers only ~10 follow a hook that does work.
* `boost::barrier::wait` = mutex + condition_variable + `notify_all`
  (`/opt/homebrew/include/boost/thread/barrier.hpp:218-234`). Measured on this machine
  (`barrier_bench`, same algorithm with std::mutex/condvar):

  | threads | condvar barrier | spin barrier | C++20 atomic wait (spin 2000 then park) |
  |---|---|---|---|
  | 2 | 2.07 µs | 0.12 µs | 0.13 µs |
  | 4 | 4.69 µs | 0.21 µs | 0.21 µs |
  | 6 | 11.8 µs | 0.40 µs | 0.82 µs |
  | 8 | 15.9 µs | 0.52 µs | 0.99 µs |
  | 10 | 19.3 µs | 0.74 µs | 5.6 µs |

  QoS `USER_INTERACTIVE` on the workers changes none of these. In context (kernel_bench, threads
  arrive unevenly) the condvar barrier costs 4.9 µs (tutorial grid) to 8.7 µs (big grid) at 4
  threads and 16-24 µs at 8 threads.
* Static equal x-slab split: `operator_multithread.cpp:93-114` → `AssignJobs2Threads`
  (`tools/useful.cpp:188-218`), no P/E weighting, no work stealing; macOS has no affinity API, so
  which slab lands on an E-core is up to the scheduler. This is why 5 threads are slower than 4
  (one slab of 1/5 on a ~2.5x slower core finishes later than 4 slabs of 1/4) and 6 ≈ 4.
* Auto-tuner (`engine_multithread.cpp:209-224`): starts at 1 thread, adds one per 4-second
  progress interval until speed drops -- on a 10-20 s run it averages ~60 % of the best speed
  (615 vs 1041 MC/s measured).
* `numTS` is incremented by thread 0 after the last barrier (`engine_multithread.cpp:366-367`);
  other threads may read it for the next step's hooks before the increment (benign today: only
  `Engine_Ext_Mur_ABC::IsActive` reads it). Increment it before the last barrier when reducing barriers.

### 1.4 Extensions

* UPML and Mur engine code is scalar and goes through `Engine_sse::GetVolt/SetVolt`, which compute
  `z%numVectors` and `z/numVectors` with a runtime divisor (`engine_sse.h:38-84`). Installed code:
  `Engine_Ext_UPML::DoPreVoltageUpdatesImpl<Engine_sse>` inner loop (0x7160c-0x7182c) = **~130
  instructions per PML cell with 3 `udiv` + 3 `msub` and 45 `mul/madd`**, no NEON
  (`ext_5Engine_Ext_UPML23DoPreVoltageUpdat.s`); the other three UPML hooks are similar (157-195
  instructions per function), so ≈ 500 instructions per PML cell per timestep versus 47 per volume
  cell (188/4). Mur: `DoPreVoltageUpdatesImpl` 163 instructions, 2 `udiv`; `Apply2VoltagesImpl` 119,
  2 `udiv`; ≈ 190 instructions per face cell per timestep.
* Work split inside extensions: UPML splits its own x-lines
  (`engine_ext_upml.cpp:41-50`): a PML_8 slab has 9 lines, so 8 threads get 2,1,1,1,1,1,1,1 lines
  and 4 threads 3,2,2,2 → the barrier waits for the thread with 2 (3) lines: the PML critical path
  is 2/9 (3/9) of the single-thread PML time instead of 1/8 (1/4). Mur splits its face along
  `nyP` (`engine_ext_mur_abc.cpp:73-82`), fine. Excitation runs on thread 0 only
  (`engine_extension.cpp:50-90`), negligible.
* The `#ifdef __SSE2__` lane-shift paths in `engine_sse_compressed.cpp:125-134, 146-155, 254-263,
  276-285` are not taken on arm64; the scalar `temp.f[]` fallback compiles to
  `movi; ld1.s {v0}[1]; ldr d1; mov.d v0[1], v1[0]` (0x5a704-0x5a710), ~4 instructions instead of
  one `ext` -- minor (1 of numVectors lines).

### 1.5 Main thread (`openems.cpp:1484-1494`)

`while (...) { FDTD_Eng->IterateTS(step); step = PA->Process(); ... }`: the workers wait at
`m_startBarrier` while the main thread runs `ProcessingArray::Process` serially
(`Common/processing.cpp:367-378`, comment "this could be done nicely in parallel??").
* Probes: `ProcessInterval = Nyquist/OverSampling`, OverSampling default 4
  (`openems.cpp:120, 591-593`). Each probe is a short line integral of virtual `GetVolt` calls
  plus the FD accumulation (401 or 1601 frequencies). Nyquist (from the mesh, estimated): patch x5
  ≈ 670 TS, patch x1 ≈ 135, notch x3 ≈ 1300 → probes run every 34-330 TS: negligible
  (< 0.1 %).
* nf2ff box = 12 TD dumps (6 faces x E,H) at the same interval (`openems.cpp:669-671`), each a
  `ProcessFields::CalcField` loop of `GetEField` with node interpolation (virtual calls,
  `engine_interface_fdtd.cpp:58-100`) plus an HDF5 write. Measured in step 1: < 1 % on patch x5,
  ~22 % on the tutorial patch at 4 threads (205 vs 262 MC/s with `--disable-dumps`).
* End criterion: `CalcFastEnergy` full-domain sum every 4 s wall clock (`openems.cpp:1517-1522`),
  negligible.
* Start/stop barriers of `IterateTS` (2 condvar barriers per `step` interval): negligible.

### 1.6 Other checks

* `tools/denormal.h` is x86-only (`BOOST_ARCH_X86`). AArch64 does have `FPCR.FZ` (bit 24) and
  `FZ16`; CLAUDE.md's "no FPCR.FZ on arm64" is wrong, it is simply not implemented. Apple cores
  handle subnormals at full speed, so no gain is expected and enabling it would break bit-identity.
* Huge pages: no user-visible superpage API on Apple-silicon macOS (the `VM_FLAGS_SUPERPAGE_*`
  flags are x86-only); pages are 16 KB and the access pattern is sequential, TLB cost ≈ 0.
* `aligned_allocator` / `posix_memalign` give 16-byte alignment only; irrelevant for streaming.

---------------------------------------------------------------------------------------------------

## 2. Standalone measurements (kernel_bench.cpp)

Faithful copy of the stock loops (same member indirections; function size 234 vs 237 in the dylib)
versus the hoisted loops, same layout, 4000 unique operators, patch-x5 grid, 8 timesteps, and the
tutorial grid, 600 timesteps. Every variant was memcmp'd against the stock single-thread result.
Background load from other sessions: 14-55 % during these runs.

Patch x5 grid (7.86 MC), 2 barriers per timestep (run 1 / run 2):

| config | stock | clean |
|---|---|---|
| 1 thread | 488 / 485 | 878 / 882 |
| 4 thr static + condvar | 1378 | 1461 |
| 4 thr dynamic + spin | 1423 | 1548 |
| 8 thr static + condvar | 1553 | 1645 |
| 8 thr dynamic + spin | 1635 | **1689** (= 125 GB/s at 74 B/cell) |
| 10 thr static + condvar | 1510 | 1650 |
| 10 thr dynamic + spin | 1420 | 1623 (spinning loses when other load is present) |

Patch x5 grid with 44 condvar barriers per timestep (as openEMS does for the patch):

| config | stock | clean |
|---|---|---|
| 4 thr static + condvar | 1295 (-6 %) | 1378 |
| 8 thr static + condvar | 1299 (-16 %) | 1362 |
| 10 thr static + condvar | 1271 | 1390 |
| 10 thr dynamic + 44 spin barriers | 1517 | 1535 |

Tutorial grid 49x47x45 (0.104 MC):

| config | 2 barriers, stock | 2 barriers, clean | 44 condvar, stock | 44 condvar, clean | 44 spin + dynamic, stock | 44 spin + dynamic, clean |
|---|---|---|---|---|---|---|
| 1 thread | 451 | 819 | 409 | 728 | – | – |
| 4 threads | 1196 | 1854 | **353** | 386 | 1269 | **1840** |
| 8 threads | 1101 | 1570 | 138 | 145 | 1263 | 1675 |
| 10 threads | 1011 | 1346 | 114 | 117 | 1066 | 1410 |

The 44-condvar column reproduces the measured openEMS behaviour (353/138/114 here vs 205/86/64
MC/s for the real tutorial at 4/8/10 threads, the remainder being the Mur faces and the dumps).

---------------------------------------------------------------------------------------------------

## 3. Where the "30 % CPU gap" comes from (patch x5, 8 threads, 7.55 ms per timestep)

Accounting (harness numbers + measured barrier costs + instruction counts; cycle rates assumed):

| term | ms / TS | how |
|---|---|---|
| stock loops, 8 threads, static split, 2 barriers | 5.06 | kernel_bench 1553 MC/s |
| 42 extra condvar barriers x 24 µs (in-context cost at 8 thr) | 1.0 | kernel_bench: 1553 → 1299 |
| Mur ABC, 6 faces: 238k face cells x 190 instr = 45M instr / 8 thr at ~3 instr/cycle, 4.4 GHz | ~0.45 | estimate |
| nf2ff dumps + probes | ~0.1 | step-1 measurement (< 1 %) |
| sum | 6.6 | measured 7.55; the rest is other sessions' load during step 1 ("others 53 %") and E-core slowness on the scalar Mur loops |

So the gap to the Swift loop (1491 MC/s, 10 cores, GCD dynamic scheduling, ~25 instr/cell) is not
the memory bus: it is (1) the barrier structure, (2) a loop that does 2x the necessary instructions
and starves the memory system of parallelism (single thread 29 GB/s), (3) static slabs on a
4P+6E machine, (4) scalar extension code. With the loop fixed and dynamic scheduling the CPU
reaches 125 GB/s, the same as the Metal kernel (127 GB/s).

Notch x3 (845 MC/s, 6.2 ms/TS at 8 threads), estimate: PML = 2 slabs x 9 x 224 x 34 = 137k cells x
~500 instr = 69M instr ≈ 5.3 ms single-thread; critical path 2/9 of it at 8 threads = 1.2 ms
(19 % of the TS), 3/9 at 4 threads = 1.8 ms (23 %). Plus 36 extension barriers (0.9 ms at 8 thr),
plus 5.6 % z-padding. Single-thread evidence: notch x3 290 MC/s vs patch x5 394 (-26 %), notch
tutorial 133 vs patch tutorial 255 (-48 %; PML there is 20.7k cells x 500 = 10M instr against
12.7M for the volume).

---------------------------------------------------------------------------------------------------

## 4. The items in detail

### A. Barrier diet + spin/park barrier (plan step 2, new)

What: in `Engine_Multithread::Do*/Apply2*`, barrier once per hook group instead of once per
extension, and skip the group entirely when no extension implements that hook. Give
`Engine_Extension` a bitmask of implemented hooks (set in the constructor of UPML, Mur, excitation,
lumped RLC, ...). Replace `boost::barrier` with an atomic generation barrier that spins ~20-50 µs
then parks (`std::atomic::wait`, measured 0.2-1 µs at ≤ 8 threads). Increment `numTS` before the
last barrier.

Hook conflicts to respect (needed for bit-identity): `DoPre/DoPostVoltageUpdates` of Mur and UPML
only read engine fields and write their own arrays → one barrier per group is safe. In
`Apply2Voltages` two Mur faces write the same edge cells (x-face writes Ey,Ez on x=0 including
y=0; y-face writes Ez,Ex on y=0), and today the later extension in priority order wins; keep one
barrier per extension in that group (7 for the patch) or make edge writes exclusive to the last
face (same final bits, 1 barrier). UPML regions are disjoint by construction
(`Create_UPML` skips corners). Result: patch 44 → 4-10 barriers, notch 38 → 7.

Gain: measured in context: 42 condvar barriers cost 0.36 ms (4 thr) / 1.0 ms (8 thr) per TS on
the big grid (+5 % / +15 %) and 0.21 ms (4 thr) / 0.66 ms (8 thr) on the tutorial grid where the
timestep is 0.09 ms of work (+60-100 % at 4 threads, 5-8x at 8-10 threads). Risk: low.
Verify: openems_bench probes/S-params bitwise vs the current engine, both models, both sizes, 4 and 8 threads.

### B. Inner-loop rewrite (plan step 2)

What: `UpdateVoltages_clean/UpdateCurrents_clean` in `kernel_bench.cpp` are drop-in replacements
for `engine_sse_compressed.cpp:51-311`: local `__restrict` pointers for the two field arrays, the
index array and the six tables, per-line base pointers, `ptrdiff_t` offsets, and `a = v*vv;
v = a + vi*t` (one store; same fmul-then-fmla contraction as today, so bit-identical, verified by
memcmp after 8 and 600 timesteps). The z-wrap uses `__builtin_shufflevector` (one `ext`).
Optionally keep the `union`, but all stores through `v4sf` pointers.

Gain: single thread 488 → 878 MC/s (1.8x). Bandwidth-bound big grid: +6-9 % static, +3-5 %
dynamic. Compute-bound tutorials: +50-80 % (1196 → 1854 at 4 threads). Also the precondition for E
(after fusion the loop is compute-heavier). Risk: low; `GetVolt/SetVolt` accessors untouched.
Verify: as A. Also compare `otool` instruction count of the new loop (expect ~45 per iteration).

### C. Scheduling (plan step 2)

What: replace the static slab split with chunks of 2-4 x-planes handed out from an atomic
counter (threads keep consecutive planes so the x-1 plane stays in L2); workers spin-then-park;
run the main thread as worker 0; `numThreads=0` → start at `AvailableThreads()` (or 8) and only
probe downwards, never ramp from 1. Optionally `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE)`
on workers so other sessions' load does not push them to E-cores (measured: no effect on barrier
cost; effect on placement not measurable here).

Gain: static → dynamic measured +5 % at 8 threads on the big grid, +15-25 % on the tutorial
grid; default-engine users +40-60 % from the ramp fix alone (615 → ~1000 MC/s on patch x5).
Risk: none for results; spinning hurts when the machine is oversubscribed (10 thr dynamic+spin
1420 vs static 1510 under load) → park after a short spin and leave one core to the OS/other
sessions by default (8-9 workers + main).

### D. Mur / UPML engine paths (plan step 2, new)

What: add `Engine_sse` specialisations that work on `f4vector`s directly:
* x- and y-PML slabs and x/y Mur faces cover the full z range, so a PML cell row is exactly the
  3-component f4vector triples of the main loop: 4 hooks x 3 components become `fmul/fmls/fmla.4s`
  on contiguous data with the flux arrays laid out the same way (I-J-K-N, f4vector), no `udiv`.
* z-PML / z-Mur touch one lane of consecutive slots (`z ↔ (z%nvec, z/nvec)`): precompute the
  (slot, lane) pair per z once (no division in the loop), keep scalar math with the same fmul/fmsub
  pairing as today.
* Split PML work by (x,y) rows across threads (2016 rows for notch x3) instead of 9 x-lines.
Gain: patch x5 +5 % (Mur 0.45 → ~0.05 ms/TS), notch x3 +15-25 % (PML 1.2-1.8 → ~0.2 ms/TS plus
the imbalance fix), tutorial patch +25 % (Mur ≈ 34 % of its instructions), notch tutorial
+40-60 % (PML ≈ 45 %). Risk: medium for bit-identity (vector vs scalar contraction must match:
`f_help = vv*E - vvfo*flux` is `fmul + fmsub` scalar → use `fmul + fmls` vector); otherwise
S-params agree to ~1e-7. Verify: bitwise probe comparison on the notch (PML) and patch (Mur).

### G. Dumps and probes off the critical path (new)

What: run `ProcessFields::CalcField` for the 12 nf2ff faces on the worker threads (they are
independent; replace the virtual `GetEField` with a direct f4vector reader) and hand the HDF5
write to a helper thread; probes are already cheap. Gain: tutorial patch ~+20 % today
(measured 22 % dump cost), and once A-D shrink the timestep to ~0.05 ms the dumps dominate
(0.03-0.1 ms amortised per TS) → +40-60 %. Big models ~1 %. Risk: none for results.

### E. Fused E/H sweep (plan step 4, promote)

What: one sweep per timestep: for x ascending do E(x) then H(x-1). E(x) needs H(x), H(x-1) old
(H(x-1) is updated after), H(x-1) needs E(x-1), E(x) new (both done) → identical operands,
bit-identical. DRAM per 4 cells: read volt+curr (96) + write both (96) + index (4, once) =
196 B → **49 B/cell** instead of 74 (-34 %). Each thread keeps a 3-plane window (3 x 0.88 MB
for patch x5) in L2: 4 P-threads = 10.6 MB of the 16 MB P-cluster L2; E-core threads (4 MB
shared L2) will spill part of it, so expect the gain mainly from the P-cores. Slab boundaries
need one flag per boundary ("E(x_start) of the next slab done") instead of a global barrier.
Extension hooks become per-plane: Mur y/z faces and UPML are plane-local; the x-face Mur needs
E(x=1) new before H(0) → run its post/apply right after E(1). Probes/dumps see the same end-of-
timestep state. Gain estimate: 125 GB/s / 49 B = 2550 MC/s ceiling; compute ceiling after B is
878 x (4 + 6 x 0.4) ≈ 5600 → expect ~2200-2400 MC/s on patch x5 (+35-45 % over A-D). Tutorials: 0.
Effort: new engine class + per-plane hook interface, 1-2 weeks. Multi-step temporal blocking
(k ≥ 2 full timesteps) is the natural continuation but needs 2k+2 planes per thread (k=2: 7 MB per
P-thread, borderline) and complicates probes; do k=1 first.

### H. fp16 storage (plan step 4)

Halves the field bytes: 74 → 38 B/cell (49 → 26 after E). CPU cost is one `fcvtl/fcvtn` per
vector load/store. Not bit-identical: 11-bit mantissa, rounding noise ~5e-4 per update accumulates
over 10^4 timesteps → noise floor roughly -60 dB; a -40 dB S21 stopband or a -50 dB end criterion
may move. Test on the GPU first as planned, compare S-params to fp32 at 1e-3.

### F. Metal engine (plan step 3) -- see §5 and §6

---------------------------------------------------------------------------------------------------

## 5. What in the CLAUDE.md plan looks wrong or low-value

1. "GPU gets ~15-20 % more of the bus than the CPU cores" / step 3 as a bandwidth play: with the
   loop and scheduling fixed, the CPU reaches 125 GB/s here (1689 MC/s at 74 B/cell) against the
   GPU's 127 GB/s (1763 at 72 B/cell). A Metal engine at the same bytes/cell buys ~5 % for weeks of
   work and loses every extension that stays on the CPU. It only pays with fp16 (H) or
   threadgroup-memory temporal blocking. Do A-D (and E) first; they are 3-5 days of C++.
2. `m_Op_index` → uint8/uint16: < 1 % (the index is per 4 cells = 1 B/cell, 2 B/cell of 74).
3. Build flags: `-O3` is already what CMake Release uses; `-mcpu=apple-m4` produces the identical
   instruction stream (verified); fp-contract is already on (`fmla` present); `-ffast-math`
   would allow reassociation (not bit-identical) and gains nothing because the loop is not
   FP-bound (15 of 94 instructions); LTO changes nothing in the hot loop. 0 %.
4. "check thread count / chunking in engine_multithread.cpp": the real issues are the
   per-extension barrier (44/38 per TS), the condvar implementation (5-25 µs each), the static
   split on 4P+6E, and the 1→N ramp of the auto-tuner. None of these is "thread count".
5. "Flush-to-zero: no FPCR.FZ on arm64": AArch64 has FPCR.FZ; it is just not implemented in
   `denormal.h`. Apple cores have no subnormal penalty, so leave it off (bit-identity).
6. Missing from the plan: the scalar Mur/UPML paths with `udiv` (D), the barrier structure (A),
   the tutorial-size behaviour (A, C, G), and CPU-side traffic reduction by E/H fusion (E), which
   is the only CPU route below 74 B/cell that keeps bit-identity.
7. Layout waste from z-padding is real but model-dependent (notch x1 12.5 %, notch x3 5.6 %,
   patch x1 6.2 %, patch x5 0 %). The engine-side fix (vectorize along the longest axis) touches
   every extension; the cheap test is model-side: build the notch with x↔z swapped (nvec 4 → 59,
   padding 0.4 %, 59-iteration inner loop) and measure; results would agree to ~1e-6 but not
   bitwise (curl term order changes with the component mapping).

---------------------------------------------------------------------------------------------------

## 6. Notes that should shape the Metal engine if it is still built

* Everything that runs every timestep (excitation, Mur, UPML, lumped RLC, steady-state) must be a
  GPU kernel before command buffers can batch 50 timesteps; a CPU hook per timestep means a
  CPU↔GPU round trip (~50-100 µs) per TS: ~1 % on patch x5, fatal for the tutorials (0.05-0.4 ms/TS).
  Probes at Nyquist/4 intervals (34-330 TS) can stay on the CPU.
* The compressed operator is per f4vector: the 4 lanes of a table entry hold 4 different z-cells
  (different dz / material), so a per-cell GPU table needs a per-cell index of unique 12-float
  tuples; with graded meshes that is 10^4-10^5 entries → a uint16/uint32 index per cell
  (2-4 B/cell), not the 1 byte of `fdtd_bench2.swift` (3 materials). Budget 74-76 B/cell, same as
  the CPU; the GPU's edge is fp16 (native half) and the 32 KB threadgroup memory for 2.5D tiling.
* Keep the CPU engine's I-J-K-N f4vector layout in the shared buffers if CPU extensions/probes
  read them through `Engine_Interface`; otherwise every accessor needs a mapping.
* The 1763 MC/s GPU number was measured with the CPU idle; CPU-side extensions running
  concurrently share the same 150 GB/s.
* The GPU's MLP advantage disappears once the CPU loop issues loads without the dependent
  pointer chains (B); do not expect the "GPU 1.7x" of CLAUDE.md to survive A-D.

---------------------------------------------------------------------------------------------------

## 7. Files produced (scratchpad, not in the project)

* `barrier_bench.cpp` / `barrier_bench`: condvar vs spin vs atomic-wait barrier cost, 2-10 threads.
* `kernel_bench.cpp` / `kernel_bench`: stock vs hoisted openEMS loops, static+condvar vs
  dynamic+spin, with an `extra_barriers` argument; `UpdateVoltages_clean/UpdateCurrents_clean` are
  the proposed replacement code (bit-identical, verified).
* `engine_sse_compressed_O3.s`, `engine_sse_compressed_m4.s`: the engine file compiled alone with
  `-O3` and with `-O3 -mcpu=apple-m4` (identical instruction mix).
* `ext_*.s`: disassembly of the UPML and Mur `Engine_sse` template instantiations from the dylib.
* `mesh_dims.py`: mesh line counts, numVectors and padding of the four bench models.
