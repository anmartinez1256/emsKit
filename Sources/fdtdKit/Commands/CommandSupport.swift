// SPDX-License-Identifier: GPL-3.0-or-later

// The steps the commands share, as an extension of FdtdSession: discovery with its caches, library resolution, the
// child environment, the distribution record, the protected-folder check, the concurrency gate, the run folder,
// caffeinate and spawning a job through a backend. Each step fills its part of the envelope, adds its warnings, and
// throws FdtdError to stop the command. Everything here runs on the dispatcher's thread; only the onLine closures run
// on the pump thread.
import Foundation
import Synchronization

/// The child that the installed library's probe is, by what can change its answer: the Python as named (a venv's
/// python3 is a link to its base Python and still another Python), the tools tree as a folder (file identity, so
/// that a link or another spelling of it is the same tree), and the environment without RFSIM_PATH, which
/// `import openEMS` does not read. Two probes that are equal in these give the same answer.
struct FdtdInstalledProbe: Equatable {
    var python: String
    var tree: FdtdInode?
    var repo: String
    var environment: [String: String]

    init(python: String, repo: String, environment: [String: String], system: any FdtdSystem) {
        self.python = python
        tree = system.fileIdentity(repo)
        // the path counts only where the folder has no identity
        self.repo = tree == nil ? repo : ""
        self.environment = environment.filter { $0.key != "RFSIM_PATH" }
    }
}

/// The shared steps' caches: each probe and scan runs once per command.
struct FdtdSessionMemo {
    var repo: FdtdRepo? = nil
    var python: String? = nil
    /// Probe results by the DYLD value sent (FdtdDiscovery.noDyld when none).
    var probes: [String: FdtdProbeResult] = [:]
    var snapshotIndex: FdtdSnapshotIndex? = nil
    var installedDir: String? = nil
    var rfsimSearched = false
    var rfsim: FdtdRfsim? = nil
    var environment: FdtdChildEnvironment? = nil
    /// The protected folders as named; every check locates them again, so only their discovery is kept (never one
    /// that a stop cut short).
    var protectedRoots: [FdtdProtectedRoot]? = nil
    /// Resolved libraries by LIB spec.
    var libraries: [String: FdtdLibrary] = [:]
    /// Folders the zsh pre-probe has passed.
    var zshProbed: Set<String> = []
}

extension FdtdSession {
    /// The tools tree (spec 3.1), once: envelope.repo, with tools_tree_skipped and tools_modified.
    func discoverRepo() throws -> FdtdRepo {
        if let repo = memo.repo { return repo }
        var warnings: [FdtdIssue] = []
        let started = context.clock.uptime()
        // the warnings found before a failure still belong in the envelope
        defer {
            addProbeSeconds(context.clock.uptime() - started)
            warn(contentsOf: warnings)
        }
        let repo = try FdtdDiscovery.findRepo(option: common.repo, context: context, warnings: &warnings)
        memo.repo = repo
        envelope.repo = repo
        return repo
    }

    /// PY (spec 3.2), once, with python_skipped.
    func discoverPython() throws -> String {
        if let python = memo.python { return python }
        var warnings: [FdtdIssue] = []
        defer { warn(contentsOf: warnings) }
        let python = try FdtdDiscovery.findPython(option: common.python, context: context, warnings: &warnings)
        memo.python = python
        if envelope.python == nil { envelope.python = FdtdPython(path: python) }
        return python
    }

    /// The python probe with DYLD_LIBRARY_PATH = `dyld` (nil: /var/empty), once per value; the first one fills
    /// envelope.python. 3 python_strips_dyld when `snapshotNeeded` and DYLD did not survive; 3 python_no_openems.
    func probePython(dyld: String?, snapshotNeeded: Bool) throws -> FdtdProbeResult {
        let key = dyld ?? FdtdDiscovery.noDyld
        let python = try discoverPython()
        let probe: FdtdProbeResult
        if let cached = memo.probes[key] {
            probe = cached
        } else {
            let repo = try discoverRepo()
            let environment = try childEnvironment()
            let started = context.clock.uptime()
            defer { addProbeSeconds(context.clock.uptime() - started) }
            probe = try FdtdDiscovery.probePython(python, repo: repo.root, dyld: dyld,
                                                  environment: environment.environment, context: context, stop: stop)
            let first = memo.probes.isEmpty
            memo.probes[key] = probe
            if first { envelope.python = FdtdDiscovery.pythonRecord(python, probe: probe, dyldSent: dyld) }
        }
        try FdtdDiscovery.requireUsable(probe, dyldSent: dyld, snapshotNeeded: snapshotNeeded)
        return probe
    }

    /// SNAPS (spec 3.3).
    func snapshotsFolder() -> String { FdtdDiscovery.snapshotsFolder(option: common.snaps, context: context) }

    /// SNAPS read once.
    func snapshotIndex() -> FdtdSnapshotIndex {
        if let index = memo.snapshotIndex { return index }
        let started = context.clock.uptime()
        let index = FdtdLibraries.index(snaps: snapshotsFolder(), system: context.system)
        addProbeSeconds(context.clock.uptime() - started)
        memo.snapshotIndex = index
        return index
    }

    /// The installed library's folder: that of the libopenEMS the probe loaded without a snapshot; 2
    /// library_not_found when it loaded none.
    func installedLibraryDir() throws -> String {
        if let dir = memo.installedDir { return dir }
        let probe = try probePython(dyld: nil, snapshotNeeded: false)
        guard let dir = FdtdDiscovery.installedDir(probe, system: context.system) else {
            throw FdtdError(.libraryNotFound, "installed names no folder: the python probe loaded no libopenEMS",
                            field: "LIB", hint: "emskit fdtd info")
        }
        memo.installedDir = dir
        return dir
    }

    /// A LIB form located, complete (2 library_incomplete) and identified, once per spec; added to envelope.libraries.
    func resolveLibrary(_ spec: String) throws -> FdtdLibrary {
        if let library = memo.libraries[spec] { return library }
        let installed: String? = spec == "installed" ? try installedLibraryDir() : nil
        let index = snapshotIndex()
        let started = context.clock.uptime()
        defer { addProbeSeconds(context.clock.uptime() - started) }
        let location = try FdtdLibraries.locate(spec, snaps: snapshotsFolder(), installedDir: installed, cwd: context.cwd,
                                                home: context.home, system: context.system)
        try FdtdLibraries.requireComplete(location)
        // from the index when it has read and hashed this folder already (a snapshot by its name or by its path)
        let library = FdtdLibraries.record(location, index: index, system: context.system)
        memo.libraries[spec] = library
        addLibrary(library)
        return library
    }

    /// rfsim (spec 3.4), probed once: nil when neither --rfsim nor $RFSIM_PATH names one; `required` throws 2
    /// rfsim_not_found instead. Fills envelope.rfsim.
    func discoverRfsim(required: Bool) throws -> FdtdRfsim? {
        if memo.rfsimSearched {
            if memo.rfsim == nil, required { throw rfsimMissing() }
            return memo.rfsim
        }
        let found: String?
        do {
            found = try FdtdDiscovery.findRfsim(option: common.rfsim, context: context)
        } catch let e as FdtdError {
            // a stale $RFSIM_PATH counts as no toolkit; an explicit --rfsim must be right
            guard common.rfsim == nil, !required else {
                memo.rfsimSearched = true
                throw e
            }
            found = nil
        }
        guard let dir = found else {
            memo.rfsimSearched = true
            if required { throw rfsimMissing() }
            return nil
        }
        let python = try discoverPython()
        // the search counts as done only after this: built here, the base environment names the toolkit being probed
        // (rfsimPathForChildren), as it does when an earlier step (--output's protected-folder check) built it
        let environment = try childEnvironment()
        memo.rfsimSearched = true
        let started = context.clock.uptime()
        defer { addProbeSeconds(context.clock.uptime() - started) }
        let record = try FdtdDiscovery.probeRfsim(dir, python: python, environment: environment.environment,
                                                  context: context, stop: stop)
        memo.rfsim = record
        envelope.rfsim = record
        return record
    }

    /// The base child environment (spec 5.1), once; its warnings are added.
    func childEnvironment() throws -> FdtdChildEnvironment {
        if let environment = memo.environment { return environment }
        let python = try discoverPython()
        let rfsimPath = try rfsimPathForChildren()
        var warnings: [FdtdIssue] = []
        let environment = FdtdChildEnv.base(inherited: context.environment, python: python, rfsimPath: rfsimPath,
                                            warnings: &warnings)
        warn(contentsOf: warnings)
        memo.environment = environment
        return environment
    }

    /// RUNS (spec 3.5).
    func runsBase() -> String { FdtdDiscovery.runsBase(option: common.runs.map { absolutePath($0) }, context: context) }

    /// The run folder this command would get, without creating anything (dry runs and refusals resolve against it);
    /// for load, the scratch folder createScratch would make.
    func plannedRunFolder() -> FdtdRunFolder {
        if command == .load {
            return FdtdRunFolders.plannedScratch(base: runsBase(), pid: context.pid, now: context.clock.now(),
                                                 timeZone: context.timeZone)
        }
        return FdtdRunFolders.planned(base: runsBase(), command: command, pid: context.pid, now: context.clock.now(),
                                      timeZone: context.timeZone)
    }

    /// The folders no command writes into (S3): the installed library's prefix (above the lib/ folder of the
    /// libopenEMS the probe loaded without a snapshot, by dyld's path and by the real path, and BUILD.md's
    /// ~/opt/openEMS, which stays covered when the probe cannot run or load openEMS) and the snapshot folder (SNAPS,
    /// and also $OPENEMS_BENCH_SNAPS and ~/opt/openEMS-dev/snap when SNAPS is another folder). `~` is $HOME and also
    /// the account's home folder when $HOME names another. A folder reached by two paths is listed under both. Only
    /// folders that exist are protected; one that discovery cannot find protects nothing and stops nothing. So is
    /// every folder that the line names as a LIB by its path (SNAP, --stock, --lib, --ref, a CFG's LIB), complete
    /// library or not; a LIB given as a snapshot name lies in SNAPS, and a folder of that name in the working
    /// directory is protected too (a slip can turn a relative --snaps folder into such a name).
    ///
    /// One rule for the discovery options (--repo, --python, --rfsim, --snaps): the list is the union of what
    /// discovery finds with the line's options and what it finds with all of them ignored. An option can therefore
    /// add a protected folder and never take one away, whether it is mistyped or not. The line's options count one
    /// by one: an option that names nothing leaves the others standing (the default takes its place).
    ///
    /// Returns the list, and whether a stop cut one of the installed library's probes short: the list then lacks
    /// whatever prefix that probe would have named, so it is not kept for the rest of the command, and
    /// refuseProtected lets nothing through on it.
    func protectedFolders() -> (roots: [FdtdProtectedRoot], cutShort: Bool) {
        if let roots = memo.protectedRoots { return (roots, false) }
        var cutShort = false
        let system = context.system
        let homes = homeFolders()
        var roots: [FdtdProtectedRoot] = []
        // one folder can be listed under several paths (the probe reports the real path of a linked prefix, the
        // default is its name): each path stays a root, because the folders above each of them hold it
        func add(_ name: String, _ path: String) {
            guard system.fileIdentity(path) != nil, !roots.contains(where: { $0.path == path }) else { return }
            roots.append(FdtdProtectedRoot(name: name, path: path))
        }
        func addInstalled(_ dir: String) {
            var folders = [dir]
            if let real = system.realPath(FdtdPaths.join(dir, FdtdLibraries.openEMSFile)) {
                folders.append(FdtdPaths.dirname(real))
            }
            for folder in folders {
                let prefix = FdtdProtectedPaths.prefix(of: folder, homes: homes, system: system)
                add("the installed openEMS prefix", prefix)
            }
        }
        // (a) the line's own discovery: the probe that finds the installed library runs in the command's tools
        // tree, with its Python and its environment
        var asked: [FdtdInstalledProbe] = []
        if let repo = try? discoverRepo(), let python = try? discoverPython(),
           let environment = try? childEnvironment() {
            asked.append(FdtdInstalledProbe(python: python, repo: repo.root, environment: environment.environment,
                                            system: system))
            if let dir = try? installedLibraryDir() {
                addInstalled(dir)
            } else if memo.probes[FdtdDiscovery.noDyld] == nil, stop.stopRequested {
                // a stop kills the probe, or each child as it starts: no answer then is no "none installed" (a
                // probe that did answer, or a Python that cannot be found, is the same answer after a stop)
                cutShort = true
            }
        } else if !common.discoveryGiven.isEmpty {
            // one of the line's options names nothing, so the command's own probe cannot run: the others still
            // name an installation (a correct --python beside a mistyped --rfsim), and its prefix stays protected
            let partly = installedDirAside(lineOptions: true, asked: &asked)
            if let dir = partly.dir { addInstalled(dir) }
            cutShort = cutShort || partly.cutShort
        }
        // (b) discovery with the line's options ignored, whenever the line has one of them (without any, it is
        // (a) again): a mistyped option must not hide the prefix that the plain line protects
        if !common.discoveryGiven.isEmpty {
            let plain = installedDirAside(lineOptions: false, asked: &asked)
            if let dir = plain.dir { addInstalled(dir) }
            cutShort = cutShort || plain.cutShort
        }
        func defaults(_ path: String) -> [String] {
            homes.map { FdtdPaths.absolute(path, cwd: context.cwd, home: $0) }
        }
        for folder in defaults(FdtdDiscovery.defaultPrefix) { add("the installed openEMS prefix", folder) }
        // SNAPS of the line, then SNAPS without --snaps and the default: the same union
        let snapshots = [snapshotsFolder(), FdtdDiscovery.snapshotsFolder(option: nil, context: context)]
            + defaults(FdtdDiscovery.defaultSnapshots)
        for folder in snapshots { add("the snapshot folder", folder) }
        // every LIB that the line names by its path (the '/' rule of FdtdLibraries.locate) and that is a folder,
        // whether it holds a library or not: a slip can make any folder a LIB (an option left without its value
        // turns the next one's folder into a SNAP), and the command then ends before anything else looks at it
        for spec in lineLibraries where spec.contains("/") {
            let folder = absolutePath(spec)
            if system.isDirectory(folder) { add("a library folder of this line", folder) }
        }
        // a LIB without '/' is a snapshot name in SNAPS (protected above), but the slip can also leave a bare
        // relative folder there (`--stock -snaps mysnaps`): a folder of that name in the working directory is
        // protected as well. Not the words that locate never reads as a snapshot name.
        for spec in lineLibraries where FdtdLibraries.isSnapshotName(spec) {
            let folder = FdtdPaths.join(context.cwd, spec)
            if system.isDirectory(folder) { add("a folder named like a library of this line", folder) }
        }
        if !cutShort { memo.protectedRoots = roots }
        return (roots, cutShort)
    }

    /// The installed library's folder as a probe beside the command's own finds it. `lineOptions`: with each of
    /// --repo, --python and --rfsim that resolves, and the default in place of each one that does not; otherwise
    /// with all three ignored. The defaults: the tools tree of the cwd/executable walk, PATH's python and $RFSIM_PATH
    /// (a stale one counts as none). Nothing of it is kept or recorded: the command goes on with its own discovery.
    /// No probe runs when it would be a child that was asked already (`asked`: the options name what the defaults
    /// find, or differ only in what the probe does not read). `cutShort`: a stop ended the probe before it answered.
    private func installedDirAside(lineOptions: Bool,
                                   asked: inout [FdtdInstalledProbe]) -> (dir: String?, cutShort: Bool) {
        var discarded: [FdtdIssue] = []
        func found<T>(_ option: String?, _ find: (String?) throws -> T) -> T? {
            if lineOptions, let option, let own = try? find(option) { return own }
            return try? find(nil)
        }
        let tree = found(common.repo) {
            try FdtdDiscovery.findRepoRoot(option: $0, context: context, warnings: &discarded)
        }
        let interpreter = found(common.python) {
            try FdtdDiscovery.findPython(option: $0, context: context, warnings: &discarded)
        }
        guard let repo = tree, let python = interpreter else { return (nil, false) }
        let rfsim = found(common.rfsim) { try FdtdDiscovery.findRfsim(option: $0, context: context) } ?? nil
        let environment = FdtdChildEnv.base(inherited: context.environment, python: python, rfsimPath: rfsim,
                                            warnings: &discarded).environment
        let child = FdtdInstalledProbe(python: python, repo: repo, environment: environment, system: context.system)
        if asked.contains(child) { return (nil, false) }
        asked.append(child)
        let started = context.clock.uptime()
        defer { addProbeSeconds(context.clock.uptime() - started) }
        guard let probe = try? FdtdDiscovery.probePython(python, repo: repo, dyld: nil, environment: environment,
                                                         context: context, stop: stop) else {
            return (nil, stop.stopRequested)
        }
        return (FdtdDiscovery.installedDir(probe, system: context.system), false)
    }

    /// $HOME, and the account's home folder (the password database) when $HOME names another one.
    func homeFolders() -> [String] {
        var homes = [context.home]
        if let account = context.system.accountHome(), !account.isEmpty, !homes.contains(account) {
            homes.append(account)
        }
        return homes
    }

    /// 2 protected_path for every target that is a protected folder or lies inside one, or (renamed or replaced as a
    /// whole) holds one, or (written in place by a tool) is another name of a file in one (S3). It runs before anything
    /// is created, renamed or spawned, in a dry run too, and no option overrides it. A target inside one already
    /// refused is not named again. When a stop cut the installed library's probe short, the folders are not all
    /// known: the targets inside the known ones are refused as ever, and the others end the command as interrupted
    /// (130) with nothing written to them.
    func refuseProtected(_ targets: [FdtdWriteTarget]) throws {
        let (roots, cutShort) = protectedFolders()
        var issues: [FdtdIssue] = []
        var refused: [String] = []
        for target in targets {
            if refused.contains(where: { target.path == $0 || target.path.hasPrefix($0 + "/") }) { continue }
            guard let issue = FdtdProtectedPaths.refusal(target, roots: roots, system: context.system) else { continue }
            issues.append(issue)
            refused.append(target.path)
        }
        if !issues.isEmpty { throw FdtdError(issues) }
        if cutShort, !targets.isEmpty {
            throw FdtdError(.interrupted, "a stop was requested before the installed library's probe answered, so the "
                                + "protected folders are not all known and nothing is written")
        }
    }

    /// A named output that is replaced as a whole (or, `inPlace`, opened for writing by a tool) and, with --overwrite
    /// when it exists, the backup planned next to it.
    func replacedTargets(_ path: String, label: String, field: String, inPlace: Bool = false) -> [FdtdWriteTarget] {
        var targets = [inPlace ? FdtdWriteTarget.inPlace(label, field: field, path) : .whole(label, field: field, path)]
        if common.overwrite, context.system.fileExists(path) {
            let backup = FdtdOutputs.backupPath(path, now: context.clock.now(), timeZone: context.timeZone)
            targets.append(.whole("the backup of \(label)", field: field, backup))
        }
        return targets
    }

    /// RUNS and the folder this command would make in it (load: its scratch folder), as write targets.
    func runFolderTargets() -> [FdtdWriteTarget] {
        let base = runsBase()
        let fromEnvironment = context.environment["OPENEMS_BENCH_RUNS"].map { !$0.isEmpty } ?? false
        let label = common.runs != nil ? "--runs" : fromEnvironment ? "OPENEMS_BENCH_RUNS" : "the runs folder"
        guard command != .load else {
            // load takes no --runs
            return [.into(label, field: nil, base), .into("the scratch folder", field: nil, plannedRunFolder().path)]
        }
        return [.into(label, field: "--runs", base), .into("the run folder", field: "--runs", plannedRunFolder().path)]
    }

    /// The distribution record and its warnings (spec 12): envelope.distribution.
    func distributionRecord() throws {
        var warnings: [FdtdIssue] = []
        defer { warn(contentsOf: warnings) }
        let hosts = common.hosts.map { absolutePath($0) }
        envelope.distribution = try FdtdDistributions.record(common, command: command, hostsPath: hosts,
                                                             system: context.system, warnings: &warnings)
    }

    /// The two scans and the policy (spec 11) over the installed libopenEMS, every complete snapshot's and those of
    /// `libraries`: envelope.concurrent; throws 5 on bench, ab and e2e unless `quietGiven` or --allow-concurrent.
    /// After a stop it throws 130 (interrupted); only a process that the scans found before the stop still refuses
    /// (5) or warns.
    func concurrencyGate(libraries: [FdtdLibrary], quietGiven: Bool) throws {
        // a stop kills each child as it starts: the installed library's probe and both lsof scans would answer
        // nothing, and a scan without an exit status reads as concurrency_unknown (5), which outranks the
        // interruption (130)
        if stop.stopRequested { throw FdtdError(.interrupted, "a stop was requested before the concurrency scans") }
        var files: [String] = []
        func add(_ path: String) {
            if !files.contains(path) { files.append(path) }
        }
        // a Python that cannot load openEMS has no installed library to watch
        if let dir = try? installedLibraryDir() { add(FdtdPaths.join(dir, FdtdLibraries.openEMSFile)) }
        for entry in snapshotIndex().entries where entry.complete {
            add(FdtdPaths.join(entry.dir, FdtdLibraries.openEMSFile))
        }
        for library in libraries {
            add(library.file(FdtdLibraries.openEMSFile)?.path ?? FdtdPaths.join(library.dir, FdtdLibraries.openEMSFile))
        }
        let started = context.clock.uptime()
        let concurrent = FdtdConcurrency.scan(libraries: files, context: context, stop: stop)
        addProbeSeconds(context.clock.uptime() - started)
        envelope.concurrent = concurrent
        // after a stop only a process the scans found still counts (5 outranks 130); the unknown or empty answer of
        // a stopped scan says nothing, and the command ends as interrupted
        let stopped = stop.stopRequested
        if !stopped || concurrent.result == .found {
            warn(contentsOf: try FdtdConcurrency.enforce(concurrent, command: command, quietGiven: quietGiven,
                                                         allowConcurrent: common.allowConcurrent))
        }
        if stopped { throw FdtdError(.interrupted, "a stop was requested during the concurrency scans") }
    }

    /// Runs the refusal checks (protected folders, overwrite, concurrency); when one throws, or a stop ends the
    /// command at the concurrency gate, `jobs` are recorded as planned against the run folder they would have had
    /// (ran false, interrupted when a stop was requested; a sampler check as an invocation only), so that the
    /// envelope shows what would have run.
    func refusals(_ jobs: [FdtdJob], libraries: [FdtdLibrary], _ checks: () throws -> Void) throws {
        do {
            try checks()
        } catch {
            recordPlanned(jobs, libraries: libraries, interrupted: stop.stopRequested)
            throw error
        }
    }

    /// The run folder the invocations resolve against: only planned in a dry run; otherwise created, the launcher
    /// copy written and recorded in outputs, and `runFolder` set.
    func prepareRunFolder() throws -> FdtdRunFolder {
        if common.dryRun { return plannedRunFolder() }
        let folder = try FdtdRunFolders.create(base: runsBase(), command: command, pid: context.pid,
                                               now: context.clock.now(), timeZone: context.timeZone,
                                               system: context.system)
        runFolder = folder
        addOutput(try FdtdRunFolders.writeLauncher(folder, system: context.system))
        return folder
    }

    /// caffeinate beside the run, unless --no-caffeinate or a dry run; caffeinate_failed when it could not start.
    func startCaffeinate() {
        guard !common.noCaffeinate, !common.dryRun else { return }
        guard !context.system.startCaffeinate(watching: context.pid) else { return }
        let message = "/usr/bin/caffeinate -i -w \(context.pid) could not start, so the Mac may sleep during the run"
        warn(FdtdIssue(.caffeinateFailed, message, hint: "--no-caffeinate"))
    }

    /// The local backend for this command's jobs (`libraries` give the spec → folder map).
    func localBackend(runFolder: FdtdRunFolder, libraries: [FdtdLibrary]) throws -> FdtdLocalBackend {
        let python = try discoverPython()
        let repo = try discoverRepo()
        let environment = try childEnvironment()
        var dirs: [String: String] = [:]
        for library in libraries { dirs[library.spec] = library.dir }
        let rfsim = memo.rfsim?.path ?? environment.environment["RFSIM_PATH"]
        let setup = FdtdLocalSetup(python: python, repo: repo.root, runFolder: runFolder, snaps: snapshotsFolder(),
                                   libraryDirs: dirs, rfsim: rfsim, environment: environment, cliCwd: context.cwd)
        return FdtdLocalBackend(context: context, setup: setup)
    }

    /// Adds `job` to envelope.jobs, resolves and records its invocation; in a dry run it stops there and returns nil
    /// (ran false). Otherwise it runs the invocation, updates the record (exit, seconds, ran, interrupted) and the
    /// tool time, and returns the result. A child that could not start throws 4 spawn_failed; a launcher child
    /// without a readable report gives launcher_failed unless a stop was requested.
    func spawnJob(_ job: FdtdJob, backend: any FdtdBackend,
                  onLine: (@Sendable (String) -> Void)?) throws -> FdtdJobResult? {
        // ab's sampler checks are invocations without a job (spec 7)
        if job.role != .samplerCheck { addJob(job) }
        let invocation = try backend.resolve(job, host: "local")
        let index = record(invocation)
        if common.dryRun { return nil }
        if stop.stopRequested {
            updateInvocation(index) { $0.interrupted = true }
            throw FdtdError(.interrupted, "a stop was requested before job \(job.id) started")
        }
        let result = try backend.run(invocation, control: stop, onLine: onLine)
        let outcome = result.outcome
        updateInvocation(index) { entry in
            entry.exit = result.exit
            entry.seconds = result.seconds
            entry.ran = outcome.ran
            entry.interrupted = outcome.interrupted
        }
        addToolSeconds(result.seconds)
        if let log = result.logPath, context.system.fileExists(log) { recordOutput(log) }
        if let reason = outcome.spawnError {
            throw FdtdError(.spawnFailed, "job \(job.id) could not start: \(reason)")
        }
        if invocation.controlPipe, result.report == nil, !stop.stopRequested {
            let message = "the launcher of job \(job.id) left no readable report"
            error(FdtdIssue(.launcherFailed, message + FdtdFigures.exitSuffix(result.exit)))
        }
        return result
    }

    /// The quiet wait of e2e and run: the QUIET helper under the launcher; quiet_wait_timed_out when it ran late.
    func quietWait(_ quiet: FdtdQuiet, backend: any FdtdBackend) throws {
        let collector = FdtdLineCollector()
        guard let result = try spawnJob(.quiet(quiet), backend: backend, onLine: { collector.append($0) }) else {
            return
        }
        let text = collector.all.joined(separator: "\n")
        guard let line = FdtdParsers.taggedJSON(FdtdSnippets.quietTag, in: text, as: FdtdQuietLine.self) else {
            // a stop during the wait ends the command before its run (spawnJob refuses to start it)
            if stop.stopRequested { return }
            let message = "the quiet wait printed no \(FdtdSnippets.quietTag) line"
            throw FdtdError(.toolOutputUnparsed, message + FdtdFigures.exitSuffix(result.exit))
        }
        if line.late {
            let limit = FdtdOptions.formatG(quiet.maxSeconds)
            let level = FdtdOptions.formatG(quiet.percent)
            let message = "others stayed above \(level)% cpu for \(limit) s, so the run started anyway"
            warn(FdtdIssue(.quietWaitTimedOut, message, field: "--quiet-max", hint: "--quiet-max S"))
        }
    }

    /// ab's sampler check: `[PY, -B, -c, LOAD, R/bench, 1]` directly (no DYLD), resolved by `backend` as a refused or
    /// planned envelope records it, and recorded as a sampler-check invocation; its load is valid only when the
    /// sampler saw processes and took GPU samples.
    func samplerCheck(backend: any FdtdBackend) throws -> FdtdLoad {
        let invocation = try backend.resolve(.samplerCheck(), host: "local")
        let index = record(invocation)
        var missing = FdtdLoad(source: .sampler, valid: false)
        if common.dryRun {
            missing.invalidReason = "dry run: the sampler check did not run"
            return missing
        }
        let request = FdtdCaptureRequest(argv: invocation.argv, cwd: invocation.cwd,
                                         environment: invocation.environment, timeoutSeconds: 60)
        let result = context.system.capture(request, stop: stop)
        let stopped = stop.stopRequested
        updateInvocation(index) { entry in
            entry.exit = result.exit
            entry.seconds = result.seconds
            entry.ran = result.ran
            entry.interrupted = stopped
        }
        addToolSeconds(result.seconds)
        guard let line = FdtdParsers.taggedJSON(FdtdSnippets.loadTag, in: result.stdout, as: FdtdLoadLine.self) else {
            missing.invalidReason = "the sampler check printed no \(FdtdSnippets.loadTag) line"
                + FdtdFigures.exitSuffix(result.exit)
            return missing
        }
        return FdtdLoads.fromSampler(line.load, counts: line.counts, thresholds: thresholds)
    }

    /// The plan line: `emskit fdtd: COMMAND ...: ..., run folder PATH`.
    func planLine(_ text: String) { note(text) }

    /// RUN/tool.log as text; empty when it cannot be read.
    func toolLog(_ folder: FdtdRunFolder) -> String {
        context.system.readFile(folder.toolLog).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// `, run folder PATH`, or the planned one in a dry run.
    func runFolderText(_ folder: FdtdRunFolder) -> String {
        common.dryRun ? ", run folder \(folder.path) (dry run: not created)" : ", run folder \(folder.path)"
    }

    /// load_missing for figures shown without a valid load, and loaded_mac when the others went over the marks.
    func loadWarnings(withheld: [String], loaded: [String]) {
        if !withheld.isEmpty {
            let names = withheld.joined(separator: ", ")
            warn(FdtdIssue(.loadMissing, "no valid load during \(names): the figures are withheld",
                           hint: "emskit fdtd load"))
        }
        if !loaded.isEmpty {
            let marks = "cpu > \(FdtdOptions.formatG(common.warnCpu))% or gpu > \(FdtdOptions.formatG(common.warnGpu))%"
            let names = loaded.joined(separator: ", ")
            warn(FdtdIssue(.loadedMac, "others used the Mac (\(marks)) during \(names)", hint: "--quiet 60"))
        }
    }

    /// The status the errors so far give, for the summary line.
    var statusSoFar: String { FdtdExit.status(for: exitSoFar, partial: partial).rawValue }

    /// An output the run wrote (tool.log after each child), recorded once with its current sha256.
    func recordOutput(_ path: String, existedBefore: Bool = false, backup: String? = nil) {
        if let k = envelope.outputs.firstIndex(where: { $0.path == path }) {
            let earlier = envelope.outputs[k]
            envelope.outputs[k] = FdtdOutputs.record(path, existedBefore: earlier.existedBefore,
                                                     backup: earlier.backup ?? backup, system: context.system)
        } else {
            addOutput(FdtdOutputs.record(path, existedBefore: existedBefore, backup: backup, system: context.system))
        }
    }

    /// Copies each existing table next to itself before a tool writes over it (--overwrite), with output_backed_up;
    /// a dry run copies nothing and only plans the backups. Returns the backups by path (none in a dry run).
    func backUpTables(_ paths: [String]) throws -> [String: String] {
        var backups: [String: String] = [:]
        for path in paths where context.system.fileExists(path) {
            guard !common.dryRun else {
                planBackup(path)
                continue
            }
            let kept = try FdtdOutputs.backup(path, mode: .copy, now: context.clock.now(), timeZone: context.timeZone,
                                              system: context.system)
            backups[path] = kept
            warn(FdtdIssue(.outputBackedUp, "the old \(path) is kept as \(kept)"))
        }
        return backups
    }

    /// A dry run's output_backed_up: where --overwrite would keep the old file (spec 10, 16.1 PlanTests).
    func planBackup(_ path: String) {
        let kept = FdtdOutputs.backupPath(path, now: context.clock.now(), timeZone: context.timeZone)
        warn(FdtdIssue(.outputBackedUp, "dry run: the old \(path) would be kept as \(kept)"))
    }

    /// The library and engine of a command whose own Python loads openEMS (validate, e2e, run): ENGINE known (3
    /// engine_unsupported) and listed by the library (3), LIB resolved, and for a library other than the installed
    /// one the probe sent its folder, so that this Python is shown to keep DYLD (3 python_strips_dyld) and to load
    /// the three files from that folder (4 library_not_loaded, before the run: dyld takes the installed copy of a file
    /// it cannot use without a message).
    func scriptLibrary(_ spec: String, engine name: String?) throws -> (library: FdtdLibrary, engine: FdtdEngine?) {
        var engine: FdtdEngine? = nil
        if let name {
            guard let known = FdtdEngine(rawValue: name) else {
                let names = FdtdEngine.allCases.map(\.rawValue)
                throw FdtdError(.engineUnsupported, "engine \(name) is not one of " + names.joined(separator: ", "),
                                field: "--engine", hint: FdtdOptions.nearest(name, among: names))
            }
            engine = known
        }
        let library = try resolveLibrary(spec)
        if spec == "installed" {
            _ = try probePython(dyld: nil, snapshotNeeded: false)
        } else {
            let probe = try probePython(dyld: library.dir, snapshotNeeded: true)
            do {
                try FdtdDiscovery.requireLoaded(probe, from: library.dir, system: context.system)
            } catch let e as FdtdError {
                throw FdtdError(e.issues.map { FdtdIssue($0.code, $0.message, field: "--lib", hint: $0.hint) })
            }
        }
        if let engine { try FdtdLibraries.requireEngine(engine, in: library) }
        return (library, engine)
    }

    /// --knob K=V settings for the child's environment: parsed and validated for this command (2), present in the
    /// library's bytes (3 knob_unsupported), their warnings added for `engine` (nil = the script picks its own).
    func environmentKnobs(_ texts: [String], library: FdtdLibrary, engine: FdtdEngine?) throws -> [FdtdKnobSetting] {
        let settings = try texts.map { try FdtdKnobs.parse($0, field: "--knob") }
        for setting in settings {
            try FdtdKnobs.validate(setting, command: command, transport: .environment, system: context.system)
        }
        try FdtdKnobs.requireSupported(settings, library: library)
        warn(contentsOf: FdtdKnobs.repeated(settings))
        // a value that a later --knob replaced never reaches the engine: only the last one of a name is judged
        let effective = settings.enumerated().filter { k, setting in
            settings.lastIndex(where: { $0.name == setting.name }) == k
        }.map(\.element)
        warn(contentsOf: FdtdKnobs.warnings(effective, engine: engine))
        return settings
    }

    /// debye-check's and diamond-check's zsh pre-probe of a library folder, once per folder, then the three files
    /// from that folder (4 library_not_loaded for either failure: the scripts' zsh → python3 path would not load it).
    func zshPreProbe(_ library: FdtdLibrary) throws {
        let dir = library.dir
        if memo.zshProbed.contains(dir) { return }
        let repo = try discoverRepo()
        let environment = try childEnvironment()
        let started = context.clock.uptime()
        defer { addProbeSeconds(context.clock.uptime() - started) }
        let probe: FdtdProbeResult
        do {
            probe = try FdtdDiscovery.zshPreProbe(libDir: dir, repo: repo.root, environment: environment.environment,
                                                  context: context, stop: stop)
        } catch let e as FdtdError {
            throw FdtdError(e.issues.map { FdtdIssue(.libraryNotLoaded, $0.message, field: "LIB", hint: $0.hint) })
        }
        try FdtdDiscovery.requireLoaded(probe, from: dir, system: context.system)
        memo.zshProbed.insert(dir)
    }

    /// The launcher's whole-run load (its --load sampler) as envelope.load; an invalid one when there is no report.
    func wholeRunLoad(_ report: FdtdLauncherReport?) -> FdtdLoad {
        var load = FdtdLoads.fromSampler(report?.load, counts: report?.loadCounts, thresholds: thresholds)
        if report == nil { load.invalidReason = "the launcher left no report" }
        envelope.load = load
        return load
    }

    // MARK: - Private

    private func rfsimMissing() -> FdtdError {
        let searched = FdtdDiscovery.rfsimSearch(option: common.rfsim, context: context)
        return FdtdError(.rfsimNotFound, "the rfsim toolkit is needed, and none was found: " + searched,
                         field: "--rfsim", hint: "--rfsim DIR, the folder that holds rfsim/")
    }

    /// RFSIM_PATH for the base environment: the probed toolkit, else what discovery finds without probing (a stale
    /// $RFSIM_PATH is left out; an explicit --rfsim that is not a toolkit stops the command).
    private func rfsimPathForChildren() throws -> String? {
        if let rfsim = memo.rfsim { return rfsim.path }
        if memo.rfsimSearched { return nil }
        do {
            return try FdtdDiscovery.findRfsim(option: common.rfsim, context: context)
        } catch let e as FdtdError {
            if common.rfsim != nil { throw e }
            return nil
        }
    }

    private func recordPlanned(_ jobs: [FdtdJob], libraries: [FdtdLibrary], interrupted: Bool) {
        guard let backend = try? localBackend(runFolder: plannedRunFolder(), libraries: libraries) else { return }
        for job in jobs {
            // ab's sampler checks are invocations without a job, as in spawnJob
            if job.role != .samplerCheck { addJob(job) }
            if let invocation = try? backend.resolve(job, host: "local") {
                let index = record(invocation)
                // as spawnJob marks a job that a stop kept from starting
                if interrupted { updateInvocation(index) { $0.interrupted = true } }
            }
        }
    }
}

/// The CLI's own figure texts: percentages, seconds and the load clauses of its stderr lines.
enum FdtdFigures {
    /// `45%`, or `unknown` for a figure the source did not give.
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "unknown" }
        return String(format: "%.0f%%", value == 0 ? 0.0 : value)
    }

    /// `4.1 s`; below 0.1 s in milliseconds (`4.5 ms`), so that a short stage does not read as `0.0 s`.
    static func seconds(_ value: Double) -> String {
        value < 0.1 ? String(format: "%.1f ms", value * 1000) : String(format: "%.1f s", value)
    }

    /// `1702.0`.
    static func mcs(_ value: Double) -> String { String(format: "%.1f", value) }

    /// `others cpu C% gpu G%`.
    static func others(_ load: FdtdLoad) -> String {
        "others cpu \(percent(load.othersCpuPercent)) gpu \(percent(load.othersGpuPercent))"
    }

    /// ` (exit status N)`, or nothing without a status.
    static func exitSuffix(_ exit: Int32?) -> String { exit.map { " (exit status \($0))" } ?? "" }

    /// How an FDTD.Run call stopped, as `probe end after N TS`; nil when no stop line was printed.
    static func stop(_ stop: FdtdRunStop?) -> String? {
        guard let stop else { return nil }
        let after = stop.timesteps.map { " after \($0) TS" } ?? ""
        switch stop.kind {
        case .probeEnd: return "probe end" + after
        case .energy: return "end criteria" + after
        case .maxTimesteps: return "max timesteps" + after
        case .aborted: return "aborted" + after
        }
    }

    /// `others cpu C% gpu G% over the whole run`.
    static func wholeRun(_ load: FdtdLoad) -> String { others(load) + " over the whole run" }

    /// A whole-run load as `others cpu C% gpu G% (gpu dev D%) over S s [busy]`.
    static func loadLine(_ load: FdtdLoad) -> String {
        var text = others(load)
        if let device = load.gpuDevicePercent { text += " (gpu dev \(percent(device)))" }
        if let wall = load.wallSeconds { text += " over " + seconds(wall) }
        if !load.busy.isEmpty { text += " [" + load.busy.joined(separator: ",") + "]" }
        return text
    }
}

/// Per-key counters for the live stderr lines that the pump thread prints (bench and check rows, ab runs).
final class FdtdLiveCounter: Sendable {
    private let counts = Mutex<[String: Int]>([:])

    init() {}

    /// The next number for `key`, from 1.
    func next(_ key: String) -> Int {
        counts.withLock { state in
            let n = (state[key] ?? 0) + 1
            state[key] = n
            return n
        }
    }

    /// Starts `key` again from 1.
    func reset(_ key: String) { counts.withLock { $0[key] = nil } }
}
