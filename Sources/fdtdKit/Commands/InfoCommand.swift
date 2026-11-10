// SPDX-License-Identifier: GPL-3.0-or-later

// `emskit fdtd info` (spec 2.2): what this Mac has. Missing pieces become null plus a warning; the exit is 0 (64 for
// usage, 130 after a stop). No run folder, no caffeinate; about 1 s, mostly the snapshot index and the Python probe.
import Foundation

/// info's machine{}: sysctl machdep.cpu.brand_string, hw.perflevel0/1.physicalcpu, and ProcessInfo.
struct FdtdMachine: Codable, Sendable, Equatable {
    @FdtdNullable var chip: String? = nil
    var cpuCores: Int
    @FdtdNullable var performanceCores: Int? = nil
    @FdtdNullable var efficiencyCores: Int? = nil
    var memoryBytes: UInt64
    var os: String
}

/// info's result.
struct FdtdInfoResult: Codable, Sendable, Equatable {
    var machine: FdtdMachine
    /// The library the probe loads without a snapshot; null when none loaded.
    @FdtdNullable var installed: FdtdLibrary? = nil
    /// Every snapshot, or only the --lib ones.
    var snapshots: [FdtdLibrary] = []
    var builds: [FdtdBuildInfo] = []
    var knobs: [FdtdKnobInfo] = []
}

/// `emskit fdtd info`.
enum InfoCommand: FdtdCommandBody {
    static let name = FdtdCommandName.info

    /// The repo, Python probed without a snapshot (DYLD /var/empty), the machine, the installed library and the
    /// snapshots (or the --lib ones) with sameBytes/sameBuild, each --build (build_installs_over_prefix), rfsim, the
    /// two concurrency scans (reported, never enforced; unknown stays unknown) and the knob registry.
    static func run(_ options: FdtdInfoOptions, session: FdtdSession) throws {
        let context = session.context
        let system = context.system
        // info never stops on a missing piece: each failure becomes a warning and the piece stays null. A stop
        // request does end it (130), after the step it arrived in: a child that the stop ended is no missing piece
        func stopped() throws {
            guard session.stop.stopRequested else { return }
            throw FdtdError(.interrupted, "a stop was requested; info ended before its last step")
        }
        func soft<T>(_ body: () throws -> T) throws -> T? {
            var value: T? = nil
            do {
                value = try body()
            } catch let e as FdtdError {
                if !session.stop.stopRequested { session.warn(contentsOf: e.issues) }
            } catch {
                session.warn(FdtdIssue(.toolFailed, "unexpected error: \(error)"))
            }
            try stopped()
            return value
        }

        let repo = try soft { try session.discoverRepo() }
        // a --rfsim that names no toolkit is reported here, once: left to the probe's child environment it would
        // stop the probe, and the installed library would read as unknown
        var rfsimReported = false
        if repo != nil, session.common.rfsim != nil,
           (try? FdtdDiscovery.findRfsim(option: session.common.rfsim, context: context)) == nil {
            _ = try soft { try session.discoverRfsim(required: false) }
            rfsimReported = true
        }
        if repo != nil { _ = try soft { try session.probePython(dyld: nil, snapshotNeeded: false) } }
        let machine = machineFacts(system)
        let index = session.snapshotIndex()
        try stopped()

        var result = FdtdInfoResult(machine: machine)
        let installedDir = repo == nil ? nil : try soft { try session.installedLibraryDir() }
        if let installedDir {
            result.installed = try soft {
                try describe("installed", installedDir: installedDir, session: session, index: index)
            }
        } else if repo != nil {
            let message = "the python probe loaded no libopenEMS, so the installed library is unknown"
            session.warn(FdtdIssue(.libraryNotFound, message, hint: "--python /path/to/python3"))
        }
        if options.libs.isEmpty {
            // the index has read every snapshot already: each record is built from its entry
            result.snapshots = index.entries.map { FdtdLibraries.identify($0, index: index, system: system) }
            if index.entries.isEmpty {
                session.warn(FdtdIssue(.libraryNotFound, "no snapshot folders in \(index.folder)", field: "--snaps",
                                       hint: "--snaps DIR"))
            }
        } else {
            for spec in options.libs {
                let library = try soft {
                    try describe(spec, installedDir: installedDir, session: session, index: index)
                }
                if let library { result.snapshots.append(library) }
            }
        }
        for dir in options.builds {
            var warnings: [FdtdIssue] = []
            let build = FdtdLibraries.readBuild(session.absolutePath(dir), installedDir: installedDir, index: index,
                                                system: system, warnings: &warnings)
            session.warn(contentsOf: warnings)
            result.builds.append(build)
        }
        if repo != nil, !rfsimReported {
            do {
                if try session.discoverRfsim(required: false) == nil {
                    let searched = FdtdDiscovery.rfsimSearch(option: session.common.rfsim, context: context)
                    session.warn(FdtdIssue(.rfsimNotFound, "no rfsim toolkit: " + searched, field: "--rfsim",
                                           hint: "--rfsim DIR"))
                }
            } catch let e as FdtdError {
                if !session.stop.stopRequested { session.warn(contentsOf: e.issues) }
            }
            try stopped()
        }
        let watched = result.snapshots + result.builds.compactMap { $0.library }
        if repo != nil { _ = try soft { try session.concurrencyGate(libraries: watched, quietGiven: false) } }
        _ = try soft { try session.distributionRecord() }
        result.knobs = FdtdKnobs.info()
        session.setResult(result)
        session.note(summary(result, session: session))
    }

    // MARK: - Private

    private static func machineFacts(_ system: any FdtdSystem) -> FdtdMachine {
        let facts = system.hostFacts()
        var machine = FdtdMachine(cpuCores: facts.activeProcessorCount, memoryBytes: facts.physicalMemory,
                                  os: facts.operatingSystemVersion)
        machine.chip = system.sysctlString("machdep.cpu.brand_string")
        machine.performanceCores = system.sysctlInt("hw.perflevel0.physicalcpu")
        machine.efficiencyCores = system.sysctlInt("hw.perflevel1.physicalcpu")
        return machine
    }

    /// A LIB form's identity record, complete or not (an incomplete folder gives library_incomplete as a warning).
    private static func describe(_ spec: String, installedDir: String?, session: FdtdSession,
                                 index: FdtdSnapshotIndex) throws -> FdtdLibrary {
        let context = session.context
        let location = try FdtdLibraries.locate(spec, snaps: session.snapshotsFolder(), installedDir: installedDir,
                                                cwd: context.cwd, home: context.home, system: context.system)
        do {
            try FdtdLibraries.requireComplete(location)
        } catch let e as FdtdError {
            session.warn(contentsOf: e.issues)
        }
        // from the index when it has read this folder already (a snapshot by its name or by its path)
        return FdtdLibraries.record(location, index: index, system: context.system)
    }

    /// `info: python P (openEMS V), installed DIR (NOTE), N snapshots (M complete), concurrent R`.
    private static func summary(_ result: FdtdInfoResult, session: FdtdSession) -> String {
        var parts: [String] = []
        if let python = session.envelope.python {
            let binding = python.openemsVersion.map { " (openEMS \($0))" } ?? ""
            parts.append("python \(python.path)" + binding)
        }
        if let installed = result.installed {
            let note = installed.note.map { " (\($0))" } ?? ""
            parts.append("installed \(installed.dir)" + note)
        } else {
            parts.append("installed library unknown")
        }
        let complete = result.snapshots.filter { $0.complete }.count
        parts.append("\(result.snapshots.count) libraries listed (\(complete) complete)")
        if let concurrent = session.envelope.concurrent {
            parts.append("running simulations: \(concurrent.result.rawValue)")
        }
        return "info: " + parts.joined(separator: ", ")
    }
}
