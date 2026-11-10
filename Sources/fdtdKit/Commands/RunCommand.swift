// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd run` (spec 2.10): any Python script, run as `python3 SCRIPT ARGS` would be, under the launcher in script
// mode with --load --calls; --engine/--threads/--nodumps are injected into every FDTD.Run call. The call records here
// are shared with e2e.
import Foundation

/// One FDTD.Run call (spec 7, "call"): the launcher's record joined with its segment's openEMS lines. seconds and mcs
/// are null without a valid call load.
struct FdtdCall: Codable, Sendable, Equatable {
    var index: Int
    @FdtdNullable var simPath: String? = nil
    var setupOnly = false
    var options: [String: String] = [:]
    var applied: [String: String] = [:]
    var overridden: [String: FdtdOverride] = [:]
    var optionsLost: [String] = []
    var stdoutRedirected = false
    var stopRequested = false
    @FdtdNullable var wallSeconds: Double? = nil
    @FdtdNullable var load: FdtdLoad? = nil
    @FdtdNullable var createLine: String? = nil
    @FdtdNullable var engineConfirmed: Bool? = nil
    /// false when the script had redirected fd 1 around the call.
    var engineObservable = true
    @FdtdNullable var threadsFixed: Int? = nil
    @FdtdNullable var threadsPicked: Int? = nil
    @FdtdNullable var timesteps: Int? = nil
    @FdtdNullable var cells: Double? = nil
    @FdtdNullable var seconds: Double? = nil
    @FdtdNullable var mcs: Double? = nil
    @FdtdNullable var stop: FdtdRunStop? = nil
    /// OPENEMS_PROBE_END_DB and _HOLD in effect for the call.
    var probeEnd: [String: String?] = [:]
}

/// run's result.
struct FdtdRunResult: Codable, Sendable, Equatable {
    /// The script's absolute path.
    var script: String
    var args: [String]
    var cwd: String
    @FdtdNullable var exit: Int32? = nil
    @FdtdNullable var exception: String? = nil
    var calls: [FdtdCall] = []
    /// What the script loaded (the launcher report's libraries).
    var libraries: [String] = []
}

/// Calls from a launcher report and tool.log (run and e2e).
enum FdtdCalls {
    /// The report's calls joined with tool.log's segments (FdtdParsers.callSegments, openEMSFacts), each with its load
    /// (FdtdLoads.fromSampler) and engine confirmation against `engine`. Without a report (after SIGTERM or SIGKILL in
    /// script mode) the calls are rebuilt from the segments alone, loads null, and `rebuilt` is true (report_rebuilt).
    static func build(report: FdtdLauncherReport?, toolLog: String, engine: FdtdEngine?,
                      thresholds: FdtdThresholds) -> (calls: [FdtdCall], rebuilt: Bool) {
        let segments = FdtdParsers.callSegments(toolLog)
        var facts: [Int: FdtdOpenEMSFacts] = [:]
        for segment in segments where facts[segment.index] == nil {
            facts[segment.index] = FdtdParsers.openEMSFacts(segment.lines)
        }
        guard let report else {
            let calls = segments.map { segment in
                var call = FdtdCall(index: segment.index)
                fill(&call, facts: facts[segment.index] ?? FdtdOpenEMSFacts(), engine: engine)
                return call
            }
            return (calls, true)
        }
        let calls = report.calls.map { record in
            var call = FdtdCall(index: record.index)
            call.simPath = record.simPath
            call.setupOnly = record.setupOnly
            call.options = record.options
            call.applied = record.applied
            call.overridden = record.overridden
            call.optionsLost = record.optionsLost
            call.stdoutRedirected = record.stdoutRedirected
            call.stopRequested = record.stopRequested
            call.engineObservable = !record.stdoutRedirected
            call.probeEnd = record.probeEnd
            call.load = FdtdLoads.fromSampler(record.load, counts: record.loadCounts, thresholds: thresholds)
            // the call's wall time is a run time too (spec 14 S4): shown only with its valid load
            if call.load?.valid == true { call.wallSeconds = record.wallSeconds }
            fill(&call, facts: facts[record.index] ?? FdtdOpenEMSFacts(), engine: engine)
            return call
        }
        return (calls, false)
    }

    /// `call K: LABEL X MC/s (others cpu C% gpu G%), probe end after N TS`, or the withheld form.
    static func line(_ call: FdtdCall, label: String) -> String {
        var text = "call \(call.index): \(label)"
        if call.setupOnly {
            text += ": setup only"
        } else if let mcs = call.mcs, let load = call.load, load.valid {
            text += " " + FdtdFigures.mcs(mcs) + " MC/s (" + FdtdFigures.others(load) + ")"
        } else if call.load?.valid == true {
            text += ": no speed line"
        } else {
            text += ": speed withheld (no valid load during the run)"
        }
        if let stop = FdtdFigures.stop(call.stop) { text += ", " + stop }
        return text
    }

    /// The indices of the calls whose segment printed the Engine_Metal_Diamond fallback line (gpu_fallback).
    static func gpuFallbackCalls(_ toolLog: String) -> [Int] {
        FdtdParsers.callSegments(toolLog).filter { FdtdParsers.openEMSFacts($0.lines).gpuFallback }.map(\.index)
    }

    /// The openEMS facts of a call's segment; time and speed only with a valid call load.
    private static func fill(_ call: inout FdtdCall, facts: FdtdOpenEMSFacts, engine: FdtdEngine?) {
        // a Create line the engine does not print is the one to show, so that the verdict sees it
        let mismatch = engine.flatMap { e in facts.creates.first { !e.accepts($0) } }
        call.createLine = (mismatch ?? facts.creates.first)?.line
        if let engine, call.engineObservable {
            call.engineConfirmed = !facts.creates.isEmpty && facts.creates.allSatisfy { engine.accepts($0) }
        }
        call.threadsFixed = facts.threadsFixed
        call.threadsPicked = facts.threadsPicked
        call.timesteps = facts.timesteps
        call.cells = facts.cells
        call.stop = facts.stop
        if call.load?.valid == true {
            call.seconds = facts.seconds
            call.mcs = facts.mcs
        }
    }
}

/// `emskit fdtd run`.
enum RunCommand: FdtdCommandBody {
    static let name = FdtdCommandName.run

    /// SCRIPT must be a file (2 script_not_found); --lib (default installed) with DYLD; --engine present in the
    /// library; knobs in the environment (all 30; EXPORT_* name existing folders); the protected folders (the EXPORT_*
    /// folders and RUNS); the concurrency warning; the quiet wait; then the script with cwd = the CLI's cwd, the calls,
    /// the verdict and the summary line.
    static func run(_ options: FdtdRunOptions, session: FdtdSession) throws {
        let context = session.context
        let system = context.system
        let script = session.absolutePath(options.script)
        guard system.isRegularFile(script) else {
            let what = system.fileExists(script) ? "is not a file" : "does not exist"
            throw FdtdError(.scriptNotFound, "script \(script) \(what)", field: "SCRIPT")
        }
        let sha256 = FdtdLibraries.sha256(path: script, system: system)
        _ = try session.discoverRepo()
        let (library, engine) = try session.scriptLibrary(options.lib, engine: options.engine)
        let knobs = try session.environmentKnobs(options.knobs, library: library, engine: engine)
        try session.distributionRecord()

        let job = FdtdJob.script(path: script, sha256: sha256, arguments: options.scriptArguments, library: library,
                                 engine: options.engine, threads: options.threads, nodumps: options.nodumps,
                                 knobs: FdtdKnobs.environment(knobs))
        let planned = (options.quiet.map { [FdtdJob.quiet($0)] } ?? []) + [job]
        try session.refusals(planned, libraries: [library]) {
            // openEMS writes the exported operator and fields into the EXPORT_* folders
            let exports = knobs.filter { FdtdKnobs.knob(named: $0.name)?.rule == .existingFolder }
                .map { FdtdWriteTarget.into("--knob \($0.name)", field: "--knob", $0.value) }
            try session.refuseProtected(exports + session.runFolderTargets())
            try session.concurrencyGate(libraries: [library], quietGiven: options.quiet != nil)
        }

        var result = FdtdRunResult(script: script, args: options.scriptArguments, cwd: context.cwd)
        session.setResult(result)
        let folder = try session.prepareRunFolder()
        session.planLine(planText(script, options, library: library) + session.runFolderText(folder))
        session.startCaffeinate()
        let backend = try session.localBackend(runFolder: folder, libraries: [library])
        if let quiet = options.quiet { try session.quietWait(quiet, backend: backend) }
        guard let spawned = try session.spawnJob(job, backend: backend, onLine: nil) else { return }

        let report = spawned.report
        let toolLog = session.toolLog(folder)
        let built = FdtdCalls.build(report: report, toolLog: toolLog, engine: engine, thresholds: session.thresholds)
        if built.rebuilt {
            let message = "the launcher left no report, so \(built.calls.count) calls were rebuilt from tool.log"
            session.warn(FdtdIssue(.reportRebuilt, message))
        }
        let load = session.wholeRunLoad(report)
        let exit = report?.exit ?? spawned.exit
        // without a report the launcher failure (or the stop) is the finding; its libraries are unknown
        if let report {
            let verdict = FdtdVerdicts.run(exit: exit, exception: report.exception, calls: built.calls, engine: engine,
                                           libraries: report.libraries, targetDir: library.dir, system: system,
                                           gpuFallbackCalls: FdtdCalls.gpuFallbackCalls(toolLog))
            if !session.stop.stopRequested { session.error(contentsOf: verdict.errors) }
            session.warn(contentsOf: verdict.warnings)
        }

        result.exit = exit
        result.exception = report?.exception
        result.calls = built.calls
        result.libraries = report?.libraries ?? []
        session.setResult(result)
        for call in built.calls { session.note(FdtdCalls.line(call, label: "FDTD.Run")) }
        let withheld = built.calls.filter { $0.load?.valid != true && !$0.setupOnly }.map { "call \($0.index)" }
        var loaded = built.calls.filter { $0.load?.loaded == true }.map { "call \($0.index)" }
        if load.valid && load.loaded { loaded.append("the whole run") }
        session.loadWarnings(withheld: withheld, loaded: loaded)
        session.note(summary(result, session: session))
    }

    // MARK: - Private

    /// `run SCRIPT: N args, LIB[, engine E][, N threads][, nodumps]`.
    private static func planText(_ script: String, _ options: FdtdRunOptions, library: FdtdLibrary) -> String {
        var parts = ["library \(library.spec)"]
        if !options.scriptArguments.isEmpty {
            parts.append("\(options.scriptArguments.count) argument\(options.scriptArguments.count == 1 ? "" : "s")")
        }
        if let engine = options.engine { parts.append("engine \(engine)") }
        if let threads = options.threads { parts.append("\(threads) threads") }
        if options.nodumps { parts.append("nodumps") }
        return "run \(script): " + parts.joined(separator: ", ")
    }

    /// `run SCRIPT: STATUS: exit N, K calls[; FDTD.Run X MC/s (others cpu C% gpu G%)]...`.
    private static func summary(_ result: FdtdRunResult, session: FdtdSession) -> String {
        var text = "run \(FdtdPaths.basename(result.script)): \(session.statusSoFar): "
        if let exception = result.exception {
            text += "raised \(exception)"
        } else {
            text += result.exit.map { "exit \($0)" } ?? "no exit status"
        }
        text += ", \(result.calls.count) FDTD.Run call\(result.calls.count == 1 ? "" : "s")"
        for call in result.calls {
            guard let mcs = call.mcs, let load = call.load, load.valid else { continue }
            text += "; call \(call.index) " + FdtdFigures.mcs(mcs) + " MC/s (" + FdtdFigures.others(load) + ")"
        }
        return text
    }
}
