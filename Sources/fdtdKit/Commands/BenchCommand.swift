// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd bench` (spec 2.4): one bench.py call under the launcher (exec mode, no launcher sampler, so nothing
// disturbs the benchmark). The rows carry their own during-run loads; a speed without a valid one is withheld.
// The row records here are shared with check, whose model blocks are bench outputs.
import Foundation

/// A row's S-parameter field.
struct FdtdSParam: Codable, Sendable, Equatable {
    var name: String
    @FdtdNullable var maxAbsDiff: Double? = nil
    @FdtdNullable var maxDb: Double? = nil
    var exact: Bool
}

/// The envelope's bench row (spec 7). mcs and seconds are null when the load is not valid (speedWithheld).
struct FdtdBenchRow: Codable, Sendable, Equatable {
    var label: String
    var config: String
    /// The LIB spec, or "installed".
    var lib: String
    var engine: String
    @FdtdNullable var threads: Int? = nil
    var nodumps = false
    var knobs: [String: String] = [:]
    var reference = false
    var tolerant = false
    @FdtdNullable var mcs: Double? = nil
    @FdtdNullable var seconds: Double? = nil
    var speedWithheld = false
    @FdtdNullable var timesteps: Int? = nil
    /// Million cells, as bench prints them (`x MC`).
    @FdtdNullable var cells: Double? = nil
    @FdtdNullable var repeats: Int? = nil
    @FdtdNullable var autoPickedThreads: Int? = nil
    /// top's reading from the second before the run; never a load.
    @FdtdNullable var othersCpuBefore: Int? = nil
    var busyBefore: [String] = []
    var quietWaitTimedOut = false
    @FdtdNullable var load: FdtdLoad? = nil
    @FdtdNullable var probesRel: Double? = nil
    @FdtdNullable var zeroFiles: FdtdZeroFiles? = nil
    var problems: [String] = []
    var sparams: [FdtdSParam] = []
    @FdtdNullable var sparamNote: String? = nil
    @FdtdNullable var openemsVersion: String? = nil
    /// RUN/runs/NAME/SUB/rep{k}, one per repeat.
    var runFolders: [String] = []
    @FdtdNullable var createLine: String? = nil
    @FdtdNullable var engineConfirmed: Bool? = nil
    /// null for the reference row (nothing compared).
    @FdtdNullable var exact: Bool? = nil
}

/// bench's result.
struct FdtdBenchResult: Codable, Sendable, Equatable {
    var model: String
    var scale: Double
    var nrts: Int
    /// `MODEL_s%g_nN`.
    var name: String
    /// The first CFG.
    var reference: String
    var rows: [FdtdBenchRow] = []
    @FdtdNullable var summary: FdtdBenchSummary? = nil
    @FdtdNullable var resultsFile: String? = nil
    var exact: Bool
}

/// Rows from a parsed bench output (bench and check).
enum FdtdBenchRows {
    /// Each parsed row with its config (in config order), its load (FdtdLoads.fromBenchRow) with mcs and seconds
    /// withheld without a valid one, its run folders under `runsDir`/NAME (FdtdBenchConfigs.runSubfolders), the Create
    /// line of every rep*/openEMS.log (engineConfirmed), and exactness (null for the reference).
    static func build(_ parsed: FdtdParsedBench, configs: [FdtdBenchConfig], runsDir: String, thresholds: FdtdThresholds,
                      system: any FdtdSystem) -> [FdtdBenchRow] {
        let labels = configs.map { FdtdBenchConfigs.label($0.text) }
        let subfolders = FdtdBenchConfigs.runSubfolders(labels)
        let base = FdtdPaths.join(runsDir, parsed.name ?? "")
        var rows: [FdtdBenchRow] = []
        var next = 0
        for parsedRow in parsed.rows {
            // bench prints one row per config in config order; the label confirms the pairing
            guard next < configs.count else { break }
            let k = (next..<configs.count).first(where: { labels[$0] == parsedRow.label }) ?? next
            next = k + 1
            var row = provisional(parsedRow, thresholds: thresholds)
            fill(&row, config: configs[k])
            confirm(&row, folder: FdtdPaths.join(base, subfolders[k]), engine: configs[k].engine, system: system)
            rows.append(row)
        }
        return rows
    }

    /// `bench row I of N: LABEL X MC/s (others cpu C% gpu G% during W s), exact`, or `bench row I of N: LABEL: speed
    /// withheld (no valid load during the run)`.
    static func line(_ row: FdtdBenchRow, index: Int, count: Int) -> String {
        var text = "bench row \(index) of \(count): "
        if let load = row.load, FdtdLoads.shows(load), let mcs = row.mcs {
            var inside = FdtdFigures.others(load)
            if let wall = load.wallSeconds { inside += " during " + FdtdFigures.seconds(wall) }
            text += "\(row.label) \(FdtdFigures.mcs(mcs)) MC/s (\(inside))"
        } else {
            text += "\(row.label): speed withheld (no valid load during the run)"
        }
        if let exact = row.exact {
            if exact {
                text += ", exact"
            } else {
                text += row.tolerant ? ", not exact (tolerant)" : ", not exact"
            }
        }
        return text
    }

    /// The labels of the metal-diamond rows whose rep*/openEMS.log has a fallback line (spec 4.4): bench.py writes the
    /// run's stdout and stderr there, and such a row still shows its engine's Create line.
    static func gpuFallbacks(_ rows: [FdtdBenchRow], system: any FdtdSystem) -> [String] {
        rows.filter { row in
            row.engine == FdtdEngine.metalDiamond.rawValue && row.runFolders.contains { dir in
                let data = system.readFile(FdtdPaths.join(dir, "openEMS.log"))
                return !FdtdParsers.gpuFallbackLines(data.map { String(decoding: $0, as: UTF8.self) } ?? "").isEmpty
            }
        }.map(\.label)
    }

    /// A row from its printed line alone (label, figures, load, comparison), as the live stderr lines need it; the
    /// config fields stay empty.
    static func provisional(_ parsed: FdtdParsedBenchRow, thresholds: FdtdThresholds) -> FdtdBenchRow {
        var row = FdtdBenchRow(label: parsed.label, config: parsed.label, lib: "", engine: "")
        row.reference = parsed.reference
        row.tolerant = parsed.tolerant
        let load = FdtdLoads.fromBenchRow(parsed, thresholds: thresholds)
        row.load = load
        if FdtdLoads.shows(load) {
            row.mcs = parsed.mcs
            row.seconds = parsed.seconds
        } else {
            row.speedWithheld = true
        }
        row.timesteps = parsed.timesteps
        row.cells = parsed.megaCells
        row.repeats = parsed.repeats ?? 1
        row.autoPickedThreads = parsed.autoPickedThreads
        row.othersCpuBefore = parsed.othersCpuBefore
        row.busyBefore = parsed.busyBefore
        row.quietWaitTimedOut = parsed.quietWaitTimedOut
        row.probesRel = parsed.probesRel
        row.zeroFiles = parsed.zeroFiles
        row.problems = parsed.problems
        row.sparams = parsed.sparams.map { s in
            FdtdSParam(name: s.name, maxAbsDiff: s.maxAbsDiff, maxDb: s.maxDb, exact: s.exact)
        }
        row.sparamNote = parsed.sparamNote
        row.openemsVersion = parsed.openemsVersion
        // compared rows carry probes rel=; the full check's reference is compared too (--repeat 2)
        row.exact = parsed.probesRel != nil ? parsed.exact : nil
        return row
    }

    /// The live line of a row as the pump sees it: `labels` and `tolerance` are per config, `index` counts from 1.
    static func liveLine(_ parsed: FdtdParsedBenchRow, index: Int, count: Int, tolerance: [Bool],
                         thresholds: FdtdThresholds) -> String {
        var row = provisional(parsed, thresholds: thresholds)
        if index >= 1, index <= tolerance.count, tolerance[index - 1] { row.tolerant = true }
        return line(row, index: index, count: count)
    }

    // MARK: - Private

    private static func fill(_ row: inout FdtdBenchRow, config: FdtdBenchConfig) {
        row.config = config.text
        row.lib = config.lib ?? "installed"
        row.engine = config.engine.rawValue
        row.threads = config.threads
        row.nodumps = config.nodumps
        row.knobs = FdtdKnobs.environment(config.knobs)
        if FdtdBenchConfigs.isTolerant(config) { row.tolerant = true }
    }

    /// Run folders and engine confirmation: every rep*/openEMS.log must show only Create lines of `engine` (F6).
    private static func confirm(_ row: inout FdtdBenchRow, folder: String, engine: FdtdEngine, system: any FdtdSystem) {
        let count = max(row.repeats ?? 1, 1)
        row.runFolders = (0..<count).map { FdtdPaths.join(folder, "rep\($0)") }
        var confirmed = true
        var create: String? = nil
        for dir in row.runFolders {
            let data = system.readFile(FdtdPaths.join(dir, "openEMS.log"))
            let log = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            if create == nil {
                create = log.split(whereSeparator: \.isNewline).lazy
                    .compactMap { FdtdParsers.createLine(String($0)) }.first?.line
            }
            if !FdtdBenchConfigs.createLineMatches(engine, log: log) { confirmed = false }
        }
        row.createLine = create
        row.engineConfirmed = confirmed
    }
}

/// `emskit fdtd bench`.
enum BenchCommand: FdtdCommandBody {
    static let name = FdtdCommandName.bench

    /// CFGs parsed and merged with --knob, libraries resolved (engine and knobs present), rfsim for kgcpw/ksma, the
    /// distribution record, the protected folders (RESULTS, the --tag table, RUNS), the --tag table refusal, the
    /// concurrency gate (refuses), the plan line; then bench under
    /// the launcher with a line per row as it completes, the rows and summary, engine confirmation from RUN/runs, the
    /// verdict and the summary line.
    static func run(_ options: FdtdBenchOptions, session: FdtdSession) throws {
        let context = session.context
        let system = context.system
        let model = options.run
        let configs = try benchConfigs(options.configs, knobs: options.knobs, command: .bench, session: session)
        // after the --knob usage rules (64) and before any probe: a usage error outranks a bad tag (2)
        try FdtdOptions.requireTag(options.tag)
        let repo = try session.discoverRepo()
        let libraries = try resolveConfigLibraries(configs, session: session)
        if model.model.needsRfsim { _ = try session.discoverRfsim(required: true) }

        var resultsFolder: String? = nil
        var table: String? = nil
        if let tag = options.tag {
            let folder = try FdtdDiscovery.resultsFolder(repo: repo.root, option: options.results, context: context)
            resultsFolder = folder
            table = FdtdPaths.join(folder, "\(model.name)_\(tag).txt")
        }
        try session.distributionRecord()

        let used = uniqueLibraries(configs, libraries)
        let jobConfigs = try jobConfigsFor(configs, libraries)
        let job = FdtdJob.bench(run: model, configs: jobConfigs, repeatCount: options.repeatCount, quiet: options.quiet,
                                noSparams: options.noSparams, tag: options.tag,
                                results: options.results == nil ? nil : resultsFolder)
        var tableExisted = false
        try session.refusals([job], libraries: used) {
            var targets: [FdtdWriteTarget] = []
            if let resultsFolder, let table {
                let label = options.results == nil ? "the results folder" : "--results"
                targets.append(.into(label, field: "--results", resultsFolder))
                targets += session.replacedTargets(table, label: "the table", field: "--tag", inPlace: true)
            }
            try session.refuseProtected(targets + session.runFolderTargets())
            if let table {
                tableExisted = try FdtdOutputs.refuseExisting(table, overwrite: session.common.overwrite, field: "--tag",
                                                              system: system)
            }
            try session.concurrencyGate(libraries: used, quietGiven: options.quiet != nil)
        }
        let backups = tableExisted ? try session.backUpTables(table.map { [$0] } ?? []) : [:]

        var result = FdtdBenchResult(model: model.model.rawValue, scale: model.scale, nrts: model.nrts, name: model.name,
                                     reference: configs[0].text, exact: options.exact)
        session.setResult(result)
        let folder = try session.prepareRunFolder()
        var plan = "bench \(model.model.rawValue): \(configs.count) config\(configs.count == 1 ? "" : "s")"
        plan += " x \(model.nrts) timesteps"
        if options.repeatCount > 1 { plan += ", \(options.repeatCount) runs each" }
        session.planLine(plan + session.runFolderText(folder))
        session.startCaffeinate()
        let backend = try session.localBackend(runFolder: folder, libraries: used)

        let collector = FdtdLineCollector()
        let onLine = liveRows(collector: collector, configs: configs, session: session)
        guard let spawned = try session.spawnJob(job, backend: backend, onLine: onLine) else { return }

        let parsed = FdtdParsers.benchOutput(collector.all.joined(separator: "\n"))
        let stopped = session.stop.stopRequested
        // a summary line stands for a finished bench run, whatever the CLI could read of its rows
        let summarized = parsed.summary != nil && !stopped
        if !parsed.rows.isEmpty || summarized {
            let names = (system.listDirectory(folder.runs) ?? []).filter { !$0.hasPrefix(".") }
            if names != [model.name] || (parsed.name != nil && parsed.name != model.name) {
                let listed = names.isEmpty ? "nothing" : names.joined(separator: ", ")
                let message = "\(folder.runs) holds \(listed), not the one folder \(model.name)"
                session.error(FdtdIssue(.toolOutputUnparsed, message))
            }
        }
        // bench prints one row per config before its summary; with fewer, the summary covers runs that no row here
        // shows, no engine was confirmed for them and --exact has nothing to look at
        if summarized, parsed.rows.count != configs.count {
            let message = "bench.py printed a summary line, but \(parsed.rows.count) readable "
                + "row\(parsed.rows.count == 1 ? "" : "s") for \(configs.count) config\(configs.count == 1 ? "" : "s")"
            session.error(FdtdIssue(.toolOutputUnparsed, message))
        }
        let rows = FdtdBenchRows.build(parsed, configs: configs, runsDir: folder.runs, thresholds: session.thresholds,
                                       system: system)
        for row in rows where row.engineConfirmed != true {
            let message = "\(row.label): not every rep*/openEMS.log shows a Create line of the \(row.engine) engine"
            session.error(FdtdIssue(.engineNotConfirmed, message, field: "--config"))
        }
        for label in FdtdBenchRows.gpuFallbacks(rows, system: system) { session.warn(FdtdVerdicts.gpuFallback(label)) }
        let verdict = FdtdVerdicts.bench(summary: parsed.summary, rows: rows, exact: options.exact,
                                         benchExit: spawned.report?.exit ?? spawned.exit)
        // after a stop the tool's exit says nothing about the comparison; finish() reports the interruption
        if !stopped { session.error(contentsOf: verdict.errors) }
        session.warn(contentsOf: verdict.warnings)
        session.partial = verdict.partial
        session.loadWarnings(withheld: rows.filter(\.speedWithheld).map(\.label),
                             loaded: rows.filter { $0.load?.loaded == true }.map(\.label))

        result.rows = rows
        result.summary = parsed.summary
        if let table, parsed.wrote != nil, system.fileExists(table) {
            result.resultsFile = table
            session.recordOutput(table, existedBefore: tableExisted, backup: backups[table])
        }
        session.setResult(result)
        session.note(summaryLine("bench \(model.model.rawValue)", kind: parsed.summary?.kind, rows: rows,
                                 session: session))
    }

    // MARK: - Shared with ab and check

    /// The CFGs parsed for `command` (bench or ab), with the --knob settings validated and merged into each.
    static func benchConfigs(_ texts: [String], knobs: [String], command: FdtdCommandName,
                             session: FdtdSession) throws -> [FdtdBenchConfig] {
        let context = session.context
        let configs = try texts.map { text in
            try FdtdBenchConfigs.parse(text, command: command, cwd: context.cwd, home: context.home,
                                       system: context.system)
        }
        let settings = try knobs.map { try FdtdKnobs.parse($0, field: "--knob") }
        for setting in settings {
            try FdtdKnobs.validate(setting, command: command, transport: .cfgList, system: context.system)
        }
        return try FdtdKnobs.merge(settings, into: configs)
    }

    /// The configs' libraries by spec ("installed" for a bare CFG): resolved, the python probe sent the first
    /// snapshot folder (bench sets DYLD itself, so the probe proves this Python keeps it), engines and knobs present
    /// (3), knob warnings added.
    static func resolveConfigLibraries(_ configs: [FdtdBenchConfig],
                                       session: FdtdSession) throws -> [String: FdtdLibrary] {
        var libraries: [String: FdtdLibrary] = [:]
        var specs: [String] = []
        for config in configs {
            let spec = config.lib ?? "installed"
            if !specs.contains(spec) { specs.append(spec) }
        }
        for spec in specs where spec != "installed" {
            let library = try session.resolveLibrary(spec)
            // bench.py refuses a folder of links to files elsewhere, but only after the first simulation
            try FdtdLibraries.requireOwnFiles(library, field: "--config", system: session.context.system)
            libraries[spec] = library
        }
        if let first = specs.first(where: { $0 != "installed" }), let library = libraries[first] {
            _ = try session.probePython(dyld: library.dir, snapshotNeeded: true)
        } else {
            _ = try session.probePython(dyld: nil, snapshotNeeded: false)
        }
        if specs.contains("installed") { libraries["installed"] = try session.resolveLibrary("installed") }
        try requireSupport(configs, libraries, session: session)
        return libraries
    }

    /// Each CFG against its library (by spec, "installed" for a bare CFG): the engine listed (3 engine_unsupported),
    /// the knobs present in its bytes (3 knob_unsupported), the knob warnings added. Shared with check's --extra.
    static func requireSupport(_ configs: [FdtdBenchConfig], _ libraries: [String: FdtdLibrary],
                               session: FdtdSession) throws {
        for config in configs {
            guard let library = libraries[config.lib ?? "installed"] else { continue }
            try FdtdLibraries.requireEngine(config.engine, in: library)
            try FdtdKnobs.requireSupported(config.knobs, library: library)
            session.warn(contentsOf: FdtdKnobs.warnings(config.knobs, engine: config.engine))
        }
    }

    /// Each CFG with its library's identity.
    static func jobConfigsFor(_ configs: [FdtdBenchConfig],
                              _ libraries: [String: FdtdLibrary]) throws -> [FdtdJobConfig] {
        try configs.map { config in
            guard let library = libraries[config.lib ?? "installed"] else {
                throw FdtdError(.libraryNotFound, "\(config.text): its library was not resolved", field: "--config")
            }
            return FdtdJobConfig.bench(config, library: library)
        }
    }

    /// The libraries in first-use order.
    static func uniqueLibraries(_ configs: [FdtdBenchConfig], _ libraries: [String: FdtdLibrary]) -> [FdtdLibrary] {
        var seen: [String] = []
        var list: [FdtdLibrary] = []
        for config in configs {
            let spec = config.lib ?? "installed"
            guard !seen.contains(spec), let library = libraries[spec] else { continue }
            seen.append(spec)
            list.append(library)
        }
        return list
    }

    /// `HEAD: STATUS: KIND; LABEL X MC/s (others cpu C% gpu G%), ...`: the figures of the rows with a valid load.
    static func summaryLine(_ head: String, kind: String?, rows: [FdtdBenchRow], session: FdtdSession) -> String {
        var text = head + ": " + session.statusSoFar
        if let kind { text += ": " + kind }
        let figures = rows.filter { FdtdLoads.shows($0.load) && $0.mcs != nil }.map { row in
            FdtdLoads.figure(row.label, mcs: row.mcs, load: row.load)
        }
        if !figures.isEmpty { text += "; " + figures.joined(separator: ", ") }
        return text
    }

    // MARK: - Private

    /// The pump-side handler: every line to the collector, and a stderr line for each bench row as it completes.
    private static func liveRows(collector: FdtdLineCollector, configs: [FdtdBenchConfig],
                                 session: FdtdSession) -> @Sendable (String) -> Void {
        let sink = session.context.stderr
        let counter = FdtdLiveCounter()
        let thresholds = session.thresholds
        let tolerance = configs.map { FdtdBenchConfigs.isTolerant($0) }
        let count = configs.count
        return { line in
            collector.append(line)
            guard let parsed = FdtdParsers.benchRow(line) else { return }
            let index = counter.next("row")
            let text = FdtdBenchRows.liveLine(parsed, index: index, count: count, tolerance: tolerance,
                                              thresholds: thresholds)
            sink.line("emskit fdtd: " + text)
        }
    }
}
