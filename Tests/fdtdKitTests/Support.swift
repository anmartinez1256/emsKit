// SPDX-License-Identifier: GPL-3.0-or-later

// The fake Mac of the unit tests (spec 16.1): FakeSystem (files, probes, scans, spawns), FakeClock, FakeSignalSource and
// FakeProcessControl, synthetic Mach-O libraries, and FakeWorld: a tools tree, a Python, snapshots, an installed
// folder and an rfsim toolkit, with FdtdCLI.run against them. Nothing here starts a process.
import Foundation
import Synchronization
@testable import fdtdKit

// MARK: - Paths

enum TestPaths {
    /// Tests/fdtdKitTests.
    static let suite = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    static let fixtures = suite + "/Fixtures"
    /// The package root, which is the tools tree too (bench/, results/, scripts/).
    static let repo = URL(fileURLWithPath: suite).deletingLastPathComponent().deletingLastPathComponent().path

    static func fixture(_ name: String) -> String { fixtures + "/" + name }

    static func text(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }

    static func lines(_ path: String) throws -> [String] {
        try text(path).split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    }
}

/// A new folder under the temporary directory for tests that need real files.
struct TempFolder {
    let path: String

    init(_ label: String) throws {
        // realpath(3): children see /private/var/..., which URL.resolvingSymlinksInPath turns back into /var/...
        var base = NSTemporaryDirectory()
        if let resolved = realpath(base, nil) {
            base = String(cString: resolved)
            free(resolved)
        }
        path = base + "/fdtdkit-tests-\(label)-" + UUID().uuidString.prefix(8)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> String { path + "/" + name }

    func write(_ name: String, _ data: Data) throws {
        let target = file(name)
        try FileManager.default.createDirectory(atPath: (target as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: target))
    }

    /// Only folders this type made are removed.
    func remove() {
        guard FdtdPaths.basename(path).hasPrefix("fdtdkit-tests-") else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Sinks, clock, signals, process control

final class TextCollector: Sendable {
    private let text = Mutex("")

    var sink: FdtdSink { FdtdSink { [self] piece in text.withLock { $0 += piece } } }
    var value: String { text.withLock { $0 } }
}

/// Time moves only through advance(); timers fire there, in due order, never inside after().
final class FakeClock: FdtdClock {
    private struct Pending: Sendable {
        var due: Double
        var timer: FdtdTimer
        var action: @Sendable () -> Void
    }

    private struct State: Sendable {
        var uptime = 1000.0
        var pending: [Pending] = []
    }

    private let state = Mutex(State())
    let start: Date

    init(start: Date) { self.start = start }

    func now() -> Date { start.addingTimeInterval(uptime() - 1000) }

    func uptime() -> Double { state.withLock { $0.uptime } }

    func after(_ seconds: Double, _ action: @escaping @Sendable () -> Void) -> FdtdTimer {
        let timer = FdtdTimer()
        state.withLock { $0.pending.append(Pending(due: $0.uptime + seconds, timer: timer, action: action)) }
        return timer
    }

    func advance(_ seconds: Double) {
        let target = state.withLock { $0.uptime + seconds }
        while true {
            let next: Pending? = state.withLock { s in
                guard let k = s.pending.indices.min(by: { s.pending[$0].due < s.pending[$1].due }),
                      s.pending[k].due <= target else { return nil }
                let item = s.pending.remove(at: k)
                s.uptime = max(s.uptime, item.due)
                return item
            }
            guard let item = next else { break }
            item.timer.fireIfLive(item.action)
        }
        state.withLock { $0.uptime = target }
    }

    /// Timers neither fired nor cancelled.
    var liveTimers: Int { state.withLock { $0.pending.filter { !$0.timer.isCancelled }.count } }
}

final class FakeSignalSource: FdtdSignalSource {
    private struct State: Sendable {
        var handler: (@Sendable (Int32) -> Void)? = nil
        var installs = 0
        var restores = 0
        var gaveUp: [Int32] = []
    }

    private let state = Mutex(State())

    func install(_ handler: @escaping @Sendable (Int32) -> Void) -> any FdtdSignalInstallation {
        state.withLock { s in
            s.handler = handler
            s.installs += 1
        }
        return Installation(source: self)
    }

    /// The signal as the live source would deliver it, on the calling thread.
    func trigger(_ signo: Int32) {
        let handler = state.withLock { $0.handler }
        handler?(signo)
    }

    var installs: Int { state.withLock { $0.installs } }
    var restores: Int { state.withLock { $0.restores } }
    var installed: Bool { state.withLock { $0.handler != nil } }
    /// The signals the CLI gave up on (the live source ends the process there).
    var gaveUp: [Int32] { state.withLock { $0.gaveUp } }

    fileprivate func restored() {
        state.withLock { s in
            s.handler = nil
            s.restores += 1
        }
    }

    private struct Installation: FdtdSignalInstallation {
        let source: FakeSignalSource
        func restore() { source.restored() }
        func giveUp(_ signo: Int32) { source.state.withLock { $0.gaveUp.append(signo) } }
    }
}

struct SentSignal: Equatable, Sendable {
    var group: Int32
    var signo: Int32
}

struct ControlWrite: Equatable, Sendable {
    var fd: Int32
    var text: String
}

final class FakeProcessControl: FdtdProcessControl {
    private struct State: Sendable {
        var sent: [SentSignal] = []
        var writes: [ControlWrite] = []
        var closed: [Int32] = []
        var alive: Set<Int32> = []
    }

    private let state = Mutex(State())

    func setAlive(_ group: Int32, _ alive: Bool) {
        state.withLock { s in
            if alive { s.alive.insert(group) } else { s.alive.remove(group) }
        }
    }

    func signalGroup(_ pgid: Int32, _ signo: Int32) -> Bool {
        state.withLock { s in
            s.sent.append(SentSignal(group: pgid, signo: signo))
            let alive = s.alive.contains(pgid)
            if signo == SIGKILL { s.alive.remove(pgid) }
            return alive
        }
    }

    func groupAlive(_ pgid: Int32) -> Bool { state.withLock { $0.alive.contains(pgid) } }

    func writeControl(_ fd: Int32, _ text: String) -> Bool {
        state.withLock { s in
            guard !s.closed.contains(fd) else { return false }
            s.writes.append(ControlWrite(fd: fd, text: text))
            return true
        }
    }

    func closeControl(_ fd: Int32) { state.withLock { $0.closed.append(fd) } }

    var sent: [SentSignal] { state.withLock { $0.sent } }
    var writes: [ControlWrite] { state.withLock { $0.writes } }
    var closed: [Int32] { state.withLock { $0.closed } }
}

// MARK: - Synthetic Mach-O libraries

enum MachO {
    static let arm64: UInt32 = 0x0100_000c
    static let x86_64: UInt32 = 0x0100_0007

    static func le32(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
    static func be32(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }

    static func uuidBytes(_ text: String) -> [UInt8] {
        let hex = Array(text.replacingOccurrences(of: "-", with: ""))
        return stride(from: 0, to: hex.count, by: 2).map { UInt8(String(hex[$0..<$0 + 2]), radix: 16) ?? 0 }
    }

    /// A thin Mach-O 64 header (cputype `cpu`), a filler load command, LC_UUID when `uuid` is given, then each string
    /// between NUL bytes and `trailer`.
    static func thin(uuid: String?, strings: [String], cpu: UInt32 = arm64, trailer: [UInt8] = []) -> Data {
        var commands = le32(0x2) + le32(24) + [UInt8](repeating: 0, count: 16)
        var count: UInt32 = 1
        if let uuid {
            commands += le32(0x1b) + le32(24) + uuidBytes(uuid)
            count += 1
        }
        var bytes = le32(0xfeed_facf) + le32(cpu) + le32(0) + le32(6) + le32(count) + le32(UInt32(commands.count))
        bytes += le32(0) + le32(0) + commands
        for text in strings { bytes += [0] + Array(text.utf8) + [0] }
        return Data(bytes + trailer)
    }

    /// A fat file (FAT_MAGIC, 20-byte fat_arch entries) holding `slices`.
    static func fat(_ slices: [(cpu: UInt32, subtype: UInt32, data: Data)]) -> Data {
        var bytes = be32(0xcafe_babe) + be32(UInt32(slices.count))
        var offset = 8 + 20 * slices.count
        var placed: [(Int, Data)] = []
        for slice in slices {
            offset = (offset + 15) / 16 * 16
            bytes += be32(slice.cpu) + be32(slice.subtype) + be32(UInt32(offset)) + be32(UInt32(slice.data.count))
            bytes += be32(4)
            placed.append((offset, slice.data))
            offset += slice.data.count
        }
        for (at, data) in placed {
            bytes += [UInt8](repeating: 0, count: at - bytes.count)
            bytes += [UInt8](data)
        }
        return Data(bytes)
    }
}

/// What one synthetic library folder holds.
struct FakeLibrary: Sendable {
    var version: String?
    var engines: [FdtdEngine]
    var knobs: [String]
    var openEMSUUID: String?
    var csxcadUUID: String
    var nf2ffUUID: String
    var salt: String
    /// Extra bytes at the end of libopenEMS: the same build in other bytes (an installed copy).
    var trailer: [UInt8] = []

    var openEMS: Data {
        let knobNames = knobs.filter { $0 != "OPENEMS_NF2FF_LEGACY" }
        let strings = (version.map { [$0] } ?? []) + engines.map(\.helpString) + knobNames + ["libopenEMS " + salt]
        return MachO.thin(uuid: openEMSUUID, strings: strings, trailer: trailer)
    }

    var csxcad: Data { MachO.thin(uuid: csxcadUUID, strings: ["libCSXCAD " + salt]) }

    var nf2ff: Data {
        let legacy = knobs.contains("OPENEMS_NF2FF_LEGACY") ? ["OPENEMS_NF2FF_LEGACY"] : []
        return MachO.thin(uuid: nf2ffUUID, strings: legacy + ["libnf2ff " + salt])
    }

    var files: [String: Data] {
        ["libopenEMS.0.dylib": openEMS, "libCSXCAD.0.dylib": csxcad, "libnf2ff.0.dylib": nf2ff]
    }

    static let allKnobs = FdtdKnobs.registry.map(\.name)
    static let cpu = FdtdEngine.cpuEngines
    static let withGPU = FdtdEngine.cpuEngines + [.gpu, .gpuReference]
    static let all = FdtdEngine.allCases

    static let stock = FakeLibrary(version: "v0.37.0", engines: cpu, knobs: [],
                                   openEMSUUID: "B1A89DA1-0000-4000-8000-000000000001",
                                   csxcadUUID: "B1A89DA1-0000-4000-8000-000000000002",
                                   nf2ffUUID: "B1A89DA1-0000-4000-8000-000000000003", salt: "stock")
    static let cg18 = FakeLibrary(version: "v0.37.0-24-g087ce9e", engines: withGPU,
                                  knobs: ["OPENEMS_FUSED", "OPENEMS_FUSED_BLOCK", "OPENEMS_BALANCE", "OPENEMS_NO_STAGGER",
                                          "OPENEMS_NO_PACKED_COEFF", "OPENEMS_NO_PML_TABLE", "OPENEMS_QOS", "OPENEMS_FTZ",
                                          "OPENEMS_NF2FF_LEGACY", "OPENEMS_SETUP_TIMING", "OPENEMS_EXPORT_OPERATOR",
                                          "OPENEMS_EXPORT_FIELDS", "OPENEMS_PROBE_END_DB", "OPENEMS_PROBE_END_HOLD"],
                                  openEMSUUID: "24C8A7F2-0000-4000-8000-000000000001",
                                  csxcadUUID: "24C8A7F2-0000-4000-8000-000000000002",
                                  nf2ffUUID: "24C8A7F2-0000-4000-8000-000000000003", salt: "cg18")
    static let cg27 = FakeLibrary(version: "v0.37.0-38-g4127e1e", engines: all,
                                  knobs: allKnobs.filter { !["OPENEMS_DIAMOND_TUNE", "OPENEMS_FLAGS",
                                                             "OPENEMS_FLAGS_SPIN_US"].contains($0) },
                                  openEMSUUID: "4127E1E0-0000-4000-8000-000000000001",
                                  csxcadUUID: "4127E1E0-0000-4000-8000-000000000002",
                                  nf2ffUUID: "4127E1E0-0000-4000-8000-000000000003", salt: "cg27")
    static let cg29 = FakeLibrary(version: "v0.37.0-44-g074a687", engines: all, knobs: allKnobs,
                                  openEMSUUID: "40BC8CFF-0000-4000-8000-000000000001",
                                  csxcadUUID: "40BC8CFF-0000-4000-8000-000000000002",
                                  nf2ffUUID: "40BC8CFF-0000-4000-8000-000000000003", salt: "cg29")
}

// MARK: - FakeSystem

struct FakeCapture: Sendable {
    var exit: Int32? = 0
    var stdout = ""
    var stderr = ""
}

/// Files and folders in memory, plus answers for every child the CLI captures (probes, git, lsof, ps) and a
/// handler for spawned tools.
final class FakeSystem: FdtdSystem {
    struct Behaviour: Sendable {
        /// The python probe echoes the DYLD value it was sent; false = a Python that strips it.
        var dyldKept = true
        var importError: String? = nil
        /// The images the python probe reports instead of the three files of the folder it would load from.
        var probeLibraries: [String]? = nil
        /// The same for the probe of one Python (by the path it is started as): a Python with a library of its own.
        var probeLibrariesOf: [String: [String]] = [:]
        var legacyEmptyOption = true
        var lsofA = FakeCapture(exit: 1)
        var lsofB = FakeCapture(exit: 1)
        /// A signal that arrives while lsof runs; that lsof then ends without an exit status, as after SIGTERM.
        var signalDuringLsof: Int32? = nil
        /// The same for scan B alone (scan A answers); nil: signalDuringLsof.
        var signalDuringLsofB: Int32? = nil
        /// A signal that arrives once the first capture with this snippet in its argv has answered (then cleared).
        var signalAfterSnippet: (snippet: String, signo: Int32)? = nil
        /// A signal that arrives while the first capture with this snippet in its argv runs (then cleared); that
        /// child ends without an exit status, as after SIGTERM.
        var signalDuringSnippet: (snippet: String, signo: Int32)? = nil
        /// Paths that listDirectory leaves out of their folder's listing (the folder itself stays readable).
        var unlisted: Set<String> = []
        /// Sources whose moveItem fails (a rename that the volume refuses).
        var failMoves: Set<String> = []
        /// Paths whose removeItem fails.
        var failRemoves: Set<String> = []
        /// Atomic writes of this path fail once `after` of them went through.
        var failWrites: (path: String, after: Int)? = nil
        /// A capture that starts after a stop ends without an exit status, as the stop controller kills each child as
        /// it starts.
        var killAfterStop = false
        var psTree = FakeCapture(exit: 0)
        var psCommands = FakeCapture(exit: 0)
        var gitStatus = ""
        /// `git rev-parse --show-prefix`: the tools tree below the top level of its repository (empty at the top).
        var gitPrefix = ""
        var rfsim: [String: FdtdJSONValue] = [
            "probeEndDb": .number(-60), "probeEndHold": .number(0.5), "zMult": .number(4), "minCell": .number(0.05),
            "minCellEffective": .number(0.05), "env": .object([:]),
        ]
        var samplerLoad: FdtdJSONValue = FakeSystem.load(cpuOther: 52, gpuOther: 1)
        /// The password database's home folder of the account (nil: unknown).
        var accountHome: String? = FakeWorld.home
        var caffeinateStarts = true
        var spawn: (@Sendable (FdtdSpawnRequest, FdtdStopController) -> FdtdSpawnOutcome)? = nil
    }

    private struct State: Sendable {
        var files: [String: Data] = [:]
        var directories: Set<String> = ["/"]
        var executables: Set<String> = []
        var links: [String: String] = [:]
        /// Hard links: a second name, by the name whose file (inode and link count) it shares.
        var hardLinks: [String: String] = [:]
        /// Inode numbers by resolved path, given out on first use.
        var inodes: [String: UInt64] = [:]
        var captures: [FdtdCaptureRequest] = []
        var spawned: [FdtdInvocation] = []
        var caffeinated: [Int32] = []
        /// readChunks calls by resolved path.
        var chunkReads: [String: Int] = [:]
        /// readFile calls (whole reads, not those of readChunks) by resolved path.
        var wholeReads: [String: Int] = [:]
    }

    private let state = Mutex(State())
    let behaviour = Mutex(Behaviour())
    let control = FakeProcessControl()

    var processControl: any FdtdProcessControl { control }

    // MARK: Setup

    func addDirectory(_ path: String) { state.withLock { Self.makeParents(path, &$0); $0.directories.insert(path) } }

    func addFile(_ path: String, _ data: Data, executable: Bool = false) {
        state.withLock { s in
            Self.makeParents(FdtdPaths.dirname(path), &s)
            s.directories.insert(FdtdPaths.dirname(path))
            s.files[path] = data
            if executable { s.executables.insert(path) }
        }
    }

    func addFile(_ path: String, _ text: String, executable: Bool = false) {
        addFile(path, Data(text.utf8), executable: executable)
    }

    func addLink(_ path: String, to target: String) {
        state.withLock { s in
            Self.makeParents(FdtdPaths.dirname(path), &s)
            s.directories.insert(FdtdPaths.dirname(path))
            s.links[path] = target
        }
    }

    /// `path` as a second name of the file `existing` (ln without -s): one identity, two names. The bytes are copied,
    /// since the tests look at names and identities, not at writes through one of them.
    func addHardLink(_ path: String, to existing: String) {
        state.withLock { s in
            let original = Self.resolve(existing, s)
            Self.makeParents(FdtdPaths.dirname(path), &s)
            s.directories.insert(FdtdPaths.dirname(path))
            s.files[path] = s.files[original]
            s.hardLinks[path] = original
        }
    }

    /// `path` as a second name of the folder `existing` that no real path unifies (another letter case on a
    /// case-insensitive volume): one identity, two names.
    func addFolderAlias(_ path: String, of existing: String) {
        state.withLock { s in
            Self.makeParents(path, &s)
            s.directories.insert(path)
            s.hardLinks[path] = Self.resolve(existing, s)
        }
    }

    func addLibraryFolder(_ dir: String, _ files: [String: Data]) {
        addDirectory(dir)
        for (name, data) in files { addFile(dir + "/" + name, data, executable: true) }
    }

    func update(_ body: (inout Behaviour) -> Void) { behaviour.withLock { body(&$0) } }

    var captures: [FdtdCaptureRequest] { state.withLock { $0.captures } }
    var spawned: [FdtdInvocation] { state.withLock { $0.spawned } }
    var caffeinated: [Int32] { state.withLock { $0.caffeinated } }
    var allPaths: [String] { state.withLock { Array($0.files.keys) + Array($0.directories) }.sorted() }

    /// How often readChunks streamed `path` (hashing reads a file this way).
    func chunkReads(_ path: String) -> Int { state.withLock { $0.chunkReads[Self.resolve(path, $0)] ?? 0 } }

    /// How often readFile read `path` whole.
    func wholeReads(_ path: String) -> Int { state.withLock { $0.wholeReads[Self.resolve(path, $0)] ?? 0 } }

    func contents(_ path: String) -> String? { readFile(path).map { String(decoding: $0, as: UTF8.self) } }

    // MARK: FdtdSystem: files

    func fileExists(_ path: String) -> Bool {
        state.withLock { s in
            let p = Self.resolve(path, s)
            return s.files[p] != nil || s.directories.contains(p)
        }
    }

    func isDirectory(_ path: String) -> Bool { state.withLock { $0.directories.contains(Self.resolve(path, $0)) } }

    func isRegularFile(_ path: String) -> Bool { state.withLock { $0.files[Self.resolve(path, $0)] != nil } }

    func isExecutableFile(_ path: String) -> Bool {
        state.withLock { s in
            let p = Self.resolve(path, s)
            return s.files[p] != nil && s.executables.contains(p)
        }
    }

    func realPath(_ path: String) -> String? {
        state.withLock { s in
            let p = Self.resolve(path, s)
            return s.files[p] != nil || s.directories.contains(p) ? p : nil
        }
    }

    func fileIdentity(_ path: String) -> FdtdInode? {
        state.withLock { s in
            var p = Self.resolve(path, s)
            guard s.files[p] != nil || s.directories.contains(p) else { return nil }
            p = s.hardLinks[p] ?? p
            if let known = s.inodes[p] { return FdtdInode(device: 1, inode: known) }
            let inode = UInt64(s.inodes.count + 2)
            s.inodes[p] = inode
            return FdtdInode(device: 1, inode: inode)
        }
    }

    func linkCount(_ path: String) -> Int? {
        state.withLock { s in
            let p = Self.resolve(path, s)
            guard s.files[p] != nil || s.directories.contains(p) else { return nil }
            let original = s.hardLinks[p] ?? p
            return 1 + s.hardLinks.values.filter { $0 == original }.count
        }
    }

    func symbolicLinkTarget(_ path: String) -> String? {
        state.withLock { s in
            // the link's own name is not followed, the folders above it are
            let folder = Self.resolve(FdtdPaths.dirname(path), s)
            return s.links[FdtdPaths.join(folder, FdtdPaths.basename(path))]
        }
    }

    func accountHome() -> String? { behaviour.withLock { $0.accountHome } }

    func fileSize(_ path: String) -> Int? { state.withLock { $0.files[Self.resolve(path, $0)]?.count } }

    func readFile(_ path: String) -> Data? {
        state.withLock { s in
            let resolved = Self.resolve(path, s)
            s.wholeReads[resolved, default: 0] += 1
            return s.files[resolved]
        }
    }

    func readChunks(_ path: String, chunkSize: Int, _ body: (Data) -> Void) -> Bool {
        let found: Data? = state.withLock { s in
            let resolved = Self.resolve(path, s)
            s.chunkReads[resolved, default: 0] += 1
            return s.files[resolved]
        }
        guard let data = found else { return false }
        var at = 0
        while at < data.count {
            let end = min(at + chunkSize, data.count)
            body(data.subdata(in: at..<end))
            at = end
        }
        return true
    }

    func listDirectory(_ path: String) -> [String]? {
        let unlisted = behaviour.withLock { $0.unlisted }
        return state.withLock { s in
            let dir = Self.resolve(path, s)
            guard s.directories.contains(dir) else { return nil }
            let prefix = dir == "/" ? "/" : dir + "/"
            var names = Set<String>()
            for key in Array(s.files.keys) + Array(s.directories) + Array(s.links.keys) where key.hasPrefix(prefix) {
                let rest = key.dropFirst(prefix.count)
                if !rest.isEmpty, !rest.contains("/"), !unlisted.contains(key) { names.insert(String(rest)) }
            }
            return names.sorted()
        }
    }

    func createDirectories(_ path: String) throws {
        try state.withLock { s in
            if s.files[path] != nil { throw FdtdSystemError(path: path, message: "File exists") }
            Self.makeParents(path, &s)
            s.directories.insert(path)
        }
    }

    func makeDirectoryExclusive(_ path: String) -> FdtdMkdirResult {
        state.withLock { s in
            if s.files[path] != nil || s.directories.contains(path) { return .exists }
            guard s.directories.contains(FdtdPaths.dirname(path)) else { return .failed("No such file or directory") }
            s.directories.insert(path)
            return .created
        }
    }

    /// The folders on the way are followed like the kernel's walk; an atomic write replaces a link at the last name
    /// (rename(2) over it), a plain one writes through it.
    func writeFile(_ path: String, _ data: Data, atomically: Bool) throws {
        let refused = behaviour.withLock { b -> Bool in
            guard atomically, let rule = b.failWrites, rule.path == path else { return false }
            if rule.after > 0 { b.failWrites = (path, rule.after - 1) }
            return rule.after <= 0
        }
        if refused { throw FdtdSystemError(path: path, message: "No space left on device") }
        try state.withLock { s in
            let folder = Self.resolve(FdtdPaths.dirname(path), s)
            let target = atomically ? FdtdPaths.join(folder, FdtdPaths.basename(path)) : Self.resolve(path, s)
            guard s.directories.contains(FdtdPaths.dirname(target)) else {
                throw FdtdSystemError(path: path, message: "No such file or directory")
            }
            if atomically { s.links[target] = nil }
            s.files[target] = data
        }
    }

    func appendToFile(_ path: String, _ data: Data) throws {
        try state.withLock { s in
            guard s.directories.contains(FdtdPaths.dirname(path)) else {
                throw FdtdSystemError(path: path, message: "No such file or directory")
            }
            s.files[path, default: Data()].append(data)
        }
    }

    func copyItem(_ source: String, to destination: String) throws {
        try state.withLock { s in
            guard s.files[destination] == nil, !s.directories.contains(destination) else {
                throw FdtdSystemError(path: destination, message: "File exists")
            }
            if let data = s.files[source] {
                s.files[destination] = data
                return
            }
            guard s.directories.contains(source) else { throw FdtdSystemError(path: source, message: "No such file") }
            for (key, data) in s.files where key.hasPrefix(source + "/") {
                s.files[destination + key.dropFirst(source.count)] = data
            }
            for key in s.directories where key == source || key.hasPrefix(source + "/") {
                s.directories.insert(destination + key.dropFirst(source.count))
            }
        }
    }

    func moveItem(_ source: String, to destination: String) throws {
        if behaviour.withLock({ $0.failMoves.contains(source) }) {
            throw FdtdSystemError(path: source, message: "Operation not permitted")
        }
        try copyItem(source, to: destination)
        try removeItem(source)
    }

    func removeItem(_ path: String) throws {
        if behaviour.withLock({ $0.failRemoves.contains(path) }) {
            throw FdtdSystemError(path: path, message: "Operation not permitted")
        }
        try state.withLock { s in
            if s.files.removeValue(forKey: path) != nil || s.links.removeValue(forKey: path) != nil { return }
            guard s.directories.contains(path) else { throw FdtdSystemError(path: path, message: "No such file") }
            for key in Array(s.files.keys) where key.hasPrefix(path + "/") { s.files[key] = nil }
            for key in Array(s.directories) where key == path || key.hasPrefix(path + "/") { s.directories.remove(key) }
        }
    }

    // MARK: FdtdSystem: machine

    func sysctlString(_ name: String) -> String? { name == "machdep.cpu.brand_string" ? "Apple M5" : nil }

    func sysctlInt(_ name: String) -> Int? {
        ["hw.perflevel0.physicalcpu": 4, "hw.perflevel1.physicalcpu": 6][name]
    }

    func hostFacts() -> FdtdHostFacts {
        FdtdHostFacts(activeProcessorCount: 10, physicalMemory: 16 << 30, operatingSystemVersion: "Version 26.1")
    }

    // MARK: FdtdSystem: children

    func capture(_ request: FdtdCaptureRequest, stop: FdtdStopController?) -> FdtdCaptureResult {
        state.withLock { $0.captures.append(request) }
        if stop?.stopRequested == true, behaviour.withLock({ $0.killAfterStop }) {
            return FdtdCaptureResult(exit: nil, stdout: "", stderr: "", seconds: 0.01)
        }
        if request.argv.first == "/usr/sbin/lsof" {
            let scanB = request.argv.contains("--")
            let signal = behaviour.withLock { b in
                scanB ? (b.signalDuringLsofB ?? b.signalDuringLsof) : b.signalDuringLsof
            }
            if let signo = signal {
                stop?.signalArrived(signo)
                return FdtdCaptureResult(exit: nil, stdout: "", stderr: "", seconds: 0.01)
            }
        }
        let during = behaviour.withLock { b -> Int32? in
            guard let during = b.signalDuringSnippet, request.argv.contains(during.snippet) else { return nil }
            b.signalDuringSnippet = nil
            return during.signo
        }
        if let during {
            stop?.signalArrived(during)
            return FdtdCaptureResult(exit: nil, stdout: "", stderr: "", seconds: 0.01)
        }
        let answer = respond(request)
        var result = FdtdCaptureResult(exit: answer.exit, stdout: answer.stdout, stderr: answer.stderr, seconds: 0.01)
        if answer.exit == nil && answer.stdout.isEmpty { result.spawnError = "FakeSystem has no answer" }
        let after = behaviour.withLock { b -> Int32? in
            guard let after = b.signalAfterSnippet, request.argv.contains(after.snippet) else { return nil }
            b.signalAfterSnippet = nil
            return after.signo
        }
        if let after { stop?.signalArrived(after) }
        return result
    }

    func spawn(_ request: FdtdSpawnRequest, stop: FdtdStopController) -> FdtdSpawnOutcome {
        state.withLock { $0.spawned.append(request.invocation) }
        guard let handler = behaviour.withLock({ $0.spawn }) else {
            return FdtdSpawnOutcome(spawnError: "FakeSystem spawns nothing")
        }
        return handler(request, stop)
    }

    func startCaffeinate(watching pid: Int32) -> Bool {
        state.withLock { $0.caffeinated.append(pid) }
        return behaviour.withLock { $0.caffeinateStarts }
    }

    // MARK: Answers

    /// A sampler result as usage.Sampler.stop() returns it.
    static func load(cpuOther: Double, gpuOther: Double, cpuSelf: Double = 101, wall: Double = 1.0) -> FdtdJSONValue {
        .object(["cpu_self": .number(cpuSelf), "cpu_other": .number(cpuOther), "gpu_self": .number(0),
                 "gpu_other": .number(gpuOther), "wall": .number(wall), "gpu_dev": .number(4), "busy": .array([])])
    }

    /// Porcelain lines as git prints them by default: a path with a byte above 0x7f in quotes, those bytes as octal.
    static func cQuoted(_ status: String) -> String {
        status.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard line.utf8.contains(where: { $0 > 0x7f }), line.count > 3 else { return String(line) }
            let path = line.dropFirst(3).utf8.map { byte -> String in
                byte > 0x7f ? "\\" + String(byte, radix: 8) : String(decoding: [byte], as: UTF8.self)
            }
            return line.prefix(3) + "\"" + path.joined() + "\""
        }.joined(separator: "\n")
    }

    static func line(_ tag: String, _ value: FdtdJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("null".utf8)
        return tag + " " + String(decoding: data, as: UTF8.self) + "\n"
    }

    private func respond(_ request: FdtdCaptureRequest) -> FakeCapture {
        let argv = request.argv
        let b = behaviour.withLock { $0 }
        guard let tool = argv.first else { return FakeCapture(exit: nil) }
        switch tool {
        case "/usr/bin/git":
            var words = Array(argv.dropFirst(3))
            // the status must be asked with unquoted paths; a plain `status` gets git's C-quoted form of gitStatus
            let unquoted = words.starts(with: ["-c", "core.quotePath=false"])
            if unquoted { words.removeFirst(2) }
            if words.starts(with: ["rev-parse", "--show-prefix"]) { return FakeCapture(stdout: b.gitPrefix + "\n") }
            if words.starts(with: ["rev-parse"]) { return FakeCapture(stdout: argv[2] == FakeWorld.rfsim ? "fed9876\n" : "abc1234\n") }
            if words.starts(with: ["status"]) {
                return FakeCapture(stdout: unquoted ? b.gitStatus : Self.cQuoted(b.gitStatus))
            }
            if words.starts(with: ["log"]) { return FakeCapture(stdout: "1a2b3c4\n") }
            return FakeCapture(exit: 128)
        case "/usr/sbin/lsof":
            return argv.contains("--") ? b.lsofB : b.lsofA
        case "/bin/ps":
            return argv.contains("-Ao") ? b.psTree : b.psCommands
        case "/bin/zsh":
            // the pre-probe: DYLD_LIBRARY_PATH="$1" python3 ... with $1 = LIBDIR
            guard argv.count >= 6 else { return FakeCapture(exit: 1) }
            return FakeCapture(stdout: probeLine(executable: FakeWorld.python, dyld: argv[5], behaviour: b))
        default:
            break
        }
        guard argv.count >= 4, argv[1] == "-B", argv[2] == "-c" else { return FakeCapture(exit: nil) }
        switch argv[3] {
        case FdtdSnippets.probe:
            let sent = request.environment["DYLD_LIBRARY_PATH"]
            return FakeCapture(stdout: probeLine(executable: tool, dyld: b.dyldKept ? sent : nil, behaviour: b))
        case FdtdSnippets.rfsim:
            var values = b.rfsim
            values["core"] = .string(argv[4] + "/rfsim/openems/core.py")
            return FakeCapture(stdout: Self.line(FdtdSnippets.rfsimTag, .object(values)))
        case FdtdSnippets.load:
            let value: FdtdJSONValue = .object(["load": b.samplerLoad, "processesSeen": .number(412),
                                                "gpuClientsSeen": .number(9), "utilSamples": .number(2)])
            return FakeCapture(stdout: Self.line(FdtdSnippets.loadTag, value))
        default:
            return FakeCapture(exit: nil)
        }
    }

    /// The probe line: the libraries of the folder DYLD names when it holds the three files, else the installed ones.
    private func probeLine(executable: String, dyld: String?, behaviour b: Behaviour) -> String {
        var out: [String: FdtdJSONValue] = [
            "executable": .string(executable), "realPath": .string(realPath(executable) ?? executable),
            "version": .string("3.14.6"), "dyld": dyld.map { .string($0) } ?? .null,
        ]
        if let error = b.importError {
            out["numpy"] = .string("2.3.4")
            out["importError"] = .string(error)
        } else {
            let names = FdtdLibraries.fileNames
            let folder = dyld.flatMap { dir in names.allSatisfy { isRegularFile(dir + "/" + $0) } ? dir : nil }
                ?? FakeWorld.installed
            out["numpy"] = .string("2.3.4")
            out["openemsModule"] = .string(FakeWorld.home + "/.local/lib/python3.14/site-packages/openEMS/__init__.py")
            // dyld reports the real folder of an image, not the name it was reached by
            let real = realPath(folder) ?? folder
            let images = ["libCSXCAD.0.dylib", "libnf2ff.0.dylib", "libopenEMS.0.dylib"].map { real + "/" + $0 }
            let reported = b.probeLibrariesOf[executable] ?? b.probeLibraries ?? images
            out["libraries"] = .array(reported.map { .string($0) })
            out["openemsVersion"] = .string("0.0.36")
            out["legacyEmptyOption"] = .bool(b.legacyEmptyOption)
        }
        return "loading\n" + Self.line(FdtdSnippets.probeTag, .object(out))
    }

    // MARK: Paths

    /// `path` as the kernel walks it: name by name, each link replaced by its target (relative to the link's folder),
    /// `.` skipped and `..` taken on the folder reached so far; at most 32 links.
    private static func resolve(_ path: String, _ s: State) -> String {
        var done: [String] = []
        var todo = path.split(separator: "/").map(String.init)
        var hops = 0
        while !todo.isEmpty {
            let name = todo.removeFirst()
            if name == "." { continue }
            if name == ".." {
                if !done.isEmpty { done.removeLast() }
                continue
            }
            let here = "/" + (done + [name]).joined(separator: "/")
            guard hops < 32, let target = s.links[here] else {
                done.append(name)
                continue
            }
            hops += 1
            if target.hasPrefix("/") { done = [] }
            todo = target.split(separator: "/").map(String.init) + todo
        }
        return "/" + done.joined(separator: "/")
    }

    private static func makeParents(_ path: String, _ s: inout State) {
        var dir = path
        while !dir.isEmpty, dir != "/" {
            s.directories.insert(dir)
            dir = FdtdPaths.dirname(dir)
        }
    }
}

// MARK: - The fake Mac

struct CLIRun {
    var exit: Int32
    var data: Data?
    var stdout: String
    var stderr: String

    /// The envelope (null when none was printed).
    var envelope: FdtdJSONValue {
        guard let data, let value = try? FdtdJSON.decode(FdtdJSONValue.self, from: data) else { return .null }
        return value
    }

    var text: String { data.map { String(decoding: $0, as: UTF8.self) } ?? "" }
    var status: String? { envelope["status"]?.string }
    var errorCodes: [String] { codes("errors") }
    var warningCodes: [String] { codes("warnings") }
    var result: FdtdJSONValue { envelope["result"] ?? .null }

    func codes(_ key: String) -> [String] { envelope[key]?.array?.compactMap { $0["code"]?.string } ?? [] }

    func issue(_ key: String, _ code: String) -> FdtdJSONValue? {
        envelope[key]?.array?.first { $0["code"]?.string == code }
    }
}

/// A Mac with a tools tree (REPO), a Python outside the system folders, the snapshots stock, cg18, cg27, cg29 and an
/// incomplete one, the installed library (cg18's build in other bytes), an rfsim toolkit and a fixed clock.
struct FakeWorld {
    static let home = "/Users/tester"
    static let repo = "/work/emsKit"
    static let python = "/opt/py/bin/python3"
    static let pythonReal = "/opt/py/bin/python3.14"
    static let snaps = "/Users/tester/opt/openEMS-dev/snap"
    static let installed = "/Users/tester/opt/openEMS/lib"
    static let rfsim = "/work/rfsim"
    static let runs = "/tmp/openems_bench_runs"
    static let pid: Int32 = 4242
    /// 2026-11-06 12:00:00 UTC.
    static let start = Date(timeIntervalSince1970: 1_793_966_400)
    static let stamp = "20261106-120000"

    let system = FakeSystem()
    let clock = FakeClock(start: FakeWorld.start)
    let signals = FakeSignalSource()
    var environment: [String: String] = [
        "HOME": FakeWorld.home, "PATH": "/opt/py/bin:/usr/bin:/bin", "USER": "tester", "LANG": "en_US.UTF-8",
        "DYLD_LIBRARY_PATH": "/opt/elsewhere/lib",
    ]
    var cwd = FakeWorld.repo
    var executablePath = "/usr/local/bin/emskit"

    init(snapshots: Bool = true) {
        for marker in FdtdDiscovery.markers {
            let body = marker == "bench/bench.py" ? "line += '  ' + usage.fmt(r['use'])\n" : "# \(marker)\n"
            system.addFile(Self.repo + "/" + marker, body)
        }
        system.addDirectory(Self.repo + "/results")
        system.addFile(Self.pythonReal, "#!python\n", executable: true)
        system.addLink(Self.python, to: Self.pythonReal)
        system.addFile("/usr/bin/python3", "#!stub\n", executable: true)
        if snapshots {
            system.addLibraryFolder(Self.snaps + "/stock", FakeLibrary.stock.files)
            system.addLibraryFolder(Self.snaps + "/cg18", FakeLibrary.cg18.files)
            system.addLibraryFolder(Self.snaps + "/cg27", FakeLibrary.cg27.files)
            system.addLibraryFolder(Self.snaps + "/cg29", FakeLibrary.cg29.files)
            var broken = FakeLibrary.cg29.files
            broken["libnf2ff.0.dylib"] = nil
            system.addLibraryFolder(Self.snaps + "/broken", broken)
        }
        var installed = FakeLibrary.cg18
        installed.trailer = Array("installed copy".utf8)
        system.addFile(Self.installed + "/libopenEMS.0.37.0.dylib", installed.openEMS, executable: true)
        system.addLink(Self.installed + "/libopenEMS.0.dylib", to: "libopenEMS.0.37.0.dylib")
        system.addFile(Self.installed + "/libCSXCAD.0.dylib", FakeLibrary.cg29.csxcad, executable: true)
        system.addFile(Self.installed + "/libnf2ff.0.dylib", FakeLibrary.cg29.nf2ff, executable: true)
        system.addFile(Self.rfsim + "/rfsim/openems/core.py", "PROBE_END_DB = -60\n")
        system.addFile(Self.rfsim + "/rfsim/openems/launch.py", "MIN_CELL = 0.05\n")
        system.addDirectory("/tmp")
    }

    func context(stdout: TextCollector, stderr: TextCollector) -> FdtdContext {
        FdtdContext(environment: environment, cwd: cwd, pid: Self.pid, executablePath: executablePath,
                    timeZone: TimeZone(identifier: "UTC")!, clock: clock, stdout: stdout.sink, stderr: stderr.sink,
                    signals: signals, system: system)
    }

    /// `emskit fdtd ARGS` on this world.
    func run(_ arguments: [String]) -> CLIRun {
        let out = TextCollector()
        let err = TextCollector()
        let (exit, data) = FdtdCLI.run(arguments: arguments, context: context(stdout: out, stderr: err))
        return CLIRun(exit: exit, data: data, stdout: out.value, stderr: err.value)
    }

    /// The run folder a command started now gets.
    static func runFolder(_ command: String) -> String { runs + "/emskit-fdtd/\(stamp)-\(command)-\(pid)" }
}

// MARK: - Fake tool runs

/// What a fake tool prints and leaves behind: stdout lines (through onLine and into tool.log), files relative to the
/// run folder, the launcher report and the exit status.
struct FakeToolRun: Sendable {
    var lines: [String] = []
    var files: [String: String] = [:]
    var absoluteFiles: [String: String] = [:]
    var exit: Int32 = 0
    var report: FdtdJSONValue? = nil
    var group: Int32 = 7001
    /// Runs while the child "runs": attached to the stop controller, before the outcome is returned.
    var during: (@Sendable (FdtdStopController) -> Void)? = nil

    /// The spawn handler that plays this run.
    func handler(_ system: FakeSystem) -> @Sendable (FdtdSpawnRequest, FdtdStopController) -> FdtdSpawnOutcome {
        let run = self
        return { request, stop in
            let argv = request.invocation.argv
            let reportPath = argv.firstIndex(of: "--report").map { argv[$0 + 1] }
            let folder = reportPath.map { FdtdPaths.dirname($0) } ?? FakeWorld.runs
            stop.attach(processGroup: run.group, controlFd: request.invocation.controlPipe ? 90 : nil)
            for line in run.lines {
                if let log = request.logPath { try? system.appendToFile(log, Data((line + "\n").utf8)) }
                request.onLine?(line)
            }
            for (name, text) in run.files {
                let path = folder + "/" + name
                try? system.createDirectories(FdtdPaths.dirname(path))
                try? system.writeFile(path, Data(text.utf8), atomically: true)
            }
            for (path, text) in run.absoluteFiles {
                try? system.createDirectories(FdtdPaths.dirname(path))
                try? system.writeFile(path, Data(text.utf8), atomically: true)
            }
            run.during?(stop)
            if let reportPath, let report = run.report {
                let data = (try? JSONEncoder().encode(report)) ?? Data()
                try? system.writeFile(reportPath, data, atomically: true)
            }
            stop.detach(processGroup: run.group)
            return FdtdSpawnOutcome(exit: run.exit, seconds: 1.5, ran: true, interrupted: stop.stopRequested,
                                    killed: stop.killed, processGroup: run.group)
        }
    }

    /// A launcher report in the launcher's own layout (fdtdkit_run.py REP).
    static func report(mode: String, argv: [String], exit: Int32, calls: [FdtdJSONValue] = [],
                       load: FdtdJSONValue = .null, libraries: [String] = [], interrupted: Bool = false,
                       exception: String? = nil) -> FdtdJSONValue {
        let counts: FdtdJSONValue = load == .null ? .null : .object(["processesSeen": .number(400),
                                                                    "gpuClientsSeen": .number(8),
                                                                    "utilSamples": .number(6)])
        return .object([
            "mode": .string(mode), "target": .string(argv.first ?? ""), "argv": .array(argv.map { .string($0) }),
            "exit": .number(Double(exit)), "interrupted": .bool(interrupted),
            "exception": exception.map { .string($0) } ?? .null, "wallSeconds": .number(3.25), "load": load,
            "loadCounts": counts, "libraries": .array(libraries.map { .string($0) }), "dyld": .null,
            "python": .object(["executable": .string(FakeWorld.pythonReal), "version": .string("3.14.6")]),
            "binding": .object(["version": .string("0.0.36"), "legacyEmptyOption": .bool(true)]),
            "calls": .array(calls),
        ])
    }

    /// One call record as the launcher's shim writes it.
    static func call(index: Int, load: FdtdJSONValue, options: [String: String] = [:],
                     applied: [String: String] = [:]) -> FdtdJSONValue {
        let counts: FdtdJSONValue = load == .null ? .null : .object(["processesSeen": .number(400),
                                                                    "gpuClientsSeen": .number(8),
                                                                    "utilSamples": .number(3)])
        return .object([
            "index": .number(Double(index)), "simPath": .string("/work/sim\(index)"), "setupOnly": .bool(false),
            "options": .object(options.mapValues { .string($0) }), "applied": .object(applied.mapValues { .string($0) }),
            "overridden": .object([:]), "optionsLost": .array([]), "stdoutRedirected": .bool(false),
            "wallSeconds": .number(2.5), "load": load, "loadCounts": counts, "stopRequested": .bool(false),
            "probeEnd": .object(["OPENEMS_PROBE_END_DB": .null, "OPENEMS_PROBE_END_HOLD": .null]),
        ])
    }
}

/// A framework or Homebrew python3 for the tests that start real children; nil disables them.
enum TestPython {
    static let path: String? = {
        let candidates = ["/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
                          "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()
}
