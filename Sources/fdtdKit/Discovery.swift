// SPDX-License-Identifier: GPL-3.0-or-later

// Where things are (spec 3) and the probes that say what they are (spec 5.2). For each item the option comes first,
// then the environment, then a walk or the default. Paths handed in are already absolute (FdtdSession.absolutePath);
// every child goes through context.system.capture, never through a shell with user data.
import Foundation

/// The embedded Python snippets of spec 5.2 (since 2026-11-09 the probe looks up the binding's version and its pyx in
/// try blocks of their own; since 2026-11-10 with the launcher's two rules for them). Each prints one tagged line that
/// the CLI finds among other output (FdtdParsers.taggedJSON).
enum FdtdSnippets {
    static let probeTag = "FDTDKIT_PROBE"
    static let rfsimTag = "FDTDKIT_RFSIM"
    static let quietTag = "FDTDKIT_QUIET"
    static let loadTag = "FDTDKIT_LOAD"

    /// `[PY, -B, -c, PROBE, LIBINFO]`: the interpreter, whether DYLD survived, the openEMS binding and its libraries.
    static let probe = #"""
        import sys, os, json, importlib, importlib.util, importlib.metadata
        s = importlib.util.spec_from_file_location('_fdtdkit_libinfo', sys.argv[1]); li = importlib.util.module_from_spec(s); s.loader.exec_module(li)
        out = dict(executable=sys.executable, realPath=os.path.realpath(sys.executable), version=sys.version.split()[0], dyld=os.environ.get('DYLD_LIBRARY_PATH'))
        try:
            import numpy; out['numpy'] = numpy.__version__
            import openEMS; out['openemsModule'] = openEMS.__file__; out['libraries'] = li.loaded_libs()
        except Exception as e:
            out['importError'] = f'{type(e).__name__}: {e}'
        else:
            # optional: a binding without package metadata (a build tree on PYTHONPATH) imports all the same. The
            # name alone can belong to another installed copy, so the version counts only when one of the
            # distribution's files lies in the imported package's folder (the launcher's binding_version)
            try:
                here = os.path.realpath(os.path.dirname(openEMS.__file__))
                dist = importlib.metadata.distribution('openEMS')
                if any(os.path.dirname(os.path.realpath(str(dist.locate_file(f)))) == here for f in dist.files or []):
                    out['openemsVersion'] = dist.version
            except Exception:
                pass
            # the launcher's rule (legacy_binding): true unless a pyx beside the binding can be read and lacks the
            # line; left out only when openEMS.openEMS does not import (the launcher then installs no shim)
            try:
                m = importlib.import_module('openEMS.openEMS')
            except Exception:
                m = None
            if m is not None:
                try:
                    pyx = os.path.join(os.path.dirname(getattr(m, '__file__', None) or ''), 'openEMS.pyx')
                    with open(pyx, encoding='utf-8', errors='replace') as fh:
                        out['legacyEmptyOption'] = 'opt = ""' in fh.read()
                except OSError:
                    out['legacyEmptyOption'] = True
        print('FDTDKIT_PROBE ' + json.dumps(out))
        """#

    /// `[PY, -B, -c, RFSIM, RFSIM_DIR]`: the toolkit's defaults, each null when the toolkit has none.
    static let rfsim = #"""
        import sys, os, json, math; sys.path.insert(0, sys.argv[1]); from rfsim.openems import core
        # each value is optional (an older toolkit lacks some): one that is missing or no finite number is null
        try:
            from rfsim.openems import launch
        except Exception:
            launch = None
        def num(v):
            return v if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) else None
        p0 = getattr(launch, 'P0', None)
        out = dict(core=core.__file__, probeEndDb=num(getattr(core, 'PROBE_END_DB', None)))
        out['probeEndHold'] = num(getattr(core, 'PROBE_END_HOLD', None))
        out['zMult'] = num(getattr(core, 'Z_MULT', None))
        out['minCell'] = num(getattr(launch, 'MIN_CELL', None))
        out['minCellEffective'] = num(p0.get('min_cell')) if isinstance(p0, dict) else None
        out['env'] = {k: v for k, v in os.environ.items() if k.startswith('RFSIM_')}
        print('FDTDKIT_RFSIM ' + json.dumps(out))
        """#

    /// `[..., QUIET, R/bench, PCT, MAX, GPU]`: bench.wait_quiet, run under the launcher (e2e, run).
    static let quiet = #"""
        import sys, json; sys.path.insert(0, sys.argv[1]); import bench; c, b, late = bench.wait_quiet(float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])); print('FDTDKIT_QUIET ' + json.dumps(dict(cpu=c, busy=b, late=late)))
        """#

    /// `[..., LOAD, R/bench, S]`: one usage.Sampler over S seconds (the load command, ab's sampler checks).
    static let load = #"""
        import sys, json, time; sys.path.insert(0, sys.argv[1]); import usage; s = usage.Sampler(); time.sleep(float(sys.argv[2])); r = s.stop()
        print('FDTDKIT_LOAD ' + json.dumps(dict(load=r, processesSeen=len(getattr(s, 'cpu1', {})), gpuClientsSeen=len(getattr(s, 'gpu1', {})), utilSamples=len(getattr(s, 'util', [])))))
        """#
}

/// Discovery of the tools tree, Python, snapshots, rfsim, runs and results, with the git facts and the probes.
enum FdtdDiscovery {
    /// The ten marker files of a tools tree (spec 3.1). bench/bench.py must also contain `usage.fmt(`: the sibling
    /// worktrees hold an older harness whose bench.py prints no load (F25).
    static let markers = ["bench/bench.py", "bench/abtest.py", "bench/check.sh", "bench/usage.py", "bench/libinfo.py",
                          "bench/validation/run_validation.py", "scripts/checks/debye_check.sh",
                          "scripts/checks/diamond_check.sh", "scripts/e2e/run_one.py", "scripts/cache_valley/box.py"]
    /// bench/bench.py must contain this.
    static let benchLoadMarker = "usage.fmt("
    /// Porcelain paths under these give the warning tools_modified.
    static let toolPrefixes = ["bench/", "scripts/checks/", "scripts/e2e/", "scripts/cache_valley/"]
    /// A python3 whose real path lies under one of these is skipped (python_skipped): the system Pythons strip DYLD (F1).
    static let systemPrefixes = ["/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/", "/usr/libexec/", "/System/"]
    /// The DYLD_LIBRARY_PATH a probe gets when no snapshot is needed.
    static let noDyld = "/var/empty"

    /// The tools tree: `option` (2 tool_missing listing the missing markers when incomplete), else the walk up from the
    /// cwd, else from the real path of the executable; a folder with only some markers is skipped with
    /// tools_tree_skipped and the walk goes on; none → 2 repo_not_found (hint "--repo /path/to/emsKit"). head, dirty
    /// and toolsModified come from git (tools_modified for porcelain paths under toolPrefixes); in a tree kept inside
    /// another repository, head is that repository's commit, and dirty and toolsModified look at the tree alone.
    static func findRepo(option: String?, context: FdtdContext, warnings: inout [FdtdIssue]) throws -> FdtdRepo {
        let root = try findRepoRoot(option: option, context: context, warnings: &warnings)
        var repo = FdtdRepo(root: root)
        repo.head = gitHead(root, context: context)
        // porcelain paths start at the repository's top level, which is above a tools tree kept inside another
        // repository; there the status is asked for this folder only
        let prefix = gitPrefix(root, context: context)
        if let status = gitStatus(root, path: prefix.isEmpty ? nil : ".", context: context) {
            repo.dirty = !status.isEmpty
            repo.toolsModified = modifiedTools(status, prefix: prefix)
        }
        if !repo.toolsModified.isEmpty {
            let list = repo.toolsModified.joined(separator: ", ")
            warnings.append(FdtdIssue(.toolsModified, "the tools have uncommitted changes: \(list)"))
        }
        return repo
    }

    /// Where findRepo finds the tools tree, without the git facts: the protected-folder check asks this for the
    /// tree of a line without --repo and starts no git for it.
    static func findRepoRoot(option: String?, context: FdtdContext, warnings: inout [FdtdIssue]) throws -> String {
        let system = context.system
        let root: String
        if let option {
            let dir = FdtdPaths.absolute(option, cwd: context.cwd, home: context.home)
            guard system.isDirectory(dir) else {
                throw FdtdError(.repoNotFound, "--repo \(dir) is not a folder", field: "--repo",
                                hint: "--repo /path/to/emsKit")
            }
            let missing = missingMarkers(dir, system: system)
            guard missing.isEmpty else {
                let list = describe(missing, in: dir, system: system)
                throw FdtdError(.toolMissing, "--repo \(dir) is not a tools tree: it lacks \(list)", field: "--repo")
            }
            root = dir
        } else {
            guard let found = walk(context: context, warnings: &warnings) else {
                throw FdtdError(.repoNotFound,
                                "no tools tree in \(context.cwd), above it, or above the executable",
                                hint: "--repo /path/to/emsKit")
            }
            root = found
        }
        return root
    }

    /// The markers missing from `root` (the `usage.fmt(` test counts as bench/bench.py); empty for a tools tree.
    static func missingMarkers(_ root: String, system: any FdtdSystem) -> [String] {
        markers.filter { (marker: String) -> Bool in
            let path = FdtdPaths.join(root, marker)
            guard system.isRegularFile(path) else { return true }
            guard marker == "bench/bench.py" else { return false }
            guard let data = system.readFile(path) else { return true }
            return !FdtdLibraries.contains(data, FdtdDiscovery.benchLoadMarker)
        }
    }

    /// `/usr/bin/git -C DIR rev-parse --short HEAD`; nil when git fails.
    static func gitHead(_ dir: String, context: FdtdContext) -> String? {
        git(dir, ["rev-parse", "--short", "HEAD"], context: context).flatMap { commitLine($0) }
    }

    /// `/usr/bin/git -C DIR rev-parse --show-prefix`: DIR below the top level of its repository (`vendor/emsKit/`),
    /// empty at the top level and when git fails.
    static func gitPrefix(_ dir: String, context: FdtdContext) -> String {
        guard let output = git(dir, ["rev-parse", "--show-prefix"], context: context) else { return "" }
        return output.split(separator: "\n", omittingEmptySubsequences: true).first.map { String($0) } ?? ""
    }

    /// `/usr/bin/git -C DIR -c core.quotePath=false status --porcelain [-- PATH]`, one entry per line; nil when git
    /// fails. Without the setting git writes a name with a letter outside ASCII in octal escapes, which the prefix of
    /// `rev-parse --show-prefix` (never quoted) would not match.
    static func gitStatus(_ dir: String, path: String?, context: FdtdContext) -> [String]? {
        var arguments = ["-c", "core.quotePath=false", "status", "--porcelain"]
        if let path { arguments += ["--", path] }
        guard let output = git(dir, arguments, context: context) else { return nil }
        // The two status columns lead each line, so lines are kept as they are (no trimming).
        return output.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
    }

    /// `/usr/bin/git -C DIR log -1 --format=%h -- PATH`; nil when git fails.
    static func gitLastCommit(_ dir: String, path: String, context: FdtdContext) -> String? {
        git(dir, ["log", "-1", "--format=%h", "--", path], context: context).flatMap { commitLine($0) }
    }

    /// PY: `option`, else the first python3 on PATH whose real path is outside systemPrefixes (python_skipped for each
    /// one passed over); none → 3 python_not_found.
    static func findPython(option: String?, context: FdtdContext, warnings: inout [FdtdIssue]) throws -> String {
        let system = context.system
        if let option {
            let path = FdtdPaths.absolute(option, cwd: context.cwd, home: context.home)
            guard system.isExecutableFile(path) else {
                throw FdtdError(.pythonNotFound, "--python \(path) is not an executable file", field: "--python")
            }
            return path
        }
        for candidate in system.executables(named: "python3", onPath: context.environment["PATH"] ?? "") {
            let path = FdtdPaths.absolute(candidate, cwd: context.cwd, home: context.home)
            let real = system.realPath(path) ?? path
            guard !systemPrefixes.contains(where: { real.hasPrefix($0) }) else {
                warnings.append(FdtdIssue(.pythonSkipped,
                                          "\(path) (\(real)) is a system Python, which drops DYLD_LIBRARY_PATH",
                                          hint: "--python /path/to/python3"))
                continue
            }
            return path
        }
        throw FdtdError(.pythonNotFound, "no python3 on PATH outside the system folders", field: "--python",
                        hint: "--python /path/to/python3")
    }

    /// The python probe `[PY, -B, -c, PROBE, REPO/bench/libinfo.py]`, cwd REPO, with `environment` (the base child
    /// environment) plus DYLD_LIBRARY_PATH = `dyld` (a snapshot folder) or noDyld. 4 tool_output_unparsed without the
    /// tagged line.
    static func probePython(_ python: String, repo: String, dyld: String?, environment: [String: String],
                            context: FdtdContext, stop: FdtdStopController?) throws -> FdtdProbeResult {
        var childEnvironment = environment.filter { !$0.key.hasPrefix("DYLD_") }
        childEnvironment["DYLD_LIBRARY_PATH"] = dyld ?? noDyld
        let argv = [python, "-B", "-c", FdtdSnippets.probe, FdtdPaths.join(repo, "bench/libinfo.py")]
        let request = FdtdCaptureRequest(argv: argv, cwd: repo, environment: childEnvironment)
        let result = context.system.capture(request, stop: stop)
        let what = "the python probe of \(python)"
        return try tagged(result, FdtdSnippets.probeTag, as: FdtdProbeResult.self, what: what)
    }

    /// 3 python_strips_dyld when a snapshot is needed and the probe did not see the DYLD value sent; 3
    /// python_no_openems when `import openEMS` failed (importError).
    static func requireUsable(_ probe: FdtdProbeResult, dyldSent: String?, snapshotNeeded: Bool) throws {
        var issues: [FdtdIssue] = []
        let sent = dyldSent ?? noDyld
        if snapshotNeeded, probe.dyld != sent {
            let seen = probe.dyld ?? "unset"
            let message = "\(probe.executable) saw DYLD_LIBRARY_PATH \(seen) instead of \(sent), "
                + "so it cannot load a snapshot"
            issues.append(FdtdIssue(.pythonStripsDyld, message, field: "--python",
                                    hint: "--python /path/to/python3 (not /usr/bin/python3)"))
        }
        if let error = probe.importError {
            issues.append(FdtdIssue(.pythonNoOpenems, "\(probe.executable) cannot import openEMS: \(error)",
                                    field: "--python"))
        }
        if !issues.isEmpty { throw FdtdError(issues) }
    }

    /// Whether a loaded image lies in the library folder `dir`: dyld reports real paths, and `dir` is kept as it was
    /// given, so the image or its real path must lie in the folder as given or in its real path, or be the file that
    /// one of the folder's three names leads to. The one rule of the probe (requireLoaded) and of the verdicts of
    /// validate, e2e and run.
    static func lies(_ image: String, in dir: String, system: any FdtdSystem) -> Bool {
        let folders = [dir, system.realPath(dir) ?? dir].map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        let real = system.realPath(image) ?? image
        if folders.contains(where: { image.hasPrefix($0) || real.hasPrefix($0) }) { return true }
        // a folder whose three names are links to files elsewhere: dyld loads those files and reports where they
        // are, so the image is the folder's when it is the very file one of the names leads to
        guard let identity = system.fileIdentity(image) else { return false }
        return FdtdLibraries.fileNames.contains { system.fileIdentity(FdtdPaths.join(dir, $0)) == identity }
    }

    /// 4 library_not_loaded unless the probe's libraries all lie in `dir` (real paths compared).
    static func requireLoaded(_ probe: FdtdProbeResult, from dir: String, system: any FdtdSystem) throws {
        let images = probe.libraries ?? []
        var problems: [String] = []
        for name in ["libopenEMS", "libCSXCAD", "libnf2ff"] {
            let loaded = images.filter { FdtdPaths.basename($0).hasPrefix(name + ".") }
            if loaded.isEmpty { problems.append("no \(name) was loaded") }
            for image in loaded where !lies(image, in: dir, system: system) {
                problems.append("\(name) came from \(image)")
            }
        }
        guard !problems.isEmpty else { return }
        var message = "the probe did not load the three libraries from \(dir): " + problems.joined(separator: "; ")
        if let error = probe.importError { message += " (import failed: \(error))" }
        throw FdtdError(.libraryNotLoaded, message)
    }

    /// The envelope's `python` from PY and its first probe; dyldKept = the probe saw the DYLD value sent.
    static func pythonRecord(_ python: String, probe: FdtdProbeResult?, dyldSent: String?) -> FdtdPython {
        var record = FdtdPython(path: python)
        guard let probe else { return record }
        record.realPath = probe.realPath
        record.version = probe.version
        record.dyldKept = probe.dyld == (dyldSent ?? noDyld)
        record.openemsModule = probe.openemsModule
        record.openemsVersion = probe.openemsVersion
        record.legacyEmptyOption = probe.legacyEmptyOption
        record.numpy = probe.numpy
        return record
    }

    /// check, debye-check and diamond-check run zsh scripts that call `python3` by name: dirname(PY)/python3 must
    /// resolve to realpath(PY), otherwise 3 python_name_mismatch.
    static func requirePythonName(_ python: String, system: any FdtdSystem) throws {
        let named = FdtdPaths.join(FdtdPaths.dirname(python), "python3")
        let target = system.realPath(python) ?? python
        let exists = system.isExecutableFile(named)
        let resolved = system.realPath(named) ?? named
        if exists, resolved == target { return }
        let found = exists ? "resolves to \(resolved)" : "does not exist"
        throw FdtdError(.pythonNameMismatch, "the scripts call python3 by name, and \(named) \(found), not \(target)",
                        field: "--python", hint: exists ? "--python \(named)" : nil)
    }

    /// The zsh pre-probe of debye-check and diamond-check, once per folder: `[/bin/zsh, -f, -c,
    /// 'DYLD_LIBRARY_PATH="$1" python3 -B -c "$2" "$3"', fdtdkit-probe, LIBDIR, PROBE, LIBINFO]` with `environment`
    /// (no DYLD; PATH with PY's folder first). It proves that the scripts' own zsh → python3 path keeps DYLD.
    static func zshPreProbe(libDir: String, repo: String, environment: [String: String], context: FdtdContext,
                            stop: FdtdStopController?) throws -> FdtdProbeResult {
        // DYLD is never given to /bin/zsh (F1): the script line sets it for python3 itself, as the check scripts do.
        let childEnvironment = environment.filter { !$0.key.hasPrefix("DYLD_") }
        let line = "DYLD_LIBRARY_PATH=\"$1\" python3 -B -c \"$2\" \"$3\""
        let argv = ["/bin/zsh", "-f", "-c", line, "fdtdkit-probe", libDir, FdtdSnippets.probe,
                    FdtdPaths.join(repo, "bench/libinfo.py")]
        let request = FdtdCaptureRequest(argv: argv, cwd: repo, environment: childEnvironment)
        let result = context.system.capture(request, stop: stop)
        let what = "the zsh pre-probe of \(libDir)"
        return try tagged(result, FdtdSnippets.probeTag, as: FdtdProbeResult.self, what: what)
    }

    /// The folder of the libopenEMS the probe loaded without a snapshot (the installed library, spec 3.7); nil when
    /// none was loaded. No prefix is hardcoded.
    static func installedDir(_ probe: FdtdProbeResult, system: any FdtdSystem) -> String? {
        let images = probe.libraries ?? []
        guard let image = images.first(where: { FdtdPaths.basename($0).hasPrefix("libopenEMS.") }) else { return nil }
        // dyld reports the real path on current macOS, so both folders are then the real one: the installed library
        // must hold its three .0.dylib names in the real folder of libopenEMS (a folder of links into separate real
        // folders is not found from here). The path as reported stays first for a dyld that keeps the linking name.
        let folders = [FdtdPaths.dirname(image), FdtdPaths.dirname(system.realPath(image) ?? image)]
        let complete = folders.first(where: { (folder: String) -> Bool in
            FdtdLibraries.fileNames.allSatisfy { system.isRegularFile(FdtdPaths.join(folder, $0)) }
        })
        return complete ?? folders[0]
    }

    /// SNAPS without --snaps and $OPENEMS_BENCH_SNAPS.
    static let defaultSnapshots = "~/opt/openEMS-dev/snap"

    /// BUILD.md's install prefix (upstream's default). The installed library stays whatever the probe loads; this
    /// folder is only protected as well (S3), so that a probe that cannot run or cannot load openEMS leaves it covered.
    static let defaultPrefix = "~/opt/openEMS"

    /// SNAPS: `option`, else $OPENEMS_BENCH_SNAPS, else ~/opt/openEMS-dev/snap.
    static func snapshotsFolder(option: String?, context: FdtdContext) -> String {
        let given = option ?? context.environment["OPENEMS_BENCH_SNAPS"].flatMap { $0.isEmpty ? nil : $0 }
        return FdtdPaths.absolute(given ?? defaultSnapshots, cwd: context.cwd, home: context.home)
    }

    /// rfsim's folder: `option`, else $RFSIM_PATH; nil when neither is given. A folder without rfsim/openems/core.py
    /// → 2 rfsim_not_found, saying what was looked at (rfsimSearch).
    static func findRfsim(option: String?, context: FdtdContext) throws -> String? {
        let fromEnvironment = context.environment["RFSIM_PATH"].flatMap { $0.isEmpty ? nil : $0 }
        guard let given = option ?? fromEnvironment else { return nil }
        let dir = FdtdPaths.absolute(given, cwd: context.cwd, home: context.home)
        guard rfsimLack(dir, system: context.system) == nil else {
            throw FdtdError(.rfsimNotFound, rfsimSearch(option: option, context: context),
                            field: option == nil ? nil : "--rfsim", hint: "--rfsim DIR, the folder that holds rfsim/")
        }
        return dir
    }

    /// What the rfsim search looked at and why it took nothing: --rfsim given or not, $RFSIM_PATH set, empty or not
    /// (only without --rfsim), and what the folder named lacks; e.g. "--rfsim was not given, and RFSIM_PATH
    /// /x/sim has no rfsim/ folder".
    static func rfsimSearch(option: String?, context: FdtdContext) -> String {
        func named(_ what: String, _ given: String) -> String {
            let dir = FdtdPaths.absolute(given, cwd: context.cwd, home: context.home)
            // a toolkit folder here means that its probe failed: the search itself took it
            let lack = rfsimLack(dir, system: context.system) ?? "holds rfsim/openems/core.py, but its probe failed"
            return "\(what) \(dir) \(lack)"
        }
        if let option { return named("--rfsim", option) }
        guard let value = context.environment["RFSIM_PATH"] else {
            return "--rfsim was not given and RFSIM_PATH is not set"
        }
        guard !value.isEmpty else { return "--rfsim was not given and RFSIM_PATH is empty" }
        return "--rfsim was not given, and " + named("RFSIM_PATH", value)
    }

    /// What keeps `dir` from being a toolkit folder: no folder, no rfsim/ in it, or no rfsim/openems/core.py; nil for
    /// a toolkit folder.
    private static func rfsimLack(_ dir: String, system: any FdtdSystem) -> String? {
        if system.isRegularFile(FdtdPaths.join(dir, "rfsim/openems/core.py")) { return nil }
        guard system.isDirectory(dir) else { return "is not a folder" }
        guard system.isDirectory(FdtdPaths.join(dir, "rfsim")) else { return "has no rfsim/ folder" }
        return "has rfsim/ but no rfsim/openems/core.py"
    }

    /// The rfsim probe `[PY, -B, -c, RFSIM, DIR]` (no DYLD) plus the git facts: the envelope's `rfsim`.
    static func probeRfsim(_ dir: String, python: String, environment: [String: String], context: FdtdContext,
                           stop: FdtdStopController?) throws -> FdtdRfsim {
        // cwd is the toolkit folder: with -c the cwd comes first on sys.path, so the CLI's cwd cannot shadow an import.
        let childEnvironment = environment.filter { !$0.key.hasPrefix("DYLD_") }
        let request = FdtdCaptureRequest(argv: [python, "-B", "-c", FdtdSnippets.rfsim, dir], cwd: dir,
                                         environment: childEnvironment)
        let result = context.system.capture(request, stop: stop)
        let what = "the rfsim probe of \(dir)"
        let probe = try tagged(result, FdtdSnippets.rfsimTag, as: FdtdRfsimProbe.self, what: what)
        var record = FdtdRfsim(path: dir)
        record.head = gitHead(dir, context: context)
        record.rfsimCommit = gitLastCommit(dir, path: "rfsim", context: context)
        record.dirty = gitStatus(dir, path: "rfsim", context: context).map { !$0.isEmpty }
        record.probeEndDb = probe.probeEndDb
        record.probeEndHold = probe.probeEndHold
        record.zMult = probe.zMult
        record.minCell = probe.minCell
        record.minCellEffective = probe.minCellEffective
        record.env = probe.env ?? [:]
        return record
    }

    /// RUNS: `option`, else $OPENEMS_BENCH_RUNS, else /tmp/openems_bench_runs.
    static func runsBase(option: String?, context: FdtdContext) -> String {
        let given = option ?? context.environment["OPENEMS_BENCH_RUNS"].flatMap { $0.isEmpty ? nil : $0 }
        return FdtdPaths.absolute(given ?? "/tmp/openems_bench_runs", cwd: context.cwd, home: context.home)
    }

    /// The folder check.sh's tables go to: check.sh changes to the real folder of its own path (`cd "${0:A:h}"`) and
    /// runs bench.py there without --out, so bench.py's RESULTS is the results/ beside that folder. REPO/results
    /// unless REPO/bench or check.sh is a symbolic link.
    static func checkResultsFolder(repo: String, system: any FdtdSystem) -> String {
        guard let script = system.realPath(FdtdPaths.join(repo, "bench/check.sh")) else {
            return FdtdPaths.join(repo, "results")
        }
        return FdtdPaths.join(FdtdPaths.dirname(FdtdPaths.dirname(script)), "results")
    }

    /// REPO/results, or `option` (--results DIR), which must exist (2 folder_missing).
    static func resultsFolder(repo: String, option: String?, context: FdtdContext) throws -> String {
        guard let option else { return FdtdPaths.join(repo, "results") }
        let dir = FdtdPaths.absolute(option, cwd: context.cwd, home: context.home)
        guard context.system.isDirectory(dir) else {
            throw FdtdError(.folderMissing, "--results \(dir) does not exist", field: "--results")
        }
        return dir
    }

    // MARK: - Private

    private static let hexBytes = Set("0123456789abcdef".utf8)

    /// The cwd's folder and those above it, then the executable's (by its real path) and those above it; the first
    /// complete tools tree wins, and each folder passed over that holds some markers gives tools_tree_skipped.
    private static func walk(context: FdtdContext, warnings: inout [FdtdIssue]) -> String? {
        let system = context.system
        var starts = [FdtdPaths.absolute(context.cwd, cwd: "/", home: context.home)]
        if !context.executablePath.isEmpty {
            let executable = FdtdPaths.absolute(context.executablePath, cwd: context.cwd, home: context.home)
            starts.append(FdtdPaths.dirname(system.realPath(executable) ?? executable))
        }
        var visited = Set<String>()
        for start in starts {
            var dir = start
            while true {
                if visited.insert(dir).inserted {
                    let missing = missingMarkers(dir, system: system)
                    if missing.isEmpty { return dir }
                    let folder = dir
                    if markers.contains(where: { system.isRegularFile(FdtdPaths.join(folder, $0)) }) {
                        let list = describe(missing, in: folder, system: system)
                        warnings.append(FdtdIssue(.toolsTreeSkipped, "\(folder) is not a tools tree: it lacks \(list)"))
                    }
                }
                let parent = FdtdPaths.dirname(dir)
                if parent == dir || parent.isEmpty { break }
                dir = parent
            }
        }
        return nil
    }

    /// The missing markers as a list; a bench/bench.py without `usage.fmt(` is named as the older harness it is (F25).
    private static func describe(_ missing: [String], in root: String, system: any FdtdSystem) -> String {
        let named = missing.map { (marker: String) -> String in
            guard marker == "bench/bench.py", system.isRegularFile(FdtdPaths.join(root, marker)) else { return marker }
            return "a bench/bench.py with usage.fmt( (this one is an older harness)"
        }
        return named.joined(separator: ", ")
    }

    /// The porcelain paths under toolPrefixes (both sides of a rename, quotes removed), each once and relative to the
    /// tools tree: `prefix` (the tree below the repository's top level) is taken off, and a path outside it is no tool.
    static func modifiedTools(_ lines: [String], prefix: String = "") -> [String] {
        var paths: [String] = []
        for line in lines where line.count > 3 {
            for part in String(line.dropFirst(3)).components(separatedBy: " -> ") {
                var path = part
                if path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") {
                    path = String(path.dropFirst().dropLast())
                }
                guard path.hasPrefix(prefix) else { continue }
                path = String(path.dropFirst(prefix.count))
                if toolPrefixes.contains(where: { path.hasPrefix($0) }), !paths.contains(path) { paths.append(path) }
            }
        }
        return paths
    }

    /// `/usr/bin/git -C DIR ARGS` with the CLI's environment minus GIT_* (a hook's GIT_DIR would name another
    /// repository) plus GIT_OPTIONAL_LOCKS=0, so that status never takes the index lock from another session; stdout
    /// when git exits 0.
    private static func git(_ dir: String, _ arguments: [String], context: FdtdContext) -> String? {
        var environment = context.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        let request = FdtdCaptureRequest(argv: ["/usr/bin/git", "-C", dir] + arguments, cwd: dir,
                                         environment: environment, timeoutSeconds: 30)
        let result = context.system.capture(request, stop: nil)
        guard result.ran, result.exit == 0 else { return nil }
        return result.stdout
    }

    /// The first line when it is a lowercase hex abbreviation (a commit), else nil.
    private static func commitLine(_ output: String) -> String? {
        guard let first = output.split(whereSeparator: \.isNewline).first else { return nil }
        let line = first.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, line.utf8.allSatisfy({ FdtdDiscovery.hexBytes.contains($0) }) else { return nil }
        return line
    }

    /// The tagged line's JSON; 4 spawn_failed when the child never started, 4 tool_output_unparsed without the line.
    private static func tagged<T: Decodable>(_ result: FdtdCaptureResult, _ tag: String, as type: T.Type,
                                             what: String) throws -> T {
        if let error = result.spawnError {
            throw FdtdError(.spawnFailed, "\(what) could not start: \(error)")
        }
        if let value = FdtdParsers.taggedJSON(tag, in: result.stdout, as: type) { return value }
        var detail: String
        if let signal = result.termSignal {
            detail = "ended by signal \(signal)"
        } else if let exit = result.exit {
            detail = "exit \(exit)"
        } else {
            detail = "no exit status"
        }
        if let line = lastLine(result.stderr) { detail += ", last stderr line: " + line }
        throw FdtdError(.toolOutputUnparsed, "\(what) printed no \(tag) line (\(detail))")
    }

    /// The last non-blank line, at most 200 characters.
    private static func lastLine(_ text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let last = lines.last(where: { !$0.allSatisfy(\.isWhitespace) }) else { return nil }
        let line = last.trimmingCharacters(in: .whitespaces)
        return line.count > 200 ? String(line.prefix(200)) + "..." : line
    }
}
