// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 ConcurrencyTests (S6, section 11): lsof's records, the found/none/unknown decision, the CLI's own
// descendants, and the policy (bench refuses, check warns).
import Foundation
import Testing
@testable import fdtdKit

@Suite struct ConcurrencyTests {
    /// lsof -F pcn output for one Python process holding a copy of libopenEMS outside every listed folder.
    static let copyHolder = "p5001\ncPython\nf12\nn/Users/tester/scratch/copy/libopenEMS.0.37.0.dylib\nftxt\nn/usr/lib/dyld\n"

    @Test func recordsIgnoreOtherFieldLetters() {
        let text = "p123\ncPython\nf3\na r\nn/x/libopenEMS.0.dylib\nl \np456\ncopenEMS\nftxt\nn/usr/lib/libz.dylib\n"
            + "pnot-a-pid\ncghost\nn/ghost/libopenEMS.dylib\n"
        let records = FdtdConcurrency.parseRecords(text)
        #expect(records == [FdtdLsofRecord(pid: 123, command: "Python", names: ["/x/libopenEMS.0.dylib"]),
                            FdtdLsofRecord(pid: 456, command: "openEMS", names: ["/usr/lib/libz.dylib"])])
        #expect(FdtdConcurrency.scanAKeeps(records[0]))
        #expect(!FdtdConcurrency.scanAKeeps(records[1]))
        #expect(FdtdConcurrency.scanBKeeps(records[1], files: ["/usr/lib/libz.dylib"]))
    }

    @Test func decision() {
        let kept = [FdtdLsofRecord(pid: 9, names: ["/a/libopenEMS.0.dylib"])]
        #expect(FdtdConcurrency.decide(exit: 1, records: kept, kept: kept) == .found)
        #expect(FdtdConcurrency.decide(exit: 1, records: [], kept: []) == .noneFound)
        #expect(FdtdConcurrency.decide(exit: 2, records: [], kept: []) == .unknown)
        #expect(FdtdConcurrency.decide(exit: nil, records: [], kept: []) == .unknown)
        // lsof exits 0 when it listed everything asked for and none of it was an openEMS library
        #expect(FdtdConcurrency.decide(exit: 0, records: [FdtdLsofRecord(pid: 3)], kept: []) == .noneFound)
    }

    @Test func descendantsAndCommands() {
        let tree = "    1     0\n 4242     1\n 4300  4242\n 4301  4300\n 5001     1\n"
        #expect(FdtdConcurrency.descendants(of: 4242, psOutput: tree) == [4242, 4300, 4301])
        #expect(FdtdConcurrency.commands(psOutput: " 5001 /opt/py/bin/python3 -B sim.py --x 1\n")
                == [5001: "/opt/py/bin/python3 -B sim.py --x 1"])
    }

    @Test func unknownRefusesBenchAndWarnsOnCheck() throws {
        let bench = FakeWorld()
        bench.system.update { $0.lsofA = FakeCapture(exit: 2, stderr: "lsof: WARNING") }
        let refused = bench.run(["bench", "patch", "--config", "stock@multithreaded:4", "--config",
                                 "cg29@multithreaded:4", "--dry-run"])
        #expect(refused.exit == 5)
        #expect(refused.status == "refused")
        #expect(refused.errorCodes == ["concurrency_unknown"])
        #expect(refused.issue("errors", "concurrency_unknown")?["hint"]?.string
                == "wait, add --quiet 60, or pass --allow-concurrent")
        #expect(refused.envelope["concurrent"]?["result"]?.string == "unknown")

        let check = FakeWorld()
        check.system.update { $0.lsofA = FakeCapture(exit: 2) }
        let warned = check.run(["check", "cg29", "--tag", "conc", "--lite", "--rfsim", FakeWorld.rfsim, "--dry-run"])
        #expect(warned.exit == 0)
        #expect(warned.warningCodes.contains("concurrency_unknown"))
    }

    /// Ctrl-C while lsof runs: the stopped scan has no exit status, which must not refuse (5) over the interruption.
    @Test func aStopDuringTheScansIsAnInterruptionNotARefusal() throws {
        let world = FakeWorld()
        world.system.update { $0.signalDuringLsof = SIGINT }
        let run = world.run(["bench", "patch", "--config", "stock@multithreaded:4", "--config",
                             "cg29@multithreaded:4", "--dry-run"])
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(run.status == "interrupted")
        #expect(!run.errorCodes.contains("concurrency_unknown"))
        #expect(run.errorCodes.contains("interrupted"))
        // the planned job is recorded as a stop kept it from starting
        let invocations = run.envelope["invocations"]?.array ?? []
        #expect(!invocations.isEmpty)
        #expect(invocations.allSatisfy { $0["ran"]?.bool == false && $0["interrupted"]?.bool == true })

        // check only warns on an unknown scan; after a stop it says nothing of the scans either
        let check = FakeWorld()
        check.system.update { $0.signalDuringLsof = SIGINT }
        let stopped = check.run(["check", "cg29", "--tag", "stop", "--lite", "--rfsim", FakeWorld.rfsim, "--dry-run"])
        #expect(stopped.exit == 130, "\(stopped.stderr)")
        #expect(!stopped.warningCodes.contains("concurrency_unknown"))
        #expect(stopped.errorCodes.contains("interrupted"))
        #expect(stopped.envelope["runFolder"] == .null)
    }

    /// Ctrl-C before the gate, every later child killed as it starts: the gate starts none, neither a second probe for
    /// the installed library (the protected-folder check's one was killed) nor a scan.
    @Test func aStopBeforeTheGateStartsNoChild() throws {
        let world = FakeWorld()
        world.system.update {
            $0.signalAfterSnippet = (FdtdSnippets.probe, SIGINT)
            $0.killAfterStop = true
        }
        let run = world.run(["bench", "patch", "--config", "stock@multithreaded:4", "--config",
                             "cg29@multithreaded:4", "--dry-run"])
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(run.errorCodes.contains("interrupted"))
        #expect(!run.errorCodes.contains("concurrency_unknown"))
        let captures = world.system.captures
        // the snapshot's probe, then the protected-folder check's probe of the installed library
        let probes = captures.filter { $0.argv.contains(FdtdSnippets.probe) }
        let dyld = probes.map { $0.environment["DYLD_LIBRARY_PATH"] }
        #expect(dyld == [FakeWorld.snaps + "/stock", FdtdDiscovery.noDyld],
                "\(captures.map { ($0.argv.first ?? "", $0.environment["DYLD_LIBRARY_PATH"] ?? "-") })")
        #expect(!captures.contains { $0.argv.first == "/usr/sbin/lsof" })
    }

    /// A process scan A found still refuses bench when Ctrl-C ends scan B (5 outranks 130); check warns and ends as
    /// interrupted.
    @Test func aProcessFoundBeforeAStopStillCounts() throws {
        func world() -> FakeWorld {
            let world = FakeWorld()
            world.system.update {
                $0.lsofA = FakeCapture(exit: 0, stdout: Self.copyHolder)
                $0.psTree = FakeCapture(stdout: " 4242 1\n 5001 1\n")
                $0.psCommands = FakeCapture(stdout: " 5001 /opt/py/bin/python3 -B board.py\n")
                $0.signalDuringLsofB = SIGINT
            }
            return world
        }
        let bench = world().run(["bench", "patch", "--config", "cg29@multithreaded:4", "--config",
                                 "cg29@multithreaded:8", "--dry-run"])
        #expect(bench.exit == 5, "\(bench.stderr)")
        #expect(bench.errorCodes.contains("simulation_running"))
        #expect(bench.envelope["concurrent"]?["result"]?.string == "found")

        let check = world().run(["check", "cg29", "--tag", "stop", "--lite", "--rfsim", FakeWorld.rfsim, "--dry-run"])
        #expect(check.exit == 130, "\(check.stderr)")
        #expect(check.warningCodes.contains("simulation_running"))
        #expect(check.errorCodes.contains("interrupted"))
    }

    @Test func scanAFindsACopyOutsideEveryListedPath() throws {
        let world = FakeWorld()
        world.system.update {
            $0.lsofA = FakeCapture(exit: 0, stdout: Self.copyHolder)
            $0.psTree = FakeCapture(stdout: " 4242 1\n 5001 1\n")
            $0.psCommands = FakeCapture(stdout: " 5001 /opt/py/bin/python3 -B board.py\n")
        }
        let run = world.run(["bench", "patch", "--config", "cg29@multithreaded:4", "--config",
                             "cg29@multithreaded:8", "--dry-run"])
        #expect(run.exit == 5)
        #expect(run.errorCodes == ["simulation_running"])
        let process = try #require(run.envelope["concurrent"]?["processes"]?.array?.first)
        #expect(process["pid"]?.double == 5001)
        #expect(process["command"]?.string == "/opt/py/bin/python3 -B board.py")
        #expect(process["libraries"]?.array?.first?.string == "/Users/tester/scratch/copy/libopenEMS.0.37.0.dylib")
        // scan B asked for the libraries the command uses, by their real paths
        let scanB = try #require(world.system.captures.first { $0.argv.first == "/usr/sbin/lsof" && $0.argv.contains("--") })
        #expect(scanB.argv.contains(FakeWorld.snaps + "/cg29/libopenEMS.0.dylib"))
        #expect(scanB.argv.contains(FakeWorld.installed + "/libopenEMS.0.37.0.dylib"))

        let allowed = FakeWorld()
        allowed.system.update { $0.lsofA = FakeCapture(exit: 0, stdout: Self.copyHolder) }
        let warned = allowed.run(["bench", "patch", "--config", "cg29@multithreaded:4", "--config",
                                  "cg29@multithreaded:8", "--dry-run", "--allow-concurrent"])
        #expect(warned.exit == 0)
        #expect(warned.warningCodes.contains("simulation_running"))
    }

    @Test func theCLIsOwnDescendantsAreDropped() {
        let world = FakeWorld()
        let own = "p4242\ncemskit\nn/Users/tester/opt/openEMS/lib/libopenEMS.0.37.0.dylib\n"
            + "p4300\ncPython\nn/Users/tester/opt/openEMS/lib/libopenEMS.0.37.0.dylib\n"
            + "p4301\ncopenEMS\nn/Users/tester/opt/openEMS/lib/libopenEMS.0.37.0.dylib\n"
        world.system.update {
            $0.lsofA = FakeCapture(exit: 0, stdout: own)
            $0.psTree = FakeCapture(stdout: " 4242 1\n 4300 4242\n 4301 4300\n 5001 1\n")
        }
        let run = world.run(["bench", "patch", "--config", "cg29@multithreaded:4", "--config",
                             "cg29@multithreaded:8", "--dry-run"])
        #expect(run.exit == 0)
        #expect(run.envelope["concurrent"]?["result"]?.string == "none")
        #expect(run.envelope["concurrent"]?["processes"]?.array?.isEmpty == true)
        // nothing was held by others, so no ps -o command= ran
        #expect(!world.system.captures.contains { $0.argv.first == "/bin/ps" && $0.argv.contains("-p") })
    }
}
