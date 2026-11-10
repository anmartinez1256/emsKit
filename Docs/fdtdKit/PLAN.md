# fdtdKit plan: the command line `emskit fdtd`

**Status:** written 2026-11-05; built, tested and run through the acceptance runs of v1a and v1b on 2026-11-06;
corrected after a cloud code review and tested and run through them again on 2026-11-09 (section 16 logs them).

This plan condenses the design of `emskit fdtd` v1: its specification (revision 2 of 2026-11-05, written after a
critic's review and checked against the files) and the fact sheet it rests on. It was written while a GPU-against-CPU
benchmark ran on the Mac, before anything in it was compiled or run; the facts of section 3 were read from the files
and probed on 2026-11-05. Section 16 logs what has been built and verified since, and where the code and this plan
differed, which was verified.

The code comments cite that specification as "spec N" or "spec section N", and some as a bare "section N"; it was a
working note and is not published. Its sections 2 to 16, the only ones the code cites, correspond to this plan as
follows: 2 = 4.1 and 4.2, with the reference identity of 2.6 in 5.2; 3 = 5.3, item for item, with item 7 (the
installed library) in 5.1; 4.1 and 4.2 = 5.1; 4.3 = 6.2; 4.4 = the Create lines per engine in 4.4; 5.1 = 6.1;
5.2 = 4.3; 5.3 = 4.3 and 9 (its output pump in 7.2, the record of each invocation in 7.1); 6 = 4.4, with the guard
of 6.3 in the check part of 4.2; 7 = 7.1 and 8; 8 = 7.2; 9 = 7.3; 10 = 10.2; 11 = 10.1 and 9; 12 = 11; 13 = 4.3;
14 = 10; 15 = the table of files in section 2; 16 = 12. The facts F1-F27, the rules S1-S10 and the smoke runs 1-13
have the same numbers in both.

## 1. Name and scope

- **fdtdKit** is the name the FDTD project (the openEMS fork, the benchmark harness and its checks, the toolkit knobs)
  takes in the documents and the paper since 2026-11-05; it was called emsKit before. The repository and its folder
  keep the name emsKit. **EMSKit** is the family: one Swift package with one `emskit` command and four kits, fdtdKit,
  femKit (finite elements), momKit (method of moments) and sbrKit (shooting and bouncing rays), each developed on a
  branch of its own.
- **`emskit fdtd`** is fdtdKit's command line, version 0.1.0: the library `Sources/fdtdKit` (all parsing lives there,
  so the tests reach it) and the `fdtd` case of `Sources/emskit-cli`.
- **v1 wraps the verified tools and installs nothing.** It never re-implements a tool. It parses the tools' printed
  lines strictly, builds every child's environment explicitly, and takes its verdicts from the tools' own lines. It
  writes only inside its own run folder and the outputs the user names (`--tag` tables, `--record`, `--output`,
  `--out-dir`), keeps backups of those next to them, and refuses every such location, defaults and the run folder
  included, that is or lies inside the installed prefix or the snapshot folder, holds one of them while it would be
  renamed or replaced, or is a file a tool writes in place (a `--tag` table, ab's record) that is a hard link of a file
  in one (`protected_path`, exit 2, no override; S3, section 10.2).
- The design is the "thin" one of three, with these parts taken from the other two: a runpy launcher that loads
  `usage.py` and `libinfo.py` under private module names; posix_spawn with process groups; a separate quiet-wait
  helper; library identity by sha256 (same bytes) and Mach-O LC_UUID (same build), with engines and knobs found in the
  library bytes; refusing timed commands while another simulation has an openEMS library open; `run SCRIPT`, which
  injects the engine, the thread count and nodumps into every `FDTD.Run`; the per-model `--nrts` defaults of
  `check.sh`; the TTY-only install confirmation (kept for version 2, section 14); the check bundle (deferred as
  `accept`).
- Family conventions: the envelope keys follow momKit (`tool "emskit"`, `kit "fdtd"`, camelCase, warnings and errors
  as issue objects); the schema names `emskit.fdtd.<command>/1`, lowercase snake_case codes and `--output FILE`
  follow sbrKit; usage errors exit 64 as in all three; only the family's four `--distribute` values are accepted.
- Size estimate (rough, 2026-11-05): about 3,200 lines of Swift, 290 lines of Python and 1,650 lines of tests. That is
  too much to build and verify in one session on a shared, loaded Mac, hence the two phases of section 2. As built
  (2618180): 11,071 lines of Swift in `Sources/` (29 files, among them the 567-line LauncherSource.swift that embeds
  the launcher), 545 lines of Python (the launcher) and 4,927 lines of Swift tests with 1,518 lines of fixtures.
- **Where (during development).** The command line was built on the branch `fdtdkit`, started from `main` at 00e8f7d
  (a commit of the unpublished history), in a worktree of its own. The EMSKit repository is the emsKit repository, so
  its root holds `bench/`, `scripts/`, `results/` and `BUILD.md` next to `Package.swift`. Nothing was built, tested or
  written in the worktrees of the other kits (branches `femkit`, `momkit` and `sbrkit`), where other sessions worked.

## 2. Phases

| phase | content | acceptance (logged in section 16 with the load and the run time) |
|---|---|---|
| v1a | `info`, `load`, `bench`, `ab`, `check`. Discovery, libraries (sha256, LC_UUID), knobs, configs, child environment, spawn (control pipe, injected signal source), concurrency, run folders, the bench/abtest/check parsers, verdicts, envelope, distribution records (logical jobs, LocalBackend). The launcher's exec mode (watchdog, report) | the unit suites pass; smoke runs 1-6, 12 and the bench part of 13; `emskit fdtd check cg29 --tag cliaccept --lite --rfsim DIR` gives ALL IDENTICAL with acceptance true |
| v1b | the launcher's script mode and class shim; `validate`, `debye-check`, `diamond-check`, `e2e`, `run`; the parsers for validation, debye, diamond, e2e and the openEMS lines | the unit suites pass; smoke runs 7-11 and the run part of 13; `emskit fdtd diamond-check cg29` PASS; `emskit fdtd e2e gcpw --lib cg29 --rfsim DIR` ok |

- `bench`, `ab` and `check` run under the launcher's exec mode, so that a stop request or a dead CLI ends them
  (section 9). That is why the exec half of the launcher is part of v1a.
- Each phase ends with a commit on `fdtdkit` and a dated entry in section 16 (what was built and verified, with the
  load) before the next phase starts. In the end, both phases were built and acceptance-run on 2026-11-06 and committed
  together as `60fd4a3`, with their dated entries in section 16.
- The run times of the acceptance runs were not known in advance; section 16 logs them, with the load.

**Files.**

| file | content |
|---|---|
| `Package.swift` | the EMSKit package with fdtdKit's targets only: the library `fdtdKit`, the executable `emskit` (target `emskit-cli`) and the test target `fdtdKitTests`; swift-tools 6.2, macOS 26. The sibling kits add their own targets; the merged file is the union of the four branches |
| `.gitignore` | momkit's file (blob 4205f78, the same on all three sibling branches), with one comment changed on 2026-11-06: line 3, on the paper's build files and the arXiv tarball. The merge base dbc1baa (a commit of the unpublished history) has the old line 3, so a merge of a sibling branch stays clean and keeps the new one |
| `Sources/emskit-cli/main.swift` | the siblings' template with `case "fdtd"` and, since 2026-11-06, the SPDX line on top. Every kit adds its own copy, so each merge is an add/add conflict, resolved as the union: the SPDX line, one comment line naming the four subcommands, and the four case lines |
| `Sources/emskit-cli/FdtdCommand.swift` | `enum FdtdCommand`, which forwards to `FdtdCLI.main` |
| `Sources/fdtdKit/*.swift` | FdtdKit (version, dispatch, the two usage paths, exit precedence), Context (FdtdContext; FdtdSystem with LiveSystem; FdtdSignalSource), Options, Discovery, Libraries, Knobs, BenchConfig, ChildEnv, Spawn, Concurrency, RunFolder, Parsers, Loads, Verdicts, Envelope, Distribution, LauncherSource, and `Commands/` with one file per command (debye and diamond share ScriptChecks.swift) |
| `Sources/fdtdKit/Python/fdtdkit_run.py` | the launcher (section 4.3), 545 lines at 2618180 (about 220 planned), excluded from the target. LauncherSource.swift embeds its exact bytes, and a test checks that the two are equal |
| `Tests/fdtdKitTests` | the suites of section 12, with `Fixtures/` |

Public types carry the `Fdtd` prefix. Swift 6 strict concurrency; shared state sits behind `Synchronization.Mutex`.
The library uses Foundation, CryptoKit and Synchronization only (no Metal, no Accelerate), so the sibling merge items
about Accelerate's LAPACK flags do not concern it.

## 3. Facts and traps

Verified on 2026-11-05. Line numbers refer to this repository as published (they were read at 00e8f7d, a commit of the
unpublished history; the lines cited are unchanged since), to openEMS at the fork's head 78fe656 (snapshot cg29;
1620939 before the rewrite of 2026-11-07, the same tree), to the installed v0.37.0 binding (`openEMS.pyx` beside the
module in the user site-packages) and to the toolkit's `rfsim/` at 4a7e20e.

| # | fact (source) | consequence |
|---|---|---|
| F1 | SIP strips `DYLD_*` when it execs a restricted binary: `/usr/bin/env`, `/bin/zsh`, `/bin/sh`, `/bin/bash`, `/usr/bin/caffeinate`, `/usr/bin/python3`, `/usr/bin/swift`, xcrun (and the `/usr/bin/otool` stub), time, nice, top, ps, ioreg | `DYLD_LIBRARY_PATH` goes only to Python processes the CLI starts itself. The zsh scripts get library folders as arguments: check.sh through `LIB@` labels to bench.py; debye_check.sh:36 and diamond_check.sh:40-57 set it on their own `python3` command lines |
| F2 | The python.org framework Python 3.14.6 is the first `python3` on PATH (PATH starts with `~/.local/bin`, then `~/opt/openEMS/bin`, then the framework's bin). Its entitlements allow DYLD variables and disable library validation. The SwiftPM `emskit` binary is ad-hoc signed and has no hardened runtime | the default Python is found on PATH, and that it keeps DYLD is proven by a probe, not assumed. A copied `emskit` loses the walk from its own path (section 5.3) |
| F3 | `bench.is_tolerant` reads `OPENEMS_FTZ` from `os.environ` as well as from the config (bench.py:91) | an inherited `OPENEMS_FTZ=1` makes every config tolerant, and check.sh then prints ALL IDENTICAL with nothing required to match. So every `OPENEMS_*` is removed from children, and knobs travel only in configs or `--knob` |
| F4 | bench.py exits 2 on MISMATCH (bench.py:397) and also on argparse errors, which come before it prints its header (bench.py:287 vs :300); a refused config exits 1. check.sh:36-41 counts any exit 2 as FAIL | verdicts come from printed lines, never from an exit status alone |
| F5 | abtest.py exits 0 even when runs differ. With `--run-redo` and `--quiet 0` it redoes every run (abtest.py:75); with `--redo` and `--quiet 0` it never redoes (:82) | the CLI parses the diffs itself; `--redo` and `--run-redo` require `--quiet` > 0 |
| F6 | An unknown engine name silently runs the multithreaded engine (BUILD.md section 8) | engines are checked against the library's help strings before the run and against the Create line after it |
| F7 | Version strings inside the libraries can be stale. BUILD.md section 5 gives the strings that the cg19 and cg20 tables print (-24-g087ce9e, -25-g315acee) and, since 2026-11-06, those of the files now in snap/cg19 and snap/cg20, which report the next ones (cg19 = v0.37.0-25-g315acee, cg20 = -26-gcd80d8c). The author's build folder build-gpu (prefix ~/opt/openEMS, ENABLE_METAL on) carries -26-gcd80d8c and matches no snapshot. The installed libopenEMS (string -24-g087ce9e) differed in bytes from snap/cg18 but was the same build (F20); since 2026-11-06 it is cg29's build (string -44-g074a687), again in other bytes (F20) | identity is the sha256 (same bytes) and the LC_UUID (same build) of each file; the version, knob set and engine set only name candidates |
| F8 | `~/opt/openEMS-dev/snap` holds 36 folders: 24 complete (stock, base, cg9 to cg29, cg29pre) and 12 incomplete. In an incomplete folder dyld loads the installed library for the missing file (diamond_check.sh:23) | an incomplete folder is refused as LIB; the tests check properties of each folder, never these counts |
| F9 | In the v0.37.0 binding, `_SetLibraryArguments` turns a 1-valued non-integer option into True, then one equal to 0 (False, 0, 0.0, numpy zeros) into "", and that ends the option list. The integer options are verbose and numThreads | injected `FDTD.Run` options always go first; `optionsLost` is evaluated for that binding only |
| F10 | rfsim's `core.run(m, sim_dir, threads=0, cleanup=True, probe_end_db=PROBE_END_DB, probe_end_hold=PROBE_END_HOLD)` (core.py:331) sets and pops `OPENEMS_PROBE_END_*` around `m.fdtd.Run(..., verbose=0, numThreads=threads)`. Read at import: PROBE_END_DB (-60, from `RFSIM_PROBE_END_DB`, 0 = off; :327), PROBE_END_HOLD (0.5; :328), Z_MULT (`RFSIM_Z_MULT`; :22), `launch.MIN_CELL` 0.05 (launch.py:28) and `launch.P0["min_cell"]` (`RFSIM_MIN_CELL`; :68) | the CLI never sets `RFSIM_*`, except `RFSIM_PATH` from discovery; e2e passes the toolkit's own values and records them |
| F11 | `scripts/e2e/run_one.py MODEL FLOOR DB HOLD OUT`: FLOOR 0 is the toolkit default, DB is `off` or a number, and any MODEL other than gcpw runs the SMA. `E2E_ENGINE` passes the engine through a proxy (:31-40). `RFSIM_PATH` is required (KeyError otherwise, :17-18). After core.run it post-processes whatever the run left (:44-56) | the CLI accepts only gcpw or sma |
| F12 | `usage.Sampler` samples every 0.5 s (usage.py:51), so it runs ps and ioreg twice a second; it counts its own process tree as "self" and everything else as "others". `stop()` returns None only off macOS (:85-86). The return codes of ps and ioreg are not checked (:24, :40), so a failed sample reads as zero use (:93), like an idle Mac. `gpu dev` is printed only when ioreg gave utilisation samples (:113-114); every `during` part in `results/*_cg29.txt` has it (54 of 54) | whatever samples must be an ancestor of the simulation; a load counts only when it is valid (section 8) |
| F13 | openEMS prints `Create FDTD engine[ (...)]`, `Time for N iterations with C cells : T sec`, `Speed:` progress lines and the RunFDTD stop messages (openems.cpp:1911, :1917, :1921, :1924) | the parsers rely on these lines (section 4.4) |
| F14 | lsof exits 1 whenever any selected file or command is not found, even after printing records for the others: on 2026-11-05 three library files gave another session's abtest.py and exit 1, while the installed file alone gave the same records and exit 0. `/usr/sbin/lsof -n -w -F pcn -c Python -c python -c openEMS` lists the files of every Python and openEMS process in 0.05 s. With `-F`, lsof always adds `f` records | the concurrency check is decided from the records, never from the exit status, and runs two scans (section 10.1) |
| F15 | Upstream removed its MPI engine in 5261463, which v0.37.0 contains | MPI is only a reference design in section 11 |
| F16 | femkit, momkit and sbrkit share the merge base dbc1baa. Each adds `Package.swift`, `.gitignore` (blob 4205f78 in all three) and `Sources/emskit-cli/main.swift` (one template that differs only in its comment line and its case line); femkit also adds `FemCommand.swift` and `ValidateCommand.swift` (`enum Validate`). None changes README.md | `main.swift` and `Package.swift` are add/add conflicts, resolved as unions; `.gitignore` is taken verbatim; fdtdKit's command types are internal to its module, so `Validate` does not clash |
| F17 | Formats: bench rows and summaries bench.py:338-382 (`same` at :369, tolerance at :327); abtest lines abtest.py:49-114 (`# summary` at :95, medians over all runs at :99-100, the record appended only at the end, :104-106); check.sh's final lines :40, :55, :59, :61; debye_check.sh:58-66; diamond_check.sh:32-61 | the parsers use exactly these formats (section 4.4) |
| F18 | openEMS's signal handling. SetupFDTD installs a force-exit SIGINT handler (openems.cpp:1369; tools/signal.cpp:113-121, `std::_Exit(128 + signal)`). RunFDTD installs a graceful one (:1696): the first SIGINT stops the time loop at its next check (CheckAbortCond, :1630-1647), and the handler then switches to force exit; the original handler comes back at :1945. The binding runs setup and run without the GIL (openEMS.pyx:694, :700), so a Python signal handler waits until `FDTD.Run` returns. `SetAbort(True)` (pyx:703; openems.h:105) sets m_Abort, which only the constructor resets (openems.cpp:101) and CheckAbortCond tests first; a file named ABORT in the simulation folder does the same. After an abort `FDTD.Run` returns normally and the script goes on (run_one.py:44-56 would post-process the truncated run) | stop requests use SetAbort through the launcher, never SIGINT (section 9) |
| F19 | The installed binding has the package version 0.37.0. Its `openEMS.pyx` has `opt = ""` at :595-606, and at :679-685 it takes the absolute path of sim_path and changes into it, never back. The fork's binding (`python/openEMS/openEMS.pyx`) skips False options instead. Boost parses options case-insensitively (tools/global.cpp:130-135), and a key given in two spellings raises `option '--numThreads' cannot be specified more than once` | the shim normalises keys, records simPath before the call, and evaluates `optionsLost` only for the legacy binding |
| F20 | LC_UUID survives `cmake --install`; sha256 does not. The installed libopenEMS (UUID 24C8A7F2-...) was snap/cg18's build until 2026-11-06; since then it is snap/cg29's (UUID 40BC8CFF-...), copied with the prefix's install name and rpath and re-signed, which kept the UUID and changed the sha256 (section 16). The installed libCSXCAD and libnf2ff have the UUIDs of cg18, cg28 and cg29, and the bytes of cg29's copies (on 2026-11-06 info named more snapshots for both, section 5.1). build-split = cg29 (40BC8CFF-...); build-gpu (9A6EDCEE-...) matches no snapshot. No two complete snapshots share a libopenEMS UUID. Stock: libopenEMS 7eaaee52 (UUID B1A89DA1-...), libCSXCAD 9f4f419f with 561,096 B (the fork copies have 561,320 B and the same string v0.7.0), libnf2ff 28aae278 with 318,936 B (fork 322,016 or 322,024 B) | identity is per file, by sha256 and UUID; stock is judged on all three files |
| F21 | The validation suite writes the bare token NaN for a crashed case (run_validation.py:79, and :102 dumps with NaN allowed). common.py:56-67 points fd 1 at a per-run log around `fdtd.Run`. The report prints `Case times (s)` (:96) | tool JSON is read as JSON5; the launcher's markers go to a saved fd |
| F22 | diamond_check.sh always tests the tiling tuner (:53-55). `timesteps of tuning` and `OPENEMS_DIAMOND_TUNE` occur only in cg28 and cg29, although cg19 to cg27 contain metal-diamond, `OPENEMS_EXPORT_FIELDS` and `OPENEMS_FTZ`. The engine reads TILE with `sscanf("%u%*[,:]%u")` and checks only M >= 2K-1 (engine_metal_diamond.mm:1270), so V may be 0; the script's odd case is `OPENEMS_DIAMOND_TILE=7,0` (:48) | the diamond gate requires the tuner; the TILE rules are in section 6.2 |
| F23 | The eight `=1` switches act on any value other than empty or 0 since patch 0006; up to patch 0005 any value, 0 included, switched them on (BUILD.md section 7). `bench.is_tolerant` treats '0' as off (bench.py:91) | those switches accept only `1` |
| F24 | xcode-select points at the Command Line Tools; Swift 6.4, target arm64-apple-macosx27.0.0. The siblings run swift-testing with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | the test commands of section 12 |
| F25 | The sibling worktrees hold the old harness: their `bench/` has bench.py, check.sh, libinfo.py, models.py, runner.py, step1.sh and validation, but no abtest.py and no usage.py, and dbc1baa's bench.py prints no load | the tools-tree markers of section 5.3 |
| F26 | `RFSIM_PATH` is not set in the author's shell. The toolkit repository's HEAD is 26c5f64; `rfsim/` last changed in 4a7e20e and is clean | smoke and acceptance runs pass `--rfsim`; the record keeps both commits |
| F27 | Inherited Python variables change what the tools do: `PYTHONOPTIMIZE` skips diamond_compare.py's grid assert (:10); `PYTHONWARNINGS=error` turns rfsim's `warnings.warn` (core.py:104, :323, :403) into exceptions. bench's runner and check.sh's python3 run without `-B`; `bench/__pycache__/` exists and is ignored by git (.gitignore:1) | a whitelist for `PYTHON*`, and `PYTHONDONTWRITEBYTECODE=1` (section 6.1) |

Not established on 2026-11-05: the run times of `check.sh` with LITE=1 and of diamond_check.sh; which code build-gpu
holds (its UUID matches no snapshot, F20), so what `cmake --install build-gpu` would install; whether Homebrew's
python3.14 keeps DYLD and sees the user-site modules (the probe decides at run time); the exception type of an
unknown openEMS option; whether the installed (cg18) `bin/openEMS` runs on cg29 libraries through DYLD (XML runs are
deferred). Since 2026-11-06 the installed libopenEMS is cg29's, while `bin/openEMS` is still the one installed with
cg18 (section 16).

## 4. Commands

### 4.1 Grammar

- `emskit fdtd --version` prints `{"fdtdKit": "0.1.0", "repoHead": "<short head>"}` on stdout and exits 0 (`repoHead`
  is left out when no tools tree is found), like sbrKit's `{"sbrKit": ...}`. `--help` and `COMMAND --help` print
  usage on stdout and exit 0.
- **Two usage-error paths, on purpose.** Without a command, or with an unknown one, there is no schema to name an
  envelope: usage goes to stderr and the exit is 64 with no envelope, as in the family's `main.swift`. Once the
  command is known, every usage error gets an envelope of that command's schema (status `error`, code `usage`, the
  nearest valid option within edit distance 2 as the hint) and exits 64: an unknown option, a missing value, a value
  after a switch (it shows up as a stray positional), a repeated non-repeatable option, a stray positional, the
  form `--name=value`, and an empty value of an option that takes a path (below the table). A typo can never
  silently run another configuration (femKit's validate rule). A positional that starts with `-` (`check cgD --tag t
  -snaps DIR`, `debye-check -x`, `run -board.py`) is a usage error on every command: an option written with one
  dash is never read as a SNAP, LIB, MODEL or SCRIPT, and a folder or script of such a name is given by its path
  (`./-x`). The value of an option may start with one dash (`--probe-end -60`), and so may anything after run's
  `--`.
- **check's open SNAP list.** check takes any number of SNAPs, so two slips on one line can still parse:
  `check cgD --tag t --stock -snaps DIR` reads `-snaps` as the value of `--stock` and DIR as a second SNAP (the
  same after `--extra`, or after a path option such as `--runs`), and `check cgD --tag t snaps DIR` reads two more
  SNAPs. No spelling rule closes the form without a dash, so none was added. Such a line names no `--snaps`, but
  DIR is then a library that the line names by its path, and every such folder is protected for that command
  (section 10.2): an `--output` inside DIR is refused (`protected_path`, exit 2), with and without `--overwrite`,
  before the command finds that DIR holds no library. A LIB without `/` also protects a folder of that name in
  the working directory, so a DIR written as a bare name (`mysnaps`) is covered like `./mysnaps`. The commands
  with a fixed number of positionals refuse the same slips as a stray positional (64) and write nothing.
- **A line that did not parse writes no file.** When the parser refuses the line (a usage error, 64, or the bad
  `--tag` that it finds for check and validate, 2), the envelope goes to stdout, nothing is created or renamed, no
  probe and no child is started, and no signal handling is installed. When the line holds `--output` (also as
  `--output=FILE`; after run's `--` the tokens are the script's), one stderr line says that `--output` is not
  written because the line was not understood. Nothing else of such a line is read back, `--overwrite` and
  `--dry-run` included: what its tokens mean is not known, so no folder can be judged safe for its file. (An
  intermediate version of 2026-11-10 wrote the envelope to FILE and read the discovery options back from the line;
  three review rounds each found a spelling it did not read, and it was withdrawn, section 16.) A usage rule that
  is found after the options are parsed (bench's `--knob` rules against its configs, a `--knob` of validate that
  is not NAME=VALUE, `--output` that is a folder) belongs to a line that parsed: its `--output` follows section
  10.2 like any other command's. A usage error is reported before a bad `--tag` on the same line (64 > 2); that
  holds for the usage rules found after the options are parsed too.
- Options take the form `--name value` or `--name`, in any order before `--`; after `--` (`run` only) everything goes
  to the script untouched. Integers are decimal digits; floats go through `Double(...)` and must be finite.
- The CLI reads no config file. From its environment it reads only PATH, HOME, `OPENEMS_BENCH_SNAPS`,
  `OPENEMS_BENCH_RUNS` and `RFSIM_PATH`.

Common options ("run commands" are all but `info` and `load`):

| option | default | meaning |
|---|---|---|
| `--repo DIR` | discovery (section 5.3) | the emsKit tools tree |
| `--python PATH` | discovery | the interpreter for every Python child |
| `--snaps DIR` | `$OPENEMS_BENCH_SNAPS`, else `~/opt/openEMS-dev/snap` (bench.py's default) | the snapshot folders |
| `--rfsim DIR` | `$RFSIM_PATH` | the toolkit folder that contains `rfsim/` |
| `--runs DIR` | `$OPENEMS_BENCH_RUNS`, else `/tmp/openems_bench_runs` (bench.py's default) | the base of the run folders (run commands); never in a protected folder (section 10.2) |
| `--output FILE` | stdout | write the envelope to FILE (stdout stays empty); refused if FILE exists, unless `--overwrite`; FILE is a file: a folder or an empty value is a usage error (64), whatever `--overwrite` says; never in or over a protected folder (section 10.2) |
| `--overwrite` | off | allow replacing named outputs; each old file or folder is first kept next to it as `NAME.previous-STAMP`; never one in or over a protected folder (section 10.2) |
| `--keep-runs` | off | keep the bulky subfolders after an ok run (run commands) |
| `--dry-run` | off | discovery, probes, plan and refusals run; nothing is spawned except read-only probes; no run folder |
| `--no-caffeinate` | off | no `caffeinate` beside the run |
| `--allow-concurrent` | off | lift the concurrency refusal of bench, ab and e2e, also for an unknown scan result |
| `--warn-cpu PCT`, `--warn-gpu PCT` | 150, 10 | mark rows whose others' CPU or GPU use exceeds these as `loaded` (warning `loaded_mac`); never blocks a run |
| `--nodes N`, `--hosts FILE`, `--distribute MODE` | 1, none, auto | the family distribution flags (section 11) |

**Options that take a path.** `--repo`, `--python`, `--snaps`, `--rfsim`, `--runs`, `--output`, `--hosts`, and of
the commands `--results` (bench, validate), `--record` (ab), `--out-dir` (e2e) and `--build` (info). An empty value
(an unset shell variable: `--runs "$DIR"`) is a usage error (64) for each of them, found by the tokenizer before
anything is probed: made absolute, the empty path would be the working directory. Where the option takes a FILE, a
folder is refused before anything runs: `--output` and `--record` with a usage error (64; `--record` goes through
the checks of `--output`: protected folders first, then a folder, then a missing parent folder, exit 2), `--hosts`
with `hosts_file_missing` (2), `--python` with `python_not_found` (3), and run's SCRIPT with `script_not_found` (2).

### 4.2 The ten commands

| command | tool | verdict | writes |
|---|---|---|---|
| `info [--lib L]... [--build DIR]...` | probes only: the repo, Python (probed without a snapshot), the machine (chip, P and E cores, memory, OS), the installed library and every snapshot, build folders, rfsim, the two scans, the knob registry | exit 0 (130 after a stop request, section 9); a missing piece is null plus a warning, under the code a run command stops with (`rfsim_not_found`, `library_not_found`, ...; section 7.3) | nothing; no run folder, no caffeinate (about 1 s, mostly the snapshot index and the Python probe; section 16) |
| `load [--seconds S]` | the LOAD helper (`usage.Sampler`, S 1 to 600, default 5) under the launcher | the load is valid, else `load_unavailable` (exit 4) | nothing |
| `bench MODEL --config CFG...` | `bench/bench.py` | a `MISMATCH:` line fails (1); `IDENTICAL:` is ok; `NOTHING COMPARED` or `NOTHING REQUIRED TO MATCH` is ok with `nothing_verified`; with `--exact`, a compared row that is not exact fails | the run folder; with `--tag T`, `results/MODEL_s%g_nN_T.txt` (or `--results DIR`) |
| `ab MODEL --config A --config B...` | `bench/abtest.py` | ok when abtest exits 0, every config has a summary line, and every config that must match has only `identical` kept runs | the run folder; the record `RUN/abtest.txt`, or `--record FILE [--append]` |
| `check SNAP... --tag T [--lite]` | `bench/check.sh` | its last line plus an independent guard (they disagree: `verdict_disagrees`, exit 4); ok only against the stock v0.37.0 build of all three libraries, otherwise partial with `acceptance: false` (section 5.2) | the run folder; the 4 or 6 tables `results/*_T.txt` (check.sh cannot be redirected) |
| `validate [--lib L] [--engine E]` | `bench/validation/run_validation.py` | ok when it exits 0, every check passed, the libraries came from the expected folder, and each case has a run of the requested engine | the run folder; with `--tag T`, `results/validation_T.json` and `.md` |
| `debye-check LIB [--ref LIB]` | `scripts/checks/debye_check.sh` | `PASS: every comparison is identical` is ok, `FAIL:` fails | the run folder |
| `diamond-check LIB` | `scripts/checks/diamond_check.sh` | as debye-check | the run folder |
| `e2e gcpw\|sma` | `scripts/e2e/run_one.py` with the toolkit's own defaults | ok when it exits 0, the `RESULT {...}` line and `result.json` exist, and every call's Create line is the engine's | `RUN/e2e`, or `--out-dir DIR` (`result.json`, `sp.npz`) |
| `run SCRIPT [-- ARGS]` | any openEMS Python script; engine, threads and nodumps injected into every `FDTD.Run` | the script exits 0, plus the engine and library checks | the run folder (and whatever the script writes) |

Every location in the writes column, defaults included, passes the protected-folder check before anything runs (S3,
section 10.2); what a `run` script writes by itself is not checked.

**bench.**
- MODEL is patch, notch, kgcpw or ksma (bench's MODELS); kgcpw and ksma need rfsim (`rfsim_not_found`, exit 2).
- `--scale` (default 1) is a finite number > 0 that `%g` leaves unchanged, because bench names the run folders and the
  `--tag` table `MODEL_s%g_nN` and two scales that print the same would share them (exit 64, hint "at most six
  significant digits").
- `--nrts` defaults, from check.sh: patch 1 → 10500, patch 5 → 1200, notch 1 → 16000, notch 3 → 2000, kgcpw 1 → 15000,
  ksma 1 → 6000. Any other (model, scale) pair needs `--nrts`.
- CFG is bench's grammar, `[LIB@]ENGINE[:THREADS][+nodumps][#NAME=VAL,...]`, and also `ENGINE+nodumps:THREADS`.
  `installed@` is stripped (a bare CFG already means the installed library). LIB must not start with `-` (section
  5.1) or contain `@`, `#`, `,`, `;` or whitespace (`config_invalid`, exit 2); THREADS is digits only; ENGINE must be
  one of bench's engines (fastest, basic, sse, sse-compressed, multithreaded, gpu, gpu-reference, metal-diamond) and
  present in the library (`engine_unsupported`, exit 3). The first CFG is the reference.
- `--knob K=V` (repeatable) is appended to every CFG's `#` list, so the labels show it; a CFG that already sets K to
  another value exits 64.
- `--exact` needs two or more configs or `--repeat` >= 2, and requires every compared row, tolerant ones included, to
  be bit-identical.
- `--quiet PCT` (0 < PCT <= 1000) passes bench's quiet wait, with `--quiet-gpu` (default 10) and `--quiet-max`
  (default 900, bench's defaults); either of those without `--quiet` exits 64.
- `--tag T` (`[A-Za-z0-9_.][A-Za-z0-9_.-]*`, otherwise `tag_invalid`, exit 2; the same rule for check and validate)
  passes `--tag T --out RESULTS`; `--results DIR` must exist (`folder_missing`). Without `--tag` nothing is written to
  `results/`. A tag may not start with `-`: bench.py and run_validation.py (argparse) read such a value as an option
  and exit 2 before they print anything.
- Refused (exit 5) while the scans find another simulation (`simulation_running`) or cannot tell
  (`concurrency_unknown`), unless `--quiet` or `--allow-concurrent`. `--nodes` above 1 and `--hosts` exit 64: bench's
  speeds describe one Mac.
- After the run, `RUN/runs/` must hold exactly the one folder `MODEL_s%g_nN` (`tool_output_unparsed` otherwise), and
  every `rep*/openEMS.log` of a row must hold the engine's Create line (`engine_not_confirmed`, exit 4). A summary
  line needs one readable row per config beside it (`tool_output_unparsed` otherwise: a summary over rows the CLI
  cannot read confirms no engine and gives `--exact` nothing to look at); under `--exact`, `NOTHING REQUIRED TO
  MATCH` without a compared row gives `nothing_verified`.
- Warnings: `tolerant_rows` ("compared, not required to match"); `not_bit_identical_to_stock` for an FTZ knob;
  `gpu_fallback` for a metal-diamond row whose `rep*/openEMS.log` has a fallback line (section 4.4), which ab (per
  config and round), check (its extras) and validate (tool.log) give the same way.

**ab.**
- As bench, with at least two configs; `--rounds` defaults to 5. `--quiet-gpu` exits 64 (abtest waits for GPU <= 10 %
  itself and has no flag for it). `--redo N` and `--run-redo N` exclude each other and need `--quiet` > 0 (F5).
- The record: `--record FILE` is refused (`would_overwrite`) when FILE exists, unless `--append`; abtest appends at its
  end, so the CLI notes the size before the run and parses only the new part. `--overwrite` with `--record` exits 64.
  FILE goes through the checks of `--output` (section 4.1): an empty value or a folder, empty or not and with
  `--append` too, is a usage error (64), since abtest.py opens the record only after all rounds and the whole run
  would end as `tool_failed` without one; a FILE whose folder is missing is `folder_missing` (2).
- **Sampler checks.** A 1-second LOAD probe runs before and after the abtest run, because abtest's run lines carry no
  self figure and no `gpu dev`, so a sampler that saw nothing could not be told from an idle Mac there. A check
  before the run that is not valid gives `load_unavailable` (exit 4) and nothing runs; one after the run that is not
  valid makes every run's load invalid. A dry run plans both checks and runs neither, and a refused ab (section 10)
  records them as well: the invocations are the check before, abtest and the check after, as in a run, and abtest is
  the only job.
- Tolerance mirrors bench.py:327: when c0 is tolerant (a gpu* or metal-diamond engine, or `OPENEMS_FTZ=1` in its own
  knobs) every config is tolerant, and the envelope says so; otherwise each config is judged by its own CFG.
- The CLI computes each config's statistics itself from the kept runs with valid loads (section 8); abtest's own
  summary lines stay in `tool.log` and the record.

**check.**
- SNAP is a complete snapshot name, a folder, or `installed` (the folder of the loaded libopenEMS). `--tag T` is
  required. `--stock LIB` sets STOCK (check.sh's default is "stock"). A SNAP or `--stock` whose name or folder holds
  '@', '#', ',', ';' or a space cannot go into check.sh's configs (`config_invalid`, exit 2, field SNAP or
  `--stock`). `--lite` sets LITE=1; `--quiet-max S` sets
  QUIET_MAX and is allowed only without `--lite`; `--extra CFG` (repeatable, validated as a bench CFG: its library
  resolved, its engine and knobs present in that library, exit 2 or 3 before the run) goes into
  EXTRA, and tolerant extras give `extra_not_counted` (check.sh compares them but does not count them). The extras'
  libraries are listed in the envelope and scanned by the concurrency gate like the SNAPs. `--quiet`,
  `--repeat`, `--results`, `--knob` and `--config` exit 64 ("check.sh fixes these").
- With rfsim found, `RFSIM_PATH` is set and all six models run. Without it: `rfsim_not_found` (exit 2), unless
  `--allow-partial`, which runs four models (check.sh:50, :58) with status partial.
- The table files are `results/{patch_s5_n1200, notch_s3_n2000, patch_s1_n10500, notch_s1_n16000[, kgcpw_s1_n15000,
  ksma_s1_n6000]}_T.txt`; any of them existing gives `would_overwrite` (exit 5). Their `results/` is the one beside
  the real folder of `bench/check.sh`: check.sh changes to its own real folder (`cd "${0:A:h}"`) and bench.py writes
  beside its own, so for a REPO whose `bench/` is a link it is not REPO/results.
- Concurrency gives warnings only: the full check waits for others <= 60 % CPU per run itself, and `--lite` results
  are correctness only.
- **The guard:** every model block has a summary; every non-tolerant compared row is exact; their number per model
  is nSnap x (lite ? 3 : 5) + the non-tolerant extras + (lite ? 0 : 1), since the full check also compares the
  reference with itself (`--repeat 2`); every engine is confirmed. ALL IDENTICAL with a failed guard gives
  `verdict_disagrees`. As for bench, a block's summary needs one readable row per config beside it
  (`tool_output_unparsed`, exit 4, naming the model and both counts): the count above leaves out the tolerant
  extras and the reference of a lite block, and a row that is missing has no engine to confirm.
- **FAIL.** check.sh counts every bench.py exit 2 as FAIL, an argument error too, and argparse exits before bench
  prints its header, so such a model leaves no block at all (F4). FAIL is `check_failed` (exit 1) only when every
  model it names printed a MISMATCH block and every model ran; otherwise it is `tool_output_unparsed` (exit 4), naming
  the models without a MISMATCH block.

**validate.**
- `--lib` defaults to installed. `--engine E` (one of bench's engines, present in the library) sets
  `VALIDATION_ENGINE`; without it the suite's default, fastest, applies and is recorded. `--threads N` sets
  `VALIDATION_THREADS`; `--case slab|cavity|lines` (repeatable) becomes `--cases`. With `--tag T` the outputs go to
  RESULTS (refused if `validation_T.json` or `.md` exists); without it to `RUN/validation`, tagged with the run stamp.
- Knobs go into the environment; `PROBE_END_*` and `EXPORT_*` are not allowed. The launcher runs in script mode with
  `--load`, and its shim only tracks the running openEMS instances (for a stop).
- The JSON is read as JSON5 (F21); a crashed case is a failed check (exit 1), not an unreadable file. The case times
  carry the whole-run load.
- The engine rule needs at least one run of the requested engine per case, because the slab case includes basic runs
  on purpose; cases whose runs are all cylindrical are skipped.

**debye-check, diamond-check.**
- LIB and `--ref` must be complete folders (a snapshot, a path or `installed`).
- debye: both libopenEMS files must contain `OPENEMS_EXPORT_FIELDS`. Stock does not, so `--ref stock` gives
  `library_lacks_feature` (exit 3, hint "debye_check.sh needs fork builds").
- diamond: LIB must list metal-diamond and contain `OPENEMS_EXPORT_FIELDS`, `OPENEMS_FTZ` and `OPENEMS_DIAMOND_TUNE`:
  the script always tests the tiling tuner (F22), so cg19 to cg27 would print FAIL with every comparison identical
  (exit 3, hint "cg28 or later").
- `--threads N` (debye) sets THREADS (the script's default is 4); `--knob` exits 64.
- Before the run, a zsh pre-probe per folder proves that the scripts' own zsh → python3 path keeps DYLD and loads
  that folder's three files. Then the launcher runs the script in exec mode with `--load`.
- Debye's comparisons are titled by its `X vs Y:` lines (2, or 3 with `--ref`); diamond's result counts its boxes
  (`== ` lines) and comparisons (`  LABEL: IDENTICAL|DIFFERENT`). No count is hardcoded: cg29's script gives 8
  comparisons per box.

**e2e.**
- MODEL is gcpw or sma (F11); rfsim is required (exit 2).
- `--floor toolkit|MM` is for sma only (`toolkit` passes 0, the toolkit default). `--probe-end toolkit|off|DB` with
  DB < 0 (`toolkit` passes core.PROBE_END_DB formatted `%g`, and 0 as "off"; core.run refuses positive values).
  `--hold toolkit|H` with H > 0. `--engine E` sets `E2E_ENGINE`, run_one's proxy; without it `FDTD.Run` gets no engine
  and openEMS uses its default (fastest). There is no `--threads`: run_one fixes threads=0.
- `--out-dir DIR` defaults to `RUN/e2e`; an existing non-empty DIR gives exit 5 unless `--overwrite`, which renames it
  `DIR.previous-STAMP` as the last step before run_one.py starts (after the run folder and the quiet wait, so an
  error or a stop before the run leaves DIR in place). A DIR that is the run folder's place or a folder above it
  (RUNS itself) is a usage error (64): core.run empties its folder first, and with it the launcher and `tool.log`.
  So is a DIR that is, or holds, a folder the run needs (the working directory, the tools tree, the toolkit, the
  library's folder, the folder of the Python), which `--overwrite` would rename away just before the run (a `--lib`
  folder given by its path is refused earlier, as a protected folder of the line: `protected_path`, 2), and an
  empty value, which would stand for the working directory. "Holds" is the test of the protected folders (section
  10.2, one function for both): by the real path, by file identity, and by the path the folder is named by, so a
  `--runs`, `--repo` or `--rfsim` that passes through a link inside DIR counts although its real folder lies
  outside (the rename would take the name away). After the quiet wait DIR is looked at once more, with
  the same rules: a DIR that was filled meanwhile gives exit 5 without `--overwrite` (nothing run) and is renamed
  with it.
- Knobs go into the environment, except `PROBE_END_*` and `EXPORT_*` (core.run owns the probe end).
- Refused (exit 5) while the scans find a simulation or cannot tell, unless `--quiet` (which runs the quiet-wait
  helper first) or `--allow-concurrent`.
- The launcher runs in script mode with `--load --calls`. Verdict: `tool_failed` without RESULT,
  `engine_not_confirmed` on a Create mismatch (for the default engine the multithreaded text), `library_not_loaded`
  (exit 4) when a loaded library does not come from the target folder, as for run, `gpu_fallback` as a
  warning. A stopped `FDTD.Run` never reaches run_one's post-processing; `result.json` and RESULT exist only when the
  run finished before the stop, and are then reported with `result.interrupted: true`.

**run.**
- SCRIPT must be a file. It runs as `python3 SCRIPT ARGS` would: the CLI's cwd, `sys.argv = [SCRIPT, ARGS...]`,
  `sys.path[0]` = the script's folder. `--lib` defaults to installed.
- `--engine E` (present in the library), `--threads N` (>= 0) and `--nodumps` are injected into every `FDTD.Run`
  (section 4.3); the CLI's value wins, with `option_overridden` when the script's value differed.
- All 30 knobs are allowed. `EXPORT_*` must name an existing folder; `PROBE_END_*` are allowed, but rfsim's core.run
  replaces them inside its own runs, and each call records the values in effect.
- Concurrency gives a warning only.
- Verdict: exit 0 is ok; a non-zero exit or an exception fails (1) with the exception text. With `--engine`, every
  call must show that engine's Create line (`engine_not_confirmed`); a call whose fd 1 the script redirected (as the
  validation suite's common.py does) cannot show it and gives `engine_not_observable` instead. The loaded libraries
  must come from the target folder, named as given or by its real path, or be the files that the folder's three
  names link to (`library_not_loaded`, exit 4). No
  `FDTD.Run` call gives `no_openems_call`;
  `options_lost` warns when, on the legacy binding, an option equal to 0 or False drops the options after it (F9).

### 4.3 How they run: invocations and the launcher

- Every argv is spawned directly, never through a shell. The cwd is the repo, except the run folder for validate,
  debye-check, diamond-check and e2e, and the CLI's own cwd for run.
- Short probes run directly: the Python probe (`PY -B -c PROBE bench/libinfo.py`, with `DYLD_LIBRARY_PATH` set to the
  first snapshot folder the command needs, else `/var/empty`), the zsh pre-probe
  (`/bin/zsh -f -c 'DYLD_LIBRARY_PATH="$1" python3 -B -c "$2" "$3"'`), the rfsim probe, git
  (`/usr/bin/git -C DIR rev-parse --short HEAD`, `status --porcelain [-- rfsim]`, `log -1 --format=%h -- rfsim`), the
  two lsof scans and ps (section 10.1), and ab's 1-second sampler checks. The probes and the two helpers (the quiet
  wait and the load, which run under the launcher) each print one tagged line (`FDTDKIT_PROBE`, `FDTDKIT_RFSIM`,
  `FDTDKIT_QUIET`, `FDTDKIT_LOAD`) that the CLI finds among other output.
- Everything that can run longer than a few seconds runs under the launcher:
  `PY -u -B RUN/fdtdkit_run.py --repo R --control-fd 3 --report RUN/launcher-ROLE.json [--load] [--calls] [--engine E]
  [--threads N] [--nodumps] {script|exec} -- TARGET [ARGS...]`, spawned with the control pipe's read end on fd 3.
  The launcher file is written from the embedded source for each run, and its sha256 is recorded in `outputs`.
- The launcher saves the original fd 1 (for the markers) and loads `usage.py` and `libinfo.py` as `_fdtdkit_usage` and
  `_fdtdkit_libinfo`, so a user module named `usage` cannot clash. With `--load` one `usage.Sampler` covers the whole
  run; the launcher is the ancestor of everything it runs (F12). bench, ab, check and the helpers get no launcher
  sampler, so none disturbs a benchmark.
- **Exec mode** (bench, ab, check, debye-check, diamond-check, the helpers) installs no-op INT, TERM and HUP handlers
  (handlers, unlike SIG_IGN, do not survive exec) and runs `subprocess.Popen(TARGET + ARGS, close_fds=True).wait()`.
  The exit is the child's code, or 128 + signal.
- **Script mode** (validate, e2e, run) installs no signal handlers, installs the class shim, sets `sys.argv` and
  `sys.path[0]`, and runs `runpy.run_path(TARGET, run_name='__main__')`. SystemExit gives its code, KeyboardInterrupt
  gives 130, and any other exception gives 1 with its text.
- **The class shim** subclasses `openEMS.openEMS.openEMS` and puts the subclass into both modules (checked on
  2026-11-05: `from openEMS import openEMS` returns it after the swap; rfsim's core.py and box.py import the class
  after it). For each `FDTD.Run` it:
  - puts the CLI's options first (engine, numThreads, and `disable_dumps` only as True; F9);
  - drops every spelling of an injected option from the script's keywords (any case, `_` or `-`; F19) and records it in
    `overridden`;
  - lists, on the legacy binding, the options after the first one equal to 0 or False as `optionsLost`;
  - records simPath as an absolute path before the binding changes into it (F19);
  - with `--calls`, writes `FDTDKIT_CALL_BEGIN k` and `FDTDKIT_CALL_END k` through the saved fd 1 after flushing
    openEMS's output, runs a per-call sampler, and records the call (options, applied and overridden options, load,
    `stdoutRedirected`, `stopRequested`, the probe-end variables in effect). Without `--calls` it only tracks the
    running instances.
- At the end the launcher writes its report atomically: mode, target, argv, exit, interrupted, exception,
  wallSeconds, load and its counts, the loaded libraries (script mode), dyld, python, binding, calls. `binding` is
  {version, legacyEmptyOption}, by the two rules of the python probe (section 5.3, item 2).

### 4.4 Parsing

- The formats are those of F17. Numbers include `inf` and `nan`: bench prints `inf` for a probe or S-parameter
  difference that has no finite figure.
- **bench.** Header `# MODEL  load avg X` (tag files have a date instead); other `#` lines are skipped (tag files may
  open with free comments). A row has the label, MC/s, seconds, `TS x MC`, `others NN%` (top's CPU-only reading from
  the second before the run: recorded as `othersCpuBefore`, never counted as a load), and then `runs a/b`,
  `busy ...`, the `during` part (window, self CPU and GPU, others' CPU and GPU, optional `gpu dev`, busy list),
  `quiet-wait timed out`, `(auto-picked N threads)`, `[ref]`, `probes rel=NUM`, the all-zero files note, `PROBLEM:`,
  the S-parameter fields, `(tolerant)` and `openEMS VERSION`. A row is exact when its probes are `rel=0.0e+00`, it has
  no PROBLEM, and every S field is `equal` or a zero maximum difference not marked as differing below -40 dB: bench's
  own `same` (bench.py:369). The summary is `MISMATCH|NOTHING COMPARED|NOTHING REQUIRED TO MATCH|IDENTICAL: ...`,
  then `wrote PATH`. Run folders follow bench.py:302-311 (`LIB@` becomes `basename(LIB)@` for a path, `:` becomes
  `_t`, other characters become `_`, then `_2`, `_3` for repeats).
- **abtest.** The header, run lines (a discarded run starts with `# redo `), notes `# rR[ cC]: ...`, the
  `# summary NAME: ...` header and the `cI ...` summary lines; -1 means the load is missing. The logs are
  `RUN/runs/ab_NAME/c{i}/r{r}/openEMS.log`.
- **check.sh.** Model blocks are bench outputs; the final line is `ALL IDENTICAL (N models)`, `PARTIAL: ...`,
  `FAIL: ...`, or `bench.py LABEL stopped with exit status N` (`tool_failed`).
- **Other tools.** The validation JSON (meta, timings, runs, results), debye (`== ` run headers, `X vs Y:` titles,
  `IDENTICAL` or `DIFFERENT`, `no exported fields`, PASS or FAIL), diamond (`== ` boxes, the comparison lines, the
  missing GPU path line, the unfinished tuning line, `CPU run failed` or `Metal run failed`, PASS or FAIL), e2e's
  `RESULT {...}` and `result.json`. All tool JSON is read with JSON5 allowed; non-finite values become "nan", "inf" and
  "-inf" in the envelope.
- **openEMS lines**, per call segment between the markers: the Create line, `fixed number of threads: N`,
  `Best performance found using N threads`, `Time for N iterations with C cells : T sec` (mcs = N * C / T / 1e6,
  bench's formula), the stop lines (probe end, energy end criterion, maximum timesteps, aborted) and the GPU fallback
  lines (the metal-diamond row below).

**Create lines per engine** (prefix `Create FDTD engine`; a missing engine in the library's help strings exits 3 before
the run, a missing Create line exits 4 after it, which covers F6):

| engine | accepted |
|---|---|
| basic | the bare line, without parentheses |
| sse | ` (SSE)` |
| sse-compressed | ` (compressed SSE)` |
| multithreaded, fastest | ` (compressed SSE + multi-threading)`, ` (cylindrical mesh using sse compression + multithreading)`, ` (cylindrical multi grid mesh using sse compression + multithreading)` |
| gpu, gpu-reference | ` (GPU, backend: ...)`, ` (GPU, cylindrical multi-grid level ...)` |
| metal-diamond | ` (Metal, diamond-blocked)`; a line that starts with `Engine_Metal_Diamond:` and contains `running the CPU loops`, or starts with `Engine_Metal_Diamond: kernel compilation failed` or `Engine_Metal_Diamond: pipeline creation failed` (SetupGPU then runs the CPU loops too; engine_metal_diamond.mm at cg29 :976 and :983), gives the warning `gpu_fallback` |

The engine prints its Create line when it is created and sets up the GPU only in its first time step, so a run that
fell back still confirms the engine; the fallback line (on stderr) is what tells. bench, check and ab read it from
each run's `openEMS.log`, validate from `tool.log` (common.py redirects only fd 1), e2e and run from the call
segments. One fallback prints no line: more than 32 Mur faces or UPML boxes, or more than 65535 lumped or dispersive
elements (cg29 :836-839); only the `Engine_Metal_Diamond: NxNxN cells` line of a run with verbose > 0, or the
`OPENEMS_DIAMOND_TIMING` report, shows that the GPU path ran.

## 5. Library identity

### 5.1 LIB forms and the identity record

- LIB is `installed` (whatever the probe loads without a snapshot; no prefix is hardcoded), a snapshot name (a folder
  under SNAPS; the name `installed` is reserved, so such a folder is reached by path), or a path containing `/` (a
  folder with the three `.0.dylib` names). An incomplete folder gives `library_incomplete` (exit 2), because dyld would
  load the installed library for the missing file (F8); a missing one gives `library_not_found`. For bench, ab and
  check the CLI sets `OPENEMS_BENCH_SNAPS=SNAPS`, so bench resolves names the same way (bench.py:47-48).
- **A folder of links.** A LIB folder whose three names are links to files in another folder is taken by validate,
  e2e and run (dyld loads those files, and the loaded images are compared with them). bench, ab and check refuse
  it at plan time (`library_incomplete`, exit 2), for a CFG's LIB, check's SNAP, `--stock` and `--extra`: bench.py
  takes the real path of every loaded library and wants it inside the real folder (`check_loaded`), so such a run
  would fail after its first simulation. Links that stay inside the folder are fine.
- **No LIB starts with `-`,** in any of its places (check's SNAP, `--stock` and `--extra`, the LIB of a bench or ab
  CFG, `--lib` of validate, e2e, run and info, the LIB of debye-check and diamond-check, and debye-check's `--ref`).
  The CLI hands the bench and ab configs to the argparse of bench.py and abtest.py, and check.sh hands its snapshot
  names to bench.py's; argparse reads such a value as an option and exits 2 before the tool prints anything, so the
  run ended in `tool_failed` (bench, ab) or `tool_output_unparsed` (check), exit 4 either way. The CLI refuses it at
  plan time, before anything is spawned and in a dry run too: `library_not_found` (exit 2), `config_invalid` inside a
  CFG, a warning in info; where the LIB is a positional (check's SNAP, the LIB of debye-check and diamond-check) the
  tokenizer already ends the line with a usage error (64, section 4.1). The other commands hand the tools the folder's
  absolute path (info starts no tool), so for them the one rule only keeps the forms alike. The hint names the same
  folder by its path: `SNAPS/-NAME` (SNAPS spelled out) for a snapshot name, `./-NAME/...` for a relative path.
- **Per file:** the real path, the size, the sha256 (CryptoKit, streamed in 1 MiB chunks) and the LC_UUID (load
  command 0x1b, read in Swift from a thin arm64 Mach-O file or the arm64 slice of a fat one; no otool, which is an
  xcrun stub, F1), plus `sameBytes[]` and `sameBuild[]`: the snapshots whose file of that name has the same sha256 or
  the same UUID.
- **Per library:** the version string (the regex `\x00(v0\.\d+\.\d+(?:-\d+-g[0-9a-f]+)?(?:-dirty)?)\x00` over the
  libopenEMS bytes), the engines (each engine whose help string `"  NAME: \t"` occurs), the knobs (each registry name
  that occurs in the bytes; `OPENEMS_NF2FF_LEGACY` is searched in libnf2ff, the others in libopenEMS), sameBytes and
  sameBuild of libopenEMS, candidates (only when sameBuild is empty: snapshots with the same version string, knob set
  and engine set) and a note such as "same build as cg18 (UUID), other bytes (installed copy)". The version string is
  informational only (F7).
- **Read once.** SNAPS is read once per command, into the snapshot index. A LIB whose folder the index holds,
  named as a snapshot or by its path, takes its record from the index entry, and its files are not read and hashed a
  second time. One rule decides it for info, for every command's LIB and for check's stock scan and match: the
  folder's path, byte for byte, is the path of an index entry (`FdtdSnapshotIndex.entry(at:)`,
  `FdtdLibraries.record`); any other folder is read.
- **Build folders** (`info --build DIR`): `DIR/libopenEMS.0.dylib` and `DIR/nf2ff/libnf2ff.0.dylib` with their UUIDs;
  `CMAKE_INSTALL_PREFIX`, `ENABLE_METAL` and `CMAKE_BUILD_TYPE` from `CMakeCache.txt`; the warning
  `build_installs_over_prefix` when that prefix holds the installed library.

Expected on the author's Mac (test data). LibraryScanTests checks a row only while its files keep these hashes; smoke
run 2 checks the stock and cg29 rows of the author's snapshots without that guard, so it passes only with those files
(the smoke runs are written for the author's Mac):

| library | version string | knobs (libopenEMS + libnf2ff) | engines | sha256 | libopenEMS UUID |
|---|---|---|---|---|---|
| stock | v0.37.0 | 0 | 5 (fastest, basic, sse, sse-compressed, multithreaded) | 7eaaee52... | B1A89DA1-... |
| base | -18-g7bb294f | 0 | adds gpu, gpu-reference | | |
| cg18 | -24-g087ce9e | 15 + 1 | no metal-diamond | 0c32ad23... | 24C8A7F2-... |
| cg19 | -25-g315acee | 20 + 1 | adds metal-diamond | | |
| cg29 | -44-g074a687 | 29 + 1 | | 3c859d81... | 40BC8CFF-... |
| installed until 2026-11-06 | -24-g087ce9e | 15 + 1 | | 819179a2... | 24C8A7F2-... (sameBuild cg18) |
| installed since 2026-11-06 | -44-g074a687 | 29 + 1 | | 0d81372e... | 40BC8CFF-... (sameBuild cg29) |
| build-split | | | | | 40BC8CFF-... (sameBuild cg29) |
| build-gpu | -26-gcd80d8c | | | | 9A6EDCEE-... (none) |

The knob column counts the registry names in libopenEMS, plus `OPENEMS_NF2FF_LEGACY` in libnf2ff; the record's
`knobs[]` holds both, so it lists 16 names for cg18 (and the installed library until 2026-11-06), 21 for cg19 and 30
for cg29. The installed libCSXCAD has sameBuild cg9 to cg29 and cg29pre, and sameBytes cg20 to cg29 and cg29pre; the
installed libnf2ff has sameBuild cg18 to cg29 and cg29pre, and sameBytes cg20 to cg29 and cg29pre. These lists are
what `.build/release/emskit fdtd info` printed on 2026-11-06 (section 16), before the install of cg29, which left
libCSXCAD and libnf2ff as they were; F20 names only some of these snapshots. The row "installed since 2026-11-06" is
what `info` printed after that install (section 16): snap/cg29's build with the prefix's install name and rpath,
re-signed, so other bytes than snap/cg29's file. The tests check the installed row whose sha256 the installed
libopenEMS has (819179a2... until 2026-11-06, 0d81372e... since) and skip any other install: LibraryScanTests checks
the row, smoke run 2 its sameBuild (section 12).

### 5.2 The stock identity of `check`

The CPU acceptance is bit-identity to stock v0.37.0. A check counts as that acceptance only when both of these hold:
- SNAPS/stock exists and passes the stock scan: its libopenEMS version string is exactly `v0.37.0`, its engines are
  exactly the five CPU engines, and no registry knob occurs in its libopenEMS or libnf2ff;
- each of the reference's three files has the UUID (same build) or the sha256 (same bytes) of the SNAPS/stock file of
  the same name.

`result.reference` records the three files' sha256 and UUID, `matchedBy` (uuid, sha256 or null) and `acceptance`. A
reference that fails either test still runs, for example `--stock cg18`, or a folder with the stock libopenEMS beside
a fork libCSXCAD (same version string, other build; F20). The outcome is then status partial (exit 0),
`acceptance: false` and the warning `reference_not_stock`: "compared with X, which is not stock v0.37.0: not the CPU
acceptance". Whether such a check should be refused instead is open (section 17).

### 5.3 Discovery of the other inputs

1. **Tools tree.** `--repo DIR`; else a walk up from the cwd; else a walk up from the real path of the executable
   (`.build/<triple>/debug/emskit` leads to the worktree root); else `repo_not_found` (exit 2, hint
   "--repo /path/to/emsKit"). A folder counts only when all ten markers exist (bench/bench.py, bench/abtest.py,
   bench/check.sh, bench/usage.py, bench/libinfo.py, bench/validation/run_validation.py,
   scripts/checks/debye_check.sh, scripts/checks/diamond_check.sh, scripts/e2e/run_one.py,
   scripts/cache_valley/box.py) and bench.py contains `usage.fmt(`. A folder with only some of them is passed over
   with the warning `tools_tree_skipped` (the sibling worktrees hold the older harness, F25); `--repo` naming one
   gives `tool_missing` with the missing markers. Recorded: head, dirty (`status --porcelain` not empty) and
   toolsModified (porcelain paths under bench/, scripts/checks/, scripts/e2e/ or scripts/cache_valley/; warning
   `tools_modified`). In a tools tree kept inside another repository (`git rev-parse --show-prefix` not empty) the
   status is asked for the tree's folder and the paths are taken relative to it; head is then the commit of the
   repository that holds the tree. The status is asked with `-c core.quotePath=false`, so that a folder name with a
   letter outside ASCII is printed as `--show-prefix` prints it.
2. **Python.** `--python PATH`; else the first `python3` on PATH whose real path is not under /usr/bin, /bin,
   /usr/sbin, /sbin, /usr/libexec or /System (each one passed over gives `python_skipped`); none gives
   `python_not_found` (exit 3). The probe records path, realPath, version, dyldKept, openemsModule, openemsVersion,
   legacyEmptyOption, numpy and the loaded libraries. openemsVersion is the version of the package metadata named
   openEMS, taken only when one of that distribution's files lies in the folder of the imported package (the name
   alone can belong to another installed copy); otherwise it is null. legacyEmptyOption is true unless an
   `openEMS.pyx` beside `openEMS.openEMS` can be read and lacks `opt = ""` (without a readable pyx the installed
   v0.37.0 behaviour is assumed, F19); it is null only when `openEMS.openEMS` does not import, and the launcher then
   installs no shim and reports no binding. The launcher's report follows the same two rules (section 4.3), so the
   probe and a run never disagree on them. dyldKept false while a snapshot is needed gives
   `python_strips_dyld`; a failed `import openEMS` gives `python_no_openems`. For validate, e2e and run with a
   library other than the installed one, the probe must have loaded the three files from that folder, named as given
   or by its real path, or the files its three names link to (`library_not_loaded`, exit 4, before the run). For
   check, debye-check and
   diamond-check, whose zsh scripts call `python3` by name, dirname(PY)/python3 must resolve to realpath(PY)
   (`python_name_mismatch`).
3. **Snapshots.** `--snaps`, else `$OPENEMS_BENCH_SNAPS`, else `~/opt/openEMS-dev/snap`. A snapshot is a subfolder
   with libopenEMS.0.dylib, libCSXCAD.0.dylib and libnf2ff.0.dylib.
4. **rfsim.** `--rfsim`, else `$RFSIM_PATH`; the folder must contain `rfsim/openems/core.py`. The rfsim probe records
   the path, head, rfsimCommit (the last commit that changed `rfsim/`), dirty (`rfsim/` only), probeEndDb,
   probeEndHold, zMult, minCell, minCellEffective and the `RFSIM_*` environment. Each of the five values is
   optional: one that the toolkit lacks (an older one without its `launch` module, a hold or a z rule), or that is no
   finite number, is null, and the probe still answers. `rfsim_not_found` says what the
   search looked at and why it took nothing, with the hint `--rfsim DIR`: whether `--rfsim` was given, whether
   `RFSIM_PATH` is set or empty (only without `--rfsim`), and what the folder named lacks (it is not a folder, has no
   `rfsim/`, or has `rfsim/` but no `rfsim/openems/core.py`), e.g. "--rfsim was not given, and RFSIM_PATH /x is not
   a folder".
5. **Runs.** `--runs`, else `$OPENEMS_BENCH_RUNS`, else `/tmp/openems_bench_runs`. The run folder is
   `RUNS/emskit-fdtd/<yyyyMMdd-HHmmss>-<command>-<pid>/`, made by an exclusive mkdir; on EEXIST the suffix `-2`, `-3`
   and so on is added (in-process tests share one pid and one second).
6. **Results.** `REPO/results`, or `--results DIR` (bench, validate).

## 6. Child environment and knobs

### 6.1 The child environment

The CLI starts from its own environment and applies three steps.

**Remove** (each removal is recorded, and one warning `env_removed` lists name=value):
- every `DYLD_*`;
- every `OPENEMS_*` (`OPENEMS_BENCH_SNAPS` and `OPENEMS_BENCH_RUNS` are then set again where needed);
- `VALIDATION_ENGINE`, `VALIDATION_THREADS`, `VALIDATION_WORK` and `E2E_ENGINE`;
- the script inputs THREADS, STOCK, LITE, EXTRA, QUIET_MAX, DEBYE, DRUDE and ENG;
- `RFSIM_PATH`, set again from discovery only when rfsim is found;
- every `PYTHON*` except `PYTHONPATH` and `PYTHONUSERBASE`, among them `PYTHONNOUSERSITE` (it would hide the user-site
  openEMS binding), `PYTHONHOME`, `PYTHONEXECUTABLE`, `PYTHONSAFEPATH` (it would break the tools' sibling imports),
  `PYTHONINSPECT`, `PYTHONOPTIMIZE` and `PYTHONWARNINGS` (F27), `PYTHONDEVMODE` and `PYTHONTRACEMALLOC`;
- every `Malloc*` variable: libmalloc settings such as `MallocGuardEdges` or `MallocStackLogging` change where large
  blocks land and how fast allocation runs, and the allocation-placement valley depends on the field arrays'
  placement (open question 4, section 17).

**Keep:** `PYTHONPATH` and `PYTHONUSERBASE`, with the warning `python_env_kept` (they choose which openEMS binding
loads, and the probe records it; open question 5); `RFSIM_*` other than `RFSIM_PATH`, passed through and recorded with
the warning `rfsim_env` (the user's own toolkit settings).

**Set:** PATH = dirname(PY) + ":" + the old PATH, without a duplicate entry; `PYTHONDONTWRITEBYTECODE=1`, so neither
the launcher nor the Pythons the tools start write bytecode caches; then only what the command needs:
`OPENEMS_BENCH_SNAPS`, `OPENEMS_BENCH_RUNS`, `RFSIM_PATH`, `DYLD_LIBRARY_PATH` (only on Python processes the CLI starts
directly, never on `/bin/zsh`, which strips it, F1), the knobs (validate, e2e, run), `VALIDATION_ENGINE` and
`VALIDATION_THREADS`, `E2E_ENGINE`, THREADS, TMPDIR, STOCK, LITE, EXTRA and QUIET_MAX.

The CLI never starts anything through `/usr/bin/env`, `sh -c` with user data, `caffeinate` in front, `time`, `nice`,
`xcrun` or `otool`.

### 6.2 The knob registry: the 30 names of BUILD.md section 7

"Read once" means the library reads the variable once per process, at its first use.

| knob | accepted values | read once | allowed on |
|---|---|---|---|
| `OPENEMS_FUSED` | 0, 1 | no | bench, ab, validate, e2e, run |
| `OPENEMS_FUSED_BLOCK` | integer >= 1 | no | same |
| `OPENEMS_FLAGS` | 0, 1 | no | same |
| `OPENEMS_FLAGS_SPIN_US` | integer >= 0 | no | same |
| `OPENEMS_FUSED_STAT` | 1 | yes | same |
| `OPENEMS_BALANCE` | 0, 1 | no | same |
| `OPENEMS_NO_STAGGER` | 1 | yes | same |
| `OPENEMS_OP_INDEX_PER_CELL` | 1 | no | same |
| `OPENEMS_NO_PACKED_COEFF` | 1 | no | same |
| `OPENEMS_COEF` | packed, geom | no | same |
| `OPENEMS_BARRIER_SPIN_US` | integer >= 0 | yes | same |
| `OPENEMS_TUNE_WINDOW_MS` | integer >= 1 | no | same |
| `OPENEMS_NO_PML_TABLE` | 1 | no | same |
| `OPENEMS_PML_YVEC` | 0, 1 | no | same |
| `OPENEMS_ADE_MERGED` | 0, 1 | no | same |
| `OPENEMS_QOS` | 0, 1, 2 | no | same |
| `OPENEMS_FTZ` | 1 | yes | same; warning `not_bit_identical_to_stock` |
| `OPENEMS_NF2FF_LEGACY` | 1 | yes | same (searched in libnf2ff) |
| `OPENEMS_SETUP_TIMING` | 1 | yes | same |
| `OPENEMS_EXPORT_OPERATOR` | an existing folder | no | run |
| `OPENEMS_EXPORT_FIELDS` | an existing folder | no | run |
| `OPENEMS_PROBE_END_DB` | number <= 0 (0 = off) | no | run |
| `OPENEMS_PROBE_END_HOLD` | number >= 0 | no | run |
| `OPENEMS_DIAMOND_K` | integer >= 1 | no | bench, ab, validate, e2e, run |
| `OPENEMS_DIAMOND_TILE` | `M:V` with M >= 1 and V >= 0; also `M,V` on validate, e2e and run (environment) | no | same |
| `OPENEMS_DIAMOND_TUNE` | integer >= 0 | no | same |
| `OPENEMS_DIAMOND_TG` | integer >= 0 | no | same |
| `OPENEMS_DIAMOND_BATCH` | integer >= 1 | no | same |
| `OPENEMS_DIAMOND_TIMING` | 0, 1, 2 | no | same |
| `OPENEMS_DIAMOND_COEF` | packed, split | no | same |

- **The eight `=1` switches** (FUSED_STAT, NO_STAGGER, OP_INDEX_PER_CELL, NO_PACKED_COEFF, NO_PML_TABLE, FTZ,
  NF2FF_LEGACY, SETUP_TIMING) take only `1`; for "off" the knob is left out. Up to patch 0005 (cg9 to cg17, whose
  version strings cannot tell them apart) any value, 0 included, switched them on, while bench reads FTZ=0 as off
  (F23). Any other value gives `knob_value` (exit 2, hint "leave the knob out for off").
- The number knobs (FUSED, FLAGS, BALANCE, QOS, PML_YVEC, ADE_MERGED) keep 0.
- An empty value gives `knob_value` (the fork treats empty as unset; the CLI refuses it so that nothing is ambiguous).
  An unknown name gives `knob_unknown` with the nearest name as the hint; a name not allowed on the command gives
  `knob_not_allowed` (both exit 2). A name absent from the target library's bytes gives `knob_unsupported` (exit 3):
  the knob would do nothing.
- `DIAMOND_*` with an engine other than metal-diamond gives the warning `knob_no_effect`; TILE with M < 2K-1 (K is
  DIAMOND_K or 4) gives `knob_ignored`, because the engine ignores it with a message (engine_metal_diamond.mm:1270-1276).
- Inside bench and ab configs the TILE comma is refused, because bench splits `#` lists on commas and abtest turns `;`
  into `,`; no value inside a config list may contain `,` or `;`.
- check, debye-check and diamond-check take no `--knob`. For bench and ab the knobs travel only inside the configs;
  for validate, e2e and run they go into the Python process's environment.
- One name with two values in `--knob` (given twice, or against a CFG's own setting): bench and ab refuse it (exit
  64). validate, e2e and run keep the last value, since the environment holds one value per name, and give the
  warning `knob_ignored`, which names the knob and its values. The same value twice in `--knob` is no news anywhere.
  The warnings above (`knob_no_effect`, the TILE rule, FTZ) are then made for the value that reaches the child
  only: a TILE that a later `--knob` replaced is not called ignored by the engine, which never sees it.
  A name twice inside one CFG's `#` list is `config_invalid` (exit 2), whatever the values.

## 7. Envelope, stderr, exit codes

### 7.1 The envelope

One JSON document on stdout (or in `--output FILE`): JSONEncoder with `.prettyPrinted` and `.sortedKeys`; inf, -inf
and nan are written as the strings "inf", "-inf" and "nan" (the siblings' settings); all paths are absolute. Run
commands also keep a copy as `RUN/envelope.json`.

| key | content |
|---|---|
| `schema` | `emskit.fdtd.<command>/1` for info, load, bench, ab, check, validate, debye-check, diamond-check, e2e, run |
| `tool`, `kit`, `version` | "emskit", "fdtd", "0.1.0" (`FdtdKitInfo.version`) |
| `command`, `arguments` | the command, and the arguments after `fdtd` as given |
| `status` | ok, partial, fail, error, refused or interrupted |
| `dryRun` | bool |
| `warnings`, `errors` | issues `{code, message, field?, hint?}`: sbrKit's error fields in momKit's object form |
| `repo` | `{root, head, dirty, toolsModified[]}` |
| `python` | `{path, realPath, version, dyldKept, openemsModule, openemsVersion, legacyEmptyOption, numpy}` |
| `libraries` | every library the command uses (section 5.1) |
| `rfsim` | `{path, head, rfsimCommit, dirty, probeEndDb, probeEndHold, zMult, minCell, minCellEffective, env{}}` or null |
| `distribution` | `{requested, mode, nodes, hosts, reason}` (section 11) |
| `concurrent` | `{result: none, found or unknown, processes[{pid, command, libraries[]}], scans[{argv, exit, records}]}`: what the scans found at the start |
| `jobs` | the logical work units (section 11) |
| `invocations` | `[{role, jobId, argv, cwd, envSet{}, envRemoved[{name, value}], exit, seconds, ran, interrupted}]`; envSet holds only what the CLI set or changed |
| `result` | per command (below) |
| `load` | the whole-run load (load, validate, debye-check, diamond-check, e2e, run) or null; bench, ab and check carry their loads per row, so no second sampler disturbs the benchmark |
| `runFolder`, `keptRuns` | path or null; bool |
| `outputs` | `[{path, sha256, existedBefore, backup?}]` |
| `timing` | `{startedAt (ISO 8601 with offset), wallSeconds, probeSeconds, toolSeconds}` |

**FdtdLoad:** wallSeconds, selfCpuPercent, selfGpuPercent, selfGpuSecondsAtLeast, othersCpuPercent, othersGpuPercent,
gpuDevicePercent (null when absent), busy[], processesSeen, gpuClientsSeen and utilSamples (from the launcher or the
LOAD helper; null for parsed rows), source ("usage.Sampler", "bench row" or "abtest line"), valid, invalidReason, and
loaded (from `--warn-cpu` and `--warn-gpu`).

**Results per command:**
- info: machine (chip, cpuCores, performanceCores, efficiencyCores, memoryBytes, os), installed, snapshots, builds,
  knobs (name, values, readOncePerProcess, commands).
- load: seconds.
- bench: model, scale, nrts, name, reference, rows, summary (kind, line), resultsFile, exact. A row holds its label,
  config parts, reference and tolerant flags, mcs and seconds (null without a valid load, `speedWithheld`),
  timesteps, cells, repeats, autoPickedThreads, othersCpuBefore, busyBefore, quietWaitTimedOut, load, probesRel,
  zeroFiles, problems, sparams, sparamNote, openemsVersion, runFolders, createLine, engineConfirmed and exact.
- ab: model, scale, nrts, rounds, recordFile, tolerantFromReference, samplerChecks, configs (median, min and max MC/s,
  median paired ratio to c0 and its range, the others' medians, runsWithLoad, runsWithoutLoad, diffs, identical) and
  runs (round, config, mcs, othersCpu, othersGpu, loadValid, diff, kept).
- check: tag, snapshots, reference (spec, dir, files with sha256 and UUID, stockDir, stockScan, matchedBy,
  acceptance), lite, models (label, name, resultsFile, summary, rows), finalLine, verdict, exactRows,
  expectedExactRows.
- validate: tag, json, md, engine, threads, quick, cases, checks, passed, failed, runs, libraries, timings.
- debye-check: library, reference, threads, runs, comparisons (title, identical), verdictLine.
- diamond-check: library, boxes, comparisons, identical, different, gpuPathMissing, tuningUnfinished, verdictLine.
- e2e: model, floor, probeEnd (db, hold, source), engine, outDir, resultJson, spNpz, result, interrupted, calls.
- run: script, args, cwd, exit, exception, calls, libraries.
- A call holds index, simPath, setupOnly, options, applied, overridden, optionsLost, stdoutRedirected, stopRequested,
  wallSeconds, load, createLine, engineConfirmed, engineObservable, threadsFixed, threadsPicked, timesteps, cells,
  seconds and mcs (both null without a valid call load), stop (kind, timesteps) and probeEnd.
- Bookkeeping durations (`timing`, `invocations[].seconds`) are not performance figures: they carry no load and are
  never printed on stderr.

### 7.2 stderr

- A plan line, e.g. `emskit fdtd: bench patch: 2 configs x 2000 timesteps, run folder /tmp/openems_bench_runs/...`.
- Issues as `emskit fdtd: CODE: MESSAGE (hint: HINT)` (sbrKit's format), warnings and errors alike.
- The tools' output is echoed live, except the launcher's markers and every tool line that carries a speed or a run
  time (`MC/s`, `MCells/s`, `MCell/s`, `Speed:`, `Time for N iterations`, `RESULT {`, `Case times (s)`): bench rows and
  summaries, abtest run and summary lines, openEMS progress lines and the speed lines of the check scripts.
  `RUN/tool.log` keeps every byte.
- In their place the CLI prints its own figure lines, each with its valid load:
  `emskit fdtd: bench row 2 of 2: cg29@multithreaded:4 1702.0 MC/s (others cpu 41% gpu 0% during 1.9 s), exact`,
  or, without a valid load, `emskit fdtd: bench row 1 of 2: stock@multithreaded:4: speed withheld (no valid load during
  the run)` with the warning `load_missing`. The same rule covers ab runs and configs, e2e and run calls, and run
  times (e2e's build, run and post times; validate's case times), which carry the whole-run load.
- Durations print with one decimal in seconds, and below 0.1 s in milliseconds (`build 4.5 ms, run 4.5 s, post
  17.5 ms`), so that a short stage does not read as `0.0 s`; the envelope keeps the tools' numbers as they are.
- A final summary line: status and verdict, then every speed as `LABEL X MC/s (others cpu C% gpu G%)`; a speed
  without a valid load is left out.
- stdout carries only the envelope, or nothing when `--output` is given.

### 7.3 Exit codes and issue codes

| exit | status | when |
|---|---|---|
| 0 | ok, partial | the verdict passed; partial: check with `--allow-partial` (four models), or check against a reference that is not stock v0.37.0 (acceptance false) |
| 1 | fail | the tool ran and its verdict did not pass |
| 2 | error | bad input: names, files, folders, knob values, missing rfsim, snapshot or tool; an output location in or over a protected folder (S3, section 10.2) |
| 3 | error | not supported by that library or Python: engine, knob, feature; a Python that strips DYLD or lacks openEMS |
| 4 | error | at run time: a tool failed, output unparsed, engine not confirmed, library not loaded from the target, verdicts disagree, spawn or launcher failed, load unavailable |
| 5 | refused | a safety rule stopped the command before anything ran |
| 64 | error | usage |
| 130 | interrupted | INT, TERM or HUP received (not a HUP that was ignored when the CLI started, section 9) |

2, 3, 4 and 64 match sbrKit; femKit and momKit also use 64 for usage. Precedence: 64 > 2 > 3 > 5 > 4 > 1 > 0; 130
replaces 4, 1 and 0 once a signal has arrived, so a run that finished before the stop took effect and whose verdict
passed still exits 130 (status interrupted).

| exit | error codes |
|---|---|
| 64 | usage |
| 2 | repo_not_found, tool_missing, library_not_found, library_incomplete, config_invalid, knob_unknown, knob_value, knob_not_allowed, rfsim_not_found, script_not_found, folder_missing, hosts_file_missing, tag_invalid, protected_path |
| 3 | engine_unsupported, knob_unsupported, library_lacks_feature, python_not_found, python_strips_dyld, python_no_openems, python_name_mismatch |
| 4 | tool_failed, tool_output_unparsed, engine_not_confirmed, library_not_loaded, verdict_disagrees, spawn_failed, launcher_failed, load_unavailable |
| 1 | mismatch, not_exact, check_failed, validation_failed, script_check_failed, script_failed |
| 5 | simulation_running, concurrency_unknown, would_overwrite |
| 130 | interrupted |

Warning codes: env_removed, python_env_kept, rfsim_env, tools_modified, tools_tree_skipped, python_skipped,
knob_no_effect, knob_ignored, not_bit_identical_to_stock, nothing_verified, tolerant_rows, extra_not_counted,
reference_not_stock, gpu_fallback, simulation_running, concurrency_unknown, loaded_mac, load_missing,
quiet_wait_timed_out, distribute_local, frequencies_not_applicable, option_overridden, options_lost,
engine_not_observable, no_openems_call, partial, output_backed_up, build_installs_over_prefix, caffeinate_failed,
report_rebuilt, killed.

info never stops on a missing piece: it gives the error codes of the table above as warnings and exits 0, e.g.
`rfsim_not_found` when no rfsim toolkit is found (section 5.3), `repo_not_found`, `python_not_found`,
`library_not_found` (the installed library unknown, no snapshot folders, a `--lib` that names none or starts with
`-`, a `--build` folder without libopenEMS.0.dylib or nf2ff/libnf2ff.0.dylib), `library_incomplete` (a `--lib`
folder, or the installed one, without all three files) and `folder_missing` (a `--build` that is not a folder or has
no CMakeCache.txt).

## 8. Load recording

Every speed and run time is reported with the other processes' CPU and GPU use during that run, or not at all.

| figure | its load | valid when |
|---|---|---|
| bench row (mcs, seconds) | the row's `during` part, which is the load of its fastest repeat | the part is present, has `gpu dev`, and is not `self cpu 0%` over more than 1 s (a working sampler always takes a utilisation sample at stop, usage.py:89, and a run of more than a second always uses some CPU of its own) |
| bench repeats (`runs a/b`) | none | never: these speeds stay out of the envelope and stderr; `tool.log` and the `--tag` table keep them |
| ab run | the run line's others' CPU and GPU | both >= 0 (abtest prints -1 when usage returned None) and both sampler checks around the abtest run valid |
| ab config statistics | the runs above | computed from the kept runs with valid loads; a paired ratio needs both runs of its round valid; `runsWithoutLoad` counts the runs left out |
| e2e and run calls (mcs, seconds) | the shim's per-call sampler | processesSeen > 0 and utilSamples > 0 |
| whole-run figures (e2e's build, run, post and total times; validate's case times) and the top-level `load` | the launcher's sampler (`--load`) | as for a call |
| `load` | the LOAD helper | as for a call |

- A figure without a valid load is null in the envelope (bench rows also get `speedWithheld: true`), its stderr line
  names it without the figure, and the warning `load_missing` is given. abtest's own summary lines take medians over
  -1 values (abtest.py:99-100), so they stay in `tool.log` and the record only.
- `othersCpuBefore` (top's reading from the second before a bench row) is recorded but never counts as a load.
- Thresholds: `--warn-cpu` (150 %) and `--warn-gpu` (10 %) mark a load `loaded: true` with the warning `loaded_mac`;
  they never block a run. Waiting for a quiet Mac is `--quiet`'s job.
- bench, ab and check get no launcher sampler, so no second sampler disturbs the benchmark; the tools' own samplers
  give the per-row loads.
- **The launcher's two-sampler overhead.** During a call of e2e or run two samplers run (the whole-run one and the
  call's), each starting ps and ioreg twice a second (usage.py:51): a few percent of one core, counted as self.
  Merging them needs a snapshot API in `usage.Sampler` (deferred, section 18).

## 9. Stopping

- **The control pipe.** Every child that can run longer than a probe (bench, ab, check, validate, debye-check,
  diamond-check, e2e, run, the quiet wait, load) runs under the launcher in its own process group, with the control
  pipe's read end on fd 3. The CLI creates the pipe with both ends close-on-exec, keeps the only write end (children
  are spawned with CLOEXEC_DEFAULT) and closes its copy of the read end after the spawn. The launcher's watchdog
  thread reads fd 3: a `stop` line is a stop request, and EOF (the CLI was killed or crashed) is one too.
- **Script mode** (validate, e2e, run). The watchdog sets the stop flag, then calls `SetAbort(True)` on every openEMS
  instance inside `FDTD.Run`: openEMS ends the time loop at its next check, or right after the setup if the request
  came during it (F18). If no instance is inside `FDTD.Run`, it calls `_thread.interrupt_main()` instead. The shim
  raises KeyboardInterrupt after recording the aborted call, and at the start of any later `FDTD.Run`, so the script
  never goes on with a truncated run. No OS signal reaches openEMS, so its setup-time force exit (openems.cpp:1369)
  never fires and the launcher still writes its report.
- **A script blocked outside `FDTD.Run`.** `interrupt_main` sends no signal: it marks an interrupt that the main
  thread raises between bytecodes, so a script blocked in a C call outside `FDTD.Run` sees the stop only when that
  call returns (Python 3.14.6: a stop 1 s into `time.sleep(10)` raised KeyboardInterrupt after 10.0 s). If the call
  has not returned 60 s after the stop, the CLI's SIGTERM ends the script; script mode keeps Python's default TERM
  action, so the launcher writes no report: e2e and run rebuild their calls from `tool.log` (`report_rebuilt`), and
  validate, which has no calls, reports its whole-run load as missing and withholds its case times.
- **The stop race.** The shim adds its instance to the running set before it checks the stop flag, and the watchdog
  sets the flag before it reads the set, so no stop is lost. If `interrupt_main` lands while the shim writes a record,
  that record can be lost; the CLI then rebuilds it from the markers.
- **Exec mode** (bench, ab, check, debye-check, diamond-check, the helpers). The watchdog sends SIGTERM to the
  launcher's process group; the launcher's own TERM handler is a no-op, so it writes its report. SIGTERM ends zsh,
  Python and openEMS at once. SIGINT would not: a python3 inside the time loop would abort gracefully and exit
  normally, and a zsh script that survived it could start its next run.
- **The CLI's side.** INT, TERM and HUP reach it through the injected `FdtdSignalSource`: the live one sets SIG_IGN and
  a DispatchSourceSignal for these three while a command runs, and restores the previous dispositions
  once the envelope is written; the tests use a fake one. info handles them too, because its probes and scans are
  children: after a stop request it ends as `interrupted` (130) once the step the signal arrived in is over, with no
  warning for the child that the stop ended and no result. While the envelope is finished (the cleanup, `--output`,
  stdout) no child is left to stop: one signal there is only noted, and a second one ends the CLI at once with the
  signal's default action and without an envelope, so that a write that blocks (a stalled reader of stdout, a hung
  volume) can be left. A SIGHUP that was already ignored when the CLI started (`nohup`) stays ignored and is no
  stop request. INT and TERM are stop requests whatever was inherited: a non-interactive shell starts `cmd &` with
  SIGINT ignored, and `kill -INT` from the script still stops the run.
  - First signal: `stop` is written to the control pipe, the status becomes interrupted, and a 60 s timer starts.
  - A second signal, or the timer firing while `killpg(pgid, 0)` still finds the group: `killpg(pgid, SIGTERM)`.
    Two signals that arrive before the handler runs reach it as one kqueue event; the source's count makes them two
    calls, so `kill -INT p; kill -INT p` from a script escalates at once.
  - 10 s later, if the group is still alive: `killpg(pgid, SIGKILL)` and the warning `killed`.
  - Short direct probes get SIGTERM at once. A probe that exits while a process it started still holds its pipes
    is read for 2 s more; then what is left of its process group gets SIGKILL.
- The CLI ignores SIGPIPE; a write to a pipe whose reader has gone returns EPIPE instead.
- **Exit 130.** The envelope still carries what was parsed. A launcher report missing after an interrupt is expected
  after SIGTERM or SIGKILL; e2e and run then rebuild their calls from the markers and openEMS lines in `tool.log`
  (warning `report_rebuilt`) with their loads null, so their speeds are withheld. A run that finished before the stop
  took effect exits 130 as well, even when its verdict passed (section 7.3).
- **If the CLI dies,** EOF on fd 3 makes the launcher stop its children itself (the same stop as above), then send
  SIGKILL to its own process group 30 s later if anything still runs. `caffeinate -w` ends with the CLI. Nothing keeps
  simulating on the shared Mac.
- Interrupted runs keep their folders (section 10.2).

## 10. Safety

| # | rule |
|---|---|
| S1 | **SIP and DYLD.** DYLD only on direct Python children (F1), with a Python proven to keep it (the probe); the zsh scripts are proven by the pre-probe. The libraries actually loaded are checked: bench's BENCH_LIB check, the validation meta, the launcher report. No caffeinate, env, shell or otool in front |
| S2 | **No hidden defaults.** Inherited `OPENEMS_*`, `DYLD_*`, `PYTHON*` (except `PYTHONPATH` and `PYTHONUSERBASE`, kept and warned), `Malloc*`, `RFSIM_PATH` and the tool inputs are removed and listed. Knobs come only from the user and show in the labels. Every injected `FDTD.Run` option is reported per call. Other `RFSIM_*` pass untouched and are recorded; e2e passes the toolkit's own probe-end values. The CLI never edits the tools or the toolkit |
| S3 | **No install in v1.** No command writes under the installed prefix or the snapshot folder: every location a command would write, create or rename is checked at plan time, in a dry run too, and one in or over a protected folder is refused (`protected_path`, exit 2, section 10.2). The version 2 install design is in section 14 |
| S4 | **A valid load on every speed and run time** (section 8): rows, runs, calls, the top-level load and the stderr lines. A figure without one is null and withheld, with `load_missing`; no raw tool line with a speed or a run time is echoed |
| S5 | **Nothing overwritten silently** (section 10.2); backups sit next to the original |
| S6 | **Timed commands are refused while a simulation runs, or when the scans cannot tell** (section 10.1); the scans are decided from their records |
| S7 | **No viewer, no names.** The CLI opens no files and launches no apps (neither the `open` command nor AppKit's workspace API). Public text says "the author", never a first name, and describes other engines and tools by their measured differences only (the text-rule test, section 12) |
| S8 | **Bit-identity to stock v0.37.0 is the CPU acceptance:** check's reference must be the stock build in all three files (UUID or sha256 against SNAPS/stock, plus the stock scan), otherwise the status is partial with `acceptance: false`. Tolerant rows are never counted as proof, except under `--exact` |
| S9 | **Stopping is bounded and never leaves simulations running** (section 9): a stop goes through the control pipe, script mode uses SetAbort, exec mode SIGTERM to the group, the escalation to SIGTERM and SIGKILL is timed, a dead CLI stops its children through EOF, and interrupted runs keep their folders |
| S10 | **The implementing session worked only in the `fdtdkit` worktree** (during development); it never built or tested in the worktrees of the other kits |

### 10.1 Concurrency

- Before any run command, two scans list the other processes that hold an openEMS library (F14):
  - scan A, `/usr/sbin/lsof -n -w -F pcn -c Python -c python -c openEMS`, keeps every process with an `n` record whose
    file name starts with `libopenEMS` and ends in `.dylib`; that catches copies anywhere (incomplete snapshots, build
    folders, a moved-aside prefix, scratch copies);
  - scan B, `/usr/sbin/lsof -n -w -F pcn -- FILE...`, keeps every process with an `n` record for one of the listed
    files, whatever its name. FILE is the real path of the installed libopenEMS, of every complete snapshot's
    libopenEMS.0.dylib, and of every `--lib` and `--build` libopenEMS.
- Each scan is decided from its records: a process kept (scan A: a `libopenEMS*.dylib` name; scan B: a listed file)
  means found. Nothing kept means none when lsof exits 1 (something asked for was not found; with other Python
  processes only, scan A exits 1, because `-c openEMS` matches nothing, F14) or 0 (everything asked for was found and
  nothing kept: for scan A, a process for each of the three names, none with a `libopenEMS*.dylib` open); nothing
  kept with any other exit status, or with none (killed at the timeout, never started), means unknown. Field letters
  other than p, c and n (lsof always adds `f`) are ignored.
- The two scans are merged by pid; the CLI's own pid and its descendants (from `/bin/ps -Ao pid=,ppid=`) are dropped,
  and `/bin/ps -o pid=,command= -p PID,...` names the rest.
- Policy: bench, ab and e2e refuse with exit 5 (`simulation_running` when a process is found, `concurrency_unknown`
  when a scan is unknown) unless `--quiet PCT` or `--allow-concurrent` is given; check, validate, debye-check,
  diamond-check and run give the same codes as warnings.
- A stop (INT, TERM or HUP) before or during the scans ends the command as `interrupted` (130), with its planned jobs
  marked interrupted: the stop controller kills each child as it starts, and a scan cut short says nothing. Only a
  process that a scan found before the stop still counts, as a refusal (5) or a warning.
- There is no lock file, so two CLIs started in the same second can both pass (deferred, section 18).
- `caffeinate`: `/usr/bin/caffeinate -i -w <CLI pid>` runs beside every run command (its own process group, never
  waited for) unless `--no-caffeinate`. It never runs in front, where it would strip DYLD (F1).

### 10.2 Run folders, outputs and overwrite protection

The run folder (section 5.3) is made for run commands, never for `--dry-run`, info or load. It holds `tool.log` (every
byte of output), `envelope.json`, `fdtdkit_run.py` and one `launcher-ROLE.json` per launcher invocation, and the
working folders: `runs/` (bench, ab, check), `validation/` with `work/`, `tmp/` (debye-check, diamond-check) and `e2e/`.

- After ok or partial, unless `--keep-runs`, the CLI deletes `runs/`, `validation/work/`, `tmp/` and everything in
  `e2e/` except `result.json` and `sp.npz`. Nothing is deleted after fail, error or interrupted, and a user-given
  `--out-dir` is never deleted. `--output` is backed up and written once, before this cleanup, and already says
  `keptRuns` false, so a file that cannot be written is an error (exit 4) that deletes nothing, and no write follows
  the deletion. Only when the cleanup fails is the file written again, with `keptRuns` true.
- Backups go next to the original as `PATH.previous-<yyyyMMdd-HHmmss>`, never into the run folder, whose default base
  under /tmp has no established lifetime. The suffix comes after the extension, so the results globs (`*_TAG.txt`,
  `*.json`) do not pick backups up. Each backup gives `output_backed_up` and appears as `outputs[].backup`.
- A copied backup holds the bytes of the file a symbolic link points at, so it is a file of its own: the tool then
  writes through the link, and a copy of the link itself would show the new table.

| output | without `--overwrite` | with `--overwrite` |
|---|---|---|
| a bench `--tag` table | refused if it exists (exit 5, `would_overwrite`) | copied to `NAME.previous-STAMP` first, then bench writes it |
| check's 4 or 6 tables | same | same |
| validate's `.json` and `.md` | same | same |
| `--output FILE` | same; a file that appears during the run is left alone (`tool_failed`, exit 4, the envelope on stdout: the tools have run, so the status is never refused) | renamed to `FILE.previous-STAMP`, then the new file is written atomically; a folder is never renamed |
| e2e's `--out-dir` (exists and is not empty) | same | renamed to `DIR.previous-STAMP`, just before the run starts and after a second check against the protected folders |
| ab's `--record` | refused unless `--append`; a folder is a usage error (64) with or without it | refused with 64 when combined with `--record` |

Each output gets `{path, sha256, existedBefore, backup?}`. Without `--tag`, nothing goes to `results/`.

**Protected folders (S3).** Before anything is created, renamed or spawned, and in a dry run too, every location the
command would write, create or rename is checked against the protected folders. No option overrides the check.

- Protected: the installed prefix, the folder above the `lib/` that holds the installed libopenEMS as the Python
  probe finds it (taken for the folder the probe names and for the one its libopenEMS resolves to; a folder not
  called lib, or a lib folder whose parent is / or holds a home folder, protects only itself), and BUILD.md's
  default prefix `~/opt/openEMS`; and SNAPS, from `--snaps`, `$OPENEMS_BENCH_SNAPS` and the default
  `~/opt/openEMS-dev/snap`. `~` is `$HOME` and also the account's home folder from the password database when
  `$HOME` names another, so the defaults stay protected when there is no tools tree to run the probe in, its Python
  cannot load openEMS, or `$HOME` points elsewhere. Each one that exists is protected; a missing one is skipped and
  fails nothing. load runs the Python probe for this.
- **The library folders of the line.** Every LIB that the line names by its path (a LIB with a `/`, section 5.1:
  check's SNAPs, `--stock`, `--lib`, `--ref`, the LIB of each `--config`, `--extra` and ab CFG) and that is a
  folder is protected for that command like the snapshot folder, whether it holds a complete library or not, and
  before the library is resolved: a slip can make any folder a LIB (section 4.1), and the command then ends with
  `library_not_found` or `library_incomplete` after `--output` was accepted. In a CFG the LIB is the one the
  grammar of section 5.2 reads: the text before the first `#` up to its last `@`. A LIB given as a snapshot name
  lies in SNAPS; a LIB without `/` also protects a folder of that name in the working directory when there is one
  (not `installed`, which names no folder there), so `check cg29 --output cg29/e.json` is refused where `./cg29`
  exists. A path that is no folder protects nothing. It costs no probe. Outputs beside such a folder are fine.
- **One rule for the discovery options** (`--repo`, `--python`, `--rfsim`, `--snaps`): the list is the union of
  (a) what discovery finds with the line's own options and (b) what it finds with every one of them ignored: the
  tools tree of the walk from the working directory and the executable, PATH's python, `$RFSIM_PATH`,
  `$OPENEMS_BENCH_SNAPS` and the defaults. An option can therefore add a protected folder and never take one away,
  whether it is right, mistyped (a `--repo`, `--python` or `--rfsim` that names nothing ends the command, exit 2 or
  3, or is a warning of info; the prefix that the plain line protects stays protected) or names another
  installation (both prefixes are protected). In (a) the options count one by one: where one of them names
  nothing, the command's own probe cannot run, and the probe is made with the others and the default in place of
  that one, so a correct `--python` of a second installation beside a mistyped `--rfsim` or `--repo` still
  protects that installation's prefix, and a correct `--repo` beside a mistyped `--python` gives PATH's python a
  tree to be asked in. For the snapshot folders (b) costs nothing. For the installed prefix it is a second Python
  probe, run whenever the line names something with one of the four options (without any, (b) is (a)), and
  skipped when it would be a child that was asked already. Two probes are the same child when nothing that can
  change the answer differs: the Python as named (a venv's python3 is a link to its base Python and still another
  Python), the tools tree as a folder (a link to it or another spelling of its path is the same tree) and the
  environment without `RFSIM_PATH`, which `import openEMS` does not read. So a line whose options name what the
  defaults find, and the everyday line with `--rfsim DIR`, pay no second probe; a correct line with a `--python`
  or a tools tree of its own pays that one probe more. Nothing of these extra probes is kept or recorded: the
  command goes on with its own tree, Python, environment and library, and the envelope shows only those (the
  probes' time counts in `timing.probeSeconds`). Where neither the line nor the defaults give a tools tree, or a
  Python, nothing is added, as on a Mac without them. The rule is for lines that parse: one that did not writes
  no file and probes nothing (section 4.1).
- Checked: `--output` and its planned backup; ab's `--record` (default `RUN/abtest.txt`); e2e's `--out-dir` (default
  `RUN/e2e`) and its backup; RESULTS and the `--tag` tables with their backups (bench, check, validate; validate
  without `--tag`: `RUN/validation`; check's RESULTS is the `results/` beside the real folder of `bench/check.sh`,
  section 4.2, so `--repo` is the option it names); RUNS and the run folder (load: its scratch folder); run's
  `OPENEMS_EXPORT_*` folders. Default locations go through the same check; what a `run` script writes by itself is
  not checked.
- Refused: a location that is a protected folder or lies inside one; a location renamed or replaced as a whole
  (`--output`, `--record`, `--out-dir`, a table, a backup) also when it holds one (`FdtdProtectedPaths.holds`, the
  test that e2e's `--out-dir` uses for the folders its run needs, section 4.2), by the protected folder's real
  path or by the path it is named by (`--output ~/opt --overwrite` would rename the folder that holds both, also
  when `~/opt/openEMS` is a link to another volume, since the name dyld and the Python module use goes through
  `~/opt`); a file a tool writes in place when it exists (a `--tag` table with `--overwrite`, ab's `--record` with
  `--append`) also when it is another name, a hard link, of a file in a protected folder, since bench.py's and
  run_validation.py's `open(..., 'w')` and abtest's `open(out, 'a')` change the file under all its names. For a file
  with more than one name, the protected folders on its file system are searched for another one (links are not
  followed, other file systems skipped), and the message names it. RESULTS, RUNS and the EXPORT_* folders are only
  written into (bench.py, abtest.py and run_validation.py write files in them, openEMS its exports; the CLI makes its
  run folder in RUNS and cleans only inside it; table backups are copies), so for them the first rule is enough.
- Resolution: a path the CLI takes from an option is made absolute against the CLI's cwd (`~` expanded, `.` and `..`
  folded, as the CLI writes it); an `OPENEMS_EXPORT_*` value is taken as given (an absolute path, opened by openEMS),
  so a `..` in it counts after the links before it, as the kernel walks it. The nearest existing part is resolved by
  realpath(3), and the file identities (st_dev, st_ino) of that part and of the folders above it are compared with
  the protected folder's, both ways. Symbolic links, letter case on APFS and firmlinks therefore cannot hide a
  protected folder. A path that does not exist yet is judged by its nearest existing part; a dangling link on the
  way, the last name included, is followed, since a tool that writes through it creates its target. finish()
  replaces a last-name link of `--output` instead of writing through it (an atomic rename), so for `--output` the
  check is deliberately stricter than the write.
- Timing: the check runs at plan time, and finish() looks at `--output` once more after the tools ran and before it
  renames or writes it, so a folder on its path that became a link into a protected folder meanwhile is refused
  then: the file is left alone, the envelope goes to stdout and, the status being error, the run folder is kept. The
  tables, the record and `--out-dir` are written by the tools themselves, so for them the plan-time check is the
  only one.
- After a stop: a stop request ends the installed library's probe, or each child as it starts, so the prefix that
  the probe would have named is not known; that holds for each of the two probes of the rule above. Such a list is
  not kept for the rest of the command, and a check made on
  it lets nothing through: a location in a folder that is known all the same is refused as ever, and any other one
  ends the command as `interrupted` (130) with nothing written to it; an `--output` FILE is then left alone and the
  envelope goes to stdout. A probe that answered before the stop, or a Mac without a usable Python, gives the same
  list as without the stop.
- Issue: `protected_path`, exit 2 like other bad input (not 5: no option and no later moment makes the location
  acceptable). The message names the option, or what the location is (`the run folder`), the path (and what it
  resolves to, when that differs, or its other name in the protected folder) and the protected folder; the hint is
  "a path outside ROOT", "a path that does not hold ROOT", or for a hard link "a file of its own (copy it to a new
  name first), or a path outside ROOT". A location inside one already refused is not named again.

## 11. Distribution

A family rule for every kit: the kits share the flags `--nodes`, `--hosts` and `--distribute` and the two phases
below, and each kit's plan has a section on how it distributes work. This is fdtdKit's.

- **Backend abstraction.** The work units are logical and serializable, and there is no global state.
  - `FdtdJob` (Codable, Sendable) = {id, role, tool (bench, abtest, check, validation, debye, diamond, e2e, script,
    quiet, load), model?, scale?, nrts?, rounds?, configs [{library {spec, files [{name, sha256, uuid}]}, engine,
    threads?, nodumps, knobs}], knobs, tag?, options, inputs [{role, path, sha256?}], outputs [{role, path}]}. A job
    names libraries by identity (sha256 and UUID) and holds no host paths except the user's own inputs and outputs.
  - `protocol FdtdBackend { resolve(job, host) -> FdtdInvocation {role, argv, env, cwd, host};
    run(invocation, control) -> FdtdJobResult {exit, seconds, host, logPath, report?} }`.
  - v1 has only `LocalBackend`: it resolves Python, the repo, the run folder, the snapshot folders and DYLD for this
    Mac, and runs through Spawn. The envelope keeps both `jobs[]` and the resolved `invocations[]`.
- **Flags.** `--nodes N` or `--hosts FILE`, and `--distribute auto|off|frequencies|domain`, parsed on run, e2e,
  validate, check, debye-check and diamond-check. `--nodes` with `--hosts` exits 64, a missing hosts file exits 2
  (`hosts_file_missing`), any other `--distribute` value exits 64. bench and ab refuse `--nodes` above 1 and `--hosts`
  (64): their speeds describe one Mac.
- **v1 runs everything on this Mac.** `--nodes`, `--hosts` and `--distribute domain` give the warning
  `distribute_local` ("multi-Mac execution is designed but not implemented; running on this Mac", sbrKit's wording);
  the record is `distribution {requested, mode: "off", nodes: 1, hosts, reason}`.
- **`frequencies`** does not apply: one time-domain run covers the whole band, so there is nothing to split by
  frequency; it runs locally with the warning `frequencies_not_applicable`.
- **Phase 1, independent runs.** check's models, the validation cases, e2e and run jobs and sweeps run whole on single
  Macs, over ssh on a Thunderbolt Bridge. Every host has the same tools tree and libraries of the same UUID and
  sha256, and each host resolves a job's argv and environment itself; the results are copied back. Speeds are never
  pooled across hosts: each row carries its host and that host's load.
- **Phase 2, domain.** x-slabs across Macs with a one-plane E/H halo exchange per timestep (the fused sweep already
  works on x-slabs). Only worth it where a step's compute far exceeds the halo transfer and its latency. MPI serves
  only as a reference design; upstream removed its MPI engine in 5261463 (F15).
- **auto** stays local unless `--hosts` is given and the command has several independent jobs (once phase 1 exists).

## 12. Tests and acceptance

swift-testing (`@Suite`, `@Test`, `#expect`; fixtures through `URL(fileURLWithPath: #filePath)`) needs Xcode's
toolchain, while xcode-select points at the Command Line Tools (F24):
- unit tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter fdtdKitTests`;
- smoke runs, alone and serially:
  `EMSKIT_FDTD_SMOKE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter fdtdKitTests.SmokeTests --no-parallel`.

**Unit suites** (no simulations, under 30 s in total):

| suite | checks |
|---|---|
| GrammarTests | every usage example parses; the usage errors of section 4 exit 64 with their hints (`--confg`, `--config=x`, `--exact yes`, a repeated `--tag`, `ab --run-redo 2` without `--quiet`, `e2e gcpw --floor 0.05`, `check --lite --quiet-max 60`, `bench --nodes 2`, `--distribute runs`, `bench patch --scale 1.2345678 --nrts 10`, ...); a positional that starts with `-` is a usage error on every command (`check cgD --tag t -snaps DIR`, `debye-check -x`, `run -board.py`; nothing probed, nothing written), with the option meant or the path form as the hint, while an option's value and the tokens after run's `--` may start with one; `emskit fdtd` alone and an unknown command give usage on stderr, exit 64, no envelope |
| KnobTests | the registry equals the 30 names parsed from BUILD.md section 7 (read through `#filePath`); the value rules (FTZ 1 ok, FTZ 0 and 2 and empty refused; TILE 12:8 and 7:0 everywhere, 7,0 only in the environment; FUSED_BLOCK 0 refused; EXPORT_FIELDS on bench not allowed); the warnings; `--knob` merging and conflicts |
| ParserTests | every row and summary of `results/*_cg29.txt`, `*_cg28gpu.txt` and `*_step1.txt`; constructed fixtures for every format of section 4.4 (inf differences, busy lists with spaces, rows without `gpu dev`, abtest redo lines and -1 loads, the four check final lines, debye and diamond outputs, an e2e RESULT, a tool.log with call markers); `results/validation_cg18_mt4.json` (15 checks passed) and a NaN fixture read as JSON5 into a failed check |
| EnvTests | the remove, keep and set rules of section 6.1; no DYLD on a zsh invocation |
| DiscoveryTests | repo from `--repo`, the cwd walk and the executable walk; the old harness passed over; `/usr/bin/python3` passed over; `python_strips_dyld`, `python_name_mismatch`, `library_incomplete`; rfsim; the `-2` run folder suffix (FakeSystem) |
| ConcurrencyTests | records decide found, none and unknown; unknown refuses bench and warns on check; other field letters ignored; own descendants dropped; scan A finds a copy outside every listed path (FakeSystem); a stop during the scans ends as `interrupted` (130), not as a refusal, with the planned jobs marked interrupted; a stop before the gate starts no child; a process scan A found before a stop still refuses bench (5) |
| LibraryScanTests | synthetic blobs for the version regex, engine help strings, knob names, sha256 and the LC_UUID parser (thin, fat, none); on the real snapshot folder, properties per folder (never counts) and the rows of section 5.1 while their files keep those hashes; `info` and `check` stream every snapshot file once (`check` reads none whole again); a snapshot name typed in another Unicode form keeps the bytes typed |
| StockTests | the stock identity for SNAPS/stock and a copy of it; `--stock cg18` plans partial with acceptance false; stock libopenEMS beside a fork libCSXCAD gives acceptance false; a registry name in either file fails the stock scan, and the scan from the snapshot index equals the one that reads the folder; a SNAPS/stock that the folder's listing leaves out is still the stock the reference is matched against |
| EnvelopeTests | sorted keys, "inf" strings, schema names; the exit table and its precedence; the stderr issue format; null figures without a valid load, never printed; ab statistics without unloaded runs |
| PlanTests | every command's jobs and invocations (argv, cwd, envSet, envRemoved, the launcher wrapper and the control fd) equal `Fixtures/plans/<command>.json`; overwrite refusals and planned backups |
| LauncherTests | with a fake `openEMS` package: option order, dropped spellings, `optionsLost` on the legacy variant only, the sim path, redirected stdout, the report fields, exit codes, sys.argv and sys.path, `stop` during a Run (SetAbort, exit 130, report) and in Python code (interrupt_main), EOF, exec mode's SIGTERM (under 5 s); the python probe against the same package without package metadata (the suite runs when a framework or Homebrew python3 is found); the probe's and the launcher's version rule (metadata of another copy gives no version) and their one rule for legacyEmptyOption (an unreadable pyx, a package that imports nothing); the rfsim probe on toolkits that lack values |
| LauncherSourceTests | LauncherSource.swift embeds `fdtdkit_run.py` byte for byte (no Python needed) |
| SpawnTests | process-group leader, the exact environment, stdin /dev/null, output order on the merged pipe, EOF on fd 3 when the write end closes |
| SignalTests | with a fake signal source and clock: `stop` on the first trigger, SIGTERM on the second or after 60 s, SIGKILL 10 s later with `killed`, dispositions restored; info installs the handling like every command, a line that did not parse none, with `--output` or without |
| TextRuleTests | the strings the test lists (a first name, a pejorative word about other tools, the path of the `open` command and AppKit's workspace class) occur nowhere in `Sources/`, this file and the README's command-line section |
| EchoFilterTests | no tool line with a speed or a run time is echoed to stderr; other lines are (section 7.2) |
| VerdictTests | a tolerant row is no proof without `--exact`; check's FAIL rule and its guard beside the final line; two `check cg29 --lite` runs on a fake tool (exit 1 for a MISMATCH block, 4 for FAIL without blocks); a check block's summary needs a row per config, the tolerant extra's and the lite reference's too |
| GpuFallbackTests | `gpu_fallback` from a bench row, a check extra, an ab config and a validation run (section 4.4) |
| NoInstallTests | S3: no command writes under the prefix or the snapshots; `protected_path` (exit 2) for outputs, records, `--out-dir`, tables and run folders in or over a protected folder, through links, `..`, letter case and hard links, without the probe or with `$HOME` elsewhere, and once more before `--output` is written; the prefix rule, the account's home lookup, a missing protected folder, and the cases that pass (section 10.2); a refused load records its invocation in the scratch folder a real load writes to |
| LoadedLibraryTests | S1: a loaded image lies in LIB's folder as given or by its real path (dyld reports real paths); `library_not_loaded` from the probe before the run and from the verdicts of run, validate and e2e; `knob_unsupported` and `engine_unsupported` for every CFG and `--knob`, check's `--extra` among them, whose libraries join the used list; a SNAP or `--stock` that check.sh's configs cannot carry is refused under its own field; a folder whose three names are links to files elsewhere; check's probe takes an extra's snapshot folder; validate reads `~` anywhere in a library's path; bench, ab and check refuse a folder of links to files elsewhere (`library_incomplete`) |
| OutputTests | `--output` that is a folder or empty (64); finish()'s order (the `--output` backup and write before the cleanup, a file that appeared during the run left alone, signals handled until the envelope is out); a line that did not parse writes no file (stdout, one stderr line, `--dry-run` not read back either), while a usage rule found after parsing writes `--output`; a usage error before a bad `--tag`; e2e's `--out-dir` renamed only just before the run and never the run folder's place; only a SIGHUP ignored at the start stays ignored; a capture ends what its child left in its group; after the review of the fixes: an appeared `--output` is `tool_failed` (4), a failed backup writes over nothing, `--output` is written once before the cleanup and corrected when the cleanup fails, a second signal while the envelope is finished gives up, e2e's second check before the rename and no rename after a stop; a usage rule found after parsing before a bad `--tag`; e2e's `--out-dir` that is empty or holds a folder the run needs (64), looked at again after the quiet wait (filled meanwhile: 5, or a backup), the job resolved before the rename; e2e refuses an `--out-dir` that holds a folder the run needs by the name it is given through (a link inside it) |
| FailingVerdictTests | the verdicts of ab, validate, debye-check, diamond-check, e2e and run on failing inputs (a differing run, a failed check, FAIL, PASS beside DIFFERENT, an exception, another engine, a tool that failed), each directly and through its command on a fake tool (exit 1 or 4) |
| GuardTests | the sampler counts (no process or no GPU sample seen: no valid load, `load_unavailable`, a call's speed and validate's case times withheld); validate does not take an old JSON for this run's; a launcher without a report (`launcher_failed`); a child that cannot start (`spawn_failed`); the zsh pre-probe must load LIB; `--keep-runs`; bench's summary needs a row per config; `info` beside a `--rfsim` that names no toolkit; `tools_modified` in a tools tree below the top level of its repository, also under a folder name outside ASCII |
| OpenItemTests | the items left open by the two reviews and closed on 2026-11-10: a stop during the installed library's probe lets no `--output` through (130, stdout), still refuses a known folder, and its list is not kept; a record from the snapshot index equals the one from the files, for a snapshot by name or by path, and such a LIB is read once (`info --lib`, `run --lib PATH`); only the same bytes of a path find an index entry; info stops on a signal (130, no later child); a knob given with two values warns `knob_ignored`; a `--rfsim` that names no toolkit leaves the installed prefix protected; the engine's knob warnings are made for the value that reaches the child, not for one a later `--knob` replaced |
| DiscoveryOptionTests | the one rule of section 10.2 for `--repo`, `--python`, `--rfsim` and `--snaps`: an option that names nothing leaves the prefix and the snapshots of the plain line protected (info, load, bench; `--output` with and without `--overwrite`); a `--python` with a library of its own adds its prefix and changes nothing the command records; a correct `--python` beside a `--rfsim` or `--repo` that names nothing keeps its prefix protected, and a correct `--repo` beside a `--python` that names nothing gives PATH's python its tree; options that name what the defaults find pay no second probe, nor does `--rfsim DIR` without `$RFSIM_PATH` or a `--repo` through a link, while another tree pays one; a stop during the second probe lets nothing through; a `--python` that is a link to PATH's python and names a prefix of its own is another Python (two probes, both prefixes protected); a line that did not parse probes nothing; the library folders of the line: a folder that a slip makes a SNAP of check (`--stock -snaps DIR`, `snaps DIR`) refuses an `--output` inside it, with and without `--overwrite`, in a dry run too, and nothing changes; every way of naming a library by its path on the ten commands (complete library or not) refuses an `--output` inside and accepts one beside; the same two slips with DIR as a bare name (`mysnaps`) are refused too, a snapshot name protects only a folder of that name that exists in the working directory, and an `--output` elsewhere is written as before; `--record`, `--results`, `--out-dir` and `--runs` inside such a folder; a path that is no folder protects nothing (`library_not_found`) |
| UnparsedLineTests | the rule of section 4.1 for a line that did not parse: for each of the ten commands an unknown option beside `--output FILE`, with and without `--overwrite`, FILE new, existing and inside each kind of protected folder, leaves every path and its bytes as they were, starts no probe and no child, installs no signal handling, exits 64 and prints the whole envelope on stdout with the stderr line; the same for every spelling of a discovery option that the attack rounds used (`--SNAPS`, `--snapshots`, `--snaps-dir`, `--py`, `--python-path`, `--snaps=DIR`, `-snaps DIR`, given twice, without a value) and for tokens after `--`; check's and validate's bad `--tag` (2) writes no file either; the same lines parsed follow the union rule |
| PathOptionTests | the list of the options that take a DIR, a FILE or a PATH equals the grammar's; an empty value of each is a usage error (64) before any probe; ab's `--record` as a folder (64, with `--append` too), with a missing folder (2) and in a protected folder; a folder for `--output`, `--python`, `--hosts` and run's SCRIPT |

27 unit suites with 244 tests; with SmokeTests, 28 suites and 258 tests (section 16).

**Smoke runs** (only with `EMSKIT_FDTD_SMOKE=1` through the command above; `@Suite(.serialized)`; real libraries, in
process through `FdtdCLI.run` with the fake signal source; every run gets `--allow-concurrent`, because other
sessions share the Mac; rfsim runs take `--rfsim` from the test-only variable `EMSKIT_FDTD_RFSIM` and are skipped
without it; every test asserts that each speed in its envelope has a valid load and logs it; 45 to 70 s on
2026-11-06 with the other processes at 0.3 to 8 cores, section 16):
1. `--version`, `--help`, no arguments.
2. `info`: dyldKept true; stock and cg29 have their expected identities; the installed libopenEMS has sameBuild cg18
   (the install until 2026-11-06) or cg29 (since), whichever its sha256 shows (section 5.1; skipped for any other
   install).
3. `load --seconds 2`: valid.
4. `bench patch --nrts 2000 --config stock@multithreaded:4 --config cg29@multithreaded:4`: IDENTICAL, two rows, both
   engines confirmed, both loads valid.
5. `ab patch --nrts 2000 --rounds 2` on the same pair: c1's diffs only `identical`; both sampler checks valid.
6. `bench patch --nrts 2000 --config cg29@multithreaded:4 --config cg29@metal-diamond:0 --knob OPENEMS_FTZ=1 --exact`:
   ok, the tolerant rows exact, `not_bit_identical_to_stock`.
7. `validate --lib cg29 --quick --case slab --case lines`: ok, libraries from snap/cg29.
8. `debye-check cg29`: PASS, 2 comparisons.
9. `e2e gcpw --lib cg29`: ok, stop kind probeEnd, one call with mcs and a valid load.
10. `run REPO/scripts/cache_valley/box.py --lib cg29 --threads 4 -- 60 60 20 600 4 TMP/box`: one call,
    selfCpuPercent >= 50, multithreaded confirmed.
11. The same with `--engine metal-diamond -- 60 60 20 600 0 TMP/box2`: `option_overridden` (box.py passes
    engine=multithreaded), `(Metal, diamond-blocked)`, no `gpu_fallback`.
12. Refusals and plans: `bench patch --config cg18@metal-diamond:0` exits 3; an inherited `OPENEMS_FTZ=1` with
    `--dry-run` gives `env_removed` and a planned environment without it; `check cg29 --tag cg29 --lite --dry-run`
    exits 5 (the cg29 tables exist); `check cg29 --stock cg18 --tag smoke --lite --dry-run` plans partial with
    acceptance false; `diamond-check cg27 --dry-run` exits 3; `check cg29 --tag smoke --lite --dry-run` and
    `diamond-check cg29 --dry-run` give plans only.
13. Stop: `run box.py --lib cg29 -- 60 60 20 200000 4 TMP/box3` with a trigger after 3 s exits 130 within 10 s, with
    one call of stop kind aborted, the report present and no process of the group left; `bench notch --scale 3
    --nrts 20000 --config cg29@multithreaded:4` with a trigger after 3 s exits 130 and leaves no bench.py or
    runner.py.

**Acceptance** (by hand, once per phase, logged in section 16 with the load and the run time):
- v1a: `emskit fdtd check cg29 --tag cliaccept --lite --rfsim DIR` gives ALL IDENTICAL (6 models), the guard agrees,
  every row is confirmed, and acceptance is true. Afterwards the six untracked `results/*_cliaccept.txt` are deleted,
  unless the author keeps them (section 17).
- v1b: `emskit fdtd diamond-check cg29` gives PASS with 9 boxes and 72 comparisons (expected for cg29 only; the count
  is never hardcoded in the CLI); `emskit fdtd e2e gcpw --lib cg29 --rfsim DIR` is ok.

## 13. Install and publish

- Build with `swift build -c release` (macOS 26 or later, Swift 6.2 or later; on the author's Mac Swift 6.4). Run
  `.build/release/emskit`, or symlink it into a folder on PATH: discovery follows the executable's real path back to
  the worktree. A copy, for example into `~/.local/bin` (first on PATH, F2), loses that walk and then needs the cwd
  walk or `--repo`.
- The CLI installs nothing itself (S3).
- The repository side of publishing is the author's, with steps that are not part of the published repository. On
  2026-11-06 `fdtdkit` was merged into `main` (a fast-forward), and the author chose to publish the repository as one
  commit, without the history in which it was made, so `main` needs no rewrite; the other kits' branches (`femkit`,
  `momkit`, `sbrkit`) are not part of it. On 2026-11-07 the two fork branches that the patches are made from were
  rewritten for publication, with the author's public identity, upstream's trailers and the same trees, and pushed
  to the author's GitHub forks (`CHANGELOG.md`, 2026-11-07). A fresh build of the published patches passed the full
  check on 2026-11-07 (`results/fresh_build_pub29_2026-11-07.txt`), and on 2026-11-08 the author settled the kits'
  licence question (section 15). On 2026-11-10, on the author's word, this repository was pushed to
  github.com/anmartinez1256/emsKit as that one commit.

## 14. Version 2

- **`install`.**
  - An explicit command; the confirmation is a phrase typed at a TTY, never a `--yes` flag.
  - The two concurrency scans must show nothing running, decided from their records; unknown refuses.
  - A dated `cp -a` backup of the whole prefix beside it (as `~/opt/openEMS.cg16-2026-11-04` was made by hand before the
    cg18 install, and a backup of the cg18 prefix before the cg29 install of 2026-11-06).
  - Before installing, the build folder's three UUIDs must equal those of a snapshot that passed `check` and
    `debye-check`. On 2026-11-05 the author's build-gpu matches no snapshot (F20), so this gate would refuse it.
  - `cmake --install` of that build folder only (on the author's Mac build-gpu). In the author's own checkout of the
    superproject, `update_openEMS.sh`, `build_python.sh` and a private setup script build the older speed-m5 tree,
    without the probe end criterion, so the install never uses them there; a fresh checkout is built with
    `update_openEMS.sh`, as BUILD.md section 5 does, and BUILD.md section 6 rebuilds its Python modules with
    `build_python.sh`. On 2026-11-06 none of the author's build folders both matched cg29 and installed into the
    prefix, so cg29 was installed by hand without `cmake --install`: snap/cg29's libopenEMS, with the prefix's install
    name and rpath and re-signed, and `include/openEMS/openems.h` replaced the installed ones (section 16).
  - Afterwards the installed UUIDs must equal that snapshot's, and `debye-check` runs from the install (on 2026-11-06:
    the installed libopenEMS has cg29's UUID, and `debye-check installed --ref cg29` passed; section 16).
  - Names follow BUILD.md: a prefix of its own such as `$HOME/opt/fdtdKit`, and `$PREFIX.fdtdKit` for an install moved
    aside.
- **`rollback`** from that backup.
- **`accept`**: the full check as one bundle: `bench/check.sh` in all its configurations, the Debye check, the
  validation suite with two engines, the cylinder multigrid check, `diamond-check`, and the six models on the Metal
  engine against the multithreaded engine with `OPENEMS_FTZ=1`, as run for cg29 on 2026-11-05 (section 3 of
  `results/cpu_items_cg29_2026-11-05.txt`).
- **`snapshot`** (a new snapshot folder from a build), the cylinder multigrid check (run_cyl.py and h5cmp.py), and
  `bench --json` in bench.py.

## 15. Licence

Decided by the author on 2026-11-06: the Swift package of the command line (`Package.swift`, `Sources/`, `Tests/`) is
under GPL-3.0-or-later. Each of its 45 Swift files carries `// SPDX-License-Identifier: GPL-3.0-or-later`
(`Package.swift` on line 2, after the tools-version line; every other file on line 1), the launcher
`Sources/fdtdKit/Python/fdtdkit_run.py` and its embedded copy in `LauncherSource.swift` carry
`# SPDX-License-Identifier: GPL-3.0-or-later` as their first line, and `LICENSE` holds the licence text. fdtdKit's
Swift code links no openEMS code: it runs the tools of this repository, which are under GPL-3.0-or-later, as separate
processes. On 2026-11-08 the author decided that the package stays under GPL-3.0-or-later and that femKit, momKit and
sbrKit each choose their licence when they are merged and published. Code under Apache-2.0 can still join a
GPL-3.0-or-later program, but not the reverse.

## 16. Log

Dated entries: what was built and verified, with the load (others' CPU and GPU during the runs) and the run times.
Each entry names the commit on `fdtdkit`. The repository is published as one commit, without the history in which it
was made, so these hashes name commits of that history (section 13).

- **2026-11-05: plan and documents, no build.** This plan was written from the specification (revision 2), and on
  this branch the documents and the paper took the name fdtdKit (`CHANGELOG.md`, 2026-11-05). The code of both phases
  is written from the same specification in the same workflow; the commit that holds it goes into the next entry.
  Nothing was compiled, run or tested: a GPU-against-CPU benchmark ran on the Mac at the time. No acceptance run yet,
  so no load to report.
- **2026-11-06: the acceptance runs of v1a and v1b (spec 16.3).** The release build (`swift build -c release`)
  of the working tree on top of `f09c379`, committed together with the fixes of the entries below. The binary
  `.build/release/emskit` (0.1.0) found the repository by itself. DIR is the rfsim toolkit folder (the one that holds
  rfsim/; its HEAD 26c5f64, rfsim/ at 4a7e20e, clean). Times are local (UTC-6). CPU percentages count one core as
  100 %. No CLI change was needed for any of the three runs.
  - v1a, 02:33-02:36: `emskit fdtd check cg29 --tag cliaccept --lite --rfsim DIR`. Exit 0, status ok, no warnings
    or errors. Final line `check.sh cliaccept: ALL IDENTICAL (6 models)`. The guard agrees: 18 of 18 counted rows
    exact (3 per model), every model block has its summary, and all 24 rows (the six stock reference rows included)
    show their engine's Create line. The reference snap/stock passes the stock scan and matches by sha256, so
    acceptance is true. The concurrency scans found no other process with an openEMS library. Run time 180.7 s
    (check.sh 179.9 s). Load per bench row (all 24 valid, none above the loaded thresholds): others' CPU 34-113 %,
    GPU 5 %. Afterwards the six untracked `results/*_cliaccept.txt` were deleted, and results/ shows in `git status`
    as it did before the run.
  - v1b, 02:37: `emskit fdtd diamond-check cg29`. Exit 0, status ok: `PASS: every comparison is identical`, 9 boxes,
    72 of 72 comparisons identical, the tuner finished in every box. Run time 27.0 s. Whole-run load: others' CPU
    237 %, GPU 3 % (warning `loaded_mac`; the busy list names two `pw.x` processes of another session, at 87 % each,
    which hold no openEMS library). The GPU device was 72 % busy, while the check's own Metal runs show only 1.3 %
    self GPU (at least 0.33 s): usage.Sampler samples every 0.5 s, so it misses most of the GPU time of the script's
    short child runs. Others' GPU is not affected by this.
  - v1b, 02:38: `emskit fdtd e2e gcpw --lib cg29 --rfsim DIR`. Exit 0, status ok: the RESULT line and result.json
    exist, and the one FDTD.Run call shows the default engine's Create line (`compressed SSE + multi-threading`, 10
    threads picked). The toolkit's probe end (-60 dB, hold 0.5) stopped it after 34300 TS, and the three libraries
    were loaded from snap/cg29. FDTD.Run 1569.1 MC/s (others' CPU 225 %, GPU 5 %). Run 5.5 s, build and post under
    0.1 s (others' CPU 226 %, GPU 5 % over the whole run). The CLI's wall time was 6.8 s. Warning `loaded_mac` (the
    same two `pw.x` processes).
- **2026-11-06: fixes for the six confirmed review findings.** On top of `f09c379` and in the same commit as the entry
  above. The
  fixes of findings 0-4 each have a unit test that fails without the fix: the fixes were undone in the tree for one
  run of those tests, and the files restored byte for byte afterwards.
  - Finding 0: `--tag` refuses a leading `-` at parse time (`tag_invalid`, exit 2, nothing probed or spawned) for
    bench, check and validate. check's FAIL line is `check_failed` only when every model it names printed a MISMATCH
    block and every model ran, otherwise `tool_output_unparsed` (exit 4). Both correct the specification: the tag
    grammar of its section 2.4 (`[A-Za-z0-9_.-]+`) let argparse read the value as an option, and the F4 note of its
    section 6.3 expected a block without a summary, while argparse exits before bench prints the block header.
  - Finding 1: a copied backup of a table behind a symbolic link holds the bytes the link points at (section 10.2).
  - Finding 2: the signal source calls the handler once per merged signal (`data`), so two quick signals escalate
    (section 9).
  - Finding 3: `gpu_fallback` in bench, check (its extras), ab and validate as well (sections 4.2 and 4.4).
  - Finding 4: `Engine_Metal_Diamond: kernel compilation failed` and `... pipeline creation failed` are fallback lines
    too (section 4.4); the tool_log fixture has both.
  - Finding 5: VerdictTests for check's verdict (the FAIL rule, the guard, a tolerant extra, PARTIAL) and two
    FakeToolRun-driven `check cg29 --lite` runs (exit 1 for a MISMATCH block, exit 4 for FAIL without blocks).
  - `swift build` and `swift build -c release` complete. Unit suite (`swift test --filter fdtdKitTests`): 127
    tests in 20 suites passed (117 in 19 before). Smoke runs (`EMSKIT_FDTD_SMOKE=1`, `--filter
    fdtdKitTests.SmokeTests --no-parallel`), 03:27-03:29: 14 of 14 passed in 65.2 s, others' CPU 394-460 %, GPU 3-5 %
    (four `pw.x` processes of another session at about 100 % each, no openEMS library).
  - Acceptance reruns with the rebuilt release binary (findings 0, 1 and 3 are on check's path, 2 on every run
    command, 4 on e2e's call segments):
    - 03:32-03:37: `check cg29 --tag cliaccept --lite --rfsim DIR`. Exit 0, status ok, `ALL IDENTICAL (6 models)`,
      18 of 18 counted rows exact, 24 of 24 engines confirmed, acceptance true, no other openEMS process. Run time
      299.8 s (check.sh 298.2 s). Load per bench row (all 24 valid): others' CPU 373-487 %, GPU 5 %, so every row
      is named in `loaded_mac`. The six `results/*_cliaccept.txt` were deleted again, and results/ shows in
      `git status` as it did before the run.
    - 03:38: `diamond-check cg29`. Exit 0, status ok, PASS: 72 of 72 comparisons identical in 9 boxes, the tuner
      finished. Run time 36.3 s; others' CPU 431 %, GPU 3 % (GPU device 67 %), warning `loaded_mac`.
    - 03:39: `e2e gcpw --lib cg29 --rfsim DIR`. Exit 0, status ok: one FDTD.Run call with the default engine's
      Create line (9 threads picked), probe end after 34300 TS, libraries from snap/cg29. FDTD.Run 990.5 MC/s
      (others' CPU 397 %, GPU 5 %); run 8.7 s, build and post under 0.1 s (others' CPU 388 %, GPU 5 % over the
      whole run); the CLI's wall time 10.5 s; warning `loaded_mac`.
- **2026-11-06: protected folders at plan time (S3).** On top of `f09c379` and in the same commit as the entries
  above. S3 said that
  no command writes under the installed prefix or the snapshot folder, but only the default locations were tested.
  Every location a command would write, create or rename is now checked before anything is created, renamed or
  spawned, in a dry run too (section 10.2): the issue code `protected_path` (exit 2, section 7.3),
  `FdtdProtectedPaths` in RunFolder.swift, and `fileIdentity` and `symbolicLinkTarget` in FdtdSystem (LiveSystem:
  stat(2) and readlink(2); FakeSystem: its tables, with a path walk that follows links and `..` like the kernel's).
  The signal handlers are now installed before the common options are taken, since `--output` can already probe.
  - NoInstallTests gains six tests. On the fake Mac, 20 command lines are refused with exit 2, only
    `protected_path`, nothing spawned, no run folder and ~/opt unchanged: `--output` in the lib folder, on the
    installed library with `--overwrite` (its planned backup is named too) and on ~/opt with `--overwrite` (info,
    and diamond-check in a dry run), through a link in /tmp and through `..`; ab `--record` in the prefix; e2e
    `--out-dir` = snap/cg29 without and with `--overwrite`, dry and real; bench and validate `--results` = SNAPS and
    snap/cg29; a `--tag` table that is a dangling link into the prefix; `--runs` in SNAPS, = SNAPS (a real
    debye-check), through `..`, `.` and a trailing slash, and through a link; load with `$OPENEMS_BENCH_RUNS` in
    SNAPS; run with `OPENEMS_EXPORT_FIELDS` = snap/cg29. A LiveSystem test in a temporary folder with stand-in
    roots (never ~/opt) covers letter case, a link, a dangling link, `..` after a link, is, inside and holds, and
    three neighbours. One test covers the prefix rule (lib/, ~/lib), one the cases that pass: the siblings
    `openEMS-other/` and `openEMS.json`, `snap-old`, `--results` and `--runs` in ordinary folders or in the folder
    above SNAPS, and every PlanTests command line with its default locations.
  - Without the guard (`FdtdProtectedPaths.relation` made to return nil for one run, RunFolder.swift restored byte
    for byte afterwards and checked with shasum), 5 of the 6 new tests failed with 142 issues: all 20 command lines
    ended with another exit than 2, 8 of them changed ~/opt on the fake Mac (the `--output` lines wrote or renamed
    in the lib folder or renamed ~/opt, in a dry run too; e2e renamed snap/cg29; debye-check and load made their
    folders in SNAPS) and 3 spawned their tool; the LiveSystem test missed all 8 refusals. The test of the passing
    cases and the 127 earlier tests passed with and without the guard. The nine golden plans are unchanged (their
    files date from 01:51 and pass as they are): no default location is refused.
  - `swift build` and `swift build -c release` complete. Unit suite: 133 tests in 20 suites passed (127 before).
    Smoke runs, 04:37-04:38: 14 of 14 passed in 58.4 s, others' CPU 224-464 %, GPU 4-5 % (`pw.x`
    processes of another session, no openEMS library).
  - Acceptance reruns with the rebuilt release binary:
    - 04:39-04:43: `check cg29 --tag cliaccept --lite --rfsim DIR`. Exit 0, status ok, `ALL IDENTICAL (6 models)`,
      18 of 18 counted rows exact, 24 of 24 engines confirmed, acceptance true (snap/stock by sha256), no other
      openEMS process. Run time 238.6 s (check.sh 237.7 s). Load per bench row (all 24 valid): others' CPU
      180-446 %, GPU 5 %, so every row is named in `loaded_mac`. The six `results/*_cliaccept.txt` were copied
      aside and deleted, and results/ shows in `git status` as it did before the run.
    - 04:43-04:44: `diamond-check cg29`. Exit 0, status ok, PASS: 72 of 72 comparisons identical in 9 boxes, the
      tuner finished in every box. Run time 24.2 s; others' CPU 64 %, GPU 3 % (GPU device 69 %), no warnings.
    - 04:44: `e2e gcpw --lib cg29 --rfsim DIR`. Exit 0, status ok: one FDTD.Run call with the default engine's
      Create line (10 threads picked), probe end after 34300 TS, libraries from snap/cg29. FDTD.Run 2000.1 MC/s
      (others' CPU 32 %, GPU 5 %); run 4.3 s, build and post under 0.1 s (others' CPU 33 %, GPU 5 % over the
      whole run); the CLI's wall time 5.4 s; no warnings.
  - The refusal on the release binary, 04:44-04:45, dry runs only, each exit 2 with `protected_path` and its
    envelope on stdout: `validate --lib cg29 --output ~/opt/openEMS/lib/nofolder/x.json` (the installed prefix
    ~/opt/openEMS, as the probe found it); the same folder through a link in a scratch folder and spelled
    `~/OPT/openems/LIB` (both messages show the resolved path); `bench patch --tag guarddemo --results snap/cg29`;
    `e2e gcpw --out-dir snap/cg29 --overwrite` (the folder and its planned backup); `diamond-check cg29 --runs
    ../../opt/openEMS-dev/snap/runs` from the worktree. `diamond-check cg29 --dry-run` with its default locations
    still plans (exit 0). The listings of ~/opt/openEMS, its lib/, SNAPS and snap/cg29 were the same before and
    after.
- **2026-11-06: fixes for the review findings of the protected-folder check.** On top of `f09c379` and in the same
  commit as the entries above. Two reviews of the entry above gave eight findings (0-7); each was checked against the code and all
  eight hold, finding 5 as a documentation inaccuracy only. Section 10.2 states the rules as they are now.
  - Finding 0 (high): the installed prefix was protected only when the probe ran and loaded openEMS. With `--repo`
    at a folder that is not a tools tree, a `--python` that cannot import openEMS, or `$HOME` set to another folder,
    `info --output ~/opt/openEMS/lib/libopenEMS.0.37.0.dylib --overwrite` exited 0 and finish() renamed the library
    away. BUILD.md's default prefix `~/opt/openEMS` is now protected as well, and `~` also means the account's home
    folder from the password database (`accountHome` in FdtdSystem, getpwuid_r(3)); the prefix rule keeps a lib
    folder alone when its parent holds either home folder. Not done: a second probe with another Python.
  - Finding 1 (medium): a `--tag` table rewritten with `--overwrite`, or ab's record extended with `--append`, could
    be a hard link of a file in a protected folder, which the tool would then change in place. Such a target is now
    refused when the file has more than one name and another one lies in a protected folder (`linkCount` in
    FdtdSystem, `FdtdProtectedPaths.otherName`; the search follows no link and skips other file systems). RESULTS
    and RUNS are only written into, never renamed or replaced, so "is or lies inside" stays the rule for them.
  - Finding 2 (low): check.sh's bench.py writes beside the real folder of check.sh, so with a linked `bench/` the
    tables went to another `results/` than the REPO/results the CLI looked at. `FdtdDiscovery.checkResultsFolder`
    gives the real one, and check uses it for the protected check, the existing-table refusal and the backups.
  - Finding 3 (low): "holds" compared only the folders above the protected folder's real path; it now also takes
    those above the path it is named by (`Located.named`), since renaming `~/opt` cuts `~/opt/openEMS` even when that
    is a link to another volume. finish() looks at `--output` once more after the tools ran (`recheckOutput`, before
    the status, so a refusal keeps the run folder). The tables, the record and `--out-dir` are written by the tools
    themselves, so for them the time between the plan-time check and the write remains.
  - Finding 4 (low): `discoverRfsim` marked the search done before it built the base environment, so without
    `--output` an inherited `$RFSIM_PATH` was listed as removed in every invocation and missing from the quiet
    wait's, while with `--output` (whose check builds the environment first) it was kept. The search now counts as
    done once the environment is built.
  - Finding 5 (low): for a last-name link of `--output` the check follows the link while finish() replaces it, so the
    check is stricter than the write. That is kept on purpose; the comment of `locate` and section 10.2 now say so,
    and that an `OPENEMS_EXPORT_*` value is taken as given (absolute, opened by openEMS) rather than folded like the
    CLI's own paths. No behaviour change.
  - Finding 6 (low): tests for check's own call site, for "holds" through e2e's `--out-dir` and ab's `--record`, and
    for a protected folder that cannot be found (below).
  - Finding 7 (low): the build and test durations above had no load; they are gone, and this entry gives none.
  - Tests: NoInstallTests gains eight. `theDefaultsStayProtectedWithoutTheProbe` (the three cases of finding 0, in
    the prefix and in SNAPS); `hardLinksIntoAProtectedFolderAreRefused` (bench dry and real, check, ab and validate,
    and a hard link outside the protected folders that passes); `checkTablesGoBesideTheRealBenchFolder` (a `bench/`
    linked into SNAPS is refused, an ordinary linked one gives `would_overwrite` for the table beside its real
    folder); `aFolderAboveTheNameOfAProtectedFolderHoldsIt`; `outputIsCheckedAgainBeforeItIsWritten` (the folder of
    `--output` becomes a link into the lib folder while the tool runs: exit 2, nothing written there, the envelope on
    stdout, the run folder kept); `checkOutputsInAProtectedFolderAreRefused` (`--runs` in SNAPS, dry and real, and a
    table that is a dangling link into the prefix); `anOutDirOrRecordThatHoldsAProtectedFolderIsRefused` (e2e dry and
    real, ab); `aMissingProtectedFolderStopsNothing` (load with a Python that cannot import openEMS, and with a
    `--snaps` that does not exist). PlanTests gains `thePlanDoesNotDependOnOutput`, and `thePrefixIsTheFolderAboveLib`
    takes a second home folder. FakeSystem gains hard links, link counts and the account's home folder, and its
    writes follow the folders on the way like the kernel's walk.
  - Mutation runs: 14, each undoing one fix or a part of it in Sources/ for one run of the unit suite; the changed
    files were restored byte for byte from copies after each run and checked with shasum, and at the end all 70 files
    of Sources/ and Tests/ matched the checksums taken before the first run. Each run failed in the test meant for
    it: the defaults removed, `theDefaultsStayProtectedWithoutTheProbe` (all four command lines changed ~/opt); the
    account's home folder left out, the same test (its two `$HOME` lines); the prefix rule with the first home only,
    `thePrefixIsTheFolderAboveLib`; the hard-link check off, or the five call sites back to "replaced as a whole",
    `hardLinksIntoAProtectedFolderAreRefused` (all five refusals); REPO/results again,
    `checkTablesGoBesideTheRealBenchFolder`; "holds" by the real path only,
    `aFolderAboveTheNameOfAProtectedFolderHoldsIt`; no second look, `outputIsCheckedAgainBeforeItIsWritten` (the
    envelope was written into the lib folder); the second look after the cleanup, the same test (its run folder
    cleaned); the old order in `discoverRfsim`, `thePlanDoesNotDependOnOutput`; check without its protected check,
    `checkOutputsInAProtectedFolderAreRefused` and the check lines of two other tests; e2e's `--out-dir` and ab's
    `--record` only written into, `anOutDirOrRecordThatHoldsAProtectedFolderIsRefused` (the real e2e renamed
    ~/opt/openEMS-dev) and the ab line of the hard-link test; the check needing the probe's library,
    `aMissingProtectedFolderStopsNothing` and the defaults test; a missing protected folder kept and judged by its
    nearest existing part, `aMissingProtectedFolderStopsNothing`.
  - `swift build` and `swift build -c release` complete. Unit suite: 142 tests in 20 suites passed (133 before); the
    nine golden plans pass as they are. Smoke runs, 05:42-05:43: 14 of 14 passed in 45.1 s, others' CPU 28-106 %,
    GPU 3-5 %.
  - Acceptance reruns with the rebuilt release binary:
    - 05:43-05:47: `check cg29 --tag cliaccept --lite --rfsim DIR`. Exit 0, status ok, `ALL IDENTICAL (6 models)`,
      18 of 18 counted rows exact, 24 of 24 engines confirmed, acceptance true (snap/stock by sha256), no other
      openEMS process. Run time 217.2 s (check.sh 216.4 s). Load per bench row (all 24 valid): others' CPU
      47-237 %, GPU 4-5 %; 16 rows are named in `loaded_mac`. The six `results/*_cliaccept.txt` were copied aside
      and deleted, and results/ shows in `git status` as it did before the run.
    - 05:48: `diamond-check cg29`. Exit 0, status ok, PASS: 72 of 72 comparisons identical in 9 boxes, the tuner
      finished in every box. Run time 25.2 s; others' CPU 128 %, GPU 3 % (GPU device 73 %), no warnings.
    - 05:48: `e2e gcpw --lib cg29 --rfsim DIR`. Exit 0, status ok: one FDTD.Run call with the default engine's
      Create line (10 threads picked), probe end after 34300 TS, libraries from snap/cg29. FDTD.Run 1725.7 MC/s
      (others' CPU 133 %, GPU 4 %); run 5.0 s, build and post under 0.1 s (others' CPU 134 %, GPU 5 % over the
      whole run); the CLI's wall time 6.4 s; no warnings.
  - The three cases of finding 0 on the release binary, 05:51-05:52, each with an `--output` whose folder does not
    exist (so that nothing could be written either way), each exit 2 with `protected_path`: `info --repo` at an
    empty scratch folder and `info --python /usr/bin/python3`, both with `--output ~/opt/openEMS/lib/nofolder/x.json`
    (the installed openEMS prefix ~/opt/openEMS); and with `HOME` at an empty scratch folder, `info --output` into a
    missing folder of SNAPS spelled in full (the snapshot folder of the account's home folder). The listings of
    ~/opt/openEMS/lib and SNAPS were the same before and after.
- **2026-11-06: v1a and v1b committed.** Both phases were committed together as `60fd4a3` on `fdtdkit` (after
  `5e111c5`), with the fixes of the three entries above. Unit suite
  (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter fdtdKitTests`): 142 tests in 20
  suites passed. The smoke figures are those of the last full smoke run of that tree (the command of section 12 with
  `EMSKIT_FDTD_RFSIM=DIR`), 05:42:50-05:43:36: 14 of 14 tests passed in 45.1 s, others' CPU 28-106 %, GPU 3-5 %; its
  log, `smoke_final.log`, stayed in the session's scratch folder. The 14 tests are runs 1-12 of section 12 and the
  two parts of run 13. Each speed carries the load the CLI printed for it (others' CPU, GPU).
  - v1a: (1) `--version`, `--help` and no arguments passed. (2) `info` passed. (3) `load --seconds 2`: others' CPU
    106 %, GPU 5 % (GPU device 5 %) over 2.1 s. (4) `bench patch`, stock against cg29 at 4 threads: stock 205.0 MC/s
    (43 %, 5 %), cg29 1851.2 MC/s (72 %, 4 %) and exact, IDENTICAL. (5) `ab patch --rounds 2` on the same pair: stock
    210.9 and 211.7 MC/s (75 %, 5 % and 34 %, 4 %), cg29 1918.5 and 1940.6 MC/s (43 %, 4 % and 35 %, 5 %); medians
    211.3 MC/s (54 %, 4 %) and 1929.5 MC/s, x9.132 [9.097-9.167] (39 %, 4 %). (6) `bench patch --exact` with
    `OPENEMS_FTZ=1`: multithreaded:4 1937.4 MC/s (63 %, 5 %), metal-diamond 1268.0 MC/s (28 %, 3 %) and exact,
    `NOTHING REQUIRED TO MATCH` (the GPU config is tolerant). (12) The refusals and plans passed. (13, bench part) A
    stop during `bench notch` returned 0.0 s after the trigger with exit 130, and no bench.py or runner.py was left.
  - v1b: (7) `validate --lib cg29 --quick --case slab --case lines`: 10 of 10 checks passed, slab 0.9 s, lines 2.7 s
    (34 %, 4 % over the whole run). (8) `debye-check cg29`: PASS, 2 of 2 comparisons identical (42 %, 4 %). (9)
    `e2e gcpw --lib cg29`: FDTD.Run 1917.0 MC/s (30 %, 4 %), probe end after 34300 TS; run 4.5 s (32 %, 4 % over the
    whole run), with build and post printed as `0.0 s` (C1 of the next entry). (10) `run box.py` on the CPU engine,
    4 threads, 600 TS: 2769.8 MC/s (40 %, 4 %; 102 %, 4 % over the whole run). (11) The same box on metal-diamond:
    1531.7 MC/s (30 %, 4 %; 38 %, 4 % over the whole run). (13, run part) A stop during `run box.py` aborted the run
    after 89268 TS at 2770.4 MC/s (43 %, 5 %) and returned 0.1 s after the trigger with exit 130 and the report.
  - The acceptance runs of v1a and v1b are in the 2026-11-06 entries above, the last ones at 05:43-05:48.
- **2026-11-06: the round after the commit (C1-C5, D1-D7) and its review.** On top of `60fd4a3`, in the commit that
  follows it. Each code fix has a unit test that fails without it (the mutation runs below).
  - C1: a duration below 0.1 s prints in milliseconds (`FdtdFigures.seconds`, section 7.2). e2e's summary had printed
    `build 0.0 s, run 4.5 s, post 0.0 s` (smoke run 9 of the entry above); the envelope keeps the exact numbers.
  - C2: a LIB that starts with `-` is refused at plan time in all of its places (section 5.1): `library_not_found`
    from `FdtdLibraries.locate`, `config_invalid` from the CFG parser, both exit 2 with nothing spawned, and a warning
    in info.
  - C3: `accountHome` starts getpwuid_r(3) with `sysconf(_SC_GETPW_R_SIZE_MAX)` bytes when that is positive (4096
    otherwise) and doubles the buffer on ERANGE up to 1 MiB. `FdtdPasswordDatabase.home` takes the lookup as a
    closure, so that a test can drive it.
  - C4: ab's dry run plans the sampler check after the run as well (section 4.2), so that its invocations are those
    of a run. This is the only change of a golden plan: `ab.json` gains a third invocation, the check after the run
    (role `sampler-check`, the same argv and environment as the first, not run). The other eight golden plans are
    byte for byte as before.
  - C5: `rfsim_not_found` says what was looked at and why it was not taken (section 5.3): `--rfsim` not given and
    `RFSIM_PATH` not set or empty, or the folder named with "is not a folder", "has no rfsim/ folder" or "has rfsim/
    but no rfsim/openems/core.py"; the hint stays. info's warning uses the same words.
  - D7: info built the snapshot records in a second pass over every snapshot folder after the index had read them
    all. It now builds them from the index entries (`FdtdLibraries.identify(_ entry:index:system:)`), so each of the
    84 snapshot files is read and hashed once: 87 chunked reads per info instead of 171 (the 3 installed files
    included). The records are the same: the release binary's 36 snapshot records (12 of them incomplete) and its
    installed record before the change (07:20) equal those after it (07:54).
  - D1-D6: sections 4.2, 5.1, 5.3, 7.2, 7.3, 9, 10.1, 16 and 18 of this plan; the header comment of InfoCommand.swift
    now says about 1 s.
  - Tests: 148 tests in 20 suites (142 before). New: `shortRunTimesPrintInMilliseconds` (EnvelopeTests, with a fake
    e2e run), `libraryStartingWithADashIsRefused` (GrammarTests: 11 dry-run command lines, info, and the path form
    that passes), `theAccountHomeLookupGrowsItsBuffer` (NoInstallTests: 4096, 8192 and 16384 bytes for a 9 KB entry,
    the limit, EIO, no entry, and the live lookup against Foundation's), `abDryRunPlansBothSamplerChecks`
    (PlanTests), `rfsimNotFoundSaysWhatWasLookedAt` (DiscoveryTests) and `infoReadsEverySnapshotFileOnce`
    (LibraryScanTests). `sameBytesSameBuildAndCandidates` also compares the record built from an index entry with the
    one built from its location. FakeSystem counts the chunked reads per path.
  - Mutation runs, 07:41:23-07:42:02 (others' CPU and GPU were not recorded for them): each undid one fix in Sources/
    for one run of the unit suite; after each run Sources/ was restored from a copy, and all 70 files of Sources/ and
    Tests/ matched their checksums. Each run failed only in the test meant for it: C1,
    `shortRunTimesPrintInMilliseconds` (2 issues); C2 with both guards undone, `libraryStartingWithADashIsRefused`
    (35), with only the one in `locate` (22), with only the CFG one (5); C3 with a fixed 4096-byte buffer,
    `theAccountHomeLookupGrowsItsBuffer` (4); C4, `abDryRunPlansBothSamplerChecks` (2) and ab's golden plan (1); C5
    with the old messages, `rfsimNotFoundSaysWhatWasLookedAt` (6); D7 with the second pass,
    `infoReadsEverySnapshotFileOnce` (14: every snapshot file read twice).
  - D3, checked at 07:41 with Python 3.14.6: `_thread.interrupt_main()` 1 s into `time.sleep(10)` raised
    KeyboardInterrupt after 10.0 s.
  - Builds and unit suite of the final tree: `swift build` and `swift build -c release`, 07:53:34-07:53:53, complete
    without warnings (others' CPU 223 % before, 448 % after, GPU 5 %); the release build compiles the whole module.
    Unit suite, 07:53:56-07:53:58: 148 tests in 20 suites passed (others' CPU 448 % before, 458 % after, GPU 5 %),
    and again at 07:59:02-07:59:04, after the last edit of this plan in that step (07:58:59), since TextRuleTests
    reads this plan (others' CPU 425 % before, 442 % after, GPU 5 %).
    The same builds and unit suite on the tree before the comment change, 07:46:27-07:47:15, gave the same results
    (others' CPU and GPU were not recorded for them).
  - Smoke runs, 07:47:22-07:48:24, on the tree before the comment change: 14 of 14 passed in 60.5 s, others' CPU
    93-464 %, GPU 3-6 % (four `pw.x` processes of another session at about 100 % each; `loaded_mac` on every run
    with a load). (3) Others' CPU 433 %, GPU 5 %. (4) Stock 145.7 MC/s (464 %, 5 %), cg29 866.6 MC/s (442 %, 5 %),
    IDENTICAL. (5) Stock 143.1 and 182.9 MC/s (436 % and 93 %), cg29 866.3 and 849.6 MC/s (424 % and 422 %), GPU
    5 %; medians 163.0 MC/s (264 %, 5 %) and 858.0 MC/s, x5.349 [4.645-6.054] (423 %, 5 %). (6) multithreaded:4
    869.1 MC/s (435 %, 4 %), metal-diamond 1113.1 MC/s (425 %, 3 %). (7) 10 of 10 checks, slab 1.5 s, lines 5.0 s
    (432 %, 5 %). (8) PASS, 2 of 2 (429 %, 4 %). (9) FDTD.Run 1120.2 MC/s (345 %, 5 %), probe end after 34300 TS,
    and the summary `build 5.0 ms, run 7.7 s, post 23.1 ms` (362 %, 5 % over the whole run): C1 on a real run. (10)
    1427.5 MC/s (418 %, 6 %). (11) 1261.8 MC/s (425 %, 3 %). (13) The run aborted after 38786 TS at 1424.8 MC/s
    (426 %, 5 %) and returned 0.1 s after the trigger; bench returned 0.0 s after it.
  - info (D7): three runs of the final `.build/release/emskit fdtd info`, 07:54:17-07:54:34, each between two
    `load --seconds 2` windows: 0.695 s (probe 0.676 s; others' CPU 246 % before, 436 % after), 0.528 s (0.513 s;
    413 %, 416 %) and 0.758 s (0.736 s; 453 %, 447 %), GPU 5 % in all six windows. Their results are equal apart from
    the timing (36 snapshot records; warning `rfsim_not_found`, since neither `--rfsim` nor `RFSIM_PATH` was given),
    and they hold the knob counts and the sameBuild and sameBytes lists of section 5.1 (D2).
    The binary before the comment change gave 0.716, 0.626 and 0.728 s at 07:48:59-07:49:16 (others' CPU
    343-458 %, GPU 5 %). Where the time goes, from an in-process timing harness built from the same code, two runs at
    07:52 (info 0.95 and 0.79 s; others' CPU 362-487 %, GPU 5 %): the snapshot index 0.30 s, of which 0.19 s are the
    engine scans of the 36 libopenEMS files (52.0 MB, one memmem pass per engine help string, 8 per file) and
    0.05-0.08 s reading and hashing the 87 files; the Python probe 0.24-0.26 s; the two lsof scans 0.14-0.31 s; git
    0.05-0.06 s. The second pass removed by D7 cost 0.31 s there (0.29 s in two runs at 07:50, others' CPU
    410-441 %, GPU 5 %). The engine scans are left as they are, and only recorded here.
  - The review of the steps above: two read-only reviews gave 13 findings (0-12). Each was checked against the code,
    a run or the records of the runs, and all 13 hold. Finding 12 is outside this plan: README.md still gives 142
    unit tests; README.md and CHANGELOG.md are updated with the commit.
  - Finding 0 (medium): a LIB that starts with `-` was refused with the hint `./-NAME` for every form, which for a
    snapshot name is a folder below the cwd instead of the one in SNAPS, and every command blamed bench.py's argparse,
    also those that hand the tools an absolute folder. `FdtdLibraries.locate` now names the same folder by its path
    (SNAPS/-NAME for a name, ./-NAME/... for a relative path) and states the one rule ("..., so no LIB may start with
    '-'"; section 5.1). `libraryStartingWithADashIsRefused` checks the message and the hint of its 8
    `library_not_found` refusals and of info's warning, and that both hinted paths plan (`validate --dry-run`, exit 0).
  - Finding 1 (low): a refused ab recorded abtest only, without the two sampler checks it would have run. ab now hands
    both checks to `refusals` (`FdtdJob.samplerCheck`), and `recordPlanned` records a sampler check as an invocation
    without a job, as `spawnJob` does (section 4.2). New test `aRefusedAbPlansBothSamplerChecks` (PlanTests): with an
    existing `--record` and no `--append`, in a dry run and a real one, exit 5 with the jobs and invocations of the dry
    run without that file, and neither a tool nor a sampler check started. The nine golden plans are unchanged.
  - Findings 2-11 (low, this plan): section 5.1 (diamond-check has no `--ref`; before the rule, bench and ab ended in
    `tool_failed` and check in `tool_output_unparsed`), 7.3 (which info warnings come from `--lib` and which from
    `--build`), 10.1 (with other Python processes only, scan A exits 1, so it is no example of exit 0), 9 (validate
    has no calls to rebuild), 5.1 and F20 (the lists of 2026-11-06 are longer than F20's), the introduction and
    section 2 (they still said that nothing was compiled or run, and that the acceptance run times were not
    established), and this entry: the commit wording, the unit run after the last plan edit of the step above
    (07:59:02, not 07:58:41), no load average where others' CPU and GPU were not recorded, and the suite name
    LibraryScanTests (its file is LibraryTests.swift). Checked by runs: scan A at 08:35 listed 27 Python processes
    without a libopenEMS name and exited 1 (0 without `-c openEMS`); the release binary's `info` at 08:47:53 printed
    the lists and knob counts of section 5.1, in 1.0 s (probe 0.92 s; others' CPU 931 % before, 914 % after, GPU
    5-6 %).
  - Tests: 149 tests in 20 suites (148 before).
  - Mutation runs, 08:40:10-08:41:14 (others' CPU 813-955 %, GPU 6 %, before and after each run): each undid one fix
    in Sources/ for one run of the unit suite; after each run Sources/ was restored from a copy, and all 71 files of
    Sources/, Tests/ and this plan matched their checksums. Each run failed only in the test meant for it: finding 0
    undone, `libraryStartingWithADashIsRefused` (19 issues), its hint only (10), its message only (8); finding 1 undone
    in ab, `aRefusedAbPlansBothSamplerChecks` (4), in `recordPlanned` only (2).
  - Builds and unit suite of the final tree: `swift build` and `swift build -c release`, 08:45:17-08:45:52, complete
    without warnings (others' CPU 586-909 %, GPU 6 %, before and after each). Unit suite, 08:50:36-08:50:43, after the
    last edit of this plan except the figures of this sentence (TextRuleTests reads it): 149 tests in 20 suites passed
    (others' CPU 756 % before, 733 % after, GPU 63-66 %). Other sessions built and tested their kits at the same time.
  - Smoke runs, 08:46:13-08:47:26: 14 of 14 passed in 68.7 s, others' CPU 465-802 % during the runs (904 % before,
    838 % after), GPU 5-6 % (four `pw.x` processes and the builds and tests of other sessions; `loaded_mac` on every
    run with a load). (3) Others' CPU 579 %, GPU 6 %. (4) Stock 118.3 MC/s (639 %, 6 %), cg29 719.0 MC/s (582 %,
    6 %), IDENTICAL. (5) Stock 118.8 and 117.2 MC/s (586 % and 610 %), cg29 675.3 and 726.0 MC/s (581 % and 604 %),
    GPU 6 %; medians 118.0 MC/s (598 %, 6 %) and 700.6 MC/s, x5.939 [5.684-6.195] (592 %, 6 %). (6) multithreaded:4
    739.0 MC/s (582 %, 6 %), metal-diamond 1330.7 MC/s (802 %, 5 %), `NOTHING REQUIRED TO MATCH`. (7) 10 of 10
    checks, slab 2.0 s, lines 6.0 s (599 %, 6 %). (8) PASS, 2 of 2 (631 %, 6 %). (9) FDTD.Run 897.3 MC/s (465 %,
    6 %), probe end after 34300 TS; `build 7.3 ms, run 9.6 s, post 26.2 ms` (474 %, 6 % over the whole run). (10)
    1289.6 MC/s (598 %, 6 %). (11) 1022.7 MC/s (662 %, 5 %). (13) The run aborted after 34572 TS at 1303.2 MC/s
    (500 %, 6 %) and returned 0.2 s after the trigger; bench returned 0.0 s after it.
  - The final runs on the finished tree, from 08:56:53. Nothing in Sources/ or Tests/ changed in this step (their 70
    files matched the checksums taken at its start), and this plan gained only this bullet. Each build and test step
    ran between two `load --seconds 2` windows of the release binary. Four `pw.x` processes of another session ran
    at 65-100 % each throughout, and another session's `emskit` process used the GPU until about 09:09 and again
    from about 09:13.
    - Builds: `swift build`, 08:58:17-08:58:18, had nothing to rebuild (others' CPU 411 % before, 516 % after, GPU
      5 %). `swift build -c release`, 08:58:23-08:58:56, compiled fdtdKit as a whole module (569 % before, 895 %
      after, GPU 5 %) and kept the binary linked at 08:42:53, after the last change of Sources/ (08:41:11). Neither
      printed a warning, and the diagnostics files of the last compiles hold none: fdtdKit's release module (08:58),
      its 27 files in debug (08:45), emskit-cli and the tests.
    - Unit suite, 09:00:12-09:00:16: 149 tests in 20 suites passed, 135 run and the 14 smoke tests skipped (others'
      CPU 587 % before, 575 % after, GPU 71 % and 70 %).
    - Smoke runs, 09:00:36-09:01:48: 14 of 14 passed in 70.1 s, others' CPU 425-730 % during the runs (546 % before,
      596 % after), GPU 4-71 % (`loaded_mac` on every run with a load). (3) Others' CPU 425 %, GPU 44 % (GPU device
      54 %). (4) Stock 110.2 MC/s (527 %, 71 %), cg29 815.6 MC/s (492 %, 69 %), IDENTICAL. (5) Stock 110.5 and
      99.0 MC/s (539 % and 578 %), cg29 728.6 and 680.6 MC/s (585 % and 563 %), GPU 63-71 %; medians 104.8 MC/s
      (558 %, 67 %) and 704.6 MC/s, x6.734 [6.594-6.875] (574 %, 68 %). (6) multithreaded:4 799.7 MC/s (512 %,
      68 %), metal-diamond 1068.2 MC/s (588 %, 61 %), `NOTHING REQUIRED TO MATCH`. (7) 10 of 10 checks, slab 1.8 s,
      lines 6.2 s (543 %, 64 %). (8) PASS, 2 of 2 (730 %, 71 %). (9) FDTD.Run 803.5 MC/s (483 %, 61 %), probe end
      after 34300 TS; `build 6.2 ms, run 10.6 s, post 25.2 ms` (481 %, 61 % over the whole run). (10) 1285.7 MC/s
      (554 %, 5 %). (11) 1742.6 MC/s (676 %, 53 %). (13) The run aborted after 25886 TS at 1059.0 MC/s (502 %,
      43 %) and returned 0.1 s after the trigger; bench returned 0.0 s after it.
    - Acceptance runs with the release binary, one after another:
      - 09:02:28-09:08:58: `check cg29 --tag cliaccept --lite --rfsim DIR`. Exit 0, status ok, `ALL IDENTICAL (6
        models)`, 18 of 18 counted rows exact, 24 of 24 engines confirmed, acceptance true (snap/stock by sha256),
        no other openEMS process. Run time 390.6 s (check.sh 389.1 s). Load per bench row (all 24 valid): others'
        CPU 438-757 %, GPU 5-69 %, so every row is named in `loaded_mac` (557 % and 66 % in the window before, 601 %
        and 53 % after). The six `results/*_cliaccept.txt` were copied aside with their checksums (equal to those
        of the envelope) and deleted by name; `git status --short results/` then showed nothing.
      - 09:09:32-09:10:12: `diamond-check cg29`. Exit 0, status ok, PASS: 72 of 72 comparisons identical in 9
        boxes, the tuner finished in every box. Run time 40.2 s; others' CPU 546 %, GPU 2 % (GPU device 70 %, self
        GPU 0.5 %, at least 0.20 s: the undercount of section 18, item 16), warning `loaded_mac`.
      - 09:10:29-09:10:39: `e2e gcpw --lib cg29 --rfsim DIR`. Exit 0, status ok: one FDTD.Run call with the default
        engine's Create line (10 threads picked), probe end after 34300 TS, the three libraries loaded from
        snap/cg29. FDTD.Run 1026.0 MC/s (others' CPU 394 %, GPU 2 %); the summary prints `build 8.1 ms, run 8.4 s,
        post 29.3 ms` (398 %, 2 % over the whole run), while the envelope keeps t_build 0.00814 s and t_post
        0.029321 s (C1); the CLI's wall time 10.1 s; warning `loaded_mac`.
    - The listings of ~/opt/openEMS/lib and SNAPS (214 entries with size, time, inode and mode) were the same after
      these runs as at the start of the step, and nothing there was newer than its start.
    - Unit suite, 09:13:24-09:13:27, after the last edit of this plan except the figures of this sentence
      (TextRuleTests reads it): 149 tests in 20 suites passed, 135 run and the 14 smoke tests skipped (others' CPU
      588 % before, 610 % after, GPU 72 % and 70 %).
- **2026-11-06: cg29 installed, and the checks run from the install.** No file of this repository changed for the
  install, and the command line installed nothing (S3). At 10:00 snapshot cg29 (patches 0001-0027, fork commit
  1620939, version string v0.37.0-44-g074a687) was installed by hand over the author's openEMS prefix (~/opt/openEMS),
  which had held cg18 (patches 0001-0006) since 2026-11-04 02:20; the cg18 prefix was backed up beside it first. Two
  files changed: `lib/libopenEMS.0.37.0.dylib`, now snap/cg29's library with the prefix's install name and rpath,
  re-signed (the same build UUID 40BC8CFF-6082-3FAD-BE46-832EAF165E8C as snap/cg29, other bytes), and
  `include/openEMS/openems.h`. libCSXCAD and libnf2ff in the prefix already had cg29's bytes. `cmake --install` was
  not used: none of the author's build folders both matches cg29 and installs into the prefix (F20, section 14). The
  Python modules, the v0.37.0 binding in the user site-packages (F19), were not rebuilt: no file under `python/`
  changed between 087ce9e (cg18) and 1620939 (cg29), and `openems.h` only appends `EngineType_Metal_Diamond` to an
  enum. So `installed` now names cg29's build, with the Metal diamond engine (`--engine=metal-diamond`, opt-in) and
  the CPU items of 0017-0027. The tests knew only cg18's installed file (sha256 819179a2...), so they skipped the
  installed row of section 5.1 and smoke run 2's sameBuild check; the same day both got the list of the two installs
  (cg29's installed file has the sha256 0d81372e...) and check the one that is installed.
  - The checks from the install, 10:04-10:15, with the release build of 2618180 (`emskit fdtd` 0.1.0). Other programs
    kept 4.6 to 8.5 cores busy, so the speeds these runs printed are not representative; only the verdicts count.
    `debye-check installed --ref cg29`: PASS (basic against sse-compressed, sse-compressed against multithreaded, and
    the installed library against snap/cg29, all identical). `check installed --tag inst29 --lite`: ALL IDENTICAL, 18
    of 18 counted rows exact on the six models against stock v0.37.0. `e2e gcpw --lib installed`: ok, the probe end
    stopped the run at 34300 TS, as before. `diamond-check installed`: 72 of 72 comparisons identical in 9 boxes.
    `validate --lib installed`: 15 of 15 checks on the fastest engine and 15 of 15 on the multithreaded engine with 4
    threads. The check's six `results/*_inst29.txt` tables were copied out of the tree and are not in the repository.
  - The two tests, 11:34-11:36 (the Mac loaded, 8 to 9 cores busy in all): `LibraryTests.swift` and `SmokeTests.swift`
    list both installs. 149 tests in 20 suites passed (135 run, the 14 smoke tests skipped), then the 14 smoke runs
    passed in 95 s, smoke run 2 with its sameBuild check (no skip line). With cg29's installed row naming cg18
    instead, LibraryScanTests failed (`spec42RowsWhileTheHashesHold`, sameBuild); restored, it passed.
- **2026-11-06: the author's publishing decisions.** On top of `64d19f8` (the documentation update, to which `main`
  was fast-forwarded that day), in the commit that follows it. The author decided how the repository goes public; the
  documents follow those decisions (`CHANGELOG.md`, 2026-11-06), and for the package they set its licence (section
  15). The command line behaves as before: the launcher it writes into each run folder has one line more, so the
  sha256 that the envelope records for it changes.
  - `// SPDX-License-Identifier: GPL-3.0-or-later` in all 45 Swift files of the package: `Package.swift` on line 2,
    after the tools-version line; every other file on line 1, then a blank line. `# SPDX-License-Identifier:
    GPL-3.0-or-later` as line 1 of the launcher `Sources/fdtdKit/Python/fdtdkit_run.py` and of its embedded copy in
    `LauncherSource.swift`, so the two stay equal byte for byte.
  - Options.swift: the comment on `FdtdDistributeMode` names section 11 of this plan for the family's four
    `--distribute` values, instead of the assistants' working notes, which are not published.
  - This plan: sections 2 (the `.gitignore` and `main.swift` rows), 11 (the family rule), 13 (publishing), 14 and 18
    (the `accept` bundle, and item 17 of section 18 without its pointer to the publishing steps), 15 (the licence), 16
    (this entry and the note on commit hashes) and 17 (item 7 decided).
  - `swift build`, 17:39, complete without warnings (7.0 s). Unit suite (`swift test --filter fdtdKitTests`), 17:40,
    after the Swift and launcher edits and before the documents were edited: 149 tests in 20 suites passed in 2.0 s,
    135 run and the 14 smoke tests skipped, LauncherSourceTests among those run. Others' CPU and GPU were not
    recorded.
  - The final run, after the edits of the documents that the tests read, 18:52-18:54, with the other processes at 0.6
    to 1.4 cores and 5 to 6 % of the GPU between the steps: `swift build` from an empty build folder complete without
    warnings (5.7 s, Swift 6.4.2); the unit suite 149 tests in 20 suites passed (135 run, the 14 smoke tests skipped),
    among them TextRuleTests, GrammarTests and KnobTests, which read this plan, the README and `BUILD.md`, and again
    after this entry was written; the 14 smoke runs (`EMSKIT_FDTD_SMOKE=1`, `--no-parallel`) passed in 45 s, with the
    other processes at up to 1.3 cores and, during one stock run of 1.5 s, 56 % of the GPU (another program).
- **2026-11-07: the fork branches rewritten for publication and pushed.** On top of `1530ffc` (the publishing
  decisions), in the commit that follows it. No file of the package changed. At the author's request the two fork
  branches were rewritten as the publishing steps say, with one step more so that patch 0001 names both models:
  each of the 28 commits carries the public identity, a `Generated-by:` trailer and a `Signed-off-by:` line, with
  its tree and author date unchanged, and a second pass gave the message of 0006 the new hashes of the commits it
  corrects (`CHANGELOG.md`, 2026-11-07). The two branches were then pushed to the author's GitHub forks. The fork's
  head is 78fe656 (before, 1620939; the same tree, 90f8c01), which section 3 now names. The version strings that
  the libraries print, and with them those that section 5 lists and the tests compare, did not change: they name
  the commit at which a build folder was configured. The entries above keep the hashes they were written with.
  - 08:32-08:35, with the other processes at 8.3 to 8.5 cores and 6 to 46 % of the GPU between the steps: `swift build`
    complete without warnings (8.4 s from an empty build folder); the unit suite (`swift test --filter fdtdKitTests`)
    149 tests in 20 suites passed, and again after this entry was written and at 09:09 after the corrections of the
    check (the other processes then at 1.4 cores); the 14 smoke runs (`EMSKIT_FDTD_SMOKE=1`, `--no-parallel`) passed
    in 72 s.
- **2026-11-07: a fresh build of the published patches passed the full check.** In the commit after the one above.
  No file of the package changed. Section 13 now says that the full check is done, so the licence is the one
  condition left for this repository's push; the record is `results/fresh_build_pub29_2026-11-07.txt`.
  - 09:29, with the other processes at 0.4 to 0.5 cores and 0 to 1 % of the GPU: `swift build` from an empty build
    folder complete without warnings (5.4 s); the unit suite (`swift test --filter fdtdKitTests`) 149 tests in 20
    suites passed, and again after this entry was written; after the corrections from the check, at 10:01 with the
    other processes at 0.6 to 0.7 cores, the unit suite again (149 tests in 20 suites passed), and once more after
    this line was written.
- **2026-11-08: the pre-push audit's fixes and the author's decisions.** In the commit after the one above. In the
  package only the test fixture `Tests/fdtdKitTests/Fixtures/fake_openEMS/openEMS/openEMS.pyx` changed: its first line
  became five (an SPDX line, where and when the stub was cut from upstream's v0.37.0 binding, upstream's copyright
  line and a licence notice), and the 30 copied lines below them did not change, so `opt = ""`, the text that
  LauncherTests and the launcher look for, is there once as before. `Package.swift`, `Sources/` and the other files of
  `Tests/` did not change. This plan: the map of the specification's sections after the opening, the item "Where" of
  section 1, the `.gitignore` row of section 2, section 3's note on line numbers and F23, the lead-in of the identity
  table of section 5.1, S10, and sections 13, 14 and 15 (on 2026-11-08 the author settled the licence question: the
  package stays under GPL-3.0-or-later; `CHANGELOG.md`, 2026-11-08). The README's command-line section has the
  `--allow-partial` example and notes on the rfsim toolkit, the smoke runs and the Command Line Tools.
  - 07:27-07:28, with the other processes at 9.4 to 9.8 cores (Swift test processes and four pw.x processes of other
    programs) and 4 to 5 % of the GPU between the steps: `swift build` from an empty build folder complete without
    warnings (15.0 s, Swift 6.4.2); the unit suite (`swift test --filter fdtdKitTests`) 149 tests in 20 suites passed
    (135 run, the 14 smoke tests skipped), among them TextRuleTests and GrammarTests, which read this plan and the
    README's command-line section, KnobTests, which reads `BUILD.md` section 7, and LauncherTests, which runs the
    launcher against the fixture; and again at 07:31, after this entry was written (the other processes then at 2.7
    to 3.8 cores and 5 % of the GPU), and once more after this line was written.
  - 08:24, after the corrections from the change's two read-only checks, with the other processes at 8.8 to 9.9 cores
    (other programs' Swift tests and solvers) and 5 % of the GPU: `swift build` from an empty build folder complete
    without warnings (12.2 s); the unit suite again (149 tests in 20 suites passed), and once more after this line was
    written.
- **2026-11-09: the code review's fixes.** In the commit after the one above. On 2026-11-08 the author ran Claude
  Code's cloud code review on 18 of the package's 31 source files as of 2618180; it found one bug and five minor
  issues, a separate session wrote their fixes, and the main session carried them over after three read-only checks,
  with the corrections those called for (`CHANGELOG.md`, 2026-11-09). In `Sources/`: `Discovery.swift` (the python
  probe looks up the binding's version and its pyx after the import, in try blocks of their own, so a binding without
  package metadata is no longer `python_no_openems`), `Commands/CommandSupport.swift` (the concurrency gate ends the
  command as `interrupted` after a stop unless a scan found a process, and the jobs recorded after a stop are marked
  interrupted; `plannedRunFolder` gives load its scratch folder; `resolveLibrary` takes a snapshot's record from the
  index entry of the same bytes; ab's sampler check comes from the backend), `Commands/CheckCommand.swift` (the
  stock that the reference is matched against comes from the index entry or else from the folder; check.sh's library
  argument by the backend's rule), `Commands/LoadCommand.swift` (the dry-run branch, which load's grammar never
  reached, is gone), `Commands/ValidateCommand.swift` (its planned folder from `plannedRunFolder`),
  `Commands/ABCommand.swift`, `Distribution.swift` (`FdtdLocalBackend.checkArgument`) and `Libraries.swift` (the stock
  scan from the index entry, with the registry names of both files). In `Tests/`: nine tests more (the rows of
  ConcurrencyTests, LibraryScanTests, StockTests, LauncherTests and NoInstallTests in section 12) and FakeSystem's
  hooks for them (a signal during scan B or after a given capture, children killed after a stop, names that a folder
  listing leaves out, counts of whole reads). This plan: the status line, the stop rule of section 10.1, and section
  12's rows and counts.
  - 08:36-08:48, the review session's change alone, with other programs loading the Mac: the unit suite 153 tests in
    20 suites passed, the 14 smoke runs passed (78 s), and the acceptance runs on cg29 passed (`check cg29 --lite`
    all identical on the six models, `diamond-check cg29` 72 of 72, `e2e gcpw --lib cg29` stopped at 34,300 steps).
  - 09:24-09:33, the final change, with the other processes at 3.0 to 5.4 cores (another session's Fortran program and
    Swift tests) and 0 to 8 % of the GPU: the unit suite (`swift test --filter fdtdKitTests`) 158 tests in 20 suites
    passed (144 run, the 14 smoke tests skipped); seven mutants of the main session's changes, each caught by a new
    test, and the copy without them passed; the 14 smoke runs (`EMSKIT_FDTD_SMOKE=1`, `--no-parallel`) passed in
    61 s; `check cg29 --tag rvfix2 --lite` ALL IDENTICAL (18 of 18 exact rows, the reference matched to stock by
    sha256), `diamond-check cg29` 72 of 72 and `e2e gcpw --lib cg29` stopped at 34,300 steps as before (`FDTD.Run`
    8.6 s). After three lines were wrapped and one comment reworded (09:35-09:37): `swift build` from an empty build
    folder complete without warnings (6.5 s), the 14 smoke runs again (59 s), and the unit suite again, also after this
    entry was written.
- **2026-11-10: the second review's fixes.** In the commit after the one above. On 2026-11-09 a read-only workflow
  of the main session (Claude Fable 5.2) reviewed all 31 source files as of f9b7cc3: four reviewers, a refuting
  verifier for each, and one critic. Of the reviewers' 23 findings the verifiers confirmed 21 (16 distinct), called 1
  plausible and refuted 1; the critic added 5 (`CHANGELOG.md`, 2026-11-10). Three fixers of a second workflow changed
  the code, each fix with a test that fails without it. In `Sources/`: `Verdicts.swift`, `Discovery.swift`
  (`FdtdDiscovery.lies`) and the commands of e2e, run and validate (the loaded libraries are compared with LIB's
  folder as given or by its real path, e2e checks them too, and the probe refuses before the run; sections 4.2 and
  5.1), `Commands/CheckCommand.swift` and `BenchConfig.swift` (an `--extra` is matched against its own library; a
  SNAP or `--stock` that a config cannot carry is refused under its own field), `FdtdKit.swift` and `Options.swift`
  (`--output` that is a folder or empty exits 64; finish() writes `--output` before the cleanup and leaves a file
  that appeared during the run; a usage error's envelope goes to `--output FILE` (withdrawn later that day, "The
  guard attack" below) and comes before a bad `--tag`; the
  signal handling stays until the envelope is out; sections 4.1, 9 and 10.2), `Context.swift` (a signal ignored at
  the start is no stop request), `Spawn.swift` (a capture ends what its child left in its group),
  `Commands/E2ECommand.swift` (the old `--out-dir` is renamed only just before the run; an `--out-dir` that holds
  the run folder exits 64), `Commands/CommandSupport.swift` (a protected folder reached by two paths is listed under
  both), `Commands/BenchCommand.swift` (a summary line needs a row per config, section 4.2),
  `Commands/InfoCommand.swift` (a `--rfsim` that names no toolkit is reported once and no longer hides the
  installed library) and `Discovery.swift`
  (`tools_modified` in a tools tree below the top level of its repository, section 5.3). Left as it is: an
  installed library whose three files lie in separate real folders is still `library_incomplete` (its message now
  says why). The refuted finding (two `--knob` values for one name in validate, e2e and run) got a warning with the
  open items, below. In `Tests/`: the
  suites LoadedLibraryTests, OutputTests, FailingVerdictTests and GuardTests (58 tests; section 12), and FakeSystem's
  probe now reports real paths, as dyld does. This plan: sections 4.1, 4.2, 5.1, 5.3, 9 and 10.2, and section 12's
  rows and counts.
  - The fixes were then reviewed by three more read-only agents (regressions, tests by mutation, live runs of the
    built binary): 18 findings, all but two acted on by a final fixer (`CHANGELOG.md`, 2026-11-10, "The review of
    the fixes"). What changed against the list above: a file that appeared at `--output` is `tool_failed` (4), not a
    refusal; `--output` is written once, before the cleanup; only an inherited ignored SIGHUP stays ignored, INT and
    TERM are always stop requests; a second signal while the envelope is finished ends the CLI; a usage error with
    `--output` installs the signal handling before its probes (withdrawn with the guard attack, below: it probes
    nothing now); e2e checks `--out-dir` again and resolves its job
    before the rename; a library folder of links to files elsewhere is accepted by validate, e2e and run;
    `tools_modified` works under a folder name outside ASCII (sections 4.1, 4.2, 5.3, 7.3, 9 and 10.2). Left as they
    are: a probe's child that closed its pipes and stays in the group is not ended (it reads as a daemon left on
    purpose, and section 9 already says pipes); check's removal of doubles from its used list has no test, since
    nothing can see it; the three files of the installed library in
    separate real folders.
  - Unit suite (`swift test --filter fdtdKitTests`) on the tree of these fixes: 216 tests in 24 suites passed (202
    run, the 14 smoke tests skipped); `swift build` complete without warnings. The fixers took each fix and each newly
    tested rule out once in mutation runs (21 mutants for the rules that had no test and the fixes of bench, info and
    `tools_modified`, 13 for the library fixes, the output fixer's own, and 30 for the final fixer's changes
    and the rules the second set of reviewers found untested), and each time a test failed, except for one mutant
    that nothing can see (check's used list with a library twice; the scan and the backend drop doubles themselves).
  - Smoke and acceptance on that tree, by the main session, 2026-11-10 01:46-02:00 CST, with about eight cores
    busy in other programs (among them another session's openEMS simulation on the installed library), so only the
    verdicts count: the 14 smoke runs passed (108 s); `check cg29 --tag fabfix --lite` gave `ALL IDENTICAL (6
    models)`, 18 of 18 exact rows, with the warnings `simulation_running` and `loaded_mac`; `diamond-check cg29` 72 of
    72 identical; `e2e gcpw --lib cg29` was refused with `simulation_running` (exit 5) because of that other run, and
    with `--allow-concurrent` ended ok at 34,300 timesteps (FDTD.Run 14.6 s under that load).
  - The same smoke and acceptance runs again, by the main session, after the third round (03:07-03:21 CST), after
    the fourth (04:45-04:57) and on the final tree (05:40-05:53; unit suite 255 tests in 28 suites), with six to
    nine cores busy in other programs: each time the 14 smoke runs passed, `check cg29 --lite` gave `ALL IDENTICAL
    (6 models)` with 18 of 18 exact rows, `diamond-check cg29` passed every comparison and `e2e gcpw --lib cg29
    --allow-concurrent` ended ok at 34,300 timesteps.
  - The open items, closed later the same day by one more fixer: what the entries of 2026-11-09 and 2026-11-10 had
    left as it was (`CHANGELOG.md`, 2026-11-10, "The open items"). The rfsim probe reads each value with a default
    (section 5.3, item 4); a list of protected folders made while a stop cut the installed library's probe short is
    not kept, and nothing is written on it (section 10.2); one rule, `FdtdSnapshotIndex.entry(at:)` with
    `FdtdLibraries.record`, takes a record from the snapshot index, for info's `--lib` too (section 5.1); info
    handles signals and ends as `interrupted` after a stop (sections 4.2 and 9); the binding's version needs
    metadata of the imported copy, and the probe's legacyEmptyOption follows the launcher's rule (sections 4.3 and
    5.3, item 2); two `--knob` values for one name in validate, e2e and run give the warning `knob_ignored` (section
    6.2). Still as they are: the installed library in separate real folders, a probe's child that closed its pipes,
    and check's removal of doubles. Ten tests more (the suite OpenItemTests and three in LauncherTests; section 12),
    each fix taken out once in a copy (17 mutants, each caught). Unit suite on the final tree: 226 tests in 25
    suites passed (212 run, the 14 smoke tests skipped); `swift build` complete without warnings. The smoke and
    acceptance runs were not repeated on it: this fixer had no leave to start simulations.
  - The third review, of the whole change of that day (three read-only reviewers and a refuting verifier;
    `CHANGELOG.md`, 2026-11-10, "The third review"): ten findings reached one more fixer, nine distinct, all
    fixed. A `--rfsim` that names no toolkit no longer stops the probe for the installed prefix (section 10.2);
    bench's `--knob` rules and validate's NAME=VALUE rule are found before a bad `--tag` (section 4.1); e2e
    refuses an `--out-dir` that is empty or holds a folder the run needs, and looks at it again after the quiet
    wait (section 4.2); validate reads `~` anywhere in a library's path; bench, ab and check refuse a library
    folder of links to files elsewhere (section 5.1); section 6.2 names the rule for a knob twice inside a CFG.
    Six tests more (section 12), 14 mutants, each caught. Unit suite on the final tree: 232 tests in 25 suites
    passed (218 run, the 14 smoke tests skipped); `swift build` complete without warnings. The smoke and
    acceptance runs were not repeated on it either.
  - The fourth review, of the guards and of the verdict paths (two read-only reviewers and a refuting verifier for
    each; `CHANGELOG.md`, 2026-11-10, "The fourth review"): six findings raised, six confirmed (one medium), all fixed
    by one more fixer. The protected folders got one rule for the discovery options, the union of discovery with the
    line's options and without them (section 10.2), which replaces the special case for a bad `--rfsim` and covers a
    bad `--repo` or `--python` and an option repeated on a usage error's line (section 4.1; such a line writes no file
    since the guard attack, below); every option that takes a path refuses an empty value, and ab's `--record` goes
    through the checks of `--output` (sections 4.1 and 4.2); e2e's `--out-dir` and the protected folders share one
    "holds" test, which knows the path a folder is named by (section 4.2); a check block's summary needs a row per
    config (section 4.2); the engine's knob warnings look at the value that reaches the child (section 6.2). Thirteen
    tests more in two new suites and two old ones (section 12), and one test of OpenItemTests extended; each fix and
    each rule of the new tests taken out once in a copy (16 mutants, each caught). Unit suite on the final tree: 245
    tests in 27 suites passed (231 run, the 14 smoke tests skipped); `swift build` complete without warnings. The
    smoke and acceptance runs were not repeated on it either: this fixer had no leave to start simulations.
  - The re-check of the fourth review's fixes (two read-only reviewers on the fixed tree, then a last fixer;
    `CHANGELOG.md`, 2026-11-10, "The fourth review"): four findings, each reproduced by the fixer and each fixed. In
    (a) of the one rule the line's options count one by one, so a correct `--python` or `--repo` keeps its prefix
    protected beside another option that names nothing (medium; section 10.2); on a line that did not parse, a
    discovery option in a spelling that is not read (`--snaps=DIR`, `--snap DIR`, `-snaps DIR`) was counted as unclear
    like one given twice (low; withdrawn with the guard attack, below); the second probe is skipped by what can change
    its answer, so `--rfsim DIR` and a `--repo` through a link pay none (low; section 10.2); one line of section 10.2
    over 120 characters was wrapped again. Two tests more in DiscoveryOptionTests and three of its tests extended
    (section 12); each new or changed test fails on the tree before these fixes. Unit suite on the final tree: 247
    tests in 27 suites passed (233 run, the 14 smoke tests skipped); `swift build` complete without warnings. No
    simulation, smoke or acceptance run was started for it.
  - The guard attack (two read-only agents on the tree of the re-check, with the built program on scratch folders, a
    scratch home and fake Pythons; `CHANGELOG.md`, 2026-11-10, "The guard attack"): about 3,650 attack lines, and on
    the lines that parse 0 changes under a protected folder. Three distinct low findings: on a line that did not
    parse, a discovery option spelt beyond the hint's reach (`--SNAPS`, `--snapshots`, `--snaps-dir`, `--py`,
    `--python-path`, or given after `--`) was not counted as unclear, so `--output` was still written into the folder
    it names; check read `-snaps DIR` as two more SNAPs, so that line parsed and wrote there too; and no test held the
    rule "the Python as named". It was the third round in a row to find a spelling that the reading of unparsed lines
    missed, so the reading itself was withdrawn. Rule 1: a line that did not parse writes no file, renames nothing,
    probes nothing and installs no signal handling; its envelope goes to stdout and one stderr line says that
    `--output` is not written (section 4.1). `commonAfterError`, the list of unclear options and their stderr line are
    gone from `Options.swift` and `FdtdKit.swift` (49 lines less in `Sources/`: 86 removed, 37 added). Rule 2: a
    positional that starts with `-` is a usage error on every command (section 4.1), so `check cgD --tag t -snaps DIR`
    no longer parses; before, check, debye-check and diamond-check answered such a LIB with `library_not_found` (2).
    The union rule of section 10.2 for lines that parse is unchanged. Tests: the new suite UnparsedLineTests (five
    tests), two in GrammarTests and two in DiscoveryOptionTests (one for the Python that is a link to PATH's python),
    one in OutputTests; six tests that pinned the withdrawn reading were removed (section 12). Unit suite on the final
    tree: 251 tests in 28 suites passed (237 run, the 14 smoke tests skipped); `swift build` complete without
    warnings. No simulation, smoke or acceptance run was started for it.
  - The check of the guard attack's fixes (one read-only agent with the built program, then a last fixer): four low
    findings, none in the code's rules. On check, a line with two slips still parses (`--stock -snaps DIR`, or
    `snaps DIR` without a dash) and its `--output` is written inside DIR; that is the rule of section 10.2 as
    written, and section 4.1 now names it as a known limit. The README's sentence on usage errors was wider than
    section 4.1 and was narrowed to lines the parser refuses; the log line of the re-check above and one test
    comment were stale. No code changed, so the counts stand: 251 tests in 28 suites.
  - The residual of that check, closed by one rule (one more fixer): every LIB that the line names by its path
    and that is a folder is a protected folder for that command, complete library or not (section 10.2, "The
    library folders of the line"). `FdtdCommandOptions.librarySpecs` (`Options.swift`) lists the line's LIBs as
    given, `begin()` takes them before it checks `--output`, and `protectedFolders()` adds the folders among
    them; no probe more. So `check cgD --tag t --stock -snaps DIR --output DIR/...` and `check cgD snaps DIR
    --output DIR/...` are refused (`protected_path`, exit 2) with and without `--overwrite`, and section 4.1 no
    longer lists a known limit. One behaviour changed: e2e's `--out-dir` that is or holds a `--lib` folder given
    by its path is now `protected_path` (2), where it was a usage error (64). Four tests more in
    DiscoveryOptionTests, each failing with the rule taken out, and one of OutputTests edited (section 12). Unit
    suite on the final tree: 255 tests in 28 suites passed (241 run, the 14 smoke tests skipped); `swift build`
    complete without warnings. No simulation, smoke or acceptance run was started for it.
  - The last review. Two read-only reviewers, each with a refuting verifier, went over the rule for the library
    folders and the whole committed change 6344992: 4 findings, 3 confirmed (all low), 1 refuted. (1) The two-slip
    line with DIR as a bare name (`--stock -snaps mysnaps --output mysnaps/e.json`) still wrote inside DIR: a LIB
    without `/` now also protects a folder of that name in the working directory (`protectedFolders()`,
    `FdtdLibraries.isSnapshotName`; sections 4.1 and 10.2; no probe more). One behaviour changed: an output inside
    a folder of the working directory named like a snapshot of the line is `protected_path` (2). (2) `info -h` and
    `bench -help` hinted a path `./-h`; the hint is `--help` now (`Options.swift`). (3) Helpers without a caller in
    Sources: `protectedRoots()` and `FdtdSnapshotIndex.entry(_ name:)` are removed (the tests use
    `protectedFolders().roots` and the entries), `discoveryGiven` stays with a note that only the tests read its
    names. Refuted: a path with `#` in a CFG is no LIB by the grammar of section 5.2; section 10.2 says so now and
    a test pins the last `@`. Three tests more (two in DiscoveryOptionTests, one in GrammarTests), each failing
    with its fix taken out. Unit suite on the final tree: 258 tests in 28 suites passed (244 run, the 14 smoke
    tests skipped); `swift build` complete without warnings. No simulation, smoke or acceptance run was started
    for it, and the PDF was not built again for the changed count.

## 17. Open questions (the author decides)

1. **Check against a reference that is not stock.** The design runs it and reports status partial (exit 0,
   `acceptance: false`, `reference_not_stock`), so fork-to-fork regression checks stay possible. Should it instead be
   refused unless an explicit flag is given?
2. **Backups in `results/`.** `--overwrite` on check puts the backups next to the tables, as untracked
   `NAME_T.txt.previous-STAMP` files that make `git status` dirty. Acceptable, or should results backups go to a
   folder of their own?
3. **`RFSIM_PATH`.** It is not exported in the author's shell (F26), and the CLI reads no config file, so every kgcpw,
   ksma, e2e and full-check run needs `--rfsim`. Export it in the shell profile instead?
4. **`Malloc*`.** The child environment removes inherited `Malloc*` variables because they change where large blocks
   land, which the allocation-placement valley depends on. Confirm, or keep them with a warning.
5. **`PYTHONUSERBASE`** is kept with a warning rather than removed (removing it could switch a binding the user chose
   on purpose; the probe records which one loads). Confirm.
6. **The acceptance tables.** Delete the six `results/*_cliaccept.txt` after the v1a acceptance (the default), or keep
   them as a record?
7. **The licence of the Swift code** and **how the repository goes public**: decided on 2026-11-06. The licence is
   GPL-3.0-or-later (section 15). The repository is published as one commit without its history, so `main` needs no
   rewrite and the kit branches are not part of it (section 13).

## 18. Deferred (not in v1)

1. `install` and `rollback` (design in section 14).
2. The `accept` bundle (the full check of section 14).
3. A `snapshot` command.
4. The cylinder multigrid check (run_cyl.py and h5cmp.py).
5. Sweeps (mesh floor, probe end), step1.sh, tables.py and parse_results.py, and the paper and PDF build.
6. XML runs through the openEMS binary.
7. Proof of the loaded libraries in grandchild processes of `run` scripts.
8. `bench --json` in bench.py.
9. Multi-Mac phases 1 and 2, and a family-wide `runs` value for `--distribute`.
10. Linux (`LD_LIBRARY_PATH`; libinfo already reads /proc/self/maps).
11. `--timeout`.
12. An automatic GPU or CPU choice per model.
13. A shared envelope module for the family (EMSCore).
14. `OPENEMS_BENCH_BC` (runner.py's boundary override).
15. `--knob` for check.
16. A snapshot API in `usage.Sampler`, so that the launcher runs one sampler, and a self figure on abtest's lines (so
    that the sampler checks around ab can go). Beside it: the sampler undercounts the CLI's own GPU use on short child
    runs, because it samples every 0.5 s (F12). `diamond-check cg29` at 02:37 on 2026-11-06 (section 16) showed 1.3 %
    self GPU (at least 0.33 s) while the GPU device was 72 % busy; the others' figures are not affected.
    `bench/usage.py` stays as it is in v1, since the CLI wraps the tools unchanged.
17. Done, no longer deferred: the documents and paper rename to fdtdKit (2026-11-05, this branch); the four figures
    and the PDF were redrawn in the same commit, 4829e22.
18. Done, no longer deferred: BUILD.md section 5 gives both the version strings that the cg19 and cg20 tables print
    and those of the libraries now in their snapshot folders (cg19 = v0.37.0-25-g315acee, cg20 = -26-gcd80d8c; F7).
19. A lock file against two CLIs starting in the same second.
