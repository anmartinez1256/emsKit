// SPDX-License-Identifier: GPL-3.0-or-later

// Other simulations on this Mac (spec 11). Two lsof scans, each decided from its own records and never from its exit
// status alone (lsof exits 1 whenever one listed file is not open, even after it found another), merged by pid; the
// CLI's own descendants dropped; the rest named by ps. bench, ab and e2e refuse (exit 5) unless --quiet or
// --allow-concurrent; the other run commands warn; info only reports. There is no lock file: two CLIs started in the
// same second can both pass.
import Foundation

/// One process of `lsof -F pcn` output.
struct FdtdLsofRecord: Sendable, Equatable {
    var pid: Int32
    var command: String? = nil
    /// The `n` records: the file names it holds.
    var names: [String] = []
}

/// The concurrency scans and their policy.
enum FdtdConcurrency {
    /// Scan A: every Python or openEMS process with a libopenEMS*.dylib open, wherever that file lies (incomplete
    /// snapshots, build folders, backups of the install, scratch copies).
    static let scanAArgv = ["/usr/sbin/lsof", "-n", "-w", "-F", "pcn", "-c", "Python", "-c", "python", "-c", "openEMS"]

    /// Scan B: every process with one of `files` open, whatever its name.
    static func scanBArgv(_ files: [String]) -> [String] { ["/usr/sbin/lsof", "-n", "-w", "-F", "pcn", "--"] + files }

    /// lsof and ps get a fixed environment: the C locale, the system folders, nothing of the CLI's.
    private static let toolEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
    /// lsof takes about 0.05 s here; a hung one must not hold the command.
    private static let timeoutSeconds = 30.0
    /// The command line in an issue message, cut to this many characters (the envelope keeps the whole line).
    private static let commandWidth = 100
    private static let refusalHint = "wait, add --quiet 60, or pass --allow-concurrent"

    /// `p` starts a process, `c` names it, `n` adds a file; any other field letter (lsof always adds `f`) is ignored.
    static func parseRecords(_ text: String) -> [FdtdLsofRecord] {
        var records: [FdtdLsofRecord] = []
        var inRecord = false
        for line in text.split(whereSeparator: \.isNewline) {
            guard let letter = line.first else { continue }
            let value = String(line.dropFirst())
            switch letter {
            case "p":
                if let pid = Int32(value) {
                    records.append(FdtdLsofRecord(pid: pid))
                    inRecord = true
                } else {
                    inRecord = false            // its c and n lines must not land on the process before
                }
            case "c":
                if inRecord { records[records.count - 1].command = value }
            case "n":
                if inRecord { records[records.count - 1].names.append(value) }
            default:
                continue
            }
        }
        return records
    }

    /// Scan A keeps a process with an `n` record whose file name starts with libopenEMS and ends in .dylib.
    static func scanAKeeps(_ record: FdtdLsofRecord) -> Bool {
        record.names.contains(where: { isLibopenEMS($0) })
    }

    /// Scan B keeps a process with an `n` record naming one of `files` (real paths).
    static func scanBKeeps(_ record: FdtdLsofRecord, files: Set<String>) -> Bool {
        record.names.contains(where: { files.contains($0) })
    }

    /// One scan's result from its records: kept processes → found; nothing kept with exit 1 (lsof's "something
    /// asked for was not found") or exit 0 (everything listed, none of it an openEMS library) → none; nothing kept
    /// with any other status, or without one (killed at the timeout, never started) → unknown.
    static func decide(exit: Int32?, records: [FdtdLsofRecord], kept: [FdtdLsofRecord]) -> FdtdConcurrencyResult {
        if !kept.isEmpty { return .found }
        if exit == 0 || exit == 1 { return .noneFound }
        return .unknown
    }

    /// `pid` and all its descendants, from `ps -Ao pid=,ppid=` output.
    static func descendants(of pid: Int32, psOutput: String) -> Set<Int32> {
        var children: [Int32: [Int32]] = [:]
        for line in psOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, let child = Int32(fields[0]), let parent = Int32(fields[1]) else { continue }
            children[parent, default: []].append(child)
        }
        var found: Set<Int32> = [pid]
        var queue = [pid]
        while let next = queue.popLast() {
            for child in children[next] ?? [] where !found.contains(child) {
                found.insert(child)
                queue.append(child)
            }
        }
        return found
    }

    /// pid → command line, from `ps -o pid=,command= -p PID,...` output.
    static func commands(psOutput: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for line in psOutput.split(whereSeparator: \.isNewline) {
            let text = line.drop(while: { $0 == " " || $0 == "\t" })
            let end = text.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? text.endIndex
            guard let pid = Int32(text[..<end]) else { continue }
            result[pid] = String(text[end...].drop(while: { $0 == " " || $0 == "\t" }))
        }
        return result
    }

    /// Runs both scans and ps through context.system.capture, merges them by pid, drops context.pid and its
    /// descendants, and names the rest: the envelope's `concurrent`. `libraries` are scan B's files: the real paths of
    /// the installed libopenEMS, every complete snapshot's libopenEMS.0.dylib and every --lib/--build libopenEMS.
    /// Without libraries scan B does not run (`lsof --` alone would list every open file). A scan's `records` counts
    /// the processes it kept.
    static func scan(libraries: [String], context: FdtdContext, stop: FdtdStopController?) -> FdtdConcurrent {
        var concurrent = FdtdConcurrent(result: .noneFound)
        var held: [Int32: [String]] = [:]
        var unknown = false

        let a = capture(scanAArgv, context: context, stop: stop)
        let aRecords = parseRecords(a.stdout)
        let aKept = aRecords.filter { scanAKeeps($0) }
        concurrent.scans.append(FdtdConcurrencyScan(argv: scanAArgv, exit: a.exit, records: aKept.count))
        if decide(exit: a.exit, records: aRecords, kept: aKept) == .unknown { unknown = true }
        for record in aKept { held[record.pid, default: []] += record.names.filter { isLibopenEMS($0) } }

        // lsof reports the file it found open by its real path; the set also holds the paths as given.
        var listed: [String] = []
        var files = Set<String>()
        for path in libraries {
            let real = context.system.realPath(path) ?? path
            if !listed.contains(real) { listed.append(real) }
            files.insert(path)
            files.insert(real)
        }
        if !listed.isEmpty {
            let argv = scanBArgv(listed)
            let b = capture(argv, context: context, stop: stop)
            let bRecords = parseRecords(b.stdout)
            let bKept = bRecords.filter { scanBKeeps($0, files: files) }
            concurrent.scans.append(FdtdConcurrencyScan(argv: argv, exit: b.exit, records: bKept.count))
            if decide(exit: b.exit, records: bRecords, kept: bKept) == .unknown { unknown = true }
            for record in bKept { held[record.pid, default: []] += record.names.filter { files.contains($0) } }
        }

        held[context.pid] = nil
        if !held.isEmpty {
            let tree = capture(["/bin/ps", "-Ao", "pid=,ppid="], context: context, stop: stop)
            if tree.exit == 0 {
                for pid in descendants(of: context.pid, psOutput: tree.stdout) { held[pid] = nil }
            }
        }
        if !held.isEmpty {
            let pids = held.keys.sorted()
            let list = pids.map { String($0) }.joined(separator: ",")
            let named = commands(psOutput: capture(["/bin/ps", "-o", "pid=,command=", "-p", list], context: context,
                                                   stop: stop).stdout)
            concurrent.processes = pids.map { pid in
                FdtdConcurrentProcess(pid: pid, command: named[pid], libraries: Array(Set(held[pid] ?? [])).sorted())
            }
        }
        if !concurrent.processes.isEmpty {
            concurrent.result = .found
        } else if unknown {
            concurrent.result = .unknown
        }
        return concurrent
    }

    /// The policy: on bench, ab and e2e a found process throws 5 simulation_running and an unknown scan 5
    /// concurrency_unknown, unless `quietGiven` or `allowConcurrent`; on the other commands, and on those three with
    /// either option, the same codes come back as warnings (without a hint). The refusal's hint names --quiet 60 and
    /// --allow-concurrent.
    static func enforce(_ concurrent: FdtdConcurrent, command: FdtdCommandName, quietGiven: Bool,
                        allowConcurrent: Bool) throws -> [FdtdIssue] {
        var issues: [FdtdIssue] = []
        switch concurrent.result {
        case .noneFound:
            return []
        case .found:
            issues = concurrent.processes.map { FdtdIssue(.simulationRunning, describe($0)) }
            if issues.isEmpty {
                issues = [FdtdIssue(.simulationRunning, "another process has an openEMS library open")]
            }
        case .unknown:
            issues = [FdtdIssue(.concurrencyUnknown, "no answer from lsof (" + scanStatuses(concurrent.scans) + ")")]
        }
        guard refuses(command), !quietGiven, !allowConcurrent else { return issues }
        throw FdtdError(issues.map { FdtdIssue($0.code, $0.message, field: $0.field, hint: refusalHint) })
    }

    /// The commands that refuse instead of warning.
    static func refuses(_ command: FdtdCommandName) -> Bool { command == .bench || command == .ab || command == .e2e }

    private static func isLibopenEMS(_ name: String) -> Bool {
        let base = name.split(separator: "/", omittingEmptySubsequences: false).last ?? Substring(name)
        return base.hasPrefix("libopenEMS") && base.hasSuffix(".dylib")
    }

    private static func capture(_ argv: [String], context: FdtdContext,
                                stop: FdtdStopController?) -> FdtdCaptureResult {
        let request = FdtdCaptureRequest(argv: argv, cwd: "/", environment: toolEnvironment,
                                         timeoutSeconds: timeoutSeconds)
        return context.system.capture(request, stop: stop)
    }

    /// `pid N (COMMAND) has LIB open`, the command cut to commandWidth characters.
    private static func describe(_ process: FdtdConcurrentProcess) -> String {
        let files = process.libraries.isEmpty ? "an openEMS library" : process.libraries.joined(separator: ", ")
        var who = "pid " + String(process.pid)
        if let command = process.command, !command.isEmpty {
            let shown = command.count > commandWidth ? String(command.prefix(commandWidth - 3)) + "..." : command
            who += " (" + shown + ")"
        }
        return who + " has " + files + " open"
    }

    /// How the scans that gave no answer ended: `exit 2`, or `no exit status` for one killed or never started.
    private static func scanStatuses(_ scans: [FdtdConcurrencyScan]) -> String {
        let silent = scans.filter { $0.records == 0 && $0.exit != 0 && $0.exit != 1 }
        let shown = silent.isEmpty ? scans : silent
        return shown.map { s in s.exit.map { "exit " + String($0) } ?? "no exit status" }.joined(separator: "; ")
    }
}
