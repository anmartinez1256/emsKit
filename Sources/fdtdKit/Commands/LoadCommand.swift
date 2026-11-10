// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd load` (spec 2.3): one usage.Sampler over S seconds, run under the launcher, into the top-level `load`.
// No run folder: the launcher copy and its report go to a scratch folder that is removed afterwards.
import Foundation

/// load's result.
struct FdtdLoadResult: Codable, Sendable, Equatable {
    var seconds: Double
}

/// `emskit fdtd load`.
enum LoadCommand: FdtdCommandBody {
    static let name = FdtdCommandName.load

    /// RUNS and the scratch folder outside the protected folders (2 protected_path; finding the installed prefix takes
    /// the python probe), then the LOAD helper under the launcher; a load that is not valid (no processes seen or no
    /// GPU samples) → 4 load_unavailable. stderr: `load: others cpu 123% gpu 4% (gpu dev 7%) over 5.0 s
    /// [WindowServer:31/2]`.
    static func run(_ options: FdtdLoadOptions, session: FdtdSession) throws {
        let context = session.context
        let system = context.system
        _ = try session.discoverRepo()
        _ = try session.discoverPython()
        try session.distributionRecord()
        let job = FdtdJob.load(seconds: options.seconds)
        session.setResult(FdtdLoadResult(seconds: options.seconds))
        // the scratch folder goes under RUNS/emskit-fdtd, which stays
        try session.refusals([job], libraries: []) { try session.refuseProtected(session.runFolderTargets()) }

        // load is not a run command and takes no --dry-run (FdtdOptions.spec), so it always measures
        let scratch = try FdtdRunFolders.createScratch(base: session.runsBase(), pid: context.pid,
                                                       now: context.clock.now(), timeZone: context.timeZone,
                                                       system: system)
        // the scratch folder goes away, so nothing in it may stay listed as an output
        defer {
            try? system.removeItem(scratch.path)
            let prefix = scratch.path + "/"
            session.envelope.outputs.removeAll { $0.path.hasPrefix(prefix) }
        }
        _ = try FdtdRunFolders.writeLauncher(scratch, system: system)
        let backend = try session.localBackend(runFolder: scratch, libraries: [])
        let collector = FdtdLineCollector()
        guard let result = try session.spawnJob(job, backend: backend, onLine: { collector.append($0) }) else { return }

        let text = collector.all.joined(separator: "\n")
        guard let line = FdtdParsers.taggedJSON(FdtdSnippets.loadTag, in: text, as: FdtdLoadLine.self) else {
            if session.stop.stopRequested { return }
            let message = "the load helper printed no \(FdtdSnippets.loadTag) line"
            throw FdtdError(.toolOutputUnparsed, message + FdtdFigures.exitSuffix(result.exit))
        }
        let load = FdtdLoads.fromSampler(line.load, counts: line.counts, thresholds: session.thresholds)
        session.envelope.load = load
        guard load.valid else {
            let reason = load.invalidReason ?? "the sampler result is not valid"
            session.error(FdtdIssue(.loadUnavailable, "no valid load: " + reason, hint: "emskit fdtd info"))
            return
        }
        session.note("load: " + FdtdFigures.loadLine(load))
        if load.loaded { session.loadWarnings(withheld: [], loaded: ["the load window"]) }
    }
}
