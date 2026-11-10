// SPDX-License-Identifier: GPL-3.0-or-later

// Run folders and named outputs (spec 10). A run folder is RUNS/emskit-fdtd/<yyyyMMdd-HHmmss>-<command>-<pid>[-N]/,
// made by an exclusive mkdir of the leaf, for run commands only and never in a dry run. Backups of named outputs go
// next to the original as PATH.previous-<stamp> (after the extension, so the results globs miss them), never into the
// run folder. Nothing inside the installed library's prefix or a snapshot folder is written, created or renamed, and
// nothing that holds one is renamed or replaced: FdtdProtectedPaths refuses such a location at plan time (S3).
import Foundation

/// One command's run folder and the paths inside it.
struct FdtdRunFolder: Sendable, Equatable {
    var path: String

    /// Every byte of the tools' output.
    var toolLog: String { FdtdPaths.join(path, "tool.log") }
    /// A copy of the envelope, whatever the status.
    var envelopeCopy: String { FdtdPaths.join(path, "envelope.json") }
    /// The launcher copy used by this run.
    var launcher: String { FdtdPaths.join(path, FdtdLauncherSource.fileName) }
    /// bench, ab and check runs.
    var runs: String { FdtdPaths.join(path, "runs") }
    /// validate's output folder without --tag; its work/ is removed by the cleanup.
    var validation: String { FdtdPaths.join(path, "validation") }
    var validationWork: String { FdtdPaths.join(validation, "work") }
    /// debye-check's and diamond-check's TMPDIR.
    var tmp: String { FdtdPaths.join(path, "tmp") }
    /// e2e's default output folder.
    var e2e: String { FdtdPaths.join(path, "e2e") }
    /// ab's default record file.
    var abRecord: String { FdtdPaths.join(path, "abtest.txt") }

    /// The launcher report of one launcher invocation.
    func launcherReport(_ role: FdtdRole) -> String { FdtdPaths.join(path, "launcher-\(role.rawValue).json") }
}

/// Creating, filling and cleaning run folders.
enum FdtdRunFolders {
    /// The folder under RUNS that holds every run folder of this CLI.
    private static let folderName = "emskit-fdtd"
    /// What e2e's cleanup keeps (the toolkit's own result files).
    private static let keptE2E: Set<String> = ["result.json", "sp.npz"]
    /// Enough for in-process tests that share one pid and one second; a real run never needs more than one.
    private static let maxSuffix = 999

    /// `yyyyMMdd-HHmmss` in `timeZone`.
    static func stamp(_ date: Date, _ timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = [pad(c.year ?? 0, 4), pad(c.month ?? 0, 2), pad(c.day ?? 0, 2)].joined()
        let time = [pad(c.hour ?? 0, 2), pad(c.minute ?? 0, 2), pad(c.second ?? 0, 2)].joined()
        return day + "-" + time
    }

    /// The folder a run would get, without creating anything (dry runs resolve their invocations against it).
    static func planned(base: String, command: FdtdCommandName, pid: Int32, now: Date, timeZone: TimeZone) -> FdtdRunFolder {
        let name = leaf(command.rawValue, pid: pid, now: now, timeZone: timeZone)
        return FdtdRunFolder(path: FdtdPaths.join(parent(base), name))
    }

    /// Creates BASE/emskit-fdtd (as needed) and the leaf by an exclusive mkdir; on EEXIST it tries `-2`, `-3`, ...
    /// (in-process tests share one pid and one second). 2 folder_missing when BASE cannot be created.
    static func create(base: String, command: FdtdCommandName, pid: Int32, now: Date, timeZone: TimeZone,
                       system: any FdtdSystem) throws -> FdtdRunFolder {
        try makeExclusive(parent: parent(base), leaf: leaf(command.rawValue, pid: pid, now: now, timeZone: timeZone),
                          system: system)
    }

    /// A private folder for the load command's launcher copy and report (load has no run folder): created like a run
    /// folder under BASE/emskit-fdtd with a leading '.', removed by the command, never reported as runFolder.
    static func createScratch(base: String, pid: Int32, now: Date, timeZone: TimeZone,
                              system: any FdtdSystem) throws -> FdtdRunFolder {
        try makeExclusive(parent: parent(base), leaf: scratchLeaf(pid: pid, now: now, timeZone: timeZone), system: system)
    }

    /// The folder createScratch would make, without creating anything (the protected-folder check looks at it first).
    static func plannedScratch(base: String, pid: Int32, now: Date, timeZone: TimeZone) -> FdtdRunFolder {
        FdtdRunFolder(path: FdtdPaths.join(parent(base), scratchLeaf(pid: pid, now: now, timeZone: timeZone)))
    }

    /// Writes FdtdLauncherSource.source to folder.launcher and returns its outputs[] record (with sha256).
    static func writeLauncher(_ folder: FdtdRunFolder, system: any FdtdSystem) throws -> FdtdOutput {
        let data = Data(FdtdLauncherSource.source.utf8)
        do {
            try system.writeFile(folder.launcher, data, atomically: true)
        } catch {
            throw FdtdError(.launcherFailed, "cannot write the launcher copy \(folder.launcher): \(reason(error))")
        }
        return FdtdOutput(path: folder.launcher, sha256: FdtdLibraries.sha256(data), existedBefore: false)
    }

    /// Writes the envelope copy (always, whatever the status).
    static func writeEnvelopeCopy(_ data: Data, folder: FdtdRunFolder, system: any FdtdSystem) throws {
        try system.writeFile(folder.envelopeCopy, data, atomically: true)
    }

    /// After ok or partial unless --keep-runs: removes runs/, validation/work/, tmp/ and everything in e2e/ except
    /// result.json and sp.npz. A user-given --out-dir is never touched. Every entry is tried; the first failure is
    /// thrown at the end as 4 tool_failed.
    static func cleanup(_ folder: FdtdRunFolder, system: any FdtdSystem) throws {
        var doomed = [folder.runs, folder.validationWork, folder.tmp].filter { system.fileExists($0) }
        if system.isDirectory(folder.e2e), let names = system.listDirectory(folder.e2e) {
            doomed += names.filter { !keptE2E.contains($0) }.map { FdtdPaths.join(folder.e2e, $0) }
        }
        var failure: FdtdError? = nil
        for path in doomed {
            do {
                try system.removeItem(path)
            } catch {
                if failure == nil { failure = FdtdError(.toolFailed, "cannot remove \(path): \(reason(error))") }
            }
        }
        if let failure { throw failure }
    }

    /// The leaf by an exclusive mkdir, `-2`, `-3`, ... while the name is taken.
    private static func makeExclusive(parent: String, leaf: String, system: any FdtdSystem) throws -> FdtdRunFolder {
        do {
            try system.createDirectories(parent)
        } catch {
            throw FdtdError(.folderMissing, "cannot create the run folder base \(parent): \(reason(error))",
                            field: "--runs", hint: "--runs DIR")
        }
        for n in 1...maxSuffix {
            let path = FdtdPaths.join(parent, n == 1 ? leaf : leaf + "-" + String(n))
            switch system.makeDirectoryExclusive(path) {
            case .created:
                return FdtdRunFolder(path: path)
            case .exists:
                continue
            case .failed(let message):
                throw FdtdError(.folderMissing, "cannot create the run folder \(path): \(message)", field: "--runs",
                                hint: "--runs DIR")
            }
        }
        throw FdtdError(.folderMissing, "no free run folder name for \(leaf) in \(parent)", field: "--runs")
    }

    private static func parent(_ base: String) -> String { FdtdPaths.join(base, folderName) }

    private static func leaf(_ command: String, pid: Int32, now: Date, timeZone: TimeZone) -> String {
        [stamp(now, timeZone), command, String(pid)].joined(separator: "-")
    }

    private static func scratchLeaf(pid: Int32, now: Date, timeZone: TimeZone) -> String {
        "." + leaf(FdtdCommandName.load.rawValue, pid: pid, now: now, timeZone: timeZone)
    }

    /// Zero-padded decimal.
    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }

    /// The system's message for a failed file operation.
    fileprivate static func reason(_ error: any Error) -> String {
        (error as? FdtdSystemError)?.message ?? String(describing: error)
    }
}

/// How a named output is kept before it is replaced.
enum FdtdBackupMode: Sendable, Equatable {
    /// Tables the tools write over (bench --tag, check's tables, validate's .json/.md): copied first.
    case copy
    /// `--output FILE` and an e2e `--out-dir`: renamed away.
    case rename
}

/// Named outputs: overwrite refusals, backups next to the originals, records with sha256, atomic writes.
enum FdtdOutputs {
    /// `PATH.previous-<yyyyMMdd-HHmmss>`, next to the original.
    static func backupPath(_ path: String, now: Date, timeZone: TimeZone) -> String {
        path + ".previous-" + FdtdRunFolders.stamp(now, timeZone)
    }

    /// Whether `path` exists (a folder counts only when it is not empty; an unreadable one counts). Without
    /// `overwrite` an existing one throws 5 would_overwrite naming `field`; with it, true means a backup is due.
    static func refuseExisting(_ path: String, overwrite: Bool, field: String, system: any FdtdSystem) throws -> Bool {
        let exists: Bool
        if system.isDirectory(path) {
            exists = system.listDirectory(path).map { !$0.isEmpty } ?? true
        } else {
            exists = system.fileExists(path)
        }
        guard exists else { return false }
        guard overwrite else {
            // ab's record file is appended to, never replaced (--overwrite with --record is a usage error).
            let hint = field == "--record"
                ? "--append" : "another name, or --overwrite (the old one is kept next to it)"
            throw FdtdError(.wouldOverwrite, [field, path, "exists"].joined(separator: " "), field: field, hint: hint)
        }
        return true
    }

    /// Copies or renames `path` to its backupPath (never over an existing file: `-2`, `-3`, ... are added while the
    /// name is taken) and returns the backup's path. A copy holds the bytes a symbolic link points at. A failure is 4
    /// tool_failed.
    static func backup(_ path: String, mode: FdtdBackupMode, now: Date, timeZone: TimeZone,
                       system: any FdtdSystem) throws -> String {
        let first = backupPath(path, now: now, timeZone: timeZone)
        var target = first
        var n = 1
        while system.fileExists(target) {
            n += 1
            guard n <= 999 else { throw FdtdError(.toolFailed, "no free backup name for \(path)") }
            target = first + "-" + String(n)
        }
        do {
            switch mode {
            case .copy:
                // FileManager copies a link as a link, and the tool then writes the old table through the original
                // name: the backup must be a file of its own
                try system.copyItem(system.realPath(path) ?? path, to: target)
            case .rename:
                try system.moveItem(path, to: target)
            }
        } catch {
            throw FdtdError(.toolFailed, "cannot back up \(path) to \(target): \(FdtdRunFolders.reason(error))")
        }
        return target
    }

    /// The outputs[] record of a file the run wrote: sha256 (FdtdLibraries.sha256, nil when unreadable).
    static func record(_ path: String, existedBefore: Bool, backup: String?, system: any FdtdSystem) -> FdtdOutput {
        FdtdOutput(path: path, sha256: FdtdLibraries.sha256(path: path, system: system), existedBefore: existedBefore,
                   backup: backup)
    }

    /// Writes `data` to `path` atomically (a temporary file in the same folder, then rename).
    static func writeAtomically(_ data: Data, to path: String, system: any FdtdSystem) throws {
        try system.writeFile(path, data, atomically: true)
    }
}

// MARK: - Protected folders (S3)

/// A folder no command writes into: the installed library's prefix or a snapshot folder.
struct FdtdProtectedRoot: Sendable, Equatable {
    /// How messages name it: "the installed openEMS prefix" or "the snapshot folder".
    var name: String
    var path: String
}

/// A location a command would write, create or rename, as the protected-folder check sees it.
struct FdtdWriteTarget: Sendable, Equatable {
    /// How the message names it: the option that gave it (`--output`) or what it is (`the run folder`).
    var label: String
    /// The option that moves it, for the issue; nil when this command has none.
    var field: String?
    var path: String
    /// Renamed or replaced as a whole, so it must not hold a protected folder either.
    var replaced: Bool
    /// Written in place by a tool when it exists (a table with --overwrite, ab's record with --append), so it must not
    /// be another name (a hard link) of a file in a protected folder either.
    var inPlace = false

    /// A folder the CLI and the tools only write into, never rename (--results, --runs, the run folder, an EXPORT_*
    /// knob folder).
    static func into(_ label: String, field: String?, _ path: String) -> FdtdWriteTarget {
        FdtdWriteTarget(label: label, field: field, path: path, replaced: false)
    }

    /// A file or folder written, renamed or replaced as a whole (--output, --out-dir, a backup).
    static func whole(_ label: String, field: String?, _ path: String) -> FdtdWriteTarget {
        FdtdWriteTarget(label: label, field: field, path: path, replaced: true)
    }

    /// A file a tool opens for writing or appending (a table, ab's record): as `whole`, and when it exists, its other
    /// names count too.
    static func inPlace(_ label: String, field: String?, _ path: String) -> FdtdWriteTarget {
        FdtdWriteTarget(label: label, field: field, path: path, replaced: true, inPlace: true)
    }
}

/// S3 at plan time: a target is refused (2 protected_path) when it is a protected folder or lies inside one, a target
/// that is renamed or replaced also when it holds one (by the protected folder's real path or by the path it is named
/// by), and a file a tool writes in place also when it is another name of a file in one. Paths are compared by file
/// identity, so symbolic links, `..`, letter case and firmlinks cannot hide a protected folder; a path that does not
/// exist yet is judged by its nearest existing part.
enum FdtdProtectedPaths {
    /// How a target meets a protected folder.
    enum Relation: Sendable, Equatable {
        case equal
        case inside
        case holds
    }

    /// A path as the check sees it.
    struct Located: Sendable, Equatable {
        /// The real path of the nearest part that exists.
        var real: String
        /// The names below it that do not exist yet; empty when the path exists.
        var rest: [String]
        /// The identities of `real` and of every folder above it, nearest first.
        var chain: [FdtdInode]
        /// The identities of the folders above the path as it was named (each with its links followed), nearest
        /// first: renaming one of them cuts the name a protected folder is used by, even when its real path lies
        /// elsewhere.
        var named: [FdtdInode] = []

        var exists: Bool { rest.isEmpty }
        /// `real` with the missing names below it.
        var resolved: String { rest.reduce(real) { FdtdPaths.join($0, $1) } }
    }

    /// The most symbolic links followed (MAXSYMLINKS).
    private static let maxLinks = 32

    /// The protected_path issue for `target`, or nil. The message names the option, the path (and what it resolves to,
    /// when that differs, or its other name in the protected folder) and the protected folder.
    static func refusal(_ target: FdtdWriteTarget, roots: [FdtdProtectedRoot], system: any FdtdSystem) -> FdtdIssue? {
        guard let located = locate(target.path, system: system) else { return nil }
        let folders = roots.compactMap { root in locate(root.path, system: system).map { (root, $0) } }
        for (root, folder) in folders {
            guard let relation = relation(located, replaced: target.replaced, root: folder) else { continue }
            let shown = located.resolved == target.path ? target.path : "\(target.path) (\(located.resolved))"
            let (verb, tail) = switch relation {
            case .equal: ("is", "where no command writes")
            case .inside: ("lies inside", "where no command writes")
            case .holds: ("holds", "which no command moves or replaces")
            }
            let message = "\(target.label) \(shown) \(verb) \(root.name) \(root.path), \(tail)"
            let hint = relation == .holds ? "a path that does not hold \(root.path)" : "a path outside \(root.path)"
            return FdtdIssue(.protectedPath, message, field: target.field, hint: hint)
        }
        // an in-place write (bench.py's open(fn, 'w'), abtest's open(out, 'a')) changes the file under all its names
        guard target.inPlace, located.exists, system.isRegularFile(target.path),
              let names = system.linkCount(target.path), names > 1,
              let identity = system.fileIdentity(target.path) else { return nil }
        for (root, folder) in folders where folder.exists && folder.chain.first?.device == identity.device {
            guard let other = otherName(of: identity, under: folder.real, system: system) else { continue }
            let message = "\(target.label) \(target.path) is also \(other) (a hard link) in \(root.name) \(root.path), "
                + "and the tool writes it in place"
            let hint = "a file of its own (copy it to a new name first), or a path outside \(root.path)"
            return FdtdIssue(.protectedPath, message, field: target.field, hint: hint)
        }
        return nil
    }

    /// How `target` meets the protected folder `root`, or nil when it does not.
    static func relation(_ target: Located, replaced: Bool, root: Located) -> Relation? {
        guard root.exists, let folder = root.chain.first, let own = target.chain.first else { return nil }
        if own == folder { return target.exists ? .equal : .inside }
        if target.chain.contains(folder) { return .inside }
        if replaced, holds(target, root) { return .holds }
        return nil
    }

    /// Whether `target` is `folder` or holds it, so that renaming or emptying `target` takes `folder` with it: by
    /// the real path of what exists (`folder` need not exist yet: a run folder still to be made), by file identity,
    /// and by the path `folder` is named by (a link inside `target` that leads to it: the name goes with the
    /// rename, although the real folder stays). The one test of the protected folders and of e2e's --out-dir.
    static func holds(_ target: Located, _ folder: Located) -> Bool {
        if folder.resolved == target.resolved || folder.resolved.hasPrefix(target.resolved + "/") { return true }
        guard target.exists, let own = target.chain.first else { return false }
        return folder.chain.contains(own) || folder.named.contains(own)
    }

    /// The nearest part of `path` that exists (its real path and identities) and the names below it. A dangling
    /// symbolic link on the way, the last name included, is followed: a tool that opens it for writing creates its
    /// target (bench.py's tables, abtest's record, core.run's out folder, openEMS's exports). finish() replaces a
    /// last-name link of --output rather than writing through it, so there the check is deliberately stricter than the
    /// write. nil only when not even / is there.
    static func locate(_ path: String, system: any FdtdSystem) -> Located? {
        var head = path
        var rest: [String] = []
        var links = 0
        while true {
            if system.fileExists(head) {
                let real = system.realPath(head) ?? head
                return Located(real: real, rest: rest, chain: chain(real, system: system),
                               named: chain(FdtdPaths.dirname(path), system: system))
            }
            if links < maxLinks, let target = system.symbolicLinkTarget(head) {
                links += 1
                // a relative target counts from the link's folder, which exists (the link is in it)
                let folder = FdtdPaths.dirname(head)
                head = target.hasPrefix("/") ? target : FdtdPaths.join(system.realPath(folder) ?? folder, target)
                continue
            }
            let parent = FdtdPaths.dirname(head)
            guard parent != head, !parent.isEmpty else { return nil }
            rest.insert(FdtdPaths.basename(head), at: 0)
            head = parent
        }
    }

    /// The install prefix of the installed library's folder: the folder above it when it is called lib (CMake's
    /// layout), else the folder itself. A prefix that is / or holds one of `homes` (a library in ~/lib) gives the lib
    /// folder alone, so that the check never covers a home folder.
    static func prefix(of folder: String, homes: [String], system: any FdtdSystem) -> String {
        guard FdtdPaths.basename(folder) == "lib" else { return folder }
        let prefix = FdtdPaths.dirname(folder)
        guard prefix != "/", let above = locate(prefix, system: system) else { return folder }
        for home in homes {
            if let inside = locate(home, system: system), relation(inside, replaced: false, root: above) != nil {
                return folder
            }
        }
        return prefix
    }

    /// Another name of the file `identity` below the real folder `folder`, or nil. The walk follows no symbolic link
    /// (a hard link is a name in a real folder, and so the walk stays inside) and skips other file systems, which
    /// cannot hold one.
    static func otherName(of identity: FdtdInode, under folder: String, system: any FdtdSystem) -> String? {
        var pending = [folder]
        while let dir = pending.popLast() {
            for name in system.listDirectory(dir) ?? [] {
                let path = FdtdPaths.join(dir, name)
                guard system.symbolicLinkTarget(path) == nil, let entry = system.fileIdentity(path),
                      entry.device == identity.device else { continue }
                if system.isDirectory(path) {
                    pending.append(path)
                } else if entry == identity {
                    return path
                }
            }
        }
        return nil
    }

    /// The identities of `path` and of every folder above it by name, nearest first, each with its links followed
    /// (for a real path, its folders on disk).
    private static func chain(_ path: String, system: any FdtdSystem) -> [FdtdInode] {
        var identities: [FdtdInode] = []
        var dir = path
        while true {
            if let identity = system.fileIdentity(dir) { identities.append(identity) }
            let parent = FdtdPaths.dirname(dir)
            if parent == dir || parent.isEmpty { return identities }
            dir = parent
        }
    }
}
