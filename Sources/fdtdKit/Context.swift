// SPDX-License-Identifier: GPL-3.0-or-later

// What a command may touch, injected so that tests run without the Mac's state: the environment, cwd, pid, clock,
// stdout/stderr, the signal source and the system (files, sysctl, child processes). FdtdContext.live() is the real
// one; tests build their own with a FakeSystem, a fake clock and a fake signal source (spec 15, 16).
import Foundation
import Synchronization

/// Everything a command reads from or does to the outside world. No global mutable state anywhere else.
struct FdtdContext: Sendable {
    var environment: [String: String]
    var cwd: String
    var pid: Int32
    /// The executable's path as dyld reports it; Discovery walks up from its real path.
    var executablePath: String
    var timeZone: TimeZone
    var clock: any FdtdClock
    var stdout: FdtdSink
    var stderr: FdtdSink
    var signals: any FdtdSignalSource
    var system: any FdtdSystem

    var home: String { environment["HOME"] ?? NSHomeDirectory() }

    /// This process on this Mac.
    static func live() -> FdtdContext {
        let info = ProcessInfo.processInfo
        return FdtdContext(environment: info.environment, cwd: FileManager.default.currentDirectoryPath, pid: getpid(),
                           executablePath: Bundle.main.executablePath ?? info.arguments.first ?? "",
                           timeZone: TimeZone.current, clock: LiveClock(),
                           stdout: .fileDescriptor(STDOUT_FILENO), stderr: .fileDescriptor(STDERR_FILENO),
                           signals: LiveSignalSource(), system: LiveSystem())
    }
}

// MARK: - Output sinks

/// A text sink (stdout or stderr). Safe to call from any thread: the pump echoes tool lines while the command prints.
struct FdtdSink: Sendable {
    let write: @Sendable (String) -> Void

    init(_ write: @escaping @Sendable (String) -> Void) { self.write = write }

    func line(_ text: String) { write(text + "\n") }

    /// Writes to a file descriptor, one whole write(2) loop per call under a lock.
    static func fileDescriptor(_ fd: Int32) -> FdtdSink {
        let writer = FdtdDescriptorWriter(fd: fd)
        return FdtdSink { writer.write($0) }
    }
}

/// Serialises writes to one descriptor so that lines from two threads never interleave.
final class FdtdDescriptorWriter: Sendable {
    let fd: Int32
    private let lock = Mutex(())

    init(fd: Int32) { self.fd = fd }

    func write(_ text: String) {
        let bytes = Array(text.utf8)
        lock.withLock { _ in
            bytes.withUnsafeBytes { buf in
                var off = 0
                while off < buf.count {
                    let n = Darwin.write(fd, buf.baseAddress! + off, buf.count - off)
                    if n > 0 { off += n }
                    else if n < 0, errno == EINTR { continue }
                    else { break }                    // EPIPE (SIGPIPE is ignored) or a closed descriptor
                }
            }
        }
    }
}

// MARK: - Clock

/// Wall time for records, monotonic time for durations, and timers for the stop escalation (spec 11).
protocol FdtdClock: Sendable {
    func now() -> Date
    /// Monotonic seconds.
    func uptime() -> Double
    /// Runs `action` after `seconds` on some other thread unless the returned timer is cancelled first.
    func after(_ seconds: Double, _ action: @escaping @Sendable () -> Void) -> FdtdTimer
}

/// A cancellable timer shared by the live and the fake clocks.
final class FdtdTimer: Sendable {
    private let cancelled = Mutex(false)

    init() {}

    func cancel() { cancelled.withLock { $0 = true } }

    var isCancelled: Bool { cancelled.withLock { $0 } }

    /// Runs `action` unless the timer was cancelled; a clock calls this when the time has come.
    func fireIfLive(_ action: () -> Void) { if !isCancelled { action() } }
}

/// The real clock.
struct LiveClock: FdtdClock {
    func now() -> Date { Date() }

    func uptime() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    func after(_ seconds: Double, _ action: @escaping @Sendable () -> Void) -> FdtdTimer {
        let timer = FdtdTimer()
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { timer.fireIfLive(action) }
        return timer
    }
}

// MARK: - Signals

/// How INT, TERM and HUP reach the CLI. Only installed while a command can have children (spec 11).
protocol FdtdSignalSource: Sendable {
    /// Delivers INT, TERM and HUP to `handler` (on another thread) until restore() of the result.
    func install(_ handler: @escaping @Sendable (Int32) -> Void) -> any FdtdSignalInstallation
}

/// An installed signal source.
protocol FdtdSignalInstallation: Sendable {
    /// Puts the previous dispositions back; a second call does nothing.
    func restore()

    /// Ends the CLI now, as the default action of `signo` would (never returns on the live source).
    func giveUp(_ signo: Int32)
}

/// Counts the signals that arrive while finish() runs: the first is only noted, the second gives up. Before begin()
/// nothing is counted; the stop controller handles those.
final class FdtdFinishGuard: Sendable {
    private struct State: Sendable {
        var installation: (any FdtdSignalInstallation)? = nil
        var count: Int? = nil
    }

    private let state = Mutex(State())

    var installation: (any FdtdSignalInstallation)? {
        get { state.withLock { $0.installation } }
        set { state.withLock { $0.installation = newValue } }
    }

    func begin() { state.withLock { $0.count = 0 } }

    func signalArrived(_ signo: Int32) {
        let target: (any FdtdSignalInstallation)? = state.withLock { s in
            guard let seen = s.count else { return nil }
            s.count = seen + 1
            return seen >= 1 ? s.installation : nil
        }
        target?.giveUp(signo)
    }
}

/// SIG_IGN plus a DispatchSourceSignal per signal (kqueue still sees an ignored signal), restored afterwards. A SIGHUP
/// that was already ignored when the CLI started (nohup) is left alone: whoever started the CLI asked for a run that
/// outlives the terminal. INT and TERM stay stop requests whatever was inherited: a non-interactive shell starts
/// every `cmd &` with SIGINT ignored, and `kill -INT` is how a script stops such a run.
struct LiveSignalSource: FdtdSignalSource {
    static let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]
    /// The signals whose inherited SIG_IGN is honoured.
    static let leftIgnored: Set<Int32> = [SIGHUP]

    func install(_ handler: @escaping @Sendable (Int32) -> Void) -> any FdtdSignalInstallation {
        LiveSignalInstallation(signals: Self.signals, leftIgnored: Self.leftIgnored, handler: handler)
    }
}

/// @unchecked: `previous` and `sources` are written once in init and only read afterwards; dispatch sources are
/// thread-safe, and the one-time restore is guarded by a mutex.
final class LiveSignalInstallation: FdtdSignalInstallation, @unchecked Sendable {
    private let previous: [(Int32, sigaction)]
    private let sources: [any DispatchSourceSignal]
    private let restored = Mutex(false)

    init(signals: [Int32], leftIgnored: Set<Int32>, handler: @escaping @Sendable (Int32) -> Void) {
        let queue = DispatchQueue(label: "fdtdKit.signals")
        var previous: [(Int32, sigaction)] = []
        var sources: [any DispatchSourceSignal] = []
        for signo in signals {
            var old = sigaction()
            sigaction(signo, nil, &old)
            // no source for an inherited SIG_IGN of these: kqueue would report the signal all the same
            if leftIgnored.contains(signo), (old.sa_flags & SA_SIGINFO) == 0,
               Self.isIgnore(old.__sigaction_u.__sa_handler) { continue }
            previous.append((signo, old))
            signal(signo, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signo, queue: queue)
            // kqueue merges signals that arrive before the handler runs, and `data` counts them: a quick second
            // signal must still escalate (spec 11). The capture ends with cancel() in restore().
            source.setEventHandler {
                for _ in 0..<max(1, Int(source.data)) { handler(signo) }
            }
            source.resume()
            sources.append(source)
        }
        self.previous = previous
        self.sources = sources
    }

    private static func isIgnore(_ handler: (@convention(c) (Int32) -> Void)?) -> Bool {
        unsafeBitCast(handler, to: Int.self) == unsafeBitCast(SIG_IGN, to: Int.self)
    }

    /// The dispositions back, then the signal itself with its default action; an inherited SIG_IGN does not hold
    /// against the second request to end.
    func giveUp(_ signo: Int32) {
        restore()
        signal(signo, SIG_DFL)
        kill(getpid(), signo)
        usleep(200_000)
        _exit(128 + signo)
    }

    func restore() {
        let first = restored.withLock { done in
            let was = done
            done = true
            return !was
        }
        guard first else { return }
        for source in sources { source.cancel() }
        for (signo, old) in previous {
            var action = old
            sigaction(signo, &action, nil)
        }
    }
}

// MARK: - System

/// The result of an exclusive mkdir.
enum FdtdMkdirResult: Sendable, Equatable {
    case created
    case exists
    case failed(String)
}

/// The machine facts info reports besides sysctl.
struct FdtdHostFacts: Sendable, Equatable {
    var activeProcessorCount: Int
    var physicalMemory: UInt64
    var operatingSystemVersion: String
}

/// What stat(2) says a path names: (st_dev, st_ino), symbolic links followed. Two paths with the same identity name the
/// same file or folder however they are spelled (links, `..`, letter case on APFS, firmlinks).
struct FdtdInode: Sendable, Hashable {
    var device: UInt64
    var inode: UInt64
}

/// A failed file operation; callers turn it into an FdtdError with the code that fits.
struct FdtdSystemError: Error, Sendable, CustomStringConvertible {
    var path: String
    var message: String
    var description: String { "\(path): \(message)" }
}

/// Files, sysctl and child processes: everything Discovery, Libraries, RunFolder, Concurrency and the commands need
/// from the Mac. LiveSystem is the real one; the tests' FakeSystem answers from tables. Paths are absolute.
protocol FdtdSystem: Sendable {
    /// Follows symlinks: a dangling link does not exist.
    func fileExists(_ path: String) -> Bool
    func isDirectory(_ path: String) -> Bool
    func isRegularFile(_ path: String) -> Bool
    func isExecutableFile(_ path: String) -> Bool
    func realPath(_ path: String) -> String?
    /// Follows symlinks; nil when nothing is there (the protected-folder guard compares these, S3).
    func fileIdentity(_ path: String) -> FdtdInode?
    /// The number of names (hard links) of what `path` names, symlinks followed; nil when nothing is there.
    func linkCount(_ path: String) -> Int?
    /// The target a symbolic link holds, as written (readlink(2)); nil when `path` is not a link.
    func symbolicLinkTarget(_ path: String) -> String?
    /// The home folder of the account the CLI runs as, from the password database (not $HOME); nil when unknown.
    func accountHome() -> String?
    func fileSize(_ path: String) -> Int?
    func readFile(_ path: String) -> Data?
    /// Streams a file in chunks of `chunkSize` bytes; false when it cannot be read to the end.
    func readChunks(_ path: String, chunkSize: Int, _ body: (Data) -> Void) -> Bool
    /// Entry names, sorted; nil when `path` is not a readable folder.
    func listDirectory(_ path: String) -> [String]?
    func createDirectories(_ path: String) throws
    /// mkdir(2) of the leaf only, so that two runs can never share a folder.
    func makeDirectoryExclusive(_ path: String) -> FdtdMkdirResult
    func writeFile(_ path: String, _ data: Data, atomically: Bool) throws
    func appendToFile(_ path: String, _ data: Data) throws
    /// Fails when `destination` exists.
    func copyItem(_ source: String, to destination: String) throws
    /// Fails when `destination` exists.
    func moveItem(_ source: String, to destination: String) throws
    func removeItem(_ path: String) throws
    func sysctlString(_ name: String) -> String?
    func sysctlInt(_ name: String) -> Int?
    func hostFacts() -> FdtdHostFacts
    /// A short child run to completion with its output captured (probes, git, lsof, ps); never through a shell.
    func capture(_ request: FdtdCaptureRequest, stop: FdtdStopController?) -> FdtdCaptureResult
    /// A long child under the stop controller, its output pumped into tool.log and filtered onto stderr.
    func spawn(_ request: FdtdSpawnRequest, stop: FdtdStopController) -> FdtdSpawnOutcome
    /// `/usr/bin/caffeinate -i -w PID` beside the run, in its own process group, never waited for.
    func startCaffeinate(watching pid: Int32) -> Bool
    /// killpg, the group-alive test and control-pipe writes, for the stop controller.
    var processControl: any FdtdProcessControl { get }
}

extension FdtdSystem {
    /// Every executable file called `name` in the folders of `path` (a PATH value), in PATH order.
    func executables(named name: String, onPath path: String) -> [String] {
        var seen = Set<String>()
        return path.split(separator: ":", omittingEmptySubsequences: true).compactMap { dir in
            let candidate = FdtdPaths.join(String(dir), name)
            guard isExecutableFile(candidate), seen.insert(candidate).inserted else { return nil }
            return candidate
        }
    }
}

/// The real system.
struct LiveSystem: FdtdSystem {
    private func mode(_ path: String) -> mode_t? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return st.st_mode
    }

    func fileExists(_ path: String) -> Bool { mode(path) != nil }

    func isDirectory(_ path: String) -> Bool { mode(path).map { ($0 & S_IFMT) == S_IFDIR } ?? false }

    func isRegularFile(_ path: String) -> Bool { mode(path).map { ($0 & S_IFMT) == S_IFREG } ?? false }

    func isExecutableFile(_ path: String) -> Bool { isRegularFile(path) && access(path, X_OK) == 0 }

    func realPath(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    func fileIdentity(_ path: String) -> FdtdInode? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return FdtdInode(device: UInt64(UInt32(bitPattern: st.st_dev)), inode: UInt64(st.st_ino))
    }

    func linkCount(_ path: String) -> Int? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Int(st.st_nlink)
    }

    func symbolicLinkTarget(_ path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    func accountHome() -> String? {
        let start = FdtdPasswordDatabase.startSize(suggested: sysconf(_SC_GETPW_R_SIZE_MAX))
        return FdtdPasswordDatabase.home(startSize: start) { getpwuid_r(getuid(), $0, $1, $2, $3) }
    }

    func fileSize(_ path: String) -> Int? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Int(st.st_size)
    }

    func readFile(_ path: String) -> Data? { FileManager.default.contents(atPath: path) }

    func readChunks(_ path: String, chunkSize: Int, _ body: (Data) -> Void) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        do {
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty { body(chunk) }
            return true
        } catch {
            return false
        }
    }

    func listDirectory(_ path: String) -> [String]? {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.sorted()
    }

    func createDirectories(_ path: String) throws {
        do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
        catch { throw FdtdSystemError(path: path, message: error.localizedDescription) }
    }

    func makeDirectoryExclusive(_ path: String) -> FdtdMkdirResult {
        if mkdir(path, 0o755) == 0 { return .created }
        let e = errno
        return e == EEXIST ? .exists : .failed(String(cString: strerror(e)))
    }

    func writeFile(_ path: String, _ data: Data, atomically: Bool) throws {
        do { try data.write(to: URL(fileURLWithPath: path), options: atomically ? [.atomic] : []) }
        catch { throw FdtdSystemError(path: path, message: error.localizedDescription) }
    }

    func appendToFile(_ path: String, _ data: Data) throws {
        let fd = Darwin.open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw FdtdSystemError(path: path, message: String(cString: strerror(errno))) }
        defer { Darwin.close(fd) }
        try data.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let n = Darwin.write(fd, buf.baseAddress! + off, buf.count - off)
                if n > 0 { off += n }
                else if n < 0, errno == EINTR { continue }
                else { throw FdtdSystemError(path: path, message: String(cString: strerror(errno))) }
            }
        }
    }

    func copyItem(_ source: String, to destination: String) throws {
        do { try FileManager.default.copyItem(atPath: source, toPath: destination) }
        catch { throw FdtdSystemError(path: source, message: error.localizedDescription) }
    }

    func moveItem(_ source: String, to destination: String) throws {
        do { try FileManager.default.moveItem(atPath: source, toPath: destination) }
        catch { throw FdtdSystemError(path: source, message: error.localizedDescription) }
    }

    func removeItem(_ path: String) throws {
        do { try FileManager.default.removeItem(atPath: path) }
        catch { throw FdtdSystemError(path: path, message: error.localizedDescription) }
    }

    func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func sysctlInt(_ name: String) -> Int? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4:
            var v: Int32 = 0
            guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
            return Int(v)
        case 8:
            var v: Int64 = 0
            guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
            return Int(v)
        default:
            return nil
        }
    }

    func hostFacts() -> FdtdHostFacts {
        let info = ProcessInfo.processInfo
        return FdtdHostFacts(activeProcessorCount: info.activeProcessorCount, physicalMemory: info.physicalMemory,
                             operatingSystemVersion: info.operatingSystemVersionString)
    }

    func capture(_ request: FdtdCaptureRequest, stop: FdtdStopController?) -> FdtdCaptureResult {
        FdtdSpawner.capture(request, stop: stop)
    }

    func spawn(_ request: FdtdSpawnRequest, stop: FdtdStopController) -> FdtdSpawnOutcome {
        FdtdSpawner.run(request, stop: stop)
    }

    func startCaffeinate(watching pid: Int32) -> Bool { FdtdSpawner.startCaffeinate(watching: pid) }

    var processControl: any FdtdProcessControl { LiveProcessControl() }
}

// MARK: - Password database

/// The account's home folder by getpwuid_r(3), whose buffer starts at sysconf(_SC_GETPW_R_SIZE_MAX) when that is
/// positive and doubles on ERANGE up to a limit, so that a long entry is not taken for an unknown account.
enum FdtdPasswordDatabase {
    /// The first size when sysconf gives none.
    static let fallbackSize = 4096
    /// Where the doubling stops, far above any real entry.
    static let sizeLimit = 1 << 20

    /// getpwuid_r after the uid: the entry, the buffer, its size and the result pointer; 0, ERANGE or another error.
    typealias Lookup = (UnsafeMutablePointer<passwd>, UnsafeMutablePointer<CChar>, Int,
                        UnsafeMutablePointer<UnsafeMutablePointer<passwd>?>) -> Int32

    /// sysconf's size when it is positive, else fallbackSize.
    static func startSize(suggested: Int) -> Int { suggested > 0 ? suggested : fallbackSize }

    /// pw_dir of the entry `lookup` finds, with a buffer of `startSize` bytes that doubles while `lookup` answers
    /// ERANGE and the size is below `limit`; nil for no entry, another error, or ERANGE at the limit.
    static func home(startSize: Int, limit: Int = sizeLimit, lookup: Lookup) -> String? {
        var size = min(max(startSize, 1), limit)
        while true {
            var entry = passwd()
            var found: UnsafeMutablePointer<passwd>? = nil
            var buffer = [CChar](repeating: 0, count: size)
            // pw_dir points into the buffer, so it is read while the buffer is held
            let (status, home) = buffer.withUnsafeMutableBufferPointer { storage -> (Int32, String?) in
                guard let base = storage.baseAddress else { return (EINVAL, nil) }
                let status = lookup(&entry, base, storage.count, &found)
                guard status == 0, found != nil, let dir = entry.pw_dir else { return (status, nil) }
                return (status, String(cString: dir))
            }
            guard status == ERANGE, size < limit else { return home }
            size = min(size * 2, limit)
        }
    }
}

// MARK: - Paths

/// Plain path arithmetic (no symlink resolution: that is the system's realPath).
enum FdtdPaths {
    /// `path` made absolute against `cwd`, with `~` expanded and `.` and `..` folded.
    static func absolute(_ path: String, cwd: String, home: String) -> String {
        var p = path
        if p == "~" { p = home }
        else if p.hasPrefix("~/") { p = home + String(p.dropFirst()) }
        if !p.hasPrefix("/") { p = cwd + "/" + p }
        var parts: [Substring] = []
        for c in p.split(separator: "/", omittingEmptySubsequences: true) {
            if c == "." { continue }
            if c == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(c)
        }
        return "/" + parts.joined(separator: "/")
    }

    static func join(_ a: String, _ b: String) -> String { a.hasSuffix("/") ? a + b : a + "/" + b }

    static func dirname(_ path: String) -> String { (path as NSString).deletingLastPathComponent }

    static func basename(_ path: String) -> String { (path as NSString).lastPathComponent }
}
