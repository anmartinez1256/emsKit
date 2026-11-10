// SPDX-License-Identifier: GPL-3.0-or-later

// Child processes (spec 5.3, 11). posix_spawn puts every child in its own process group with /dev/null on fd 0 and
// one pipe on fds 1 and 2; a launcher child also gets the control pipe's read end on fd 3. A pump thread tees every
// byte into tool.log and echoes the lines FdtdEchoFilter passes. FdtdStopController turns signals into `stop`, SIGTERM
// and SIGKILL. Nothing here installs a process-wide handler: signals arrive through FdtdContext.signals.
import Foundation
import Synchronization

/// A short child run to completion with its output captured (the probes, git, lsof, ps, the sampler check).
struct FdtdCaptureRequest: Sendable, Equatable {
    var argv: [String]
    var cwd: String
    /// The child's whole environment; nothing is inherited.
    var environment: [String: String]
    /// SIGTERM to the child's group after this long: a hung probe must not hold the command.
    var timeoutSeconds = 120.0
}

/// What a capture gave. stdout and stderr are read from two pipes (tagged lines are searched in stdout).
struct FdtdCaptureResult: Sendable, Equatable {
    /// The exit status; nil when the child was ended by a signal or never started.
    var exit: Int32? = nil
    var termSignal: Int32? = nil
    var stdout = ""
    var stderr = ""
    var seconds = 0.0
    /// posix_spawn's error text when the child never started.
    var spawnError: String? = nil

    var ran: Bool { spawnError == nil }
}

/// A long child: its resolved invocation (argv, cwd, the whole `environment`, `controlPipe`), where its bytes go and
/// how its lines reach the CLI.
struct FdtdSpawnRequest: Sendable {
    var invocation: FdtdInvocation
    /// RUN/tool.log; every byte is appended. nil only in tests.
    var logPath: String? = nil
    /// Where echoed lines go (the CLI's stderr); nil echoes nothing.
    var echo: FdtdSink? = nil
    /// Every complete line, without its newline, on the pump thread, echoed or not. It may capture only Sendable
    /// values (sinks, copies, FdtdLineCollector), never the session.
    var onLine: (@Sendable (String) -> Void)? = nil
}

/// How a long child ended.
struct FdtdSpawnOutcome: Sendable, Equatable {
    /// The exit status, or 128 + the signal that ended it: the invocation record's `exit`.
    var exit: Int32? = nil
    var termSignal: Int32? = nil
    /// Bookkeeping, not a performance figure.
    var seconds = 0.0
    var ran = false
    /// A stop was requested while it ran.
    var interrupted = false
    /// Its group got SIGKILL.
    var killed = false
    var spawnError: String? = nil
    var processGroup: Int32? = nil
}

/// Collects a child's lines on the pump thread for the dispatcher to read once the child has ended.
final class FdtdLineCollector: Sendable {
    private let lines = Mutex([String]())

    init() {}

    func append(_ line: String) { lines.withLock { $0.append(line) } }

    var all: [String] { lines.withLock { $0 } }
}

/// Which tool lines reach stderr (spec 8): the launcher markers and every line that carries a speed or a run time
/// (`MC/s`, `MCells/s`, `MCell/s`, `Speed:`, `Time for N iterations`, `RESULT {`, `Case times (s)`) stay in tool.log
/// only; the CLI prints its own figure lines with their loads instead. Also kept back: every `FDTDKIT_` line, abtest's
/// per-config summaries (their medians carry no unit), and the OPENEMS_SETUP_TIMING and OPENEMS_FUSED_STAT timings.
enum FdtdEchoFilter {
    static func passes(_ line: String) -> Bool {
        if hiddenPrefixes.contains(where: { line.hasPrefix($0) }) { return false }
        if hiddenMarkers.contains(where: { line.contains($0) }) { return false }
        if line.hasPrefix("  thread "), line.contains("(waits ") { return false }
        return !hasIterationsTime(line) && !isAbtestSummary(line)
    }

    private static let hiddenPrefixes = ["FDTDKIT_", "RESULT {", "setup timing: ", "Fused sweep timing"]
    private static let hiddenMarkers = ["MC/s", "MCells/s", "MCell/s", "Speed:", "Case times (s)"]

    /// openEMS's `Time for N iterations with C cells : T sec`, anywhere in the line.
    private static func hasIterationsTime(_ line: String) -> Bool {
        var rest = Substring(line)
        while let found = rest.range(of: "Time for ") {
            let after = rest[found.upperBound...]
            let digits = after.prefix(while: { $0.isASCII && $0.isNumber })
            if !digits.isEmpty, after.dropFirst(digits.count).hasPrefix(" iterations") { return true }
            rest = after
        }
        return false
    }

    /// `cI CFG MEDIAN [MIN-MAX]  xRATIO [MIN-MAX]  others C%/G%  DIFFS` (abtest.py:101-102).
    private static func isAbtestSummary(_ line: String) -> Bool {
        guard line.hasPrefix("c") else { return false }
        let digits = line.dropFirst().prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, line.dropFirst(1 + digits.count).hasPrefix(" ") else { return false }
        return line.contains("]  x") && line.contains("  others ") && line.contains("%/")
    }
}

/// posix_spawn and the pump (spec 5.3). LiveSystem forwards to it; the spawn tests call it directly with python3.
enum FdtdSpawner {
    /// Seconds from a capture's SIGTERM (its timeout, or a stop request) to SIGKILL of its group.
    private static let captureKillAfter = 5.0
    /// Seconds a capture keeps reading after its child has exited: a process outside the group can hold a pipe.
    private static let captureDrainAfterExit = 2.0
    /// A capture keeps at most this much of each stream; it reads on, so the child never blocks on a full pipe.
    private static let captureLimit = 32 << 20
    /// Seconds run() keeps the pump reading once the child has exited and nothing of its group runs any more.
    private static let pumpGraceSeconds = 3.0
    private static let readSize = 1 << 16

    private enum Started {
        case child(pid_t)
        case failed(String)
    }

    /// Runs a short child to completion, stdout and stderr captured apart, its own process group, /dev/null on fd 0.
    /// With `stop`, its group is attached as a probe (SIGTERM at once on a stop request, SIGKILL 5 s later).
    static func capture(_ request: FdtdCaptureRequest, stop: FdtdStopController?) -> FdtdCaptureResult {
        let started = DispatchTime.now().uptimeNanoseconds
        var result = FdtdCaptureResult()
        guard let out = makePipe() else {
            result.spawnError = "pipe: " + text(errno)
            return result
        }
        guard let err = makePipe() else {
            let code = errno
            closeAll([out.read, out.write])
            result.spawnError = "pipe: " + text(code)
            return result
        }
        let spawned = spawnChild(request.argv, environment: request.environment, cwd: request.cwd,
                                 dups: [(out.write, 1), (err.write, 2)])
        closeAll([out.write, err.write])
        let pid: pid_t
        switch spawned {
        case .child(let child):
            pid = child
        case .failed(let message):
            closeAll([out.read, err.read])
            result.spawnError = message
            result.seconds = seconds(since: started)
            return result
        }
        stop?.attachProbe(pid)
        let drained = drain(pid, out: out.read, err: err.read, timeout: request.timeoutSeconds, stop: stop)
        stop?.detachProbe(pid)
        result.stdout = String(decoding: drained.out, as: UTF8.self)
        result.stderr = String(decoding: drained.err, as: UTF8.self)
        result.exit = drained.exit
        result.termSignal = drained.signal
        result.seconds = seconds(since: started)
        return result
    }

    /// Runs a long child under `stop`: POSIX_SPAWN_SETPGROUP (0), SETSIGDEF {INT, TERM, HUP, PIPE, QUIT}, an empty
    /// SETSIGMASK, CLOEXEC_DEFAULT; /dev/null on 0, one pipe on 1 and 2, addchdir(cwd), and the control pipe's read
    /// end on 3 when invocation.controlPipe (both ends close-on-exec; the CLI closes its read end after the spawn and
    /// hands the write end to `stop.attach`). Returns once the child has exited and the pipe has reached EOF, or, when
    /// a process outside the child's group still holds the pipe, pumpGraceSeconds after the group has gone.
    static func run(_ request: FdtdSpawnRequest, stop: FdtdStopController) -> FdtdSpawnOutcome {
        let started = DispatchTime.now().uptimeNanoseconds
        let invocation = request.invocation
        var outcome = FdtdSpawnOutcome()
        let log = openLog(request.logPath)
        if let message = log.error {
            outcome.spawnError = message
            return outcome
        }
        let logFd = log.fd
        guard let output = makePipe() else {
            let code = errno
            closeAll([logFd])
            outcome.spawnError = "pipe: " + text(code)
            return outcome
        }
        let control = invocation.controlPipe ? makePipe() : nil
        if invocation.controlPipe && control == nil {
            let code = errno
            closeAll([logFd, output.read, output.write])
            outcome.spawnError = "control pipe: " + text(code)
            return outcome
        }
        var dups: [(Int32, Int32)] = [(output.write, 1), (output.write, 2)]
        if let control { dups.append((control.read, FdtdLauncherSource.controlFd)) }
        let spawned = spawnChild(invocation.argv, environment: invocation.environment, cwd: invocation.cwd, dups: dups)
        // The child has its copies now; EOF on the output pipe must come from the child's side only.
        closeAll([output.write])
        if let control { closeAll([control.read]) }
        let pid: pid_t
        switch spawned {
        case .child(let child):
            pid = child
        case .failed(let message):
            closeAll([logFd, output.read])
            if let control { closeAll([control.write]) }
            outcome.spawnError = message
            outcome.seconds = seconds(since: started)
            return outcome
        }
        stop.attach(processGroup: pid, controlFd: control?.write)

        let gate = FdtdPumpGate()
        let done = DispatchSemaphore(value: 0)
        let readFd = output.read
        let echo = request.echo
        let onLine = request.onLine
        Thread {
            FdtdSpawner.pump(readFd, log: logFd, echo: echo, onLine: onLine, gate: gate)
            done.signal()
        }.start()

        var status: Int32 = 0
        var reaped: pid_t = -1
        repeat {
            reaped = waitpid(pid, &status, 0)
        } while reaped < 0 && errno == EINTR
        // Members of the group (the tools' own children) may still write; a writer outside it is not waited for.
        var goneSince: Double? = nil
        while done.wait(timeout: .now() + 0.25) == .timedOut {
            if killpg(pid, 0) == 0 {
                goneSince = nil
            } else if let since = goneSince {
                if monotonic() - since > pumpGraceSeconds { gate.abandon() }
            } else {
                goneSince = monotonic()
            }
        }
        closeAll([readFd, logFd])
        stop.detach(processGroup: pid)

        var decoded: (exit: Int32?, signal: Int32?) = (nil, nil)
        if reaped == pid { decoded = decode(status) }
        outcome.ran = true
        outcome.processGroup = pid
        outcome.termSignal = decoded.signal
        outcome.exit = decoded.exit ?? decoded.signal.map { 128 + $0 }
        outcome.interrupted = stop.stopRequested
        outcome.killed = stop.killed
        outcome.seconds = seconds(since: started)
        return outcome
    }

    /// `/usr/bin/caffeinate -i -w PID` in its own process group, beside the run, never waited for (a detached thread
    /// reaps it); false when it could not start.
    static func startCaffeinate(watching pid: Int32) -> Bool {
        let argv = ["/usr/bin/caffeinate", "-i", "-w", String(pid)]
        let spawned = spawnChild(argv, environment: ["PATH": "/usr/bin:/bin"], cwd: "/", dups: [], nullOutput: true)
        guard case .child(let child) = spawned else { return false }
        Thread {
            var status: Int32 = 0
            while waitpid(child, &status, 0) < 0 && errno == EINTR {}
        }.start()
        return true
    }

    /// posix_spawn with spec 5.3's attributes: its own process group, default dispositions for INT, TERM, HUP, PIPE
    /// and QUIT (the CLI ignores them while it runs), an empty mask, /dev/null on fd 0, `dups` as (source, target),
    /// and every other descriptor closed in the child. `nullOutput` puts /dev/null on 1 and 2 as well.
    /// posix_spawn_file_actions_addchdir replaces addchdir_np from macOS 26 on (the SDK deprecates the _np form).
    private static func spawnChild(_ argv: [String], environment: [String: String], cwd: String,
                                   dups: [(Int32, Int32)], nullOutput: Bool = false) -> Started {
        guard let path = argv.first, !path.isEmpty else { return .failed("empty argv") }
        var attr: posix_spawnattr_t? = nil
        var rc = posix_spawnattr_init(&attr)
        guard rc == 0 else { return .failed("posix_spawnattr_init: " + text(rc)) }
        defer { posix_spawnattr_destroy(&attr) }
        var actions: posix_spawn_file_actions_t? = nil
        rc = posix_spawn_file_actions_init(&actions)
        guard rc == 0 else { return .failed("posix_spawn_file_actions_init: " + text(rc)) }
        defer { posix_spawn_file_actions_destroy(&actions) }

        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signo in [SIGINT, SIGTERM, SIGHUP, SIGPIPE, SIGQUIT] { sigaddset(&defaults, signo) }
        var mask = sigset_t()
        sigemptyset(&mask)
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        rc = posix_spawnattr_setflags(&attr, Int16(flags))
        if rc == 0 { rc = posix_spawnattr_setpgroup(&attr, 0) }
        if rc == 0 { rc = posix_spawnattr_setsigdefault(&attr, &defaults) }
        if rc == 0 { rc = posix_spawnattr_setsigmask(&attr, &mask) }
        if rc == 0 { rc = posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0) }
        if rc == 0, nullOutput { rc = posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0) }
        if rc == 0, nullOutput { rc = posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0) }
        for (source, target) in dups where rc == 0 {
            rc = posix_spawn_file_actions_adddup2(&actions, source, target)
        }
        if rc == 0, !cwd.isEmpty { rc = posix_spawn_file_actions_addchdir(&actions, cwd) }
        guard rc == 0 else { return .failed("posix_spawn attributes: " + text(rc)) }

        var args: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        args.append(nil)
        let entries = environment.keys.sorted().map { $0 + "=" + (environment[$0] ?? "") }
        var envp: [UnsafeMutablePointer<CChar>?] = entries.map { strdup($0) }
        envp.append(nil)
        defer {
            for p in args { free(p) }
            for p in envp { free(p) }
        }
        var pid: pid_t = 0
        rc = posix_spawn(&pid, path, &actions, &attr, args, envp)
        guard rc == 0 else { return .failed(path + ": " + text(rc)) }
        return .child(pid)
    }

    /// A pipe with both ends close-on-exec and above fd 9, so that no dup2 onto fds 0-3 has the same source and
    /// target: whether such a dup2 clears FD_CLOEXEC is not something to rely on.
    private static func makePipe() -> (read: Int32, write: Int32)? {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return nil }
        let r = fcntl(fds[0], F_DUPFD_CLOEXEC, 10)
        let w = fcntl(fds[1], F_DUPFD_CLOEXEC, 10)
        let code = errno
        closeAll(fds)
        guard r >= 0, w >= 0 else {
            closeAll([r, w])
            errno = code
            return nil
        }
        return (r, w)
    }

    /// tool.log opened for appending (fd -1 without a path).
    private static func openLog(_ path: String?) -> (fd: Int32, error: String?) {
        guard let path else { return (-1, nil) }
        let fd = Darwin.open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        if fd < 0 { return (-1, path + ": " + text(errno)) }
        return (fd, nil)
    }

    /// The pump: every byte to tool.log, then the lines to `echo` (filtered) and `onLine` (all).
    private static func pump(_ fd: Int32, log logFd: Int32, echo: FdtdSink?, onLine: (@Sendable (String) -> Void)?,
                             gate: FdtdPumpGate) {
        var splitter = FdtdLineSplitter()
        var buffer = [UInt8](repeating: 0, count: readSize)
        let deliver: (String) -> Void = { line in
            if let echo, FdtdEchoFilter.passes(line) { echo.line(line) }
            onLine?(line)
        }
        while !gate.isAbandoned {
            var entry = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&entry, 1, 250)
            if ready == 0 || (ready < 0 && errno == EINTR) { continue }
            if ready < 0 { break }
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n == 0 { break }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                break
            }
            if logFd >= 0 { _ = buffer.withUnsafeBytes { writeAll(logFd, UnsafeRawBufferPointer(rebasing: $0[..<n])) } }
            splitter.feed(buffer[..<n], deliver)
        }
        splitter.finish(deliver)
    }

    /// capture's loop on the calling thread: reads both pipes until EOF and reaps the child; a child past its timeout
    /// gets SIGTERM, and SIGKILL captureKillAfter later (after a stop request, that long after the request).
    /// What is left of the child's group when the reading ends with a pipe still open gets SIGKILL.
    private static func drain(_ pid: pid_t, out: Int32, err: Int32, timeout: Double,
                              stop: FdtdStopController?) -> (out: [UInt8], err: [UInt8], exit: Int32?, signal: Int32?) {
        var fds = [out, err]                        // -1 once that pipe is at EOF
        var data: [[UInt8]] = [[], []]
        var buffer = [UInt8](repeating: 0, count: readSize)
        var status: Int32 = 0
        var exited = false
        var reapedAt: Double? = nil
        var termAt: Double? = nil
        var killSent = false
        let start = monotonic()
        while true {
            let now = monotonic()
            if reapedAt == nil {
                let r = waitpid(pid, &status, WNOHANG)
                if r == pid {
                    exited = true
                    reapedAt = now
                } else if r < 0 && errno != EINTR {
                    reapedAt = now                  // nothing to wait for and no status to report
                }
            }
            if let reapedAt {
                if fds.allSatisfy({ $0 < 0 }) { break }
                if now - reapedAt > captureDrainAfterExit {
                    // a pipe is still open: something the child started may have outlived it in its group, and
                    // capture() detaches the group next, so no later stop would reach it. Its output is not waited
                    // for any more, hence SIGKILL. The group alone: the child's own pid is reaped and can be reused.
                    _ = killpg(pid, SIGKILL)
                    break
                }
            } else {
                let late = now - start >= timeout
                if termAt == nil, late || stop?.stopRequested == true {
                    if late { signalChild(pid, SIGTERM) }     // on a stop request the controller has sent it
                    termAt = now
                }
                if let termAt, !killSent, now - termAt >= captureKillAfter {
                    signalChild(pid, SIGKILL)
                    killSent = true
                }
            }
            var entries = fds.filter { $0 >= 0 }.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            if entries.isEmpty {
                usleep(10_000)
                continue
            }
            guard poll(&entries, nfds_t(entries.count), 50) > 0 else { continue }
            for entry in entries where entry.revents != 0 {
                guard let slot = fds.firstIndex(of: entry.fd) else { continue }
                let n = buffer.withUnsafeMutableBytes { Darwin.read(entry.fd, $0.baseAddress, $0.count) }
                if n > 0 {
                    if data[slot].count < captureLimit { data[slot].append(contentsOf: buffer[..<n]) }
                } else if n == 0 || (errno != EINTR && errno != EAGAIN) {
                    closeAll([entry.fd])
                    fds[slot] = -1
                }
            }
        }
        closeAll(fds)
        var decoded: (exit: Int32?, signal: Int32?) = (nil, nil)
        if exited { decoded = decode(status) }
        return (data[0], data[1], decoded.exit, decoded.signal)
    }

    /// The child's group, or the child alone when it has left its group (a probe that called setsid).
    private static func signalChild(_ pid: pid_t, _ signo: Int32) {
        if killpg(pid, signo) != 0 { _ = kill(pid, signo) }
    }

    /// waitpid's status by hand (the W* macros do not import): the exit status, or the signal that ended the child.
    private static func decode(_ status: Int32) -> (exit: Int32?, signal: Int32?) {
        let low = status & 0x7f
        if low == 0 { return ((status >> 8) & 0xff, nil) }
        if low != 0x7f { return (nil, low) }
        return (nil, nil)
    }

    @discardableResult
    private static func writeAll(_ fd: Int32, _ bytes: UnsafeRawBufferPointer) -> Bool {
        guard let base = bytes.baseAddress else { return true }
        var offset = 0
        while offset < bytes.count {
            let n = Darwin.write(fd, base + offset, bytes.count - offset)
            if n > 0 {
                offset += n
            } else if n < 0 && errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    /// Closes the descriptors that are open (>= 0).
    private static func closeAll(_ fds: [Int32]) {
        for fd in fds where fd >= 0 { _ = Darwin.close(fd) }
    }

    private static func text(_ code: Int32) -> String { String(cString: strerror(code)) }

    private static func monotonic() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    private static func seconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }
}

/// Set by run() once the child has exited and nothing of its group runs any more while the pipe still has a writer
/// (a process a tool left outside the group): the pump stops reading instead of waiting for that writer.
private final class FdtdPumpGate: Sendable {
    private let abandoned = Mutex(false)

    func abandon() { abandoned.withLock { $0 = true } }

    var isAbandoned: Bool { abandoned.withLock { $0 } }
}

/// The pump's line splitting: '\n' ends a line and a '\r' before it is dropped; a line longer than 1 MiB is cut there
/// (output without newlines must not grow the buffer); what is left at EOF is the last line. Bytes that are not
/// UTF-8 become U+FFFD.
private struct FdtdLineSplitter {
    static let maxLine = 1 << 20
    private var pending: [UInt8] = []

    mutating func feed(_ bytes: ArraySlice<UInt8>, _ deliver: (String) -> Void) {
        var start = bytes.startIndex
        while let newline = bytes[start...].firstIndex(of: 10) {
            pending.append(contentsOf: bytes[start..<newline])
            flush(deliver)
            start = newline + 1
        }
        pending.append(contentsOf: bytes[start...])
        while pending.count >= Self.maxLine {
            deliver(String(decoding: pending.prefix(Self.maxLine), as: UTF8.self))
            pending.removeFirst(Self.maxLine)
        }
    }

    mutating func finish(_ deliver: (String) -> Void) {
        if !pending.isEmpty { flush(deliver) }
    }

    private mutating func flush(_ deliver: (String) -> Void) {
        if pending.last == 13 { pending.removeLast() }
        deliver(String(decoding: pending, as: UTF8.self))
        pending.removeAll(keepingCapacity: true)
    }
}

/// What the stop controller does to processes. LiveProcessControl is the real one; the signal tests record the calls.
protocol FdtdProcessControl: Sendable {
    /// killpg(2); false when the group is gone.
    func signalGroup(_ pgid: Int32, _ signo: Int32) -> Bool
    /// killpg(pgid, 0) succeeds: something in the group still runs.
    func groupAlive(_ pgid: Int32) -> Bool
    /// One write to the control pipe; false on EPIPE or a closed descriptor (SIGPIPE is ignored).
    func writeControl(_ fd: Int32, _ text: String) -> Bool
    /// close(2) of the CLI's write end, which the launcher reads as EOF.
    func closeControl(_ fd: Int32)
}

/// The real process control.
struct LiveProcessControl: FdtdProcessControl {
    func signalGroup(_ pgid: Int32, _ signo: Int32) -> Bool { killpg(pgid, signo) == 0 }

    func groupAlive(_ pgid: Int32) -> Bool { killpg(pgid, 0) == 0 }

    func writeControl(_ fd: Int32, _ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) } == bytes.count
    }

    func closeControl(_ fd: Int32) { _ = Darwin.close(fd) }
}

/// Turns INT/TERM/HUP into the stop sequence of spec 11 for the child that runs now. First signal: `stop` on the
/// control pipe (a direct probe gets SIGTERM at once) and a 60 s timer. A second signal, or the timer while the group
/// is alive: SIGTERM to the group. 10 s later, if it is still alive: SIGKILL, and `killed` is set (finish() warns).
/// Called from the signal queue, the timers and the dispatcher; all state is under one Mutex.
final class FdtdStopController: Sendable {
    /// Seconds from the first signal to SIGTERM while the group is still alive.
    static let termAfterSeconds = 60.0
    /// Seconds from SIGTERM to SIGKILL.
    static let killAfterSeconds = 10.0

    private struct State: Sendable {
        var stopRequested = false
        var signalCount = 0
        /// The running launcher child's process group and the CLI's write end of its control pipe.
        var group: Int32? = nil
        var controlFd: Int32? = nil
        /// Direct probes that run now.
        var probes: Set<Int32> = []
        var termSent = false
        var killed = false
        var timer: FdtdTimer? = nil
    }

    /// The timer a step asks for. Timers are made after the lock is released (a clock may run its action at once);
    /// process control and control-pipe calls happen under it, so a descriptor is never used after it was closed.
    private enum Next: Sendable {
        case nothing
        case termTimer(Int32)
        case killTimer(Int32)
    }

    let clock: any FdtdClock
    let control: any FdtdProcessControl
    private let state = Mutex(State())

    init(clock: any FdtdClock, control: any FdtdProcessControl) {
        self.clock = clock
        self.control = control
    }

    /// The signal handler's whole job (it runs on the signal source's queue). Every signal sends SIGTERM to the
    /// probes; the first one delivers the stop to the attached child, the second sends its group SIGTERM.
    func signalArrived(_ signo: Int32) {
        let next: Next = state.withLock { s in
            s.signalCount += 1
            for pgid in s.probes.sorted() { _ = control.signalGroup(pgid, SIGTERM) }
            if !s.stopRequested {
                s.stopRequested = true
                return deliverStop(&s)
            }
            guard let group = s.group, !s.termSent else { return .nothing }
            return sendTerm(&s, group)
        }
        schedule(next)
    }

    /// The child that runs now: its process group and, for launcher children, the CLI's write end of the control pipe.
    /// A stop requested before (between two children) is delivered to it at once.
    func attach(processGroup: Int32, controlFd: Int32?) {
        let next: Next = state.withLock { s in
            s.timer?.cancel()
            s.timer = nil
            if let old = s.controlFd, old != controlFd { control.closeControl(old) }
            s.group = processGroup
            s.controlFd = controlFd
            s.termSent = false
            return s.stopRequested ? deliverStop(&s) : .nothing
        }
        schedule(next)
    }

    /// The child has exited: cancels the timers and closes the control fd if it is still open.
    func detach(processGroup: Int32) {
        state.withLock { s in
            guard s.group == processGroup else { return }
            s.timer?.cancel()
            s.timer = nil
            if let fd = s.controlFd { control.closeControl(fd) }
            s.controlFd = nil
            s.group = nil
            s.termSent = false
        }
    }

    /// A direct probe's group, which gets SIGTERM at once on a stop request.
    func attachProbe(_ pgid: Int32) {
        state.withLock { s in
            s.probes.insert(pgid)
            if s.stopRequested { _ = control.signalGroup(pgid, SIGTERM) }
        }
    }

    func detachProbe(_ pgid: Int32) {
        state.withLock { s in
            _ = s.probes.remove(pgid)
        }
    }

    /// Closes the CLI's write end now; the launcher reads EOF, which is a stop request (the spawn tests use it).
    func closeControlPipe() {
        state.withLock { s in
            if let fd = s.controlFd { control.closeControl(fd) }
            s.controlFd = nil
        }
    }

    var stopRequested: Bool { state.withLock { $0.stopRequested } }

    var killed: Bool { state.withLock { $0.killed } }

    /// Under the lock: the stop for the attached child. `stop` on its control pipe and the 60 s timer; a child without
    /// a control pipe (a direct one), or a stop after two signals, gets SIGTERM at once.
    private func deliverStop(_ s: inout State) -> Next {
        guard let group = s.group else { return .nothing }
        if s.signalCount < 2, let fd = s.controlFd {
            _ = control.writeControl(fd, "stop\n")
            return .termTimer(group)
        }
        return sendTerm(&s, group)
    }

    /// Under the lock: SIGTERM to the group now and the kill timer next.
    private func sendTerm(_ s: inout State, _ group: Int32) -> Next {
        s.timer?.cancel()
        s.timer = nil
        s.termSent = true
        _ = control.signalGroup(group, SIGTERM)
        return .killTimer(group)
    }

    private func schedule(_ next: Next) {
        switch next {
        case .nothing:
            return
        case .termTimer(let group):
            let timer = clock.after(Self.termAfterSeconds) { [self] in termTimerFired(group) }
            keep(timer, group: group, afterTerm: false)
        case .killTimer(let group):
            let timer = clock.after(Self.killAfterSeconds) { [self] in killTimerFired(group) }
            keep(timer, group: group, afterTerm: true)
        }
    }

    /// Stores a new timer unless its child has gone, or the sequence moved on, while the lock was free.
    private func keep(_ timer: FdtdTimer, group: Int32, afterTerm: Bool) {
        let current: Bool = state.withLock { s in
            guard s.group == group, s.termSent == afterTerm, !s.killed, s.timer == nil else { return false }
            s.timer = timer
            return true
        }
        if !current { timer.cancel() }
    }

    private func termTimerFired(_ group: Int32) {
        let next: Next = state.withLock { s in
            guard s.group == group, s.stopRequested, !s.termSent else { return .nothing }
            s.timer = nil
            guard control.groupAlive(group) else { return .nothing }
            return sendTerm(&s, group)
        }
        schedule(next)
    }

    private func killTimerFired(_ group: Int32) {
        state.withLock { s in
            guard s.group == group, s.termSent, !s.killed else { return }
            s.timer = nil
            if control.groupAlive(group), control.signalGroup(group, SIGKILL) { s.killed = true }
        }
    }
}
