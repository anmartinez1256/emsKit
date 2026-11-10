// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 SpawnTests (5.3, 11) with a real python3: the child leads its own process group, gets exactly the given
// environment and /dev/null on stdin, no descriptor but its own (fd 3 for a control-pipe child), the merged pipe keeps
// the order, closing the write end gives EOF on fd 3 while another child runs, and SIGTERM reaches the whole group.
import Foundation
import Synchronization
import Testing
@testable import fdtdKit

/// One live child through FdtdSpawner.run under a live stop controller.
enum LiveChild {
    /// As FdtdCLI.main does: a reader that went away gives EPIPE, not a dead test process.
    static let prepared: Bool = {
        signal(SIGPIPE, SIG_IGN)
        return true
    }()

    final class Once: Sendable {
        private let done = Mutex(false)
        func first() -> Bool { done.withLock { was in defer { was = true }; return !was } }
    }

    struct Result: Sendable {
        var outcome: FdtdSpawnOutcome
        var lines: [String]
        var log: String
        var seconds: Double
    }

    /// `trigger` runs once, on another thread, for the first line that starts with `prefix`.
    static func run(_ argv: [String], cwd: String, environment: [String: String], controlPipe: Bool = false,
                    log: String, stop: FdtdStopController? = nil, on prefix: String? = nil,
                    trigger: (@Sendable (FdtdStopController) -> Void)? = nil) -> Result {
        _ = prepared
        let stop = stop ?? FdtdStopController(clock: LiveClock(), control: LiveProcessControl())
        let lines = FdtdLineCollector()
        let once = Once()
        let invocation = FdtdInvocation(role: .run, argv: argv, cwd: cwd, environment: environment,
                                        controlPipe: controlPipe)
        let request = FdtdSpawnRequest(invocation: invocation, logPath: log, echo: nil, onLine: { line in
            lines.append(line)
            guard let prefix, let trigger, line.hasPrefix(prefix), once.first() else { return }
            DispatchQueue.global().async { trigger(stop) }
        })
        let started = Date()
        let outcome = FdtdSpawner.run(request, stop: stop)
        let text = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
        return Result(outcome: outcome, lines: lines.all, log: text, seconds: Date().timeIntervalSince(started))
    }

    /// The environment python3 keeps exactly: with LANG set no locale coercion adds LC_CTYPE, and CoreFoundation adds
    /// __CF_USER_TEXT_ENCODING only when it is missing.
    static let baseEnvironment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8",
                                  "__CF_USER_TEXT_ENCODING": "0x1F5:0x0:0x0"]
}

@Suite(.enabled(if: TestPython.path != nil, "needs a framework or Homebrew python3"))
struct SpawnTests {
    static let python = TestPython.path ?? "/usr/bin/false"

    /// pid, pgid, the environment, whether fd 0 is /dev/null and the descriptors open from 3 to 255.
    static let selfReport = """
        import json, os, stat
        s, d = os.fstat(0), os.stat('/dev/null')
        fds = []
        for fd in range(3, 256):
            try:
                st = os.fstat(fd)
                fds.append([fd, stat.S_ISFIFO(st.st_mode)])
            except OSError:
                pass
        print('SELF ' + json.dumps(dict(pid=os.getpid(), pgid=os.getpgrp(), env=dict(os.environ), fds=fds,
                                        devnull=stat.S_ISCHR(s.st_mode) and s.st_rdev == d.st_rdev)))
        """

    static func selfLine(_ result: LiveChild.Result) throws -> FdtdJSONValue {
        let line = try #require(result.lines.first { $0.hasPrefix("SELF ") }, "\(result.lines)")
        return try FdtdJSON.decode(FdtdJSONValue.self, from: Data(line.dropFirst(5).utf8))
    }

    @Test func ownGroupExactEnvironmentDevNullAndNoInheritedDescriptors() throws {
        let temp = try TempFolder("spawn-self")
        defer { temp.remove() }
        var environment = LiveChild.baseEnvironment
        environment["A"] = "1"
        environment["B"] = "two words = \"quoted\""
        let result = LiveChild.run([Self.python, "-B", "-c", Self.selfReport], cwd: temp.path,
                                   environment: environment, log: temp.file("tool.log"))
        #expect(result.outcome.exit == 0 && result.outcome.ran)
        let report = try Self.selfLine(result)
        let pid = try #require(report["pid"]?.double)
        #expect(report["pgid"]?.double == pid)
        #expect(result.outcome.processGroup.map(Double.init) == pid)
        let env = try #require(report["env"]?.object)
        #expect(env.mapValues { $0.string ?? "" } == environment)
        #expect(report["devnull"]?.bool == true)
        #expect(report["fds"]?.array?.isEmpty == true, "\(report["fds"] ?? .null)")
        // a launcher child gets the control pipe's read end on fd 3 and nothing else
        let piped = LiveChild.run([Self.python, "-B", "-c", Self.selfReport], cwd: temp.path,
                                  environment: environment, controlPipe: true, log: temp.file("tool2.log"))
        let fds = try #require(try Self.selfLine(piped)["fds"]?.array)
        #expect(fds == [.array([.number(3), .bool(true)])])
    }

    @Test func theMergedPipeKeepsTheOrderAndTheLogHasEveryByte() throws {
        let temp = try TempFolder("spawn-order")
        defer { temp.remove() }
        let program = """
            import sys
            for i in range(300):
                print(f'out {i}')
                print(f'err {i}', file=sys.stderr)
            sys.stdout.write('no newline at the end')
            """
        let result = LiveChild.run([Self.python, "-u", "-B", "-c", program], cwd: temp.path,
                                   environment: LiveChild.baseEnvironment, log: temp.file("tool.log"))
        #expect(result.outcome.exit == 0)
        let expected = (0..<300).flatMap { ["out \($0)", "err \($0)"] } + ["no newline at the end"]
        #expect(result.lines == expected)
        #expect(result.log == expected.joined(separator: "\n"))
    }

    @Test func closingTheWriteEndGivesEOFWhileAnotherChildRuns() throws {
        let temp = try TempFolder("spawn-eof")
        defer { temp.remove() }
        let stopA = FdtdStopController(clock: LiveClock(), control: LiveProcessControl())
        let stopB = FdtdStopController(clock: LiveClock(), control: LiveProcessControl())
        let readyA = DispatchSemaphore(value: 0)
        let readyB = DispatchSemaphore(value: 0)
        let doneA = DispatchSemaphore(value: 0)
        let results = Mutex<[String: LiveChild.Result]>([:])
        let python = Self.python
        let path = temp.path
        // A blocks on fd 3; B, started while A's write end is open, runs on (and inherits nothing)
        Thread {
            let a = LiveChild.run([python, "-u", "-B", "-c",
                                   "import os\nprint('A READY')\nprint('A GOT ' + repr(os.read(3, 100)))"],
                                  cwd: path, environment: LiveChild.baseEnvironment, controlPipe: true,
                                  log: path + "/a.log", stop: stopA, on: "A READY", trigger: { _ in readyA.signal() })
            results.withLock { $0["a"] = a }
            doneA.signal()
        }.start()
        #expect(readyA.wait(timeout: .now() + 20) == .success)
        let doneB = DispatchSemaphore(value: 0)
        Thread {
            let b = LiveChild.run([python, "-u", "-B", "-c", "import time\nprint('B READY')\ntime.sleep(30)"],
                                  cwd: path, environment: LiveChild.baseEnvironment, controlPipe: true,
                                  log: path + "/b.log", stop: stopB, on: "B READY", trigger: { _ in readyB.signal() })
            results.withLock { $0["b"] = b }
            doneB.signal()
        }.start()
        #expect(readyB.wait(timeout: .now() + 20) == .success)
        let closed = Date()
        stopA.closeControlPipe()
        #expect(doneA.wait(timeout: .now() + 10) == .success)
        #expect(Date().timeIntervalSince(closed) < 5)
        let a = try #require(results.withLock { $0["a"] })
        #expect(a.lines == ["A READY", "A GOT b''"])
        #expect(a.outcome.exit == 0)
        // B still runs; two signals end it (stop on its pipe, which it ignores, then SIGTERM to its group)
        #expect(results.withLock { $0["b"] } == nil)
        stopB.signalArrived(SIGINT)
        stopB.signalArrived(SIGINT)
        #expect(doneB.wait(timeout: .now() + 10) == .success)
        let b = try #require(results.withLock { $0["b"] })
        #expect(b.outcome.termSignal == SIGTERM)
        #expect(b.outcome.exit == 128 + SIGTERM)
        #expect(b.outcome.interrupted && !b.outcome.killed)
    }

    @Test func sigtermReachesTheWholeGroup() throws {
        let temp = try TempFolder("spawn-group")
        defer { temp.remove() }
        // the grandchild holds the pipe: the run ends early only if the group's SIGTERM reached it too
        let result = LiveChild.run(["/bin/sh", "-c", "sleep 30 & echo STARTED; wait"], cwd: temp.path,
                                   environment: ["PATH": "/usr/bin:/bin"], log: temp.file("tool.log"),
                                   on: "STARTED", trigger: { stop in stop.signalArrived(SIGTERM) })
        #expect(result.seconds < 10)
        #expect(result.outcome.termSignal == SIGTERM)
        #expect(result.outcome.interrupted)
    }

    @Test func aMissingProgramIsASpawnError() throws {
        let temp = try TempFolder("spawn-missing")
        defer { temp.remove() }
        let result = LiveChild.run([temp.file("no-such-tool")], cwd: temp.path, environment: [:],
                                   log: temp.file("tool.log"))
        #expect(!result.outcome.ran)
        #expect(result.outcome.spawnError != nil)
    }
}
