// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd validate` (spec 2.7): the validation suite under the launcher in script mode with --load (its shim only
// tracks running openEMS instances so that a stop can abort them). The JSON is read as JSON5: a crashed case writes
// NaN and is a failed check, not an unreadable file.
import Foundation

/// validate's result.
struct FdtdValidateResult: Codable, Sendable, Equatable {
    /// --tag T, or the run stamp.
    var tag: String
    @FdtdNullable var json: String? = nil
    @FdtdNullable var md: String? = nil
    /// The requested engine, or the suite's default `fastest`.
    var engine: String
    @FdtdNullable var threads: Int? = nil
    var quick: Bool
    var cases: [String] = []
    /// The number of checks and of passed checks.
    var checks = 0
    var passed = 0
    var failed: [FdtdValidationCheck] = []
    var runs: [String: [FdtdValidationRun]] = [:]
    var libraries: [String] = []
    /// The suite's case times; null without a valid whole-run load.
    @FdtdNullable var timings: [String: FdtdJSONValue]? = nil
}

/// `emskit fdtd validate`.
enum ValidateCommand: FdtdCommandBody {
    static let name = FdtdCommandName.validate

    /// --lib (default installed) with DYLD, --engine (VALIDATION_ENGINE, present in the library), --threads
    /// (VALIDATION_THREADS), --case, knobs in the environment (not PROBE_END_*, EXPORT_*), the protected folders (the
    /// output files and RUNS), the output files (RESULTS with --tag, refused when they exist unless --overwrite; else
    /// RUN/validation with the run stamp); then the suite,
    /// its JSON, the verdict, and the case times with the whole-run load.
    static func run(_ options: FdtdValidateOptions, session: FdtdSession) throws {
        let context = session.context
        let system = context.system
        let repo = try session.discoverRepo()
        let (library, engine) = try session.scriptLibrary(options.lib, engine: options.engine)
        // without --engine the suite runs its default, fastest
        let knobs = try session.environmentKnobs(options.knobs, library: library, engine: engine ?? .fastest)
        var resultsFolder: String? = nil
        if options.tag != nil {
            resultsFolder = try FdtdDiscovery.resultsFolder(repo: repo.root, option: options.results, context: context)
        }
        try session.distributionRecord()

        let cases = options.cases.map(\.rawValue)
        func job(tag: String) -> FdtdJob {
            FdtdJob.validation(library: library, engine: options.engine, threads: options.threads, quick: options.quick,
                               cases: cases, knobs: FdtdKnobs.environment(knobs), tag: tag, out: resultsFolder)
        }
        // the refused envelope shows the job with the stamp its run folder would have had
        let plannedFolder = session.plannedRunFolder()
        let tables = resultsFolder.map { folder in
            ["json", "md"].map { FdtdPaths.join(folder, "validation_\(options.tag ?? "").\($0)") }
        } ?? []
        var existed: [String] = []
        try session.refusals([job(tag: options.tag ?? stamp(plannedFolder))], libraries: [library]) {
            var targets: [FdtdWriteTarget] = []
            if let resultsFolder {
                let label = options.results == nil ? "the results folder" : "--results"
                targets.append(.into(label, field: "--results", resultsFolder))
                for table in tables {
                    targets += session.replacedTargets(table, label: "the table", field: "--tag", inPlace: true)
                }
            } else {
                targets.append(.into("the validation folder", field: "--runs", plannedFolder.validation))
            }
            try session.refuseProtected(targets + session.runFolderTargets())
            for table in tables where try FdtdOutputs.refuseExisting(table, overwrite: session.common.overwrite,
                                                                    field: "--tag", system: system) {
                existed.append(table)
            }
            try session.concurrencyGate(libraries: [library], quietGiven: false)
        }
        let backups = try session.backUpTables(existed)

        let folder = try session.prepareRunFolder()
        let tag = options.tag ?? stamp(folder)
        let out = resultsFolder ?? folder.validation
        let jsonPath = FdtdPaths.join(out, "validation_\(tag).json")
        let mdPath = FdtdPaths.join(out, "validation_\(tag).md")
        var result = FdtdValidateResult(tag: tag, engine: options.engine ?? FdtdEngine.fastest.rawValue,
                                        threads: options.threads, quick: options.quick,
                                        cases: cases.isEmpty ? FdtdValidationCase.allCases.map(\.rawValue) : cases)
        session.setResult(result)
        session.planLine(planText(options, library: library, tag: tag, out: out) + session.runFolderText(folder))
        session.startCaffeinate()
        let backend = try session.localBackend(runFolder: folder, libraries: [library])
        // with --overwrite the old files stay in place (copied, not moved) until the suite writes them: unchanged
        // bytes after the run mean the suite did not write them, and they must not pass for this run's
        let before = [jsonPath, mdPath].reduce(into: [String: String]()) { kept, path in
            if let sha = FdtdLibraries.sha256(path: path, system: system) { kept[path] = sha }
        }
        func written(_ path: String) -> Bool {
            guard system.isRegularFile(path) else { return false }
            guard let old = before[path] else { return true }
            return FdtdLibraries.sha256(path: path, system: system) != old
        }
        guard let spawned = try session.spawnJob(job(tag: tag), backend: backend, onLine: nil) else { return }

        let load = session.wholeRunLoad(spawned.report)
        var report: FdtdValidationReport? = nil
        if written(jsonPath), let data = system.readFile(jsonPath) { report = try? FdtdParsers.validation(data) }
        let verdict = FdtdVerdicts.validate(exit: spawned.report?.exit ?? spawned.exit, report: report,
                                            expectedDir: library.dir, engine: engine ?? .fastest, home: context.home,
                                            system: system)
        // after a stop the suite's partial JSON says nothing about the checks; finish() reports the interruption
        if !session.stop.stopRequested { session.error(contentsOf: verdict.errors) }
        session.warn(contentsOf: verdict.warnings)
        // the engine prints its fallback line on stderr, which common.py leaves on the pipe: only tool.log has it
        let fallbacks = engine == .metalDiamond ? FdtdParsers.gpuFallbackLines(session.toolLog(folder)).count : 0
        if fallbacks > 0 {
            session.warn(FdtdVerdicts.gpuFallback("the validation suite (\(fallbacks) run\(fallbacks == 1 ? "" : "s"))"))
        }

        for path in [jsonPath, mdPath] where written(path) {
            session.recordOutput(path, existedBefore: existed.contains(path), backup: backups[path])
        }
        result.json = written(jsonPath) ? jsonPath : nil
        result.md = written(mdPath) ? mdPath : nil
        if let report {
            result.checks = report.results.count
            result.passed = report.results.filter(\.passed).count
            result.failed = report.results.filter { !$0.passed }
            result.runs = report.runs
            result.libraries = report.meta["libraries"]?.array?.compactMap { $0.string } ?? []
            if load.valid { result.timings = report.timings }
            if let line = caseTimesLine(report.timings, order: result.cases, load: load) { session.note(line) }
            session.loadWarnings(withheld: load.valid || report.timings.isEmpty ? [] : ["the validation run"],
                                 loaded: load.valid && load.loaded ? ["the validation run"] : [])
        }
        session.setResult(result)
        session.note(summary(result, report: report, session: session))
    }

    // MARK: - Private

    /// The run folder's `yyyyMMdd-HHmmss` (the backend's tag without --tag).
    private static func stamp(_ folder: FdtdRunFolder) -> String { String(FdtdPaths.basename(folder.path).prefix(15)) }

    /// `validate T: LIB[, engine E][, N threads][, quick][, cases C...], out DIR`.
    private static func planText(_ options: FdtdValidateOptions, library: FdtdLibrary, tag: String,
                                 out: String) -> String {
        var parts = ["library \(library.spec)", "engine \(options.engine ?? FdtdEngine.fastest.rawValue)"]
        if let threads = options.threads { parts.append("\(threads) threads") }
        if options.quick { parts.append("quick") }
        if !options.cases.isEmpty { parts.append("cases " + options.cases.map(\.rawValue).joined(separator: " ")) }
        parts.append("out \(out)")
        return "validate \(tag): " + parts.joined(separator: ", ")
    }

    /// `validate: case times slab 12.3 s, ... (others cpu C% gpu G% over the whole run)`, or the withheld form; nil
    /// when the suite timed nothing.
    private static func caseTimesLine(_ timings: [String: FdtdJSONValue], order: [String], load: FdtdLoad) -> String? {
        guard !timings.isEmpty else { return nil }
        guard load.valid else { return "validate: case times withheld (no valid load during the run)" }
        let names = order.filter { timings[$0] != nil } + timings.keys.filter { !order.contains($0) }.sorted()
        let times = names.compactMap { name in timings[name]?.double.map { name + " " + FdtdFigures.seconds($0) } }
        return "validate: case times " + times.joined(separator: ", ") + " (" + FdtdFigures.wholeRun(load) + ")"
    }

    /// `validate T: STATUS: P of N checks passed (engine E)[; failed: CASE QUANTITY, ...]`.
    private static func summary(_ result: FdtdValidateResult, report: FdtdValidationReport?,
                                session: FdtdSession) -> String {
        var text = "validate \(result.tag): \(session.statusSoFar): "
        guard report != nil else { return text + "no readable validation JSON" }
        text += "\(result.passed) of \(result.checks) checks passed (engine \(result.engine))"
        if !result.failed.isEmpty {
            text += "; failed: " + result.failed.map { "\($0.caseName) \($0.quantity)" }.joined(separator: ", ")
        }
        return text
    }
}
