// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd ab` (spec 2.5): one abtest.py call under the launcher, with a 1 s sampler check before and after it.
// The CLI computes each config's statistics itself from the kept runs with valid loads; abtest's own summary lines
// (medians over -1 values) stay in tool.log and the record file.
import Foundation

/// ab's result.
struct FdtdABResult: Codable, Sendable, Equatable {
    var model: String
    var scale: Double
    var nrts: Int
    var rounds: Int
    /// RUN/abtest.txt, or --record FILE.
    var recordFile: String
    /// c0 is tolerant, so every config is (bench.py:327).
    var tolerantFromReference: Bool
    var samplerChecks: [FdtdLoad] = []
    var configs: [FdtdABConfigResult] = []
    var runs: [FdtdABRunResult] = []
}

/// `emskit fdtd ab`.
enum ABCommand: FdtdCommandBody {
    static let name = FdtdCommandName.ab

    /// As bench up to the gate (the protected folders: the record and RUNS); the record file (a FILE in an existing
    /// folder, as --output; refused when it exists unless --append; its size is noted so only the
    /// new part is parsed); the sampler check before (invalid → 4 load_unavailable, nothing runs); abtest; the check
    /// after (invalid → every run's load invalid; a dry run or a refusal plans both checks and runs neither); the
    /// record part (or the stdout lines after an interrupt, kept null);
    /// engine confirmation from RUN/runs/ab_*/c{i}/r{r}/openEMS.log; statistics, verdict, per-run and per-config lines.
    static func run(_ options: FdtdABOptions, session: FdtdSession) throws {
        let context = session.context
        let system = context.system
        let model = options.run
        let configs = try BenchCommand.benchConfigs(options.configs, knobs: options.knobs, command: .ab,
                                                    session: session)
        _ = try session.discoverRepo()
        let libraries = try BenchCommand.resolveConfigLibraries(configs, session: session)
        if model.model.needsRfsim { _ = try session.discoverRfsim(required: true) }
        try session.distributionRecord()

        let given = options.record.map { session.absolutePath($0) }
        let used = BenchCommand.uniqueLibraries(configs, libraries)
        let job = FdtdJob.ab(run: model, configs: try BenchCommand.jobConfigsFor(configs, libraries),
                             rounds: options.rounds, quiet: options.quiet, redo: options.redo,
                             runRedo: options.runRedo, record: given)
        var recordExisted = false
        // a refused ab shows what would have run: the two sampler checks around abtest as well
        try session.refusals([.samplerCheck(), job, .samplerCheck()], libraries: used) {
            // abtest appends to the record in place
            let record = given.map { FdtdWriteTarget.inPlace("--record", field: "--record", $0) }
                ?? .inPlace("the record", field: "--record", session.plannedRunFolder().abRecord)
            try session.refuseProtected([record] + session.runFolderTargets())
            if let given {
                // --output's checks: abtest opens the record only after all rounds, and a folder would fail there
                try session.requireFile(given, option: "--record", example: "abtest.txt")
                // abtest appends at the end of the file; without --append an existing record is refused
                recordExisted = system.fileExists(given)
                if !options.append {
                    _ = try FdtdOutputs.refuseExisting(given, overwrite: false, field: "--record", system: system)
                }
            }
            try session.concurrencyGate(libraries: used, quietGiven: options.quiet != nil)
        }

        let labels = configs.map { FdtdBenchConfigs.label($0.text) }
        let folder = try session.prepareRunFolder()
        let record = given ?? folder.abRecord
        var result = FdtdABResult(model: model.model.rawValue, scale: model.scale, nrts: model.nrts,
                                  rounds: options.rounds, recordFile: record,
                                  tolerantFromReference: FdtdBenchConfigs.isTolerant(configs[0]))
        session.setResult(result)
        var plan = "ab \(model.model.rawValue): \(configs.count) configs x \(options.rounds) round"
        plan += "\(options.rounds == 1 ? "" : "s") x \(model.nrts) timesteps"
        session.planLine(plan + session.runFolderText(folder))
        session.startCaffeinate()
        let backend = try session.localBackend(runFolder: folder, libraries: used)

        // abtest's run lines carry no self figure and no gpu dev: only a sampler around the run tells a working
        // sampler from an idle Mac (spec 2.5)
        let before = try session.samplerCheck(backend: backend)
        result.samplerChecks.append(before)
        session.setResult(result)
        if !session.common.dryRun, !before.valid {
            let reason = before.invalidReason ?? "the sampler result is not valid"
            session.error(FdtdIssue(.loadUnavailable, "the sampler check before the run is not valid: " + reason,
                                    hint: "emskit fdtd load"))
            return
        }
        let sizeBefore = recordExisted ? (system.fileSize(record) ?? 0) : 0
        let collector = FdtdLineCollector()
        let onLine = liveRuns(collector: collector, labels: labels, sink: context.stderr)
        guard let spawned = try session.spawnJob(job, backend: backend, onLine: onLine) else {
            // a dry run plans the check after the run as well, so that its invocations are those of a run
            result.samplerChecks.append(try session.samplerCheck(backend: backend))
            session.setResult(result)
            return
        }
        let stopped = session.stop.stopRequested
        var after: FdtdLoad? = nil
        if !stopped {
            let check = try session.samplerCheck(backend: backend)
            result.samplerChecks.append(check)
            after = check
        }
        let checksValid = before.valid && after?.valid == true

        // the record part is written only at the end (abtest.py:104-106); without it, stdout has every run line
        var parsed = FdtdParsers.abtestOutput("")
        var kept: Bool? = nil
        if let data = system.readFile(record), data.count > sizeBefore {
            parsed = FdtdParsers.abtestOutput(String(decoding: data.dropFirst(sizeBefore), as: UTF8.self))
            session.recordOutput(record, existedBefore: recordExisted)
            kept = true
        }
        if parsed.runs.isEmpty {
            parsed = FdtdParsers.abtestOutput(collector.all.joined(separator: "\n"))
            kept = nil
        }
        let runs = parsed.runs.map { run in
            runResult(run, kept: kept.map { _ in !run.redo }, checksValid: checksValid, thresholds: session.thresholds)
        }
        let tolerance = FdtdBenchConfigs.abTolerance(configs)
        let statistics = FdtdLoads.abStatistics(runs: runs, configs: configs.map(\.text), labels: labels,
                                                tolerant: tolerance)
        result.runs = runs
        result.configs = statistics
        session.setResult(result)

        confirmEngines(configs, labels: labels, runsDir: folder.runs, stopped: stopped, session: session)
        let verdict = FdtdVerdicts.ab(abtestExit: spawned.report?.exit ?? spawned.exit, configs: statistics,
                                      summaries: parsed.summaries, exact: options.exact)
        if !stopped { session.error(contentsOf: verdict.errors) }
        session.warn(contentsOf: verdict.warnings)
        session.partial = verdict.partial
        if after?.valid == false {
            let reason = after?.invalidReason ?? "the sampler result is not valid"
            session.warn(FdtdIssue(.loadMissing, "the sampler check after the run is not valid, so no run speed counts: "
                                                 + reason, hint: "emskit fdtd load"))
        }

        for run in runs where run.kept != false {
            session.note(runLine(run, labels: labels))
        }
        for config in statistics {
            session.note(configLine(config))
        }
        let withheld = statistics.filter { $0.runsWithoutLoad > 0 }.map { "c\($0.index) \($0.label)" }
        let loaded = statistics.filter { config in
            (config.othersCpuMedian ?? 0) > session.common.warnCpu || (config.othersGpuMedian ?? 0) > session.common.warnGpu
        }.map { "c\($0.index) \($0.label)" }
        session.loadWarnings(withheld: after?.valid == false ? [] : withheld, loaded: loaded)
        session.note(summary(model.model.rawValue, statistics, session: session))
    }

    // MARK: - Private

    private static func runResult(_ run: FdtdParsedABRun, kept: Bool?, checksValid: Bool,
                                  thresholds: FdtdThresholds) -> FdtdABRunResult {
        let load = FdtdLoads.fromAbtestRun(run, samplerChecksValid: checksValid, thresholds: thresholds)
        var result = FdtdABRunResult(round: run.round, config: run.config, loadValid: load.valid, diff: run.diff)
        result.mcs = load.valid ? run.mcs : nil
        result.othersCpu = run.othersCpu >= 0 ? run.othersCpu : nil
        result.othersGpu = run.othersGpu >= 0 ? run.othersGpu : nil
        result.kept = kept
        return result
    }

    /// Every c{i}/r{r}/openEMS.log under the one RUN/runs/ab_* folder must show only Create lines of the engine; a
    /// metal-diamond log with a fallback line gives gpu_fallback.
    private static func confirmEngines(_ configs: [FdtdBenchConfig], labels: [String], runsDir: String, stopped: Bool,
                                       session: FdtdSession) {
        let system = session.context.system
        let folders = (system.listDirectory(runsDir) ?? []).filter { $0.hasPrefix("ab_") }
        guard folders.count == 1 else {
            if !stopped {
                let listed = folders.isEmpty ? "no ab_* folder" : folders.joined(separator: ", ")
                session.error(FdtdIssue(.toolOutputUnparsed, "\(runsDir) holds \(listed), not one ab_* folder"))
            }
            return
        }
        let base = FdtdPaths.join(runsDir, folders[0])
        for (i, config) in configs.enumerated() {
            let configDir = FdtdPaths.join(base, "c\(i)")
            let rounds = (system.listDirectory(configDir) ?? []).filter { $0.hasPrefix("r") }
            var problems: [String] = []
            var fallbacks: [String] = []
            for round in rounds {
                let data = system.readFile(FdtdPaths.join(FdtdPaths.join(configDir, round), "openEMS.log"))
                let log = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                if !FdtdBenchConfigs.createLineMatches(config.engine, log: log) { problems.append(round) }
                if config.engine == .metalDiamond, !FdtdParsers.gpuFallbackLines(log).isEmpty { fallbacks.append(round) }
            }
            if !fallbacks.isEmpty {
                session.warn(FdtdVerdicts.gpuFallback("c\(i) \(labels[i]) (\(fallbacks.joined(separator: ", ")))"))
            }
            if rounds.isEmpty && !stopped { problems.append("no run") }
            guard !problems.isEmpty else { continue }
            let message = "c\(i) \(labels[i]): \(problems.joined(separator: ", ")) shows no Create line of the "
                + "\(config.engine.rawValue) engine"
            session.error(FdtdIssue(.engineNotConfirmed, message, field: "--config"))
        }
    }

    /// The pump-side handler: every line to the collector, and a progress line per abtest run (its figure follows
    /// once the closing sampler check has passed).
    private static func liveRuns(collector: FdtdLineCollector, labels: [String],
                                 sink: FdtdSink) -> @Sendable (String) -> Void {
        { line in
            collector.append(line)
            let parsed = FdtdParsers.abtestOutput(line)
            guard let run = parsed.runs.first, !run.redo else { return }
            let label = run.config < labels.count ? labels[run.config] : "c\(run.config)"
            sink.line("emskit fdtd: ab r\(run.round) c\(run.config) \(label): done, \(run.diff)")
        }
    }

    /// `ab rR cI LABEL: X MC/s (others cpu C% gpu G%), DIFF`, or the label with the speed withheld.
    private static func runLine(_ run: FdtdABRunResult, labels: [String]) -> String {
        let label = run.config < labels.count ? labels[run.config] : "c\(run.config)"
        var text = "ab r\(run.round) c\(run.config) \(label): "
        if run.loadValid, let mcs = run.mcs {
            let others = "others cpu \(FdtdFigures.percent(run.othersCpu.map(Double.init))) "
                + "gpu \(FdtdFigures.percent(run.othersGpu.map(Double.init)))"
            text += "\(FdtdFigures.mcs(mcs)) MC/s (\(others))"
        } else {
            text += "speed withheld (no valid load during the run)"
        }
        if run.kept == false { text += ", discarded" }
        return text + ", " + run.diff
    }

    /// `cI LABEL x1.372 [1.351-1.390], median 1397.2 MC/s (others cpu 45% gpu 2%), 5 of 5 runs with a load`.
    private static func configLine(_ config: FdtdABConfigResult) -> String {
        let total = config.runsWithLoad + config.runsWithoutLoad
        let counted = "\(config.runsWithLoad) of \(total) runs with a load"
        var text = "c\(config.index) \(config.label)"
        guard let median = config.medianMcs else {
            return text + ": speed withheld (no valid load during the run), " + counted
        }
        if let ratio = config.medianRatio, let low = config.minRatio, let high = config.maxRatio {
            text += String(format: " x%.3f [%.3f-%.3f]", ratio, low, high)
        }
        let others = "others cpu \(FdtdFigures.percent(config.othersCpuMedian)) "
            + "gpu \(FdtdFigures.percent(config.othersGpuMedian))"
        return text + ", median \(FdtdFigures.mcs(median)) MC/s (\(others)), " + counted
    }

    /// `ab MODEL: STATUS; LABEL X MC/s (others cpu C% gpu G%), ...` with the configs' median speeds.
    private static func summary(_ model: String, _ statistics: [FdtdABConfigResult], session: FdtdSession) -> String {
        var text = "ab \(model): " + session.statusSoFar
        let figures = statistics.compactMap { config -> String? in
            guard let median = config.medianMcs else { return nil }
            let others = "others cpu \(FdtdFigures.percent(config.othersCpuMedian)) "
                + "gpu \(FdtdFigures.percent(config.othersGpuMedian))"
            return "\(config.label) \(FdtdFigures.mcs(median)) MC/s (\(others))"
        }
        if !figures.isEmpty { text += "; " + figures.joined(separator: ", ") }
        return text
    }
}
