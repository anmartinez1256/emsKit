// SPDX-License-Identifier: GPL-3.0-or-later

// Work units and backends (spec 12). A job is logical and serializable: it names libraries by identity and holds no
// host paths except the user's own inputs and outputs. A backend resolves a job for one host into an FdtdInvocation
// (argv, cwd, environment) and runs it. v1 has only the local backend: it resolves the Python, repo, run folder,
// snapshot folders and DYLD of this Mac (the exact invocations of spec 5.2) and runs through Spawn. The family flags
// --nodes/--hosts/--distribute are parsed and recorded; every run happens on this Mac.
import Foundation

/// The tool a job runs.
enum FdtdJobTool: String, Codable, Sendable {
    case bench, abtest, check, validation, debye, diamond, e2e, script, quiet, load
}

/// A library named by identity: its LIB spec and its files' sha256 and LC_UUID.
struct FdtdJobLibrary: Codable, Sendable, Equatable {
    var spec: String
    var files: [FdtdFileIdentity] = []
}

/// One CFG of a bench, ab or check job.
struct FdtdJobConfig: Codable, Sendable, Equatable {
    var library: FdtdJobLibrary
    /// The CFG text as the tool gets it: the labels and run subfolders follow it, and knob order is part of it.
    var cfg: String
    var engine: String
    var threads: Int? = nil
    var nodumps = false
    var knobs: [String: String] = [:]
}

/// A user's input or output file of a job (outputs carry no sha256).
struct FdtdJobFile: Codable, Sendable, Equatable {
    var role: String
    var path: String
    var sha256: String? = nil
}

/// One logical work unit (spec 12); `options` holds the tool's remaining settings as strings (e.g. "quiet": "60").
struct FdtdJob: Codable, Sendable, Equatable {
    var id: String
    var role: FdtdRole
    var tool: FdtdJobTool
    var model: String? = nil
    var scale: Double? = nil
    var nrts: Int? = nil
    var rounds: Int? = nil
    var configs: [FdtdJobConfig] = []
    var knobs: [String: String] = [:]
    var tag: String? = nil
    var options: [String: String] = [:]
    var inputs: [FdtdJobFile] = []
    var outputs: [FdtdJobFile] = []
}

/// What running one invocation gave (spec 12: exit, seconds, host, logPath, report).
struct FdtdJobResult: Sendable {
    var exit: Int32?
    var seconds: Double
    var host: String
    var logPath: String?
    /// The launcher report, when the invocation ran under the launcher and the report could be read.
    var report: FdtdLauncherReport?
    var outcome: FdtdSpawnOutcome
}

/// Resolves jobs for a host and runs them.
protocol FdtdBackend: Sendable {
    /// The argv, cwd and whole environment of `job` on `host` ("local" in v1), as an invocation with ran false.
    func resolve(_ job: FdtdJob, host: String) throws -> FdtdInvocation
    /// Runs a resolved invocation under `control`; `onLine` gets each output line on the pump thread.
    func run(_ invocation: FdtdInvocation, control: FdtdStopController,
             onLine: (@Sendable (String) -> Void)?) throws -> FdtdJobResult
}

extension FdtdBackend {
    /// run without a line callback.
    func run(_ invocation: FdtdInvocation, control: FdtdStopController) throws -> FdtdJobResult {
        try run(invocation, control: control, onLine: nil)
    }
}

/// What the local backend resolves against.
struct FdtdLocalSetup: Sendable, Equatable {
    var python: String
    var repo: String
    /// The created run folder, or the planned one in a dry run.
    var runFolder: FdtdRunFolder
    var snaps: String
    /// LIB spec → folder, for the libraries the command's jobs name.
    var libraryDirs: [String: String] = [:]
    /// rfsim's folder when found (RFSIM_PATH).
    var rfsim: String? = nil
    /// The base child environment (FdtdChildEnv.base).
    var environment: FdtdChildEnvironment
    /// The CLI's cwd (run's scripts run there).
    var cliCwd: String
}

/// v1's only backend: this Mac.
struct FdtdLocalBackend: FdtdBackend {
    var context: FdtdContext
    var setup: FdtdLocalSetup

    /// The exact invocation of spec 5.2 for the job's role: LCH(ROLE) + the tool's argv, cwd, the base environment plus
    /// what the role needs (DYLD only on Python processes the CLI starts directly, never on /bin/zsh), controlPipe for
    /// launcher children.
    func resolve(_ job: FdtdJob, host: String) throws -> FdtdInvocation {
        guard host == "local" else {
            throw FdtdError(.spawnFailed, "job \(job.id): host \(host): v1 runs every job on this Mac",
                            hint: "leave --hosts out")
        }
        if job.role == .samplerCheck {
            // A one-second direct child (spec 5.2): no launcher, no control pipe, no DYLD; recorded without a job id.
            let argv = [setup.python, "-B", "-c", FdtdSnippets.load, benchFolder, job.options["seconds"] ?? "1"]
            let env = setup.environment
            return FdtdInvocation(role: .samplerCheck, argv: argv, cwd: setup.repo, envSet: env.envSet,
                                  envRemoved: env.envRemoved, host: host, environment: env.environment)
        }
        let steps = try plan(for: job)
        let report = setup.runFolder.launcherReport(job.role)
        var argv = FdtdLauncherSource.argvPrefix(python: setup.python, launcher: setup.runFolder.launcher,
                                                 repo: setup.repo, report: report)
        argv += steps.flags
        argv += [steps.mode, "--"]
        argv += steps.command
        let env = steps.environment
        return FdtdInvocation(role: job.role, jobId: job.id, argv: argv, cwd: steps.cwd, envSet: env.envSet,
                              envRemoved: env.envRemoved, host: host, environment: env.environment, controlPipe: true)
    }

    /// context.system.spawn with tool.log and the CLI's stderr as echo, then the launcher report (JSON5) when the
    /// invocation ran under the launcher.
    func run(_ invocation: FdtdInvocation, control: FdtdStopController,
             onLine: (@Sendable (String) -> Void)?) throws -> FdtdJobResult {
        let log = setup.runFolder.toolLog
        let reportPath = invocation.controlPipe ? Self.launcherReportPath(in: invocation.argv) : nil
        if let reportPath, context.system.fileExists(reportPath) {
            // A report left by an earlier child of the same role must not stand in for this one's.
            try? context.system.removeItem(reportPath)
        }
        if let tmp = invocation.envSet["TMPDIR"], !context.system.isDirectory(tmp) {
            // The check scripts' mktemp -d needs RUN/tmp. It is made here, not in resolve: a dry run creates
            // nothing.
            do {
                try context.system.createDirectories(tmp)
            } catch {
                let outcome = FdtdSpawnOutcome(spawnError: "cannot create TMPDIR \(tmp): \(error)")
                return FdtdJobResult(exit: nil, seconds: 0, host: invocation.host, logPath: log, report: nil,
                                     outcome: outcome)
            }
        }
        let request = FdtdSpawnRequest(invocation: invocation, logPath: log, echo: context.stderr, onLine: onLine)
        let outcome = context.system.spawn(request, stop: control)
        var report: FdtdLauncherReport? = nil
        if let reportPath, outcome.spawnError == nil, let data = context.system.readFile(reportPath) {
            report = try? FdtdParsers.launcherReport(data)
        }
        return FdtdJobResult(exit: outcome.exit, seconds: outcome.seconds, host: invocation.host, logPath: log,
                             report: report, outcome: outcome)
    }

    /// The launcher part of an invocation (its flags and mode) and the tool's argv, cwd and environment.
    private struct Plan {
        var flags: [String] = []
        var mode: String
        var command: [String]
        var cwd: String
        var environment: FdtdChildEnvironment
    }

    private func plan(for job: FdtdJob) throws -> Plan {
        switch job.tool {
        case .bench:
            return try benchPlan(job)
        case .abtest:
            return try abPlan(job)
        case .check:
            return try checkPlan(job)
        case .validation:
            return try validationPlan(job)
        case .debye:
            return try debyePlan(job)
        case .diamond:
            return try diamondPlan(job)
        case .e2e:
            return try e2ePlan(job)
        case .script:
            return try scriptPlan(job)
        case .quiet:
            return try quietPlan(job)
        case .load:
            return loadPlan(job)
        }
    }

    /// bench.py in exec mode; bench sets each config's DYLD itself, so the launcher gets none.
    private func benchPlan(_ job: FdtdJob) throws -> Plan {
        let model = try required(job.model, "a model", job)
        let nrts = try required(job.nrts, "a time step count", job)
        let configs = try configTexts(job)
        var command = [setup.python, "-W", "ignore", FdtdPaths.join(benchFolder, "bench.py"), model]
        command += ["--nrts", String(nrts), "--scale", FdtdOptions.formatG(job.scale ?? 1), "--configs"]
        command += configs
        command += ["--runs", setup.runFolder.runs, "--repeat", job.options["repeat"] ?? "1"]
        if let quiet = job.options["quiet"] {
            command += ["--quiet", quiet, "--quiet-gpu", job.options["quietGpu"] ?? "10"]
            command += ["--quiet-max", job.options["quietMax"] ?? "900"]
        }
        if job.options["noSparams"] == "1" {
            command.append("--no-sparams")
        }
        if let tag = job.tag {
            let results = output(job, "results") ?? FdtdPaths.join(setup.repo, "results")
            command += ["--tag", tag, "--out", results]
        }
        let env = setup.environment.adding(["OPENEMS_BENCH_SNAPS": setup.snaps])
        return Plan(mode: "exec", command: command, cwd: setup.repo, environment: env)
    }

    /// abtest.py in exec mode; the record defaults to RUN/abtest.txt.
    private func abPlan(_ job: FdtdJob) throws -> Plan {
        let model = try required(job.model, "a model", job)
        let nrts = try required(job.nrts, "a time step count", job)
        let configs = try configTexts(job)
        let record = output(job, "record") ?? setup.runFolder.abRecord
        var command = [setup.python, "-W", "ignore", FdtdPaths.join(benchFolder, "abtest.py"), model]
        command += ["--scale", FdtdOptions.formatG(job.scale ?? 1), "--nrts", String(nrts)]
        command += ["--rounds", String(job.rounds ?? 5), "--configs"]
        command += configs
        command += ["--runs", setup.runFolder.runs, "--out", record]
        if let quiet = job.options["quiet"] {
            command += ["--quiet", quiet, "--quiet-max", job.options["quietMax"] ?? "900"]
        }
        if let redo = job.options["redo"] {
            command += ["--redo", redo]
        } else if let redo = job.options["runRedo"] {
            command += ["--run-redo", redo]
        }
        let env = setup.environment.adding(["OPENEMS_BENCH_SNAPS": setup.snaps])
        return Plan(mode: "exec", command: command, cwd: setup.repo, environment: env)
    }

    /// check.sh under /bin/zsh (no DYLD); a snapshot name stays a name, so bench's labels keep it.
    private func checkPlan(_ job: FdtdJob) throws -> Plan {
        let tag = try required(job.tag, "a tag", job)
        guard !job.configs.isEmpty else {
            throw FdtdError(.spawnFailed, "job \(job.id) (check) names no snapshot")
        }
        var command = ["/bin/zsh", "-f", FdtdPaths.join(benchFolder, "check.sh"), tag]
        for config in job.configs {
            let snapshot = try snapshotArgument(config.library.spec)
            command.append(snapshot)
        }
        var values = ["OPENEMS_BENCH_RUNS": setup.runFolder.runs, "OPENEMS_BENCH_SNAPS": setup.snaps]
        if let stock = job.options["stock"] {
            let reference = try snapshotArgument(stock)
            values["STOCK"] = reference
        }
        if job.options["lite"] == "1" {
            values["LITE"] = "1"
        }
        if let extra = job.options["extra"], !extra.isEmpty {
            values["EXTRA"] = extra
        }
        if let quietMax = job.options["quietMax"] {
            values["QUIET_MAX"] = quietMax
        }
        let env = setup.environment.adding(values).forZsh
        return Plan(mode: "exec", command: command, cwd: setup.repo, environment: env)
    }

    /// The validation suite in script mode with --load; without a tag the run stamp names its files.
    private func validationPlan(_ job: FdtdJob) throws -> Plan {
        let tag = job.tag ?? runStamp
        let out = output(job, "out") ?? setup.runFolder.validation
        var command = [FdtdPaths.join(benchFolder, "validation/run_validation.py")]
        command += ["--work", setup.runFolder.validationWork, "--out", out, "--tag", tag]
        if job.options["quick"] == "1" {
            command.append("--quick")
        }
        let cases = words(job.options["cases"])
        if !cases.isEmpty {
            command.append("--cases")
            command += cases
        }
        var values = try pythonValues(job)
        if let engine = job.options["engine"] {
            values["VALIDATION_ENGINE"] = engine
        }
        if let threads = job.options["threads"] {
            values["VALIDATION_THREADS"] = threads
        }
        let env = setup.environment.adding(values)
        return Plan(flags: ["--load"], mode: "script", command: command, cwd: setup.runFolder.path, environment: env)
    }

    /// debye_check.sh LIBDIR [REFDIR] under /bin/zsh; the script sets DYLD itself for each python3.
    private func debyePlan(_ job: FdtdJob) throws -> Plan {
        guard let library = job.configs.first?.library else {
            throw FdtdError(.spawnFailed, "job \(job.id) (debye) names no library")
        }
        var command = ["/bin/zsh", "-f", FdtdPaths.join(setup.repo, "scripts/checks/debye_check.sh")]
        let folder = try libraryFolder(library.spec)
        command.append(folder)
        if job.configs.count > 1 {
            let reference = try libraryFolder(job.configs[1].library.spec)
            command.append(reference)
        }
        var values = ["TMPDIR": setup.runFolder.tmp]
        if let threads = job.options["threads"] {
            values["THREADS"] = threads
        }
        let env = setup.environment.adding(values).forZsh
        return Plan(flags: ["--load"], mode: "exec", command: command, cwd: setup.runFolder.path, environment: env)
    }

    /// diamond_check.sh LIBDIR under /bin/zsh.
    private func diamondPlan(_ job: FdtdJob) throws -> Plan {
        guard let library = job.configs.first?.library else {
            throw FdtdError(.spawnFailed, "job \(job.id) (diamond) names no library")
        }
        let folder = try libraryFolder(library.spec)
        let command = ["/bin/zsh", "-f", FdtdPaths.join(setup.repo, "scripts/checks/diamond_check.sh"), folder]
        let env = setup.environment.adding(["TMPDIR": setup.runFolder.tmp]).forZsh
        return Plan(flags: ["--load"], mode: "exec", command: command, cwd: setup.runFolder.path, environment: env)
    }

    /// run_one.py MODEL FLOOR DB HOLD OUTDIR in script mode with --load --calls.
    private func e2ePlan(_ job: FdtdJob) throws -> Plan {
        let model = try required(job.model, "a model", job)
        let floor = try required(job.options["floor"], "a mesh floor", job)
        let db = try required(job.options["db"], "a probe-end level", job)
        let hold = try required(job.options["hold"], "a hold", job)
        let out = output(job, "out") ?? setup.runFolder.e2e
        var command = [FdtdPaths.join(setup.repo, "scripts/e2e/run_one.py"), model]
        command += [floor, db, hold, out]
        var values = try pythonValues(job)
        if let engine = job.options["engine"] {
            values["E2E_ENGINE"] = engine
        }
        if setup.environment.environment["RFSIM_PATH"] == nil {
            guard let rfsim = setup.rfsim else {
                throw FdtdError(.rfsimNotFound, "e2e needs the rfsim toolkit and none was found", field: "--rfsim",
                                hint: "--rfsim DIR")
            }
            values["RFSIM_PATH"] = rfsim
        }
        let env = setup.environment.adding(values)
        return Plan(flags: ["--load", "--calls"], mode: "script", command: command, cwd: setup.runFolder.path,
                    environment: env)
    }

    /// The user's script in script mode with --load --calls and the injected options, in the CLI's cwd.
    private func scriptPlan(_ job: FdtdJob) throws -> Plan {
        guard let script = job.inputs.first(where: { $0.role == "script" }) else {
            throw FdtdError(.spawnFailed, "job \(job.id) (script) names no script")
        }
        var flags = ["--load", "--calls"]
        if let engine = job.options["engine"] {
            flags += ["--engine", engine]
        }
        if let threads = job.options["threads"] {
            flags += ["--threads", threads]
        }
        if job.options["nodumps"] == "1" {
            flags.append("--nodumps")
        }
        let path = FdtdPaths.absolute(script.path, cwd: setup.cliCwd, home: context.home)
        let arguments = try scriptArguments(job)
        let values = try pythonValues(job)
        let env = setup.environment.adding(values)
        return Plan(flags: flags, mode: "script", command: [path] + arguments, cwd: setup.cliCwd, environment: env)
    }

    /// bench.wait_quiet under the launcher (exec mode, no DYLD).
    private func quietPlan(_ job: FdtdJob) throws -> Plan {
        let percent = try required(job.options["percent"], "a quiet percentage", job)
        var command = [setup.python, "-B", "-c", FdtdSnippets.quiet, benchFolder, percent]
        command += [job.options["maxSeconds"] ?? "900", job.options["gpuPercent"] ?? "10"]
        return Plan(mode: "exec", command: command, cwd: setup.repo, environment: setup.environment)
    }

    /// One usage.Sampler over S seconds under the launcher (exec mode, no DYLD).
    private func loadPlan(_ job: FdtdJob) -> Plan {
        let command = [setup.python, "-B", "-c", FdtdSnippets.load, benchFolder, job.options["seconds"] ?? "5"]
        return Plan(mode: "exec", command: command, cwd: setup.repo, environment: setup.environment)
    }

    private var benchFolder: String { FdtdPaths.join(setup.repo, "bench") }

    /// The run folder's `yyyyMMdd-HHmmss` (its leaf starts with it).
    private var runStamp: String { String(FdtdPaths.basename(setup.runFolder.path).prefix(15)) }

    private func required<T>(_ value: T?, _ what: String, _ job: FdtdJob) throws -> T {
        guard let value else {
            throw FdtdError(.spawnFailed, "job \(job.id) (\(job.tool.rawValue)) lacks \(what)")
        }
        return value
    }

    private func configTexts(_ job: FdtdJob) throws -> [String] {
        guard !job.configs.isEmpty else {
            throw FdtdError(.spawnFailed, "job \(job.id) (\(job.tool.rawValue)) has no config")
        }
        return job.configs.map(\.cfg)
    }

    private func output(_ job: FdtdJob, _ role: String) -> String? {
        job.outputs.first { $0.role == role }?.path
    }

    private func words(_ text: String?) -> [String] {
        (text ?? "").split(separator: " ").map(String.init)
    }

    /// A LIB spec's folder: the resolved one, else SNAPS/NAME or the path made absolute (spec 4.1).
    private func libraryFolder(_ spec: String) throws -> String {
        if let dir = setup.libraryDirs[spec] {
            return dir
        }
        if spec == "installed" {
            throw FdtdError(.libraryNotFound, "installed: the installed library's folder was not resolved",
                            field: "LIB")
        }
        if spec.contains("/") {
            return FdtdPaths.absolute(spec, cwd: setup.cliCwd, home: context.home)
        }
        return FdtdPaths.join(setup.snaps, spec)
    }

    /// check.sh's SNAP or STOCK for a LIB: a snapshot name as it is (bench finds it under OPENEMS_BENCH_SNAPS and its
    /// labels keep it), the library's folder for `installed` and a path. The one rule for both sides: CheckCommand
    /// predicts the bench labels and run subfolders by it (folder: the library's dir), checkPlan builds check.sh's
    /// arguments by it (folder: libraryFolder, which gives that same dir for a library the backend was handed).
    static func checkArgument(spec: String, folder: (String) throws -> String) rethrows -> String {
        if spec == "installed" || spec.contains("/") {
            return try folder(spec)
        }
        return spec
    }

    private func snapshotArgument(_ spec: String) throws -> String {
        try Self.checkArgument(spec: spec, folder: libraryFolder)
    }

    /// The knobs and, for a library other than the installed one, DYLD_LIBRARY_PATH: the launcher in script mode
    /// imports openEMS itself, so it is the Python process that needs them.
    private func pythonValues(_ job: FdtdJob) throws -> [String: String] {
        var values = job.knobs
        let spec = job.configs.first?.library.spec ?? "installed"
        if spec != "installed" {
            values["DYLD_LIBRARY_PATH"] = try libraryFolder(spec)
        }
        return values
    }

    private func scriptArguments(_ job: FdtdJob) throws -> [String] {
        guard let text = job.options["args"] else {
            return []
        }
        guard let arguments = FdtdJob.arguments(fromText: text) else {
            throw FdtdError(.spawnFailed, "job \(job.id) (script): options.args is not a JSON array of strings")
        }
        return arguments
    }

    /// The `--report` value of a launcher argv: it comes before the `--` that starts the tool's own argv.
    private static func launcherReportPath(in argv: [String]) -> String? {
        let end = argv.firstIndex(of: "--") ?? argv.endIndex
        guard let i = argv[..<end].firstIndex(of: "--report"), i + 1 < end else {
            return nil
        }
        return argv[i + 1]
    }
}

/// The distribution flags (spec 12).
enum FdtdDistributions {
    /// The record and its warnings: distribute_local ("--nodes N: multi-Mac execution is designed but not implemented;
    /// running on this Mac", likewise for --hosts and --distribute domain), frequencies_not_applicable. `hostsPath`
    /// (absolute) must name a file (2 hosts_file_missing).
    static func record(_ common: FdtdCommonOptions, command: FdtdCommandName, hostsPath: String?,
                       system: any FdtdSystem, warnings: inout [FdtdIssue]) throws -> FdtdDistribution {
        if let hostsPath {
            if !system.fileExists(hostsPath) {
                throw FdtdError(.hostsFileMissing, "--hosts \(hostsPath) does not exist", field: "--hosts",
                                hint: "leave --hosts out")
            }
            if !system.isRegularFile(hostsPath) {
                throw FdtdError(.hostsFileMissing, "--hosts \(hostsPath) is not a file", field: "--hosts",
                                hint: "leave --hosts out")
            }
        }
        let local = "multi-Mac execution is designed but not implemented; running on this Mac"
        if let nodes = common.nodes, nodes > 1 {
            warnings.append(FdtdIssue(.distributeLocal, "--nodes \(nodes): \(local)", field: "--nodes"))
        }
        if let hostsPath {
            warnings.append(FdtdIssue(.distributeLocal, "--hosts \(hostsPath): \(local)", field: "--hosts"))
        }
        switch common.distribute {
        case .domain:
            warnings.append(FdtdIssue(.distributeLocal, "--distribute domain: \(local)", field: "--distribute"))
        case .frequencies:
            let message = "one FDTD run covers the whole band in the time domain; nothing to split by frequency; "
                + "running on this Mac"
            warnings.append(FdtdIssue(.frequenciesNotApplicable, message, field: "--distribute"))
        case .auto, .off:
            break
        }
        return FdtdDistribution(requested: common.distribute.rawValue, mode: "off", nodes: 1, hosts: hostsPath,
                                reason: reason(command))
    }

    /// The record's reason, e.g. "bench measures this Mac only".
    static func reason(_ command: FdtdCommandName) -> String {
        switch command {
        case .info:
            return "info describes this Mac"
        case .load:
            return "load measures this Mac only"
        case .bench:
            return "bench measures this Mac only"
        case .ab:
            return "ab measures this Mac only"
        case .check, .validate, .debyeCheck, .diamondCheck, .e2e, .run:
            return "v1 runs every job on this Mac; multi-Mac execution is designed but not implemented"
        }
    }
}

// MARK: - Building jobs

extension FdtdJobLibrary {
    /// A resolved library by identity: its LIB spec and its three files' sha256 and LC_UUID.
    static func identity(of library: FdtdLibrary) -> FdtdJobLibrary {
        let files = library.files.map { FdtdFileIdentity(name: $0.name, sha256: $0.sha256, uuid: $0.uuid) }
        return FdtdJobLibrary(spec: library.spec, files: files)
    }
}

extension FdtdJobConfig {
    /// A bench or ab CFG with its library's identity; `cfg` is the text bench gets.
    static func bench(_ config: FdtdBenchConfig, library: FdtdLibrary) -> FdtdJobConfig {
        FdtdJobConfig(library: .identity(of: library), cfg: config.text, engine: config.engine.rawValue,
                      threads: config.threads, nodumps: config.nodumps, knobs: FdtdKnobs.environment(config.knobs))
    }

    /// The library of a check, validation, debye, diamond, e2e or script job; `engine` and `threads` are what the
    /// job asks for (informational: the backend reads the job's options).
    static func forLibrary(_ library: FdtdLibrary, engine: String, threads: Int? = nil,
                           nodumps: Bool = false) -> FdtdJobConfig {
        FdtdJobConfig(library: .identity(of: library), cfg: library.spec, engine: engine, threads: threads,
                      nodumps: nodumps)
    }
}

/// The jobs of each command in the form FdtdLocalBackend.resolve reads (spec 5.2). Libraries are `configs` (a check
/// job's in SNAP order; debye's second one is --ref). The tool settings are strings in `options`: bench repeat,
/// quiet, quietGpu, quietMax, noSparams ("1"); ab quiet, quietMax, redo or runRedo; check stock (a LIB spec), lite
/// ("1"), extra (the CFG texts joined by spaces), quietMax; validation engine, threads, quick ("1"), cases (joined by
/// spaces); debye threads; e2e floor, db, hold (as run_one.py gets them), engine; script args (a JSON array), engine,
/// threads, nodumps ("1"); quiet percent, gpuPercent, maxSeconds; load seconds. A setting is present only when
/// given. Named outputs are `outputs` by role (bench "results", ab "record", validation and e2e "out"); run's
/// script is the input "script".
extension FdtdJob {
    static func bench(id: String = "bench-1", run: FdtdModelRun, configs: [FdtdJobConfig], repeatCount: Int = 1,
                      quiet: FdtdQuiet? = nil, noSparams: Bool = false, tag: String? = nil,
                      results: String? = nil) -> FdtdJob {
        var job = FdtdJob(id: id, role: .bench, tool: .bench, model: run.model.rawValue, scale: run.scale,
                          nrts: run.nrts, configs: configs, tag: tag)
        job.options["repeat"] = String(repeatCount)
        if let quiet {
            job.options["quiet"] = optionText(quiet.percent)
            job.options["quietGpu"] = optionText(quiet.gpuPercent)
            job.options["quietMax"] = optionText(quiet.maxSeconds)
        }
        if noSparams {
            job.options["noSparams"] = "1"
        }
        if tag != nil, let results {
            job.outputs.append(FdtdJobFile(role: "results", path: results))
        }
        return job
    }

    static func ab(id: String = "ab-1", run: FdtdModelRun, configs: [FdtdJobConfig], rounds: Int = 5,
                   quiet: FdtdQuiet? = nil, redo: Int? = nil, runRedo: Int? = nil, record: String? = nil) -> FdtdJob {
        var job = FdtdJob(id: id, role: .ab, tool: .abtest, model: run.model.rawValue, scale: run.scale, nrts: run.nrts,
                          rounds: rounds, configs: configs)
        if let quiet {
            job.options["quiet"] = optionText(quiet.percent)
            job.options["quietMax"] = optionText(quiet.maxSeconds)
        }
        if let redo {
            job.options["redo"] = String(redo)
        }
        if let runRedo {
            job.options["runRedo"] = String(runRedo)
        }
        if let record {
            job.outputs.append(FdtdJobFile(role: "record", path: record))
        }
        return job
    }

    static func check(id: String = "check-1", tag: String, snapshots: [FdtdLibrary], stock: String? = nil,
                      lite: Bool = false, extras: [String] = [], quietMax: Double? = nil) -> FdtdJob {
        let configs = snapshots.map { FdtdJobConfig.forLibrary($0, engine: FdtdEngine.multithreaded.rawValue) }
        var job = FdtdJob(id: id, role: .check, tool: .check, configs: configs, tag: tag)
        if let stock {
            job.options["stock"] = stock
        }
        if lite {
            job.options["lite"] = "1"
        }
        if !extras.isEmpty {
            job.options["extra"] = extras.joined(separator: " ")
        }
        if let quietMax {
            job.options["quietMax"] = optionText(quietMax)
        }
        return job
    }

    static func validation(id: String = "validate-1", library: FdtdLibrary, engine: String? = nil, threads: Int? = nil,
                           quick: Bool = false, cases: [String] = [], knobs: [String: String] = [:], tag: String,
                           out: String? = nil) -> FdtdJob {
        let config = FdtdJobConfig.forLibrary(library, engine: engine ?? FdtdEngine.fastest.rawValue, threads: threads)
        var job = FdtdJob(id: id, role: .validate, tool: .validation, configs: [config], knobs: knobs, tag: tag)
        if let engine {
            job.options["engine"] = engine
        }
        if let threads {
            job.options["threads"] = String(threads)
        }
        if quick {
            job.options["quick"] = "1"
        }
        if !cases.isEmpty {
            job.options["cases"] = cases.joined(separator: " ")
        }
        if let out {
            job.outputs.append(FdtdJobFile(role: "out", path: out))
        }
        return job
    }

    static func debye(id: String = "debye-1", library: FdtdLibrary, reference: FdtdLibrary? = nil,
                      threads: Int? = nil) -> FdtdJob {
        var configs = [FdtdJobConfig.forLibrary(library, engine: FdtdEngine.multithreaded.rawValue, threads: threads)]
        if let reference {
            configs.append(FdtdJobConfig.forLibrary(reference, engine: FdtdEngine.sseCompressed.rawValue))
        }
        var job = FdtdJob(id: id, role: .debye, tool: .debye, configs: configs)
        if let threads {
            job.options["threads"] = String(threads)
        }
        return job
    }

    static func diamond(id: String = "diamond-1", library: FdtdLibrary) -> FdtdJob {
        let config = FdtdJobConfig.forLibrary(library, engine: FdtdEngine.metalDiamond.rawValue)
        return FdtdJob(id: id, role: .diamond, tool: .diamond, configs: [config])
    }

    /// `floor`, `db` and `hold` are run_one.py's arguments as text: FLOOR "0" for the toolkit default, DB "off" or %g.
    static func e2e(id: String = "e2e-1", model: FdtdE2EModel, library: FdtdLibrary, engine: String? = nil,
                    floor: String, db: String, hold: String, knobs: [String: String] = [:],
                    outDir: String? = nil) -> FdtdJob {
        let config = FdtdJobConfig.forLibrary(library, engine: engine ?? FdtdEngine.fastest.rawValue)
        var job = FdtdJob(id: id, role: .e2e, tool: .e2e, model: model.rawValue, configs: [config], knobs: knobs)
        job.options["floor"] = floor
        job.options["db"] = db
        job.options["hold"] = hold
        if let engine {
            job.options["engine"] = engine
        }
        if let outDir {
            job.outputs.append(FdtdJobFile(role: "out", path: outDir))
        }
        return job
    }

    /// run's job: `path` is the script's absolute path, `sha256` its bytes' hash.
    static func script(id: String = "run-1", path: String, sha256: String? = nil, arguments: [String] = [],
                       library: FdtdLibrary, engine: String? = nil, threads: Int? = nil, nodumps: Bool = false,
                       knobs: [String: String] = [:]) -> FdtdJob {
        let engineName = engine ?? FdtdEngine.fastest.rawValue
        let config = FdtdJobConfig.forLibrary(library, engine: engineName, threads: threads, nodumps: nodumps)
        let input = FdtdJobFile(role: "script", path: path, sha256: sha256)
        var job = FdtdJob(id: id, role: .run, tool: .script, configs: [config], knobs: knobs, inputs: [input])
        if !arguments.isEmpty {
            job.options["args"] = argumentsText(arguments)
        }
        if let engine {
            job.options["engine"] = engine
        }
        if let threads {
            job.options["threads"] = String(threads)
        }
        if nodumps {
            job.options["nodumps"] = "1"
        }
        return job
    }

    static func quiet(id: String = "quiet-1", _ quiet: FdtdQuiet) -> FdtdJob {
        var job = FdtdJob(id: id, role: .quiet, tool: .quiet)
        job.options["percent"] = optionText(quiet.percent)
        job.options["gpuPercent"] = optionText(quiet.gpuPercent)
        job.options["maxSeconds"] = optionText(quiet.maxSeconds)
        return job
    }

    static func load(id: String = "load-1", seconds: Double) -> FdtdJob {
        var job = FdtdJob(id: id, role: .load, tool: .load)
        job.options["seconds"] = optionText(seconds)
        return job
    }

    /// ab's one-second sampler check; resolve gives it no launcher and no job id.
    static func samplerCheck(id: String = "sampler-check") -> FdtdJob {
        var job = FdtdJob(id: id, role: .samplerCheck, tool: .load)
        job.options["seconds"] = "1"
        return job
    }

    /// A number as the tools' float() reads it; integral values without a fraction ("60", "0.5").
    static func optionText(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    /// run's ARGS as options["args"]: a JSON array of strings.
    static func argumentsText(_ arguments: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(arguments) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// options["args"] read back; nil when it is not a JSON array of strings.
    static func arguments(fromText text: String) -> [String]? {
        try? JSONDecoder().decode([String].self, from: Data(text.utf8))
    }
}
