// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd debye-check` and `emskit fdtd diamond-check` (spec 2.8): the two zsh check scripts under the launcher in
// exec mode with --load, after a zsh pre-probe per library folder that proves the scripts' own zsh → python3 path
// keeps DYLD (F1). Both need fork builds; the gates refuse other libraries before anything runs.
import Foundation

/// debye-check's result.
struct FdtdDebyeResult: Codable, Sendable, Equatable {
    /// The LIB as given; its record is in envelope.libraries.
    var library: String
    @FdtdNullable var reference: String? = nil
    @FdtdNullable var threads: Int? = nil
    /// The `== ` run headers.
    var runs: [String] = []
    /// Titled by the `X vs Y:` lines: 2 comparisons, or 3 with --ref.
    var comparisons: [FdtdScriptComparison] = []
    @FdtdNullable var verdictLine: String? = nil
}

/// diamond-check's result.
struct FdtdDiamondResult: Codable, Sendable, Equatable {
    var library: String
    /// Counted from the `== ` lines, never hardcoded.
    var boxes = 0
    var comparisons = 0
    var identical = 0
    /// "BOX: LABEL" of each DIFFERENT comparison.
    var different: [String] = []
    var gpuPathMissing: [String] = []
    var tuningUnfinished = false
    @FdtdNullable var verdictLine: String? = nil
}

/// `emskit fdtd debye-check`.
enum DebyeCheckCommand: FdtdCommandBody {
    static let name = FdtdCommandName.debyeCheck

    /// LIB and --ref complete, both with OPENEMS_EXPORT_FIELDS (3 library_lacks_feature, hint "debye_check.sh needs
    /// fork builds"); the python name rule; the pre-probes; then debye_check.sh LIBDIR [REFDIR] with THREADS and
    /// TMPDIR=RUN/tmp, cwd RUN.
    static func run(_ options: FdtdDebyeCheckOptions, session: FdtdSession) throws {
        let hint = "debye_check.sh needs fork builds"
        var libraries = [try FdtdScriptChecks.gatedLibrary(options.lib, knobs: ["OPENEMS_EXPORT_FIELDS"], engines: [],
                                                           hint: hint, session: session)]
        if let ref = options.ref {
            libraries.append(try FdtdScriptChecks.gatedLibrary(ref, knobs: ["OPENEMS_EXPORT_FIELDS"], engines: [],
                                                               hint: hint, session: session))
        }
        let job = FdtdJob.debye(library: libraries[0], reference: libraries.count > 1 ? libraries[1] : nil,
                                threads: options.threads)
        var result = FdtdDebyeResult(library: options.lib, reference: options.ref, threads: options.threads)
        var plan = "debye-check \(options.lib)"
        if let ref = options.ref { plan += " against \(ref)" }
        plan += ": debye_check.sh, \(options.threads.map(String.init) ?? "the script's default of 4") threads"
        guard let run = try FdtdScriptChecks.launch(job, libraries: libraries, plan: plan, session: session,
                                                    result: result) else { return }

        let parsed = FdtdParsers.debyeOutput(run.output)
        let verdict = FdtdVerdicts.debye(exit: run.exit, parsed: parsed)
        FdtdScriptChecks.apply(verdict, load: run.load, session: session)
        result.runs = parsed.runs
        result.comparisons = parsed.comparisons
        result.verdictLine = parsed.verdictLine
        session.setResult(result)
        let identical = parsed.comparisons.filter(\.identical).count
        let counts = "\(identical) of \(parsed.comparisons.count) comparisons identical"
        session.note(FdtdScriptChecks.summary("debye-check \(options.lib)", verdictLine: parsed.verdictLine,
                                              counts: counts, load: run.load, session: session))
    }
}

/// `emskit fdtd diamond-check`.
enum DiamondCheckCommand: FdtdCommandBody {
    static let name = FdtdCommandName.diamondCheck

    /// LIB complete, listing metal-diamond and containing OPENEMS_EXPORT_FIELDS, OPENEMS_FTZ and OPENEMS_DIAMOND_TUNE
    /// (3 library_lacks_feature, hint "diamond_check.sh tests the tiling tuner: cg28 or later"); the python name rule;
    /// the pre-probe; then diamond_check.sh LIBDIR with TMPDIR=RUN/tmp, cwd RUN.
    static func run(_ options: FdtdDiamondCheckOptions, session: FdtdSession) throws {
        let knobs = ["OPENEMS_EXPORT_FIELDS", "OPENEMS_FTZ", "OPENEMS_DIAMOND_TUNE"]
        let library = try FdtdScriptChecks.gatedLibrary(options.lib, knobs: knobs, engines: [.metalDiamond],
                                                        hint: "diamond_check.sh tests the tiling tuner: cg28 or later",
                                                        session: session)
        let job = FdtdJob.diamond(library: library)
        var result = FdtdDiamondResult(library: options.lib)
        let plan = "diamond-check \(options.lib): diamond_check.sh, the metal-diamond engine against the CPU engine"
        guard let run = try FdtdScriptChecks.launch(job, libraries: [library], plan: plan, session: session,
                                                    result: result) else { return }

        let parsed = FdtdParsers.diamondOutput(run.output)
        let verdict = FdtdVerdicts.diamond(exit: run.exit, parsed: parsed)
        FdtdScriptChecks.apply(verdict, load: run.load, session: session)
        result.boxes = parsed.boxes.count
        result.comparisons = parsed.comparisons.count
        result.identical = parsed.comparisons.filter(\.identical).count
        result.different = parsed.comparisons.filter { !$0.identical }.map { "\($0.box): \($0.label)" }
        result.gpuPathMissing = parsed.gpuPathMissing
        result.tuningUnfinished = parsed.tuningUnfinished
        result.verdictLine = parsed.verdictLine
        session.setResult(result)
        let counts = "\(result.identical) of \(result.comparisons) comparisons identical in \(result.boxes) boxes"
        session.note(FdtdScriptChecks.summary("diamond-check \(options.lib)", verdictLine: parsed.verdictLine,
                                              counts: counts, load: run.load, session: session))
    }
}

/// The steps the two script checks share.
enum FdtdScriptChecks {
    /// What one script check printed and how it ended.
    struct Run {
        var output: String
        var exit: Int32?
        var load: FdtdLoad
    }

    /// A LIB for a check script: the scripts call python3 by name (3 python_name_mismatch), the folder complete and
    /// identified, and the fork features present (3 library_lacks_feature with `hint`).
    static func gatedLibrary(_ spec: String, knobs: [String], engines: [FdtdEngine], hint: String,
                             session: FdtdSession) throws -> FdtdLibrary {
        _ = try session.discoverRepo()
        let python = try session.discoverPython()
        try FdtdDiscovery.requirePythonName(python, system: session.context.system)
        let library = try session.resolveLibrary(spec)
        try FdtdLibraries.requireFeatures(library, knobs: knobs, engines: engines, hint: hint)
        return library
    }

    /// The python probe and the zsh pre-probes (after every gate, so that a refused library costs no probe), the
    /// distribution record, the protected folders (RUNS), the concurrency warning, the run folder, the plan line and
    /// caffeinate, then the script under the launcher; nil in a dry run.
    static func launch(_ job: FdtdJob, libraries: [FdtdLibrary], plan: String, session: FdtdSession,
                       result: any Encodable & Sendable) throws -> Run? {
        // the direct probe records this Python (and that it keeps DYLD); the pre-probe proves the scripts' own path
        if let snapshot = libraries.first(where: { $0.spec != "installed" }) {
            _ = try session.probePython(dyld: snapshot.dir, snapshotNeeded: true)
        } else {
            _ = try session.probePython(dyld: nil, snapshotNeeded: false)
        }
        for library in libraries { try session.zshPreProbe(library) }
        try session.distributionRecord()
        try session.refusals([job], libraries: libraries) {
            try session.refuseProtected(session.runFolderTargets())
            try session.concurrencyGate(libraries: libraries, quietGiven: false)
        }
        session.setResult(result)
        let folder = try session.prepareRunFolder()
        session.planLine(plan + session.runFolderText(folder))
        session.startCaffeinate()
        let backend = try session.localBackend(runFolder: folder, libraries: libraries)
        let collector = FdtdLineCollector()
        guard let spawned = try session.spawnJob(job, backend: backend, onLine: { collector.append($0) }) else {
            return nil
        }
        let load = session.wholeRunLoad(spawned.report)
        return Run(output: collector.all.joined(separator: "\n"), exit: spawned.report?.exit ?? spawned.exit,
                   load: load)
    }

    /// The verdict's errors (none after a stop: finish() reports the interruption) and warnings, and loaded_mac.
    static func apply(_ verdict: FdtdVerdict, load: FdtdLoad, session: FdtdSession) {
        if !session.stop.stopRequested { session.error(contentsOf: verdict.errors) }
        session.warn(contentsOf: verdict.warnings)
        if load.valid && load.loaded { session.loadWarnings(withheld: [], loaded: ["the check run"]) }
    }

    /// `NAME: STATUS: VERDICT LINE (COUNTS)[; others cpu C% gpu G% over the whole run]`.
    static func summary(_ name: String, verdictLine: String?, counts: String, load: FdtdLoad,
                        session: FdtdSession) -> String {
        var text = "\(name): \(session.statusSoFar): " + (verdictLine ?? "no PASS or FAIL line") + " (\(counts))"
        if load.valid { text += "; " + FdtdFigures.wholeRun(load) }
        return text
    }
}
