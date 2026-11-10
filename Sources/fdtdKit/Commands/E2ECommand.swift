// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd e2e` (spec 2.9): scripts/e2e/run_one.py on the toolkit's GCPW line or SMA launch, under the launcher in
// script mode with --load --calls. Its run times carry the whole-run load and FDTD.Run's MC/s that call's load;
// each is withheld without a valid one.
import Foundation

/// e2e's probeEnd{db, hold, source}: what run_one.py got.
struct FdtdE2EProbeEnd: Codable, Sendable, Equatable {
    /// The level as passed: %g of the toolkit's or the given value, or "off".
    var db: String
    var hold: Double
    /// "toolkit" when both values came from the rfsim probe, "option" when both were given, else "mixed".
    var source: String
}

/// e2e's result.
struct FdtdE2EResult: Codable, Sendable, Equatable {
    var model: String
    /// The SMA mesh floor passed (0 = the toolkit default).
    var floor: Double
    var probeEnd: FdtdE2EProbeEnd
    /// --engine (E2E_ENGINE), or null for the toolkit's default.
    @FdtdNullable var engine: String? = nil
    var outDir: String
    @FdtdNullable var resultJson: String? = nil
    @FdtdNullable var spNpz: String? = nil
    /// The RESULT JSON, its times nulled without a valid whole-run load.
    @FdtdNullable var result: FdtdJSONValue? = nil
    /// result.json and RESULT exist although a stop was requested (the run finished first).
    var interrupted = false
    var calls: [FdtdCall] = []
}

/// `emskit fdtd e2e`.
enum E2ECommand: FdtdCommandBody {
    static let name = FdtdCommandName.e2e

    /// RESULT's run times (seconds), in the order of the summary line.
    private static let timeKeys = ["t_build", "t_run", "t_post", "t_total"]

    /// 64 for an --out-dir that is the run folder's place or a folder above it: core.run's FDTD.Run(cleanup=True)
    /// empties its folder first, and with it the launcher, tool.log and the report of this very run. The same for
    /// a folder that is or holds one of `needed` (the working directory, the tools tree, the toolkit, the library's
    /// folder, the Python's): --overwrite would rename it away just before the run that needs it. Compared with
    /// the protected folders' own test (FdtdProtectedPaths.holds): by the real path of what exists, by file
    /// identity, and by the path each folder is named by (a link inside the --out-dir that leads to it).
    static func refuseHolding(_ outDir: String, needed: [(what: String, path: String)],
                              session: FdtdSession) throws {
        let system = session.context.system
        guard let out = FdtdProtectedPaths.locate(outDir, system: system) else { return }
        func holds(_ path: String) -> Bool {
            guard let folder = FdtdProtectedPaths.locate(path, system: system) else { return false }
            return FdtdProtectedPaths.holds(out, folder)
        }
        let run = session.plannedRunFolder().path
        if holds(run) {
            let message = "--out-dir \(outDir) holds the run folder \(run), and core.run empties its folder first"
            throw FdtdOptions.usage(message, field: "--out-dir",
                                    hint: "a folder outside RUNS (\(session.runsBase())), or another --runs")
        }
        for (what, path) in needed where holds(path) {
            let message = "--out-dir \(outDir) is or holds \(what) \(path), which this run needs: core.run "
                + "empties its folder first, and --overwrite would rename it away"
            throw FdtdOptions.usage(message, field: "--out-dir", hint: "a folder of its own for the results")
        }
    }

    /// The last step before the run: the old --out-dir is renamed only here, so that an error or a stop up to here
    /// (the run folder, the quiet wait) leaves it in place; after a stop spawnJob starts nothing. The invocation
    /// is resolved first, so that a job that cannot be resolved fails before the rename. Then the checks of plan
    /// time again: during the wait a folder on the path can have become a link into a protected folder or to a
    /// folder the run needs, and the folder can have been filled by someone else (the run would empty it: 5
    /// without --overwrite, a backup with it). Returns the backup's path when the folder was renamed.
    static func prepareOutDir(_ given: String?, job: FdtdJob, backend: any FdtdBackend,
                              needed: [(what: String, path: String)], session: FdtdSession) throws -> String? {
        if session.common.dryRun { return nil }
        _ = try backend.resolve(job, host: "local")
        guard let given, !session.stop.stopRequested else { return nil }
        let context = session.context
        try session.refuseProtected(session.replacedTargets(given, label: "--out-dir", field: "--out-dir"))
        try refuseHolding(given, needed: needed, session: session)
        guard try FdtdOutputs.refuseExisting(given, overwrite: session.common.overwrite, field: "--out-dir",
                                             system: context.system) else { return nil }
        let kept = try FdtdOutputs.backup(given, mode: .rename, now: context.clock.now(),
                                          timeZone: context.timeZone, system: context.system)
        session.warn(FdtdIssue(.outputBackedUp, "the old \(given) is kept as \(kept)"))
        return kept
    }

    /// rfsim required (2) and probed (the toolkit values for --floor/--probe-end/--hold), --lib with DYLD, --engine,
    /// knobs in the environment (not PROBE_END_*, EXPORT_*), the protected folders (--out-dir and RUNS), --out-dir
    /// (default RUN/e2e; 5 when it exists and is not empty, renamed with --overwrite), the concurrency gate (refuses),
    /// the quiet wait; then run_one.py MODEL FLOOR
    /// DB HOLD OUTDIR, RESULT and result.json, the calls, the verdict and the summary line.
    static func run(_ options: FdtdE2EOptions, session: FdtdSession) throws {
        let context = session.context
        let system = context.system
        let repo = try session.discoverRepo()
        guard let rfsim = try session.discoverRfsim(required: true) else { return }
        let (library, engine) = try session.scriptLibrary(options.lib, engine: options.engine)
        // without --engine FDTD.Run gets none, so openEMS runs fastest
        let knobs = try session.environmentKnobs(options.knobs, library: library, engine: engine ?? .fastest)
        let floor = floorValue(options.floor)
        let probeEnd = try probeEndValues(options, rfsim: rfsim)
        // core.run makes the folder (os.makedirs), so a new nested --out-dir is fine
        let given = options.outDir.map { session.absolutePath($0) }
        let python = try session.discoverPython()
        let needed = [("the working directory", context.cwd), ("the tools tree", repo.root),
                      ("the rfsim toolkit", rfsim.path), ("the library folder", library.dir),
                      ("the folder of the Python", FdtdPaths.dirname(python))]
        try session.distributionRecord()

        let job = FdtdJob.e2e(model: options.model, library: library, engine: options.engine,
                              floor: FdtdJob.optionText(floor), db: probeEnd.db,
                              hold: FdtdJob.optionText(probeEnd.hold), knobs: FdtdKnobs.environment(knobs),
                              outDir: given)
        let planned = (options.quiet.map { [FdtdJob.quiet($0)] } ?? []) + [job]
        var outExisted = false
        try session.refusals(planned, libraries: [library]) {
            // --overwrite renames a given --out-dir away, and core.run's FDTD.Run(cleanup=True) empties it first
            let out = given.map { session.replacedTargets($0, label: "--out-dir", field: "--out-dir") }
                ?? [.into("the e2e folder", field: "--out-dir", session.plannedRunFolder().e2e)]
            try session.refuseProtected(out + session.runFolderTargets())
            if let given {
                try refuseHolding(given, needed: needed, session: session)
                outExisted = try FdtdOutputs.refuseExisting(given, overwrite: session.common.overwrite,
                                                            field: "--out-dir", system: system)
            }
            try session.concurrencyGate(libraries: [library], quietGiven: options.quiet != nil)
        }
        if let given, outExisted, session.common.dryRun { session.planBackup(given) }

        let folder = try session.prepareRunFolder()
        let outDir = given ?? folder.e2e
        var result = FdtdE2EResult(model: options.model.rawValue, floor: floor, probeEnd: probeEnd,
                                   engine: options.engine, outDir: outDir)
        session.setResult(result)
        session.planLine(planText(options, library: library, probeEnd: probeEnd, outDir: outDir)
                         + session.runFolderText(folder))
        session.startCaffeinate()
        let backend = try session.localBackend(runFolder: folder, libraries: [library])
        if let quiet = options.quiet { try session.quietWait(quiet, backend: backend) }
        let backup = try prepareOutDir(given, job: job, backend: backend, needed: needed, session: session)
        let collector = FdtdLineCollector()
        guard let spawned = try session.spawnJob(job, backend: backend, onLine: { collector.append($0) }) else {
            return
        }

        let report = spawned.report
        let toolLog = session.toolLog(folder)
        let resultLine = FdtdParsers.e2eResult(collector.all.joined(separator: "\n"))
        let resultJson = FdtdPaths.join(outDir, "result.json")
        let spNpz = FdtdPaths.join(outDir, "sp.npz")
        let resultJsonExists = system.isRegularFile(resultJson)
        let built = FdtdCalls.build(report: report, toolLog: toolLog, engine: engine ?? .fastest,
                                    thresholds: session.thresholds)
        if built.rebuilt {
            let message = "the launcher left no report, so \(built.calls.count) calls were rebuilt from tool.log"
            session.warn(FdtdIssue(.reportRebuilt, message))
        }
        let load = session.wholeRunLoad(report)
        let stopped = session.stop.stopRequested
        let verdict = FdtdVerdicts.e2e(exit: report?.exit ?? spawned.exit, result: resultLine,
                                       resultJsonExists: resultJsonExists, calls: built.calls, engine: engine,
                                       interrupted: stopped, libraries: report?.libraries, targetDir: library.dir,
                                       system: system, gpuFallbackCalls: FdtdCalls.gpuFallbackCalls(toolLog))
        session.error(contentsOf: verdict.errors)
        session.warn(contentsOf: verdict.warnings)

        // a renamed --out-dir keeps the earlier files under its backup name
        func previous(_ name: String) -> String? {
            guard let backup else { return nil }
            let path = FdtdPaths.join(backup, name)
            return system.fileExists(path) ? path : nil
        }
        if resultJsonExists {
            result.resultJson = resultJson
            let kept = previous("result.json")
            session.recordOutput(resultJson, existedBefore: kept != nil, backup: kept)
        }
        if system.isRegularFile(spNpz) {
            result.spNpz = spNpz
            let kept = previous("sp.npz")
            session.recordOutput(spNpz, existedBefore: kept != nil, backup: kept)
        }
        result.result = resultLine.map { withheldTimes($0, load: load) }
        result.interrupted = stopped && resultLine != nil && resultJsonExists
        result.calls = built.calls
        session.setResult(result)

        for call in built.calls { session.note(FdtdCalls.line(call, label: "FDTD.Run")) }
        var withheld = built.calls.filter { $0.load?.valid != true && !$0.setupOnly }.map { "call \($0.index)" }
        if resultLine != nil && !load.valid { withheld.insert("the whole run", at: 0) }
        var loaded = built.calls.filter { $0.load?.loaded == true }.map { "call \($0.index)" }
        if load.valid && load.loaded { loaded.insert("the whole run", at: 0) }
        session.loadWarnings(withheld: withheld, loaded: loaded)
        session.note(summary(result, resultLine: resultLine, load: load, session: session))
    }

    // MARK: - Private

    /// FLOOR as run_one.py gets it: 0 for the toolkit default (gcpw has no floor).
    private static func floorValue(_ floor: FdtdToolkitOr) -> Double {
        switch floor {
        case .toolkit: return 0
        case .value(let millimetres): return millimetres
        }
    }

    /// DB and HOLD: the toolkit's core.PROBE_END_DB (%g; 0 or none = off) and core.PROBE_END_HOLD, or the options.
    private static func probeEndValues(_ options: FdtdE2EOptions, rfsim: FdtdRfsim) throws -> FdtdE2EProbeEnd {
        var fromToolkit = 0
        let db: String
        switch options.probeEnd {
        case .toolkit:
            fromToolkit += 1
            if let level = rfsim.probeEndDb, level != 0 {
                db = FdtdOptions.formatG(level)
            } else {
                db = "off"
            }
        case .off:
            db = "off"
        case .db(let level):
            db = FdtdOptions.formatG(level)
        }
        let hold: Double
        switch options.hold {
        case .toolkit:
            fromToolkit += 1
            guard let value = rfsim.probeEndHold else {
                let message = "the rfsim probe of \(rfsim.path) gave no core.PROBE_END_HOLD, so --hold toolkit has no value"
                throw FdtdError(.rfsimNotFound, message, field: "--hold", hint: "--hold H")
            }
            hold = value
        case .value(let value):
            hold = value
        }
        let source = fromToolkit == 2 ? "toolkit" : fromToolkit == 0 ? "option" : "mixed"
        return FdtdE2EProbeEnd(db: db, hold: hold, source: source)
    }

    /// RESULT with t_build, t_run, t_post and t_total null unless the whole-run load is valid.
    private static func withheldTimes(_ value: FdtdJSONValue, load: FdtdLoad) -> FdtdJSONValue {
        guard !load.valid, var object = value.object else { return value }
        for key in timeKeys where object[key] != nil { object[key] = .null }
        return .object(object)
    }

    /// `e2e MODEL: LIB, probe end DB dB hold H (SOURCE)[, engine E], out DIR`.
    private static func planText(_ options: FdtdE2EOptions, library: FdtdLibrary, probeEnd: FdtdE2EProbeEnd,
                                 outDir: String) -> String {
        var parts = ["library \(library.spec)"]
        if case .value(let floor) = options.floor { parts.append("mesh floor \(FdtdOptions.formatG(floor)) mm") }
        if probeEnd.db == "off" {
            parts.append("probe end off (\(probeEnd.source))")
        } else {
            let hold = FdtdOptions.formatG(probeEnd.hold)
            parts.append("probe end \(probeEnd.db) dB, hold \(hold) (\(probeEnd.source))")
        }
        if let engine = options.engine { parts.append("engine \(engine)") }
        parts.append("out \(outDir)")
        return "e2e \(options.model.rawValue): " + parts.joined(separator: ", ")
    }

    /// `e2e gcpw: ok: build 0.4 s, run 4.1 s, post 0.6 s (others cpu 52% gpu 0% over the whole run); FDTD.Run 1736.2
    /// MC/s, probe end after 34300 TS (others cpu 51% gpu 0%)`; a figure without a valid load is left out.
    private static func summary(_ result: FdtdE2EResult, resultLine: FdtdJSONValue?, load: FdtdLoad,
                                session: FdtdSession) -> String {
        var parts: [String] = []
        if load.valid, let line = resultLine {
            let names = ["t_build": "build", "t_run": "run", "t_post": "post"]
            let times = ["t_build", "t_run", "t_post"].compactMap { key -> String? in
                guard let seconds = line[key]?.double, let name = names[key] else { return nil }
                return name + " " + FdtdFigures.seconds(seconds)
            }
            if !times.isEmpty { parts.append(times.joined(separator: ", ") + " (" + FdtdFigures.wholeRun(load) + ")") }
        }
        let timed = result.calls.filter { !$0.setupOnly }
        for call in timed {
            guard let mcs = call.mcs, let callLoad = call.load, callLoad.valid else { continue }
            var text = (timed.count == 1 ? "FDTD.Run " : "FDTD.Run call \(call.index) ") + FdtdFigures.mcs(mcs) + " MC/s"
            if let stop = FdtdFigures.stop(call.stop) { text += ", " + stop }
            parts.append(text + " (" + FdtdFigures.others(callLoad) + ")")
        }
        if parts.isEmpty, resultLine == nil { parts.append("no RESULT line") }
        let head = "e2e \(result.model): \(session.statusSoFar)"
        return parts.isEmpty ? head : head + ": " + parts.joined(separator: "; ")
    }
}
