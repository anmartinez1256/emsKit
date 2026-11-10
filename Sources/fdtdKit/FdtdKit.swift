// SPDX-License-Identifier: GPL-3.0-or-later

// fdtdKit: `emskit fdtd`, the command line over the emsKit tools (spec section 2). This file holds the dispatch,
// --version/--help, the two usage-error paths, the session every command fills, and the error-to-exit mapping with
// its precedence (section 9). The commands themselves are in Commands/*.swift.
import Foundation

/// fdtdKit's version, as `--version` and every envelope print it.
public enum FdtdKitInfo {
    public static let version = "0.1.0"
}

/// An error that ends a command. Its issues go to the envelope's `errors`; their codes decide the exit (FdtdExit).
/// Modules throw only this type; anything else that escapes a command becomes tool_failed.
struct FdtdError: Error, Sendable, CustomStringConvertible {
    var issues: [FdtdIssue]

    init(_ issue: FdtdIssue) { issues = [issue] }
    init(_ issues: [FdtdIssue]) { self.issues = issues }
    init(_ code: FdtdCode, _ message: String, field: String? = nil, hint: String? = nil) {
        issues = [FdtdIssue(code, message, field: field, hint: hint)]
    }

    var exitCode: Int32 { FdtdExit.combine(issues.map(\.code), interrupted: false) }
    var description: String { issues.map(\.description).joined(separator: "; ") }
}

extension FdtdCode {
    /// The exit of an error with this code (spec 9); nil for the codes that are only warnings.
    var exitCode: Int32? {
        switch self {
        case .usage: 64
        case .repoNotFound, .toolMissing, .libraryNotFound, .libraryIncomplete, .configInvalid, .knobUnknown, .knobValue,
             .knobNotAllowed, .rfsimNotFound, .scriptNotFound, .folderMissing, .hostsFileMissing, .tagInvalid,
             .protectedPath: 2
        case .engineUnsupported, .knobUnsupported, .libraryLacksFeature, .pythonNotFound, .pythonStripsDyld,
             .pythonNoOpenems, .pythonNameMismatch: 3
        case .toolFailed, .toolOutputUnparsed, .engineNotConfirmed, .libraryNotLoaded, .verdictDisagrees, .spawnFailed,
             .launcherFailed, .loadUnavailable: 4
        case .mismatch, .notExact, .checkFailed, .validationFailed, .scriptCheckFailed, .scriptFailed: 1
        case .simulationRunning, .concurrencyUnknown, .wouldOverwrite: 5
        case .interrupted: 130
        default: nil
        }
    }
}

/// Exit codes, their precedence and the status each gives (spec 9).
enum FdtdExit {
    /// Strongest first: 64 > 2 > 3 > 5 > 4 > 1 > 0, with 130 placed so that a signal replaces 4 and 1 (and 0: a run
    /// that was asked to stop is not reported as ok).
    static let precedence: [Int32] = [64, 2, 3, 5, 130, 4, 1, 0]

    static func rank(_ exit: Int32) -> Int { precedence.firstIndex(of: exit) ?? precedence.firstIndex(of: 4)! }

    /// The exit for the error codes of a command; `interrupted` adds 130.
    static func combine(_ codes: [FdtdCode], interrupted: Bool) -> Int32 {
        var exits = codes.compactMap(\.exitCode)
        if interrupted { exits.append(130) }
        return exits.min { rank($0) < rank($1) } ?? 0
    }

    static func status(for exit: Int32, partial: Bool) -> FdtdStatus {
        switch exit {
        case 0: partial ? .partial : .ok
        case 1: .fail
        case 5: .refused
        case 130: .interrupted
        default: .error
        }
    }
}

/// One entry of the command table: its typed options and its body (Commands/*.swift). The body fills `session` in the
/// order parse, discover, build jobs, refusals, resolve and spawn, parse output, verdict, and throws FdtdError to stop.
/// FdtdCLI.finish turns whatever it left into the envelope and the exit.
protocol FdtdCommandBody {
    associatedtype Options: Sendable
    static var name: FdtdCommandName { get }
    static func run(_ options: Options, session: FdtdSession) throws
}

/// Everything one command invocation builds up. It lives on the dispatcher's thread only and is not Sendable:
/// closures that run elsewhere (the spawn pump, timers, the signal handler) capture `context` or `stop`, never it.
final class FdtdSession {
    let context: FdtdContext
    let command: FdtdCommandName
    let arguments: [String]
    /// Turns signals into stop requests for the running children (Spawn.swift).
    let stop: FdtdStopController
    let startedAt: Date
    private let startUptime: Double
    private(set) var common = FdtdCommonOptions()
    var envelope: FdtdEnvelope
    /// Exit 0 counts as partial (check with --allow-partial, or a reference that is not stock).
    var partial = false
    /// Set once the run folder exists (run commands, never with --dry-run). finish() cleans it after ok or partial
    /// unless --keep-runs.
    var runFolder: FdtdRunFolder? { didSet { envelope.runFolder = runFolder?.path } }
    /// The LIBs that the line names, as given, set by begin(): a path among them that is a folder is protected.
    private(set) var lineLibraries: [String] = []
    /// The absolute `--output FILE`, set once begin() has checked it.
    private(set) var outputPath: String?
    /// Caches of the shared steps (Commands/CommandSupport.swift).
    var memo = FdtdSessionMemo()
    private var probeSeconds = 0.0
    private var toolSeconds = 0.0

    init(context: FdtdContext, command: FdtdCommandName, arguments: [String]) {
        self.context = context
        self.command = command
        self.arguments = arguments
        stop = FdtdStopController(clock: context.clock, control: context.system.processControl)
        startedAt = context.clock.now()
        startUptime = context.clock.uptime()
        envelope = FdtdEnvelope(command: command, arguments: arguments)
    }

    /// Takes the parsed common options and refuses a `--output` in or as a protected folder, or one that holds one (2
    /// protected_path: finish() renames an existing file away and writes the envelope in its place), one that is a
    /// folder (64: --overwrite would rename the whole folder away), one that exists (5, unless --overwrite) or whose
    /// folder is missing (2), before anything runs. Only a line that parsed gets here: one that did not writes no
    /// file (FdtdCLI.run). `libraries`: the LIBs of the line as given (FdtdCommandOptions.librarySpecs); the folders
    /// among them are protected from here on.
    func begin(_ common: FdtdCommonOptions, libraries: [String] = []) throws {
        self.common = common
        lineLibraries = libraries
        envelope.dryRun = common.dryRun
        guard let out = common.output else { return }
        let path = absolutePath(out)
        try refuseProtected(replacedTargets(path, label: "--output", field: "--output"))
        try requireFile(path, option: "--output", example: "envelope.json")
        if context.system.fileExists(path), !common.overwrite {
            throw FdtdError(.wouldOverwrite, "--output \(path) exists", field: "--output",
                            hint: "another FILE, or --overwrite (the old file is kept next to it)")
        }
        outputPath = path
    }

    /// The checks of a FILE that an option names for writing (--output, ab's --record): a folder is a usage error
    /// (64; --overwrite would rename all of it away, and a tool cannot open it), and its folder must exist (2).
    func requireFile(_ path: String, option: String, example: String) throws {
        if context.system.isDirectory(path) {
            throw FdtdOptions.usage("\(option) \(path) is a folder; \(option) takes a FILE", field: option,
                                    hint: "a file name inside it, e.g. \(FdtdPaths.join(path, example))")
        }
        guard context.system.isDirectory(FdtdPaths.dirname(path)) else {
            throw FdtdError(.folderMissing, "the folder of \(option) \(path) does not exist", field: option)
        }
    }

    /// finish()'s second look at `--output`, after the tools ran and before it renames or writes it: a folder on its
    /// path can have become a link into a protected folder meanwhile. Refused, the file is left alone (2
    /// protected_path), the run folder is kept and the envelope goes to stdout.
    fileprivate func recheckOutput() {
        guard let path = outputPath else { return }
        do {
            try refuseProtected(replacedTargets(path, label: "--output", field: "--output"))
        } catch let e as FdtdError {
            error(contentsOf: e.issues)
            outputPath = nil
        } catch {
            self.error(FdtdIssue(.toolFailed, "unexpected error: \(error)"))
            outputPath = nil
        }
    }

    /// A user-given path made absolute against the CLI's cwd (`~` expanded, `.` and `..` folded).
    func absolutePath(_ path: String) -> String { FdtdPaths.absolute(path, cwd: context.cwd, home: context.home) }

    /// The --warn-cpu / --warn-gpu marks for every load of this command.
    var thresholds: FdtdThresholds { FdtdThresholds(warnCpu: common.warnCpu, warnGpu: common.warnGpu) }

    /// Adds a warning (once) and prints its stderr line.
    func warn(_ issue: FdtdIssue) {
        guard !envelope.warnings.contains(issue) else { return }
        envelope.warnings.append(issue)
        context.stderr.line(issue.stderrLine)
    }

    func warn(contentsOf issues: [FdtdIssue]) {
        for issue in issues { warn(issue) }
    }

    /// Adds an error that does not stop the command (a verdict that did not pass, a missing confirmation); the exit
    /// comes from all errors at the end.
    func error(_ issue: FdtdIssue) {
        guard !envelope.errors.contains(issue) else { return }
        envelope.errors.append(issue)
        context.stderr.line(issue.stderrLine)
    }

    func error(contentsOf issues: [FdtdIssue]) {
        for issue in issues { error(issue) }
    }

    /// A plain `emskit fdtd: ...` stderr line: the plan line, the CLI's own figure lines, the summary.
    func note(_ text: String) { context.stderr.line("emskit fdtd: " + text) }

    /// Appends an invocation record and returns its index (update it once the child has run).
    @discardableResult
    func record(_ invocation: FdtdInvocation) -> Int {
        envelope.invocations.append(invocation)
        return envelope.invocations.count - 1
    }

    func updateInvocation(_ index: Int, _ body: (inout FdtdInvocation) -> Void) { body(&envelope.invocations[index]) }

    func addJob(_ job: FdtdJob) { envelope.jobs.append(job) }

    func addOutput(_ output: FdtdOutput) { envelope.outputs.append(output) }

    /// Adds a library record, replacing an earlier one of the same spec and folder.
    func addLibrary(_ library: FdtdLibrary) {
        if let k = envelope.libraries.firstIndex(where: { $0.spec == library.spec && $0.dir == library.dir }) {
            envelope.libraries[k] = library
        } else {
            envelope.libraries.append(library)
        }
    }

    func setResult(_ result: any Encodable & Sendable) { envelope.result = FdtdAnyResult(result) }

    /// Time spent in discovery probes (bookkeeping only).
    func addProbeSeconds(_ seconds: Double) { probeSeconds += seconds }

    /// Time spent in the tools (bookkeeping only).
    func addToolSeconds(_ seconds: Double) { toolSeconds += seconds }

    var hasErrors: Bool { !envelope.errors.isEmpty }

    /// The exit the errors so far give.
    var exitSoFar: Int32 { FdtdExit.combine(envelope.errors.map(\.code), interrupted: stop.stopRequested) }

    fileprivate func timing() -> FdtdTiming {
        FdtdTiming(startedAt: FdtdCLI.iso8601(startedAt, context.timeZone), wallSeconds: context.clock.uptime() - startUptime,
                   probeSeconds: probeSeconds, toolSeconds: toolSeconds)
    }
}

/// The `emskit fdtd` entry points.
public enum FdtdCLI {
    /// `emskit fdtd ARGS` on this Mac: prints the envelope (or usage) and returns the exit code.
    public static func main(_ arguments: [String]) -> Int32 {
        signal(SIGPIPE, SIG_IGN)      // a reader that went away gives EPIPE instead of killing the CLI (spec 11)
        return run(arguments: arguments, context: FdtdContext.live()).exit
    }

    /// Runs one command line against `context` (tests pass a fake one). `envelope` is nil on the paths that print
    /// none: --version, --help, and a missing or unknown command (usage on stderr, exit 64).
    static func run(arguments: [String], context: FdtdContext) -> (exit: Int32, envelope: Data?) {
        guard let word = arguments.first else {
            context.stderr.write(FdtdUsage.overview + "\n")
            return (64, nil)
        }
        if word == "--version" || word == "--help" {
            guard arguments.count == 1 else {
                context.stderr.line("emskit fdtd: \(word) takes no other arguments")
                return (64, nil)
            }
            if word == "--version" { context.stdout.line(versionLine(context)) }
            else { context.stdout.write(FdtdUsage.overview + "\n") }
            return (0, nil)
        }
        guard let command = FdtdCommandName(rawValue: word) else {
            context.stderr.line("emskit fdtd: unknown command '\(word)'")
            context.stderr.write(FdtdUsage.overview + "\n")
            return (64, nil)
        }
        let rest = Array(arguments.dropFirst())
        if FdtdOptions.wantsHelp(rest) {
            context.stdout.write(FdtdUsage.text(for: command))
            return (0, nil)
        }
        let session = FdtdSession(context: context, command: command, arguments: arguments)
        var installation: (any FdtdSignalInstallation)? = nil
        // Signals become stop requests while a command can have children; info has them too (its probes and scans).
        // In finish() no child is left to stop: one signal there is only noted, and a second one ends the CLI as its
        // default action would, so that a write that blocks (a stalled reader of stdout, a hung volume) can still be
        // left.
        let stop = session.stop
        let finishing = FdtdFinishGuard()
        do {
            let parsed: FdtdParsedCommand
            do {
                parsed = try FdtdOptions.parse(command, rest)
            } catch let e as FdtdError {
                session.error(contentsOf: e.issues)
                // a line that did not parse writes no file, renames nothing and starts no child: what its other
                // tokens mean is not known, so no folder can be judged safe for its --output. No signal handling
                // either: nothing runs that a stop could reach
                if FdtdOptions.namesOutput(command, rest) {
                    session.note("--output is not written: the line was not understood; the envelope goes to stdout")
                }
                throw FdtdError([])
            }
            // begin() can already probe (the protected folders for --output), so the signals come first
            let installed = context.signals.install({ signo in
                stop.signalArrived(signo)
                finishing.signalArrived(signo)
            })
            finishing.installation = installed
            installation = installed
            try session.begin(parsed.common, libraries: parsed.options.librarySpecs)
            try dispatch(parsed.options, session)
        } catch let e as FdtdError {
            session.error(contentsOf: e.issues)
        } catch {
            session.error(FdtdIssue(.toolFailed, "unexpected error: \(error)"))
        }
        // restored only after finish(): with the default action back, a signal during the cleanup or the envelope
        // write would end the CLI with no envelope
        finishing.begin()
        let result = finish(session)
        installation?.restore()
        return result
    }

    /// The command table.
    static func dispatch(_ options: FdtdCommandOptions, _ session: FdtdSession) throws {
        switch options {
        case .info(let o): try InfoCommand.run(o, session: session)
        case .load(let o): try LoadCommand.run(o, session: session)
        case .bench(let o): try BenchCommand.run(o, session: session)
        case .ab(let o): try ABCommand.run(o, session: session)
        case .check(let o): try CheckCommand.run(o, session: session)
        case .validate(let o): try ValidateCommand.run(o, session: session)
        case .debyeCheck(let o): try DebyeCheckCommand.run(o, session: session)
        case .diamondCheck(let o): try DiamondCheckCommand.run(o, session: session)
        case .e2e(let o): try E2ECommand.run(o, session: session)
        case .run(let o): try RunCommand.run(o, session: session)
        }
    }

    /// `{"fdtdKit": "0.1.0", "repoHead": "00e8f7d"}`; repoHead is left out when no tools tree is found.
    static func versionLine(_ context: FdtdContext) -> String {
        var ignored: [FdtdIssue] = []
        let repo = try? FdtdDiscovery.findRepo(option: nil, context: context, warnings: &ignored)
        let hexDigits = Set("0123456789abcdef".utf8)
        // Only a plain hex head is written into the hand-built JSON line.
        if let head = repo?.head, !head.isEmpty, head.utf8.allSatisfy({ hexDigits.contains($0) }) {
            return "{\"fdtdKit\": \"\(FdtdKitInfo.version)\", \"repoHead\": \"\(head)\"}"
        }
        return "{\"fdtdKit\": \"\(FdtdKitInfo.version)\"}"
    }

    /// Status and exit from the errors, --output with its backup, cleanup, the envelope on stdout or in the file, and
    /// its copy in the run folder.
    static func finish(_ s: FdtdSession) -> (exit: Int32, envelope: Data?) {
        let context = s.context
        if s.stop.stopRequested, !s.envelope.errors.contains(where: { $0.code == .interrupted }) {
            s.error(FdtdIssue(.interrupted, "a signal arrived; the running tools were asked to stop"))
        }
        if s.stop.killed {
            s.warn(FdtdIssue(.killed, "the run's process group was still alive after SIGTERM and got SIGKILL"))
        }
        // before the status: a refused --output is an error, so the run folder is kept like after any other
        s.recheckOutput()
        var exit: Int32 = 0
        func encodeEnvelope() -> Data {
            exit = FdtdExit.combine(s.envelope.errors.map(\.code), interrupted: false)
            s.envelope.status = FdtdExit.status(for: exit, partial: s.partial)
            s.envelope.timing = s.timing()
            return (try? FdtdJSON.encode(s.envelope)) ?? Data("{\"status\": \"error\"}".utf8)
        }
        func write(_ data: Data, to out: String, stale: Bool) -> Bool {
            do {
                try FdtdOutputs.writeAtomically(data, to: out, system: context.system)
                return true
            } catch {
                var message = "could not write --output \(out): \(error); the envelope went to stdout"
                if stale { message += ", and the file still says keptRuns false although the run data are kept" }
                s.error(FdtdIssue(.toolFailed, message))
                return false
            }
        }
        if s.runFolder != nil { s.envelope.keptRuns = true }
        // --output comes before the cleanup: a backup or a write that fails is an error, and nothing is deleted
        // after an error
        var written: String? = nil
        var free = false
        if let out = s.outputPath {
            let existed = context.system.fileExists(out)
            var backup: String?
            free = !existed
            if existed, context.system.isDirectory(out) {
                // begin() refuses a folder, so this one was made meanwhile; a rename would move all of it
                s.error(FdtdIssue(.toolFailed, "--output \(out) is a folder now; the envelope went to stdout",
                                  field: "--output"))
            } else if existed, !s.common.overwrite {
                // begin() saw no file, so this one appeared during the run: without --overwrite it stays. The tools
                // have run, so this is no refusal (5) but a failed step of the run, like the folder above
                let message = "--output \(out) appeared during the run and is left alone; the envelope went to stdout"
                s.error(FdtdIssue(.toolFailed, message, field: "--output",
                                  hint: "another FILE, or --overwrite (the old file is kept next to it)"))
            } else if existed {
                do {
                    let kept = try FdtdOutputs.backup(out, mode: .rename, now: context.clock.now(), timeZone: context.timeZone,
                                                      system: context.system)
                    backup = kept
                    free = true
                    s.warn(FdtdIssue(.outputBackedUp, "the old \(out) is kept as \(kept)"))
                } catch {
                    // the old file could not be moved away: never write over it
                    s.error(FdtdIssue(.toolFailed, "could not keep the old \(out) next to it: \(error)"))
                }
            }
            s.addOutput(FdtdOutput(path: out, sha256: nil, existedBefore: existed, backup: backup))
        }
        var data = encodeEnvelope()
        // the run data go after ok or partial unless --keep-runs; any error up to here keeps them
        func cleans() -> Bool {
            s.runFolder != nil && (s.envelope.status == .ok || s.envelope.status == .partial) && !s.common.keepRuns
        }
        if let out = s.outputPath, free {
            // the file is written once, before the cleanup, and says what the cleanup is about to do: a second write
            // after it could fail and leave a file that says keptRuns true beside deleted data
            if cleans() {
                s.envelope.keptRuns = false
                data = encodeEnvelope()
            }
            if write(data, to: out, stale: false) {
                written = out
            } else {
                s.envelope.keptRuns = s.runFolder != nil
                data = encodeEnvelope()
            }
        }
        if let folder = s.runFolder, cleans() {
            if (try? FdtdRunFolders.cleanup(folder, system: context.system)) != nil {
                if s.envelope.keptRuns {
                    s.envelope.keptRuns = false
                    data = encodeEnvelope()
                }
            } else if !s.envelope.keptRuns {
                // not all of the data could be removed: the file must not go on saying that they are gone
                s.envelope.keptRuns = true
                data = encodeEnvelope()
                if let out = written, !write(data, to: out, stale: true) {
                    written = nil
                    data = encodeEnvelope()
                }
            }
        }
        if written == nil { context.stdout.write(String(decoding: data, as: UTF8.self) + "\n") }
        if let folder = s.runFolder { try? FdtdRunFolders.writeEnvelopeCopy(data, folder: folder, system: context.system) }
        return (exit, data)
    }

    /// ISO 8601 with the local offset, e.g. 2026-11-05T14:22:33+01:00.
    static func iso8601(_ date: Date, _ timeZone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
