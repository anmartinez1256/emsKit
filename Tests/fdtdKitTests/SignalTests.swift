// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 SignalTests (section 11, S6): the stop sequence on a FakeClock and FakeProcessControl (stop on the control
// pipe, SIGTERM after 60 s or at a second signal, SIGKILL 10 s later), probes, attach/detach, the CLI's 130 with the
// killed warning and the restored handlers, and the live installation's sigaction bookkeeping.
import Foundation
import Synchronization
import Testing
@testable import fdtdKit

@Suite struct SignalTests {
    static let group: Int32 = 7001
    static let fd: Int32 = 90

    struct Rig {
        let clock = FakeClock(start: FakeWorld.start)
        let control = FakeProcessControl()
        let stop: FdtdStopController

        init(attached: Bool = true, controlFd: Int32? = SignalTests.fd) {
            stop = FdtdStopController(clock: clock, control: control)
            control.setAlive(SignalTests.group, true)
            if attached { stop.attach(processGroup: SignalTests.group, controlFd: controlFd) }
        }

        var signals: [Int32] { control.sent.filter { $0.group == SignalTests.group }.map(\.signo) }
    }

    @Test func firstSignalStopsThenTermAfter60ThenKillAfter10() {
        let rig = Rig()
        rig.stop.signalArrived(SIGINT)
        #expect(rig.stop.stopRequested)
        #expect(rig.control.writes == [ControlWrite(fd: Self.fd, text: "stop\n")])
        #expect(rig.signals.isEmpty)
        rig.clock.advance(59.9)
        #expect(rig.signals.isEmpty)
        rig.clock.advance(0.1)
        #expect(rig.signals == [SIGTERM])
        rig.clock.advance(9.9)
        #expect(rig.signals == [SIGTERM])
        #expect(!rig.stop.killed)
        rig.clock.advance(0.1)
        #expect(rig.signals == [SIGTERM, SIGKILL])
        #expect(rig.stop.killed)
        rig.clock.advance(100)
        #expect(rig.signals == [SIGTERM, SIGKILL])
        #expect(rig.control.writes.count == 1)
    }

    @Test func aChildThatObeysTheStopGetsNoSignal() {
        let rig = Rig()
        rig.stop.signalArrived(SIGTERM)
        rig.clock.advance(30)
        rig.control.setAlive(Self.group, false)
        rig.clock.advance(100)
        #expect(rig.signals.isEmpty)
        #expect(!rig.stop.killed)
        // the child leaves after SIGTERM: no SIGKILL
        let second = Rig()
        second.stop.signalArrived(SIGINT)
        second.clock.advance(60)
        #expect(second.signals == [SIGTERM])
        second.control.setAlive(Self.group, false)
        second.clock.advance(10)
        #expect(second.signals == [SIGTERM])
        #expect(!second.stop.killed)
    }

    @Test func secondSignalSendsTermAtOnceAndOnlyOnce() {
        let rig = Rig()
        rig.stop.signalArrived(SIGINT)
        rig.clock.advance(5)
        rig.stop.signalArrived(SIGHUP)
        #expect(rig.signals == [SIGTERM])
        rig.stop.signalArrived(SIGINT)
        #expect(rig.signals == [SIGTERM])
        // the 60 s timer was cancelled by the second signal; the kill timer runs 10 s from it
        rig.clock.advance(9.9)
        #expect(rig.signals == [SIGTERM])
        rig.clock.advance(0.1)
        #expect(rig.signals == [SIGTERM, SIGKILL])
        rig.clock.advance(120)
        #expect(rig.signals == [SIGTERM, SIGKILL])
        #expect(rig.clock.liveTimers == 0)
    }

    @Test func aDirectChildWithoutControlPipeGetsTermAtOnce() {
        let rig = Rig(controlFd: nil)
        rig.stop.signalArrived(SIGINT)
        #expect(rig.control.writes.isEmpty)
        #expect(rig.signals == [SIGTERM])
        rig.clock.advance(10)
        #expect(rig.signals == [SIGTERM, SIGKILL])
        #expect(rig.stop.killed)
    }

    @Test func probesGetTermAtEverySignal() {
        let rig = Rig(attached: false)
        rig.stop.attachProbe(501)
        rig.stop.signalArrived(SIGINT)
        #expect(rig.control.sent == [SentSignal(group: 501, signo: SIGTERM)])
        // a probe started after the stop request is stopped when it starts
        rig.stop.attachProbe(502)
        #expect(rig.control.sent.last == SentSignal(group: 502, signo: SIGTERM))
        rig.stop.detachProbe(501)
        rig.stop.signalArrived(SIGINT)
        #expect(rig.control.sent.filter { $0.group == 501 }.count == 1)
        #expect(rig.control.sent.filter { $0.group == 502 }.count == 2)
    }

    @Test func aStopBetweenTwoChildrenReachesTheNextOneAtOnce() {
        let rig = Rig(attached: false)
        rig.stop.signalArrived(SIGINT)
        #expect(rig.control.writes.isEmpty && rig.control.sent.isEmpty)
        rig.stop.attach(processGroup: Self.group, controlFd: Self.fd)
        #expect(rig.control.writes == [ControlWrite(fd: Self.fd, text: "stop\n")])
        rig.clock.advance(60)
        #expect(rig.signals == [SIGTERM])
        // after two signals with nothing attached, the next child gets SIGTERM directly
        let twice = Rig(attached: false)
        twice.stop.signalArrived(SIGINT)
        twice.stop.signalArrived(SIGINT)
        twice.stop.attach(processGroup: Self.group, controlFd: Self.fd)
        #expect(twice.control.writes.isEmpty)
        #expect(twice.signals == [SIGTERM])
    }

    @Test func detachCancelsTheTimersAndClosesTheControlFd() {
        let rig = Rig()
        rig.stop.signalArrived(SIGINT)
        rig.stop.detach(processGroup: Self.group)
        #expect(rig.control.closed == [Self.fd])
        #expect(rig.clock.liveTimers == 0)
        rig.clock.advance(200)
        #expect(rig.signals.isEmpty)
        // a detach of another group changes nothing; a new attach closes the old descriptor first
        let other = Rig()
        other.stop.detach(processGroup: 9999)
        #expect(other.control.closed.isEmpty)
        other.stop.attach(processGroup: 7002, controlFd: 91)
        #expect(other.control.closed == [Self.fd])
        other.stop.closeControlPipe()
        #expect(other.control.closed == [Self.fd, 91])
        // a stop on a closed pipe is not written
        other.stop.signalArrived(SIGINT)
        #expect(other.control.writes.isEmpty)
    }

    // MARK: - Through the CLI

    static func scriptWorld() -> FakeWorld {
        let world = FakeWorld()
        world.system.addFile("/work/board.py", "import openEMS\n")
        return world
    }

    /// Two signals while the launcher runs, the group still alive 10 s after SIGTERM: 130, interrupted, killed.
    @Test func twoSignalsAndAChildThatStaysGiveKilledAnd130() throws {
        let world = Self.scriptWorld()
        let control = world.system.control
        let signals = world.signals
        let clock = world.clock
        var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0"])
        tool.exit = 128 + SIGKILL
        tool.during = { _ in
            control.setAlive(SignalTests.group, true)
            signals.trigger(SIGINT)
            signals.trigger(SIGINT)
            clock.advance(10)
        }
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["run", "/work/board.py", "--lib", "cg29"])
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(run.status == "interrupted")
        #expect(run.errorCodes.contains("interrupted"))
        #expect(run.warningCodes.contains("killed"))
        #expect(control.writes == [ControlWrite(fd: Self.fd, text: "stop\n")])
        #expect(control.sent.filter { $0.group == Self.group }.map(\.signo) == [SIGTERM, SIGKILL])
        #expect(control.closed.contains(Self.fd))
        #expect(signals.installs == 1 && signals.restores == 1 && !signals.installed)
        // nothing is deleted after an interruption
        #expect(run.envelope["keptRuns"]?.bool == true)
        let invocation = try #require(run.envelope["invocations"]?.array?.first { $0["role"]?.string == "run" })
        #expect(invocation["interrupted"]?.bool == true)
        #expect(invocation["exit"]?.double == Double(128 + SIGKILL))
    }

    /// One signal; the launcher aborts the simulation and reports: 130 without killed and without any signal sent.
    @Test func oneSignalAndAnObedientLauncherGive130() {
        let world = Self.scriptWorld()
        let control = world.system.control
        let signals = world.signals
        var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0", "FDTDKIT_CALL_END 0"])
        tool.exit = 130
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 130,
                                         calls: [FakeToolRun.call(index: 0, load: .null)], interrupted: true)
        tool.during = { _ in
            control.setAlive(SignalTests.group, true)
            signals.trigger(SIGTERM)
            control.setAlive(SignalTests.group, false)
        }
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["run", "/work/board.py", "--lib", "cg29"])
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(run.errorCodes.contains("interrupted"))
        #expect(!run.warningCodes.contains("killed"))
        #expect(control.sent.isEmpty)
        #expect(control.writes == [ControlWrite(fd: Self.fd, text: "stop\n")])
        #expect(signals.installs == 1 && signals.restores == 1)
        #expect(world.clock.liveTimers == 0)
    }

    @Test func usageErrorsInstallNoHandler() {
        let world = FakeWorld()
        _ = world.run(["bench", "--frob"])
        // with --output too: a line that did not parse writes no file and probes nothing
        _ = world.run(["bench", "patch", "--frob", "--output", "/work/e.json"])
        #expect(world.signals.installs == 0 && world.system.captures.isEmpty)
        // info runs probes and scans, so it handles signals like every other command
        _ = world.run(["info"])
        #expect(world.signals.installs == 1 && world.signals.restores == 1)
        // a refused or failed command restores what it installed
        let refused = FakeWorld()
        _ = refused.run(["bench", "patch", "--config", "nosuch@multithreaded:4", "--config", "cg29@multithreaded:4"])
        #expect(refused.signals.installs == refused.signals.restores)
    }

    // MARK: - The live installation

    static func handlerBits(_ signo: Int32) -> (Int, Int32) {
        var action = sigaction()
        sigaction(signo, nil, &action)
        return (unsafeBitCast(action.__sigaction_u.__sa_handler, to: Int.self), action.sa_flags)
    }

    /// SIG_IGN while installed (kqueue still delivers the signal), the earlier disposition after restore().
    @Test func liveInstallationIgnoresDeliversAndRestores() {
        let before = Self.handlerBits(SIGHUP)
        let seen = Mutex<[Int32]>([])
        let arrived = DispatchSemaphore(value: 0)
        let installation = LiveSignalSource().install { signo in
            seen.withLock { $0.append(signo) }
            arrived.signal()
        }
        let ignored = unsafeBitCast(SIG_IGN, to: Int.self)
        for signo in LiveSignalSource.signals { #expect(Self.handlerBits(signo).0 == ignored, "\(signo)") }
        kill(getpid(), SIGHUP)
        #expect(arrived.wait(timeout: .now() + 5) == .success)
        #expect(seen.withLock { $0 } == [SIGHUP])
        installation.restore()
        let after = Self.handlerBits(SIGHUP)
        #expect(after.0 == before.0 && after.1 == before.1)
        // a second restore does nothing
        installation.restore()
        #expect(Self.handlerBits(SIGHUP).0 == before.0)
    }

    /// Two signals that arrive while the handler runs reach the source as one event with data 2; the handler is
    /// called once per signal, so a quick second signal still escalates (spec 11).
    @Test func liveInstallationCountsMergedSignals() {
        let calls = Mutex(0)
        let entered = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        // SIGWINCH is ignored by default, so nothing else in the test process reacts to it
        let installation = LiveSignalInstallation(signals: [SIGWINCH], leftIgnored: []) { _ in
            let first = calls.withLock { count in
                count += 1
                return count == 1
            }
            if first {
                entered.signal()
                _ = gate.wait(timeout: .now() + 5)
            }
        }
        defer { installation.restore() }
        kill(getpid(), SIGWINCH)
        #expect(entered.wait(timeout: .now() + 5) == .success)
        // both arrive while the first call holds the source's queue
        kill(getpid(), SIGWINCH)
        kill(getpid(), SIGWINCH)
        Thread.sleep(forTimeInterval: 0.2)
        gate.signal()
        let deadline = Date().addingTimeInterval(5)
        while calls.withLock({ $0 }) < 3 && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        Thread.sleep(forTimeInterval: 0.1)
        #expect(calls.withLock { $0 } == 3)
    }
}
