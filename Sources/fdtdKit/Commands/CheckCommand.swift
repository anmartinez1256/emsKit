// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd check` (spec 2.6): check.sh under the launcher, its final line checked by an independent guard, and
// the reference identity that decides whether the check is the CPU acceptance (bit-identity to stock v0.37.0) or
// only partial. check.sh always writes into the results folder beside its own real folder (REPO/results unless a
// link moves it) and fixes its own repeats, quiet wait and configs.
import Foundation
import Synchronization

/// One model of check.sh (check.sh:44-52), in its order.
struct FdtdCheckModelSpec: Sendable, Equatable {
    /// check.sh's label (patch_x5, notch_x3, patch, notch, kgcpw, ksma).
    var label: String
    var model: FdtdBenchModel
    var scale: Double
    var nrts: Int
    /// The reference config's thread count ($REF@multithreaded:N).
    var referenceThreads: Int

    /// bench's `MODEL_s%g_nN`, which names the run folder and REPO/results/NAME_TAG.txt.
    var name: String { FdtdModelRun(model: model, scale: scale, nrts: nrts, nrtsGiven: true).name }
}

/// check's reference{}.
struct FdtdCheckReference: Codable, Sendable, Equatable {
    var spec: String
    var dir: String
    var files: [FdtdFileIdentity] = []
    /// SNAPS/stock.
    var stockDir: String
    @FdtdNullable var stockScan: FdtdStockScan? = nil
    /// "uuid", "sha256" or null.
    @FdtdNullable var matchedBy: String? = nil
    var acceptance: Bool
}

/// One model block of check's result.
struct FdtdCheckModel: Codable, Sendable, Equatable {
    var label: String
    var name: String
    @FdtdNullable var resultsFile: String? = nil
    @FdtdNullable var summary: FdtdBenchSummary? = nil
    var rows: [FdtdBenchRow] = []
}

/// check's result.
struct FdtdCheckResult: Codable, Sendable, Equatable {
    var tag: String
    var snapshots: [String]
    var reference: FdtdCheckReference
    var lite: Bool
    var models: [FdtdCheckModel] = []
    @FdtdNullable var finalLine: String? = nil
    /// ALL IDENTICAL, PARTIAL, FAIL, or null.
    @FdtdNullable var verdict: String? = nil
    var exactRows = 0
    var expectedExactRows = 0
}

/// `emskit fdtd check`.
enum CheckCommand: FdtdCommandBody {
    static let name = FdtdCommandName.check

    /// check.sh's models; kgcpw and ksma run only with RFSIM_PATH.
    static let models: [FdtdCheckModelSpec] = [
        FdtdCheckModelSpec(label: "patch_x5", model: .patch, scale: 5, nrts: 1200, referenceThreads: 8),
        FdtdCheckModelSpec(label: "notch_x3", model: .notch, scale: 3, nrts: 2000, referenceThreads: 8),
        FdtdCheckModelSpec(label: "patch", model: .patch, scale: 1, nrts: 10500, referenceThreads: 2),
        FdtdCheckModelSpec(label: "notch", model: .notch, scale: 1, nrts: 16000, referenceThreads: 4),
        FdtdCheckModelSpec(label: "kgcpw", model: .kgcpw, scale: 1, nrts: 15000, referenceThreads: 4),
        FdtdCheckModelSpec(label: "ksma", model: .ksma, scale: 1, nrts: 6000, referenceThreads: 4),
    ]

    /// SNAPs resolved (a name, a folder, or `installed`), the reference (--stock or "stock") with the stock scan and
    /// match, --extra CFGs (their libraries resolved, engines and knobs present as for a bench CFG;
    /// extra_not_counted for tolerant ones), rfsim (2 unless --allow-partial), the protected
    /// folders (the results folder, the tables, RUNS), the result tables (5 when one exists, copies first with
    /// --overwrite), the python name rule, the concurrency warning; then
    /// check.sh with STOCK, LITE, EXTRA, QUIET_MAX, OPENEMS_BENCH_RUNS and OPENEMS_BENCH_SNAPS; the blocks, the final
    /// line, the guard and the verdict.
    static func run(_ options: FdtdCheckOptions, session: FdtdSession) throws {
        let context = session.context
        let system = context.system
        let extras = try options.extras.map { text in
            try FdtdBenchConfigs.parse(text, command: .check, cwd: context.cwd, home: context.home, system: system)
        }
        for extra in extras where FdtdBenchConfigs.isTolerant(extra) {
            let message = "\(extra.text) is compared, not counted: check.sh counts no gpu, metal-diamond or FTZ config"
            session.warn(FdtdIssue(.extraNotCounted, message, field: "--extra"))
        }
        let repo = try session.discoverRepo()
        let python = try session.discoverPython()
        // check.sh calls python3 by name, so that name must be the probed Python
        try FdtdDiscovery.requirePythonName(python, system: system)

        var snapshots: [FdtdLibrary] = []
        for spec in options.snapshots {
            let library = try session.resolveLibrary(spec)
            try requireCarried(library, field: "SNAP")
            // bench.py refuses a folder of links to files elsewhere, but only after the first simulation
            try FdtdLibraries.requireOwnFiles(library, field: "SNAP", system: system)
            if !snapshots.contains(where: { $0.spec == library.spec }) { snapshots.append(library) }
        }
        let referenceSpec = options.stock ?? "stock"
        let referenceLibrary = try session.resolveLibrary(referenceSpec)
        try requireCarried(referenceLibrary, field: "--stock")
        try FdtdLibraries.requireOwnFiles(referenceLibrary, field: "--stock", system: system)
        // an extra names its own library: resolved here (2), so that a dry run refuses what bench.py would
        var extraLibraries: [String: FdtdLibrary] = [:]
        for extra in extras {
            let spec = extra.lib ?? "installed"
            if extraLibraries[spec] == nil {
                let library = try session.resolveLibrary(spec)
                try FdtdLibraries.requireOwnFiles(library, field: "--extra", system: system)
                extraLibraries[spec] = library
            }
        }
        let extraOnly = BenchCommand.uniqueLibraries(extras, extraLibraries)
        // bench sets DYLD for every run itself; the probe proves that this Python keeps it
        let firstFolder = (snapshots + [referenceLibrary] + extraOnly).first(where: { $0.kind != .installed })?.dir
        _ = try session.probePython(dyld: firstFolder, snapshotNeeded: firstFolder != nil)
        // an engine or a knob the extra's library lacks would do nothing, and its row would still count (3)
        try BenchCommand.requireSupport(extras, extraLibraries, session: session)
        let reference = referenceIdentity(referenceLibrary, session: session)
        if !reference.acceptance { session.warn(FdtdVerdicts.referenceNotStock(referenceSpec)) }

        let rfsim = try session.discoverRfsim(required: !options.allowPartial)
        // the planned status (a dry run never reaches the verdict, which sets it again after a run)
        session.partial = !reference.acceptance || rfsim == nil
        let models = rfsim == nil ? Array(Self.models.prefix(4)) : Self.models
        // where check.sh's bench.py really writes: beside the real folder of check.sh, not REPO by name
        let results = FdtdDiscovery.checkResultsFolder(repo: repo.root, system: system)
        let tables = models.map { FdtdPaths.join(results, "\($0.name)_\(options.tag).txt") }
        try session.distributionRecord()

        // the configs check.sh builds for every model, so that bench's labels and run folders can be matched
        let blockConfigs = try models.map { model in
            try configs(for: model, reference: referenceLibrary, snapshots: snapshots, extras: extras,
                        lite: options.lite, session: session)
        }
        var used = snapshots
        for library in [referenceLibrary] + extraOnly where !used.contains(where: { $0.spec == library.spec }) {
            used.append(library)
        }
        let job = FdtdJob.check(tag: options.tag, snapshots: snapshots, stock: options.stock, lite: options.lite,
                                extras: extras.map(\.text), quietMax: options.quietMax)
        var existing: [String] = []
        try session.refusals([job], libraries: used) {
            // check.sh writes into the results folder beside its own real folder, which only --repo moves
            var targets = [FdtdWriteTarget.into("the results folder", field: "--repo", results)]
            for table in tables {
                targets += session.replacedTargets(table, label: "the table", field: "--tag", inPlace: true)
            }
            try session.refuseProtected(targets + session.runFolderTargets())
            for table in tables {
                if try FdtdOutputs.refuseExisting(table, overwrite: session.common.overwrite, field: "--tag",
                                                  system: system) {
                    existing.append(table)
                }
            }
            try session.concurrencyGate(libraries: used, quietGiven: false)
        }
        let backups = try session.backUpTables(existing)

        let expected = FdtdVerdicts.expectedExactRows(snapshots: snapshots.count, lite: options.lite,
                                                      nonTolerantExtras: extras.filter { !FdtdBenchConfigs.isTolerant($0) }.count)
        var result = FdtdCheckResult(tag: options.tag, snapshots: snapshots.map(\.spec), reference: reference,
                                     lite: options.lite)
        result.expectedExactRows = expected * models.count
        session.setResult(result)
        let folder = try session.prepareRunFolder()
        var plan = "check \(options.tag): " + snapshots.map(\.spec).joined(separator: ", ") + " against \(referenceSpec)"
        plan += ", \(models.count) models" + (options.lite ? ", lite" : "")
        session.planLine(plan + session.runFolderText(folder))
        session.startCaffeinate()
        let backend = try session.localBackend(runFolder: folder, libraries: used)

        let collector = FdtdLineCollector()
        let perBlock = blockConfigs.first?.count ?? 0
        let onLine = liveRows(collector: collector, count: perBlock, session: session)
        guard let spawned = try session.spawnJob(job, backend: backend, onLine: onLine) else { return }
        let stopped = session.stop.stopRequested

        let parsed = FdtdParsers.checkOutput(collector.all.joined(separator: "\n"))
        var checked: [FdtdCheckModel] = []
        for block in parsed.blocks {
            guard let k = models.firstIndex(where: { $0.name == block.name }) else {
                let message = "check.sh printed a block \(block.name ?? "without a name") that is not one of its models"
                session.error(FdtdIssue(.toolOutputUnparsed, message))
                continue
            }
            var model = FdtdCheckModel(label: models[k].label, name: models[k].name)
            model.summary = block.summary
            model.rows = FdtdBenchRows.build(block, configs: blockConfigs[k], runsDir: folder.runs,
                                             thresholds: session.thresholds, system: system)
            // bench's own rule: one row per config before the summary. The verdict counts only the exact rows, so
            // without this a missing tolerant extra or lite reference row would leave its engine unconfirmed
            let configs = blockConfigs[k].count
            if block.summary != nil, !stopped, block.rows.count != configs {
                let message = "check model \(model.label): bench.py printed a summary line, but \(block.rows.count) "
                    + "readable row\(block.rows.count == 1 ? "" : "s") for \(configs) config\(configs == 1 ? "" : "s")"
                session.error(FdtdIssue(.toolOutputUnparsed, message))
            }
            for label in FdtdBenchRows.gpuFallbacks(model.rows, system: system) {
                session.warn(FdtdVerdicts.gpuFallback("\(model.label) \(label)"))
            }
            if block.wrote != nil, system.fileExists(tables[k]) {
                model.resultsFile = tables[k]
                session.recordOutput(tables[k], existedBefore: existing.contains(tables[k]), backup: backups[tables[k]])
            }
            checked.append(model)
        }
        result.models = checked
        result.finalLine = parsed.finalLine?.line
        if let kind = parsed.finalLine?.kind, kind != .benchStopped { result.verdict = kind.rawValue }
        result.exactRows = checked.reduce(0) { total, model in
            total + model.rows.filter { !$0.tolerant && $0.exact == true }.count
        }
        session.setResult(result)

        let verdict = FdtdVerdicts.check(finalLine: parsed.finalLine, models: checked, expectedExactRows: expected,
                                         acceptance: reference.acceptance, referenceSpec: referenceSpec,
                                         allowPartial: options.allowPartial, rfsimFound: rfsim != nil)
        if !stopped {
            session.error(contentsOf: verdict.errors)
            if parsed.finalLine == nil, let exit = spawned.report?.exit ?? spawned.exit, exit != 0 {
                session.error(FdtdIssue(.toolFailed, "check.sh exited with status \(exit) without a final line"))
            }
        }
        session.warn(contentsOf: verdict.warnings)
        session.partial = verdict.partial
        let rows = checked.flatMap { model in model.rows.map { (model, $0) } }
        session.loadWarnings(withheld: rows.filter { $0.1.speedWithheld }.map { "\($0.0.label) \($0.1.label)" },
                             loaded: rows.filter { $0.1.load?.loaded == true }.map { "\($0.0.label) \($0.1.label)" })
        for model in checked {
            session.note(BenchCommand.summaryLine("check \(options.tag) \(model.label)", kind: model.summary?.kind,
                                                  rows: model.rows, session: session))
        }
        var final = "check \(options.tag): " + session.statusSoFar
        if let line = parsed.finalLine { final += ": " + line.kind.rawValue }
        final += ", \(result.exactRows) of \(result.expectedExactRows) counted rows exact"
        if !reference.acceptance { final += ", not the CPU acceptance (reference \(referenceSpec))" }
        session.note(final)
    }

    // MARK: - Private

    /// The reference's files against SNAPS/stock: the stock scan, the per-file match and the acceptance.
    private static func referenceIdentity(_ library: FdtdLibrary, session: FdtdSession) -> FdtdCheckReference {
        let context = session.context
        let index = session.snapshotIndex()
        let scan = FdtdLibraries.stockScan(snaps: session.snapshotsFolder(), index: index, system: context.system)
        var stock: FdtdLibrary? = nil
        if library.kind == .snapshot, library.spec == "stock" {
            stock = library
        } else if scan.exists,
                  let location = try? FdtdLibraries.locate("stock", snaps: session.snapshotsFolder(), installedDir: nil,
                                                           cwd: context.cwd, home: context.home,
                                                           system: context.system) {
            // from the index, which has read and hashed SNAPS/stock already, or from the files of a folder that the
            // listing leaves out (another letter case, a folder that cannot be listed)
            stock = FdtdLibraries.record(location, index: index, system: context.system)
        }
        let match = FdtdLibraries.stockMatch(reference: library, stock: stock, scan: scan)
        var reference = FdtdCheckReference(spec: library.spec, dir: library.dir, files: match.files, stockDir: scan.dir,
                                           acceptance: match.acceptance)
        reference.stockScan = scan
        reference.matchedBy = match.matchedBy
        return reference
    }

    /// 2 config_invalid under `field` (SNAP or --stock) when check.sh's configs cannot carry the library's argument;
    /// configs(for:) would refuse the same text as a bad --extra.
    private static func requireCarried(_ library: FdtdLibrary, field: String) throws {
        let text = argument(library)
        guard !FdtdBenchConfigs.carries(lib: text) else { return }
        let message = "\(library.spec): check.sh's configs cannot carry the library \(text) "
            + "('@', '#', ',', ';' or spaces in it)"
        throw FdtdError(.configInvalid, message, field: field, hint: FdtdBenchConfigs.libHint)
    }

    /// The argument check.sh gets for a library, by the rule the check job's invocation is built with
    /// (FdtdLocalBackend.checkArgument): a snapshot's name, the folder otherwise.
    private static func argument(_ library: FdtdLibrary) -> String {
        FdtdLocalBackend.checkArgument(spec: library.spec) { _ in library.dir }
    }

    /// check.sh:24-29 for one model: $REF@multithreaded:N, then per SNAP multithreaded:T for T in (4 8) or (1 4 8 10)
    /// and @fastest, then EXTRA.
    private static func configs(for model: FdtdCheckModelSpec, reference: FdtdLibrary, snapshots: [FdtdLibrary],
                                extras: [FdtdBenchConfig], lite: Bool, session: FdtdSession) throws -> [FdtdBenchConfig] {
        let context = session.context
        var texts = ["\(argument(reference))@multithreaded:\(model.referenceThreads)"]
        let threads = lite ? [4, 8] : [1, 4, 8, 10]
        for snapshot in snapshots {
            texts += threads.map { "\(argument(snapshot))@multithreaded:\($0)" }
            texts.append("\(argument(snapshot))@fastest")
        }
        var configs = try texts.map { text in
            try FdtdBenchConfigs.parse(text, command: .check, cwd: context.cwd, home: context.home,
                                       system: context.system)
        }
        // the rows name the LIB as given on the command line (installed for the installed folder)
        let specs = Dictionary(([reference] + snapshots).map { (argument($0), $0.spec) }, uniquingKeysWith: { a, _ in a })
        for k in configs.indices {
            if let lib = configs[k].lib, let spec = specs[lib] { configs[k].lib = spec }
        }
        configs += extras
        return configs
    }

    /// The pump-side handler: every line to the collector, and a stderr line per bench row as it completes, numbered
    /// within its model block (a bench header starts a block).
    private static func liveRows(collector: FdtdLineCollector, count: Int,
                                 session: FdtdSession) -> @Sendable (String) -> Void {
        let sink = session.context.stderr
        let thresholds = session.thresholds
        let block = FdtdCheckBlockState()
        return { line in
            collector.append(line)
            if line.hasPrefix("# "), let end = line.range(of: "  load avg ") {
                let start = line.index(line.startIndex, offsetBy: 2)
                if start <= end.lowerBound { block.start(String(line[start..<end.lowerBound])) }
                return
            }
            guard let parsed = FdtdParsers.benchRow(line) else { return }
            let (name, index) = block.nextRow()
            let text = FdtdBenchRows.liveLine(parsed, index: index, count: count, tolerance: [], thresholds: thresholds)
            sink.line("emskit fdtd: check \(name): " + text)
        }
    }
}

/// The model block the live check lines are in, and its row count (pump thread only, but Sendable for the closure).
private final class FdtdCheckBlockState: Sendable {
    private let state = Mutex<(name: String, rows: Int)>(("", 0))

    func start(_ name: String) { state.withLock { $0 = (name, 0) } }

    func nextRow() -> (String, Int) {
        state.withLock { current in
            current.rows += 1
            return (current.name, current.rows)
        }
    }
}
