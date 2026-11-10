// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 10.2 and 9 around the named outputs: --output that is a folder or empty, finish()'s order (the --output backup
// and write before the cleanup, nothing renamed without --overwrite, signals handled until the envelope is out), a
// line that did not parse (no file), a bad --tag beside a usage error, e2e's --out-dir (renamed last, never the run
// folder's place), an inherited SIG_IGN, and what a capture's child leaves behind in its group.
import Foundation
import Synchronization
import Testing
@testable import fdtdKit

@Suite struct OutputTests {
    static let stamp = ".previous-" + FakeWorld.stamp

    // MARK: --output is a FILE

    /// A folder as --output is refused whatever --overwrite says (finish() would rename the whole folder away), in a
    /// dry run too; so is an empty value, which would stand for the cwd.
    @Test func outputThatIsAFolderOrEmptyIsRefused() {
        let cases: [[String]] = [["info", "--output", "results", "--overwrite"], ["info", "--output", "results"],
                                 ["info", "--output", ".", "--overwrite"], ["info", "--output", "", "--overwrite"],
                                 ["diamond-check", "--output", "results", "--overwrite", "cg29", "--dry-run"]]
        for arguments in cases {
            let world = FakeWorld()
            world.system.addFile(FakeWorld.repo + "/results/table.txt", "kept\n")
            let run = world.run(arguments)
            #expect(run.exit == 64, "\(arguments) \(run.stderr)")
            #expect(run.errorCodes == ["usage"], "\(arguments)")
            #expect(run.issue("errors", "usage")?["field"]?.string == "--output", "\(arguments)")
            let message = run.issue("errors", "usage")?["message"]?.string ?? ""
            #expect(message.contains(arguments[2].isEmpty ? "the value is empty" : "is a folder"), "\(message)")
            #expect(world.system.isDirectory(FakeWorld.repo + "/results"), "\(arguments)")
            #expect(world.system.fileExists(FakeWorld.repo + "/results/table.txt"), "\(arguments)")
            #expect(!world.system.fileExists(FakeWorld.repo + "/results" + Self.stamp), "\(arguments)")
            #expect(!world.system.fileExists(FakeWorld.repo + Self.stamp), "\(arguments)")
            // the envelope went to stdout
            #expect(run.stdout.contains("\"usage\""), "\(arguments)")
        }
    }

    // MARK: finish()

    /// A passing `run --output /work/out/run.json` whose tool leaves RUN/runs/x.txt; `during` plays while it runs.
    static func passingRun(_ extra: [String] = [], prepare: (FakeWorld) -> Void = { _ in },
                           during: @escaping @Sendable (FakeSystem) -> Void = { _ in }) -> (FakeWorld, CLIRun) {
        let world = PlanTests.world()
        world.system.addDirectory("/work/out")
        prepare(world)
        let system = world.system
        var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0", "FDTDKIT_CALL_END 0"], files: ["runs/x.txt": "bulky\n"])
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: .null)],
                                         libraries: FdtdLibraries.fileNames.map { FakeWorld.snaps + "/cg29/" + $0 })
        tool.during = { _ in during(system) }
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["run", "/work/board.py", "--lib", "cg29", "--output", "/work/out/run.json"] + extra)
        return (world, run)
    }

    static let bulky = FakeWorld.runFolder("run") + "/runs/x.txt"

    static func fileEnvelope(_ world: FakeWorld) -> FdtdJSONValue? {
        world.system.readFile("/work/out/run.json").flatMap { try? FdtdJSON.decode(FdtdJSONValue.self, from: $0) }
    }

    /// The ordinary case: the file holds the final envelope (after the cleanup), stdout stays empty.
    @Test func outputHoldsTheEnvelopeAfterTheCleanup() throws {
        let (world, run) = Self.passingRun()
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.stdout.isEmpty)
        #expect(!world.system.fileExists(Self.bulky))
        let written = try #require(Self.fileEnvelope(world))
        #expect(written == run.envelope)
        #expect(written["keptRuns"]?.bool == false)
        #expect(written["status"]?.string == "ok")
    }

    /// --output is written before the cleanup: when the write fails, the run is an error and its data stay.
    @Test func aFailedOutputWriteDeletesNothing() {
        let (world, run) = Self.passingRun(during: { try? $0.removeItem("/work/out") })
        #expect(run.exit == 4, "\(run.stderr)")
        #expect(run.errorCodes == ["tool_failed"])
        #expect(run.envelope["keptRuns"]?.bool == true)
        #expect(world.system.fileExists(Self.bulky))
        #expect(run.stdout.contains("\"tool_failed\""))
    }

    /// A file that appeared at --output during the run is not renamed away without --overwrite: it stays as it is,
    /// the envelope goes to stdout and the run folder is kept. The tools have run, so this is an error of the run
    /// (4), never `refused`.
    @Test func anOutputThatAppearedDuringTheRunIsLeftAlone() throws {
        let appear: @Sendable (FakeSystem) -> Void = { $0.addFile("/work/out/run.json", "theirs\n") }
        let (world, run) = Self.passingRun(during: appear)
        #expect(run.exit == 4, "\(run.stderr)")
        #expect(run.errorCodes == ["tool_failed"])
        #expect(run.status == "error")
        #expect(run.issue("errors", "tool_failed")?["field"]?.string == "--output")
        #expect(world.system.readFile("/work/out/run.json") == Data("theirs\n".utf8))
        #expect(!world.system.fileExists("/work/out/run.json" + Self.stamp))
        #expect(!run.warningCodes.contains("output_backed_up"))
        #expect(run.stdout.contains("\"tool_failed\""))
        #expect(run.envelope["keptRuns"]?.bool == true)
        #expect(world.system.fileExists(Self.bulky))
        // with --overwrite the old file is kept next to the new one, as at plan time
        let (kept, replaced) = Self.passingRun(["--overwrite"], during: appear)
        #expect(replaced.exit == 0, "\(replaced.stderr)")
        #expect(kept.system.readFile("/work/out/run.json" + Self.stamp) == Data("theirs\n".utf8))
        #expect(try #require(Self.fileEnvelope(kept))["status"]?.string == "ok")
        // a folder that appeared there is never renamed, --overwrite or not
        let (folder, refused) = Self.passingRun(["--overwrite"], during: { $0.addFile("/work/out/run.json/x", "x\n") })
        #expect(refused.exit == 4 && refused.errorCodes == ["tool_failed"], "\(refused.stderr)")
        #expect(folder.system.fileExists("/work/out/run.json/x"))
        #expect(!folder.system.fileExists("/work/out/run.json" + Self.stamp))
    }

    /// The same beside a failed script: the status stays one of a run that ran, with both errors listed.
    @Test func anAppearedOutputNeverTurnsAFailedRunIntoARefusal() {
        let world = PlanTests.world()
        world.system.addDirectory("/work/out")
        let system = world.system
        var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0", "FDTDKIT_CALL_END 0"])
        tool.exit = 1
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 1,
                                         calls: [FakeToolRun.call(index: 0, load: .null)],
                                         libraries: FdtdLibraries.fileNames.map { FakeWorld.snaps + "/cg29/" + $0 })
        tool.during = { _ in system.addFile("/work/out/run.json", "theirs\n") }
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["run", "/work/board.py", "--lib", "cg29", "--output", "/work/out/run.json"])
        #expect(run.errorCodes == ["script_failed", "tool_failed"], "\(run.stderr)")
        #expect(run.exit == 4 && run.status == "error")
        #expect(!run.errorCodes.contains("would_overwrite"))
    }

    /// The old --output could not be moved away: it is never written over. The envelope goes to stdout, the run is
    /// an error and its data stay.
    @Test func aFailedBackupNeverWritesOverTheOldOutput() {
        let (world, run) = Self.passingRun(["--overwrite"], prepare: { world in
            world.system.addFile("/work/out/run.json", "old\n")
            world.system.update { $0.failMoves = ["/work/out/run.json"] }
        })
        #expect(run.exit == 4, "\(run.stderr)")
        #expect(run.errorCodes == ["tool_failed"])
        #expect(world.system.readFile("/work/out/run.json") == Data("old\n".utf8))
        #expect(!world.system.fileExists("/work/out/run.json" + Self.stamp))
        #expect(!run.warningCodes.contains("output_backed_up"))
        #expect(run.stdout.contains("\"tool_failed\""))
        #expect(run.envelope["keptRuns"]?.bool == true)
        #expect(world.system.fileExists(Self.bulky))
    }

    /// --output is written once, before the cleanup, and already says keptRuns false: no second write can fail
    /// after the data are gone.
    @Test func outputIsWrittenOnceBeforeTheCleanup() throws {
        let (world, run) = Self.passingRun(prepare: { world in
            world.system.update { $0.failWrites = ("/work/out/run.json", 1) }
        })
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.stdout.isEmpty)
        #expect(!world.system.fileExists(Self.bulky))
        #expect(try #require(Self.fileEnvelope(world)) == run.envelope)
        #expect(run.envelope["keptRuns"]?.bool == false)
    }

    /// A cleanup that fails keeps the data, so the file is written again with keptRuns true; when that write fails
    /// too, the envelope goes to stdout with the error.
    @Test func aFailedCleanupCorrectsTheOutput() throws {
        let runs = FakeWorld.runFolder("run") + "/runs"
        let (world, run) = Self.passingRun(prepare: { world in world.system.update { $0.failRemoves = [runs] } })
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.stdout.isEmpty)
        #expect(world.system.fileExists(Self.bulky))
        #expect(try #require(Self.fileEnvelope(world)) == run.envelope)
        #expect(run.envelope["keptRuns"]?.bool == true)
        // the same without --output
        let plain = PlanTests.world()
        plain.system.update { $0.failRemoves = [runs] }
        var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0", "FDTDKIT_CALL_END 0"], files: ["runs/x.txt": "bulky\n"])
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: .null)],
                                         libraries: FdtdLibraries.fileNames.map { FakeWorld.snaps + "/cg29/" + $0 })
        let bare = FailingVerdictTests.run(tool, ["run", "/work/board.py", "--lib", "cg29"], world: plain)
        #expect(bare.exit == 0 && bare.envelope["keptRuns"]?.bool == true, "\(bare.stderr)")
        let (stale, failed) = Self.passingRun(prepare: { world in
            world.system.update {
                $0.failRemoves = [runs]
                $0.failWrites = ("/work/out/run.json", 1)
            }
        })
        #expect(failed.exit == 4, "\(failed.stderr)")
        #expect(failed.errorCodes == ["tool_failed"])
        #expect(failed.stdout.contains("\"tool_failed\""))
        #expect(failed.envelope["keptRuns"]?.bool == true)
        #expect(stale.system.fileExists(Self.bulky))
        let message = failed.issue("errors", "tool_failed")?["message"]?.string ?? ""
        #expect(message.contains("still says keptRuns false"), "\(message)")
        #expect(try #require(Self.fileEnvelope(stale))["keptRuns"]?.bool == false)
    }

    /// The signal handling stays installed until finish() has written the envelope: with the default action back, a
    /// signal during the cleanup or the write would end the CLI without one.
    @Test func signalsAreHandledUntilTheEnvelopeIsOut() {
        let world = FakeWorld()
        let signals = world.signals
        let installedAtWrite = Mutex<[Bool]>([])
        let stdout = FdtdSink { _ in installedAtWrite.withLock { $0.append(signals.installed) } }
        let context = FdtdContext(environment: world.environment, cwd: world.cwd, pid: FakeWorld.pid,
                                  executablePath: world.executablePath, timeZone: TimeZone(identifier: "UTC")!,
                                  clock: world.clock, stdout: stdout, stderr: TextCollector().sink, signals: signals,
                                  system: world.system)
        let (exit, _) = FdtdCLI.run(arguments: ["diamond-check", "cg29", "--dry-run"], context: context)
        #expect(exit == 0)
        #expect(installedAtWrite.withLock { $0 } == [true])
        #expect(signals.installs == 1 && signals.restores == 1 && !signals.installed)
    }

    /// finish() has no child to stop: one signal there is only noted, a second one ends the CLI (the live source
    /// re-raises it with the default action), so a write that blocks can be left. Signals before finish() are the
    /// stop controller's and never count.
    @Test func aSecondSignalDuringFinishGivesUp() {
        func run(_ atWrite: [Int32], during: [Int32] = []) -> [Int32] {
            let world = PlanTests.world()
            let signals = world.signals
            var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0", "FDTDKIT_CALL_END 0"])
            tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                             calls: [FakeToolRun.call(index: 0, load: .null)])
            tool.during = { _ in for signo in during { signals.trigger(signo) } }
            world.system.update { $0.spawn = tool.handler(world.system) }
            let stdout = FdtdSink { _ in for signo in atWrite { signals.trigger(signo) } }
            let context = FdtdContext(environment: world.environment, cwd: world.cwd, pid: FakeWorld.pid,
                                      executablePath: world.executablePath, timeZone: TimeZone(identifier: "UTC")!,
                                      clock: world.clock, stdout: stdout, stderr: TextCollector().sink,
                                      signals: signals, system: world.system)
            _ = FdtdCLI.run(arguments: ["run", "/work/board.py", "--lib", "cg29"], context: context)
            return signals.gaveUp
        }
        #expect(run([]) == [])
        #expect(run([SIGINT]) == [])
        #expect(run([SIGINT, SIGTERM]) == [SIGTERM])
        #expect(run([SIGINT, SIGINT, SIGINT]) == [SIGINT, SIGINT])
        // two signals during the run escalate there; the first one in finish() is still only noted
        #expect(run([], during: [SIGINT, SIGINT]) == [])
        #expect(run([SIGINT], during: [SIGINT, SIGINT]) == [])
        // the guard alone: nothing counts before begin()
        let guarded = FdtdFinishGuard()
        let source = FakeSignalSource()
        guarded.installation = source.install { _ in }
        guarded.signalArrived(SIGINT)
        guarded.signalArrived(SIGINT)
        #expect(source.gaveUp.isEmpty)
        guarded.begin()
        guarded.signalArrived(SIGHUP)
        guarded.signalArrived(SIGHUP)
        #expect(source.gaveUp == [SIGHUP])
    }

    // MARK: Usage errors

    /// A line that did not parse writes no file: the envelope goes to stdout and a stderr line says that --output
    /// is not written. Nothing is probed, and no signal handling is installed (UnparsedLineTests has every command).
    @Test func aUsageErrorWritesNoFile() throws {
        let world = FakeWorld()
        world.system.addDirectory("/work/out")
        world.system.addFile("/work/out/old.json", "old\n")
        let before = world.system.allPaths
        for tail in [["--output", "/work/out/e.json"], ["--output", "/work/out/old.json", "--overwrite"],
                     ["--dry-run", "--output", "/work/out/e.json"], ["--output=/work/out/e.json"],
                     ["--output", "/work/out/a.json", "--output", "/work/out/b.json"], ["--output"]] {
            let run = world.run(["bench", "patch", "--frob"] + tail)
            #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(tail): \(run.stderr)")
            #expect(run.warningCodes.isEmpty, "\(tail)")
            #expect(try FdtdJSON.decode(FdtdJSONValue.self, from: Data(run.stdout.utf8)) == run.envelope, "\(tail)")
            #expect(run.stderr.contains("emskit fdtd: --output is not written: the line was not understood"), "\(tail)")
            // nothing of the line is read back: not --dry-run either
            #expect(run.envelope["dryRun"]?.bool == false, "\(tail)")
        }
        #expect(world.system.allPaths == before && world.system.contents("/work/out/old.json") == "old\n")
        #expect(world.signals.installs == 0 && world.system.captures.isEmpty && world.system.spawned.isEmpty)
        // without --output on the line there is no such stderr line; after run's `--` the tokens are the script's
        for line in [["bench", "patch", "--frob"], ["run", "/work/board.py", "--frob", "--", "--output", "/work/x"]] {
            let plain = world.run(line)
            #expect(plain.exit == 64 && !plain.stderr.contains("is not written"), "\(line): \(plain.stderr)")
        }
        #expect(FdtdOptions.namesOutput(.info, ["--frob", "--", "--output", "/o"]))
        #expect(!FdtdOptions.namesOutput(.run, ["--frob", "--", "--output", "/o"]))
        #expect(!FdtdOptions.namesOutput(.info, ["--outputs", "/o", "--lib", "output"]))
        // a parsed line with the same --output writes it, and one whose usage rule is found after parsing too
        let parsed = world.run(["bench", "patch", "--config", "multithreaded:4", "--dry-run", "--output",
                                "/work/out/e.json"])
        #expect(parsed.exit == 0 && world.system.readFile("/work/out/e.json") == parsed.data, "\(parsed.stderr)")
        let late = world.run(["bench", "notch", "--config", "multithreaded:4", "--knob", "bogus", "--dry-run",
                              "--output", "/work/out/late.json"])
        #expect(late.exit == 64 && world.system.readFile("/work/out/late.json") == late.data, "\(late.stderr)")
    }

    /// 64 outranks 2 (spec 9): a usage error on the line is reported, not the bad --tag beside it.
    @Test func aUsageErrorOutranksABadTag() {
        let cases: [[String]] = [["bench", "patch", "--config", "cg29@multithreaded:4", "--tag", "a b", "--exact"],
                                 ["check", "cg29", "--tag", "a/b", "--lite", "--quiet-max", "5"],
                                 ["validate", "--tag", "a/b", "--case", "nosuch"],
                                 // the --knob rules are found after the options are parsed
                                 ["bench", "notch", "--config", "multithreaded:4", "--knob", "bogus", "--tag", "-x",
                                  "--dry-run"],
                                 ["bench", "notch", "--config", "multithreaded:4", "--knob", "OPENEMS_FUSED=0",
                                  "--knob", "OPENEMS_FUSED=1", "--tag", "-x"],
                                 ["bench", "notch", "--config", "multithreaded:4#OPENEMS_FUSED=0", "--knob",
                                  "OPENEMS_FUSED=1", "--tag", "a b"],
                                 ["validate", "--tag", "-x", "--knob", "bogus"]]
        for arguments in cases {
            let run = FakeWorld().run(arguments)
            #expect(run.exit == 64, "\(arguments)")
            #expect(run.errorCodes == ["usage"], "\(arguments)")
        }
        // a bad tag on bench is still refused before any probe
        let bench = FakeWorld()
        let tagged = bench.run(["bench", "notch", "--config", "multithreaded:4", "--knob", "OPENEMS_FUSED=0",
                                "--tag", "-x"])
        #expect(tagged.exit == 2 && tagged.errorCodes == ["tag_invalid"])
        #expect(bench.system.captures.isEmpty)
        // the bad tag alone is still exit 2
        let alone = FakeWorld().run(["check", "cg29", "--tag", "a/b", "--lite"])
        #expect(alone.exit == 2 && alone.errorCodes == ["tag_invalid"])
    }

    // MARK: e2e --out-dir

    static let e2e = ["e2e", "gcpw", "--lib", "cg29", "--rfsim", FakeWorld.rfsim]

    /// --overwrite renames the old --out-dir as the last step before the run: when the quiet wait fails, nothing
    /// ran and the folder is still in its place.
    @Test func e2eRenamesTheOldOutDirOnlyBeforeTheRun() {
        func world(_ tool: FakeToolRun) -> FakeWorld {
            let world = FakeWorld()
            world.system.addFile("/work/out/result.json", "old\n")
            world.system.update { $0.spawn = tool.handler(world.system) }
            return world
        }
        // the quiet helper prints no line
        let failing = world(FakeToolRun())
        let failed = failing.run(Self.e2e + ["--out-dir", "/work/out", "--overwrite", "--quiet", "60"])
        #expect(failed.exit == 4 && failed.errorCodes.contains("tool_output_unparsed"), "\(failed.stderr)")
        #expect(failing.system.readFile("/work/out/result.json") == Data("old\n".utf8))
        #expect(!failing.system.fileExists("/work/out" + Self.stamp))
        #expect(!failed.warningCodes.contains("output_backed_up"))
        // a stop during the quiet wait: the wait returns, nothing is renamed and no run starts
        var stopping = FakeToolRun()
        stopping.during = { $0.signalArrived(SIGINT) }
        let stopped = world(stopping)
        let interrupted = stopped.run(Self.e2e + ["--out-dir", "/work/out", "--overwrite", "--quiet", "60"])
        #expect(interrupted.exit == 130 && interrupted.errorCodes == ["interrupted"], "\(interrupted.stderr)")
        #expect(stopped.system.readFile("/work/out/result.json") == Data("old\n".utf8))
        #expect(!stopped.system.fileExists("/work/out" + Self.stamp))
        #expect(!interrupted.warningCodes.contains("output_backed_up"))
        #expect(stopped.system.spawned.count == 1)
        // a run that starts finds the old folder renamed
        let result = #"RESULT {"model": "gcpw", "t_build": 0.5, "t_run": 4.5, "t_post": 0.5, "t_total": 5.5}"#
        let lines = ["FDTDKIT_CALL_BEGIN 0", "Create FDTD engine (compressed SSE + multi-threading)",
                     "Time for 34300 iterations with 241995.00 cells : 4.40 sec", "FDTDKIT_CALL_END 0", result]
        let valid = FakeSystem.load(cpuOther: 40, gpuOther: 2, cpuSelf: 390, wall: 4.6)
        var tool = FakeToolRun(lines: lines, absoluteFiles: ["/work/out/result.json": "{}"])
        tool.report = FakeToolRun.report(mode: "script", argv: ["run_one.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: valid)], load: valid,
                                         libraries: FdtdLibraries.fileNames.map { FakeWorld.snaps + "/cg29/" + $0 })
        let passing = world(tool)
        let passed = passing.run(Self.e2e + ["--out-dir", "/work/out", "--overwrite"])
        #expect(passed.exit == 0, "\(passed.stderr)")
        #expect(passing.system.readFile("/work/out" + Self.stamp + "/result.json") == Data("old\n".utf8))
        #expect(passing.system.readFile("/work/out/result.json") == Data("{}".utf8))
        #expect(passed.warningCodes.contains("output_backed_up"))
    }

    /// The rename follows a wait, so the protected folders are checked again just before it: a folder on the path
    /// that became a link into SNAPS meanwhile is refused, and nothing in SNAPS is renamed.
    @Test func e2eChecksTheOutDirAgainBeforeTheRename() {
        let world = FakeWorld()
        let system = world.system
        system.addFile("/work/sub/out/result.json", "old\n")
        let inside = FakeWorld.snaps + "/cg29/out"
        var quiet = FakeToolRun(lines: [#"FDTDKIT_QUIET {"cpu": 12.0, "busy": [], "late": false}"#])
        quiet.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        quiet.during = { _ in
            try? system.removeItem("/work/sub")
            system.addLink("/work/sub", to: FakeWorld.snaps + "/cg29")
            system.addFile(inside + "/result.json", "snapshot\n")
        }
        system.update { $0.spawn = quiet.handler(system) }
        let run = world.run(Self.e2e + ["--out-dir", "/work/sub/out", "--overwrite", "--quiet", "60"])
        #expect(run.exit == 2, "\(run.stderr)")
        #expect(Set(run.errorCodes) == ["protected_path"])
        #expect(run.issue("errors", "protected_path")?["field"]?.string == "--out-dir")
        #expect(system.readFile(inside + "/result.json") == Data("snapshot\n".utf8))
        #expect(!system.fileExists(inside + Self.stamp))
        #expect(!run.warningCodes.contains("output_backed_up"))
        // only the quiet helper ran
        #expect(system.spawned.count == 1)
    }

    /// core.run empties its folder first, so an --out-dir that is the run folder's place or lies above it is refused
    /// before anything is created, in a dry run too.
    @Test func e2eRefusesAnOutDirThatHoldsTheRunFolder() {
        let cases: [[String]] = [["--runs", "/work/e2e", "--out-dir", "/work/e2e"],
                                 ["--runs", "/work/e2e", "--out-dir", "/work/e2e/emskit-fdtd", "--overwrite"],
                                 ["--runs", "/work/e2e/deep", "--out-dir", "/work/link"],
                                 ["--out-dir", FakeWorld.runs, "--overwrite"],
                                 // the run folder itself, which does not exist yet
                                 ["--out-dir", FakeWorld.runFolder("e2e")],
                                 // a second name of RUNS that no real path unifies: the same folder by identity
                                 ["--runs", "/work/e2e", "--out-dir", "/work/E2E"]]
        for tail in cases {
            for dry in [[], ["--dry-run"]] {
                let world = FakeWorld()
                world.system.addDirectory("/work/e2e")
                world.system.addLink("/work/link", to: "/work/e2e")
                world.system.addFolderAlias("/work/E2E", of: "/work/e2e")
                let run = world.run(Self.e2e + tail + dry)
                #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(tail) \(run.stderr)")
                #expect(run.issue("errors", "usage")?["field"]?.string == "--out-dir", "\(tail)")
                #expect(world.system.spawned.isEmpty, "\(tail)")
                #expect(world.system.listDirectory("/work/e2e")?.isEmpty == true, "\(tail)")
            }
        }
        // a folder beside RUNS is fine, also one whose name is the start of RUNS' name
        for beside in ["/work/e2e-out", "/work/e2"] {
            let world = FakeWorld()
            world.system.addDirectory("/work/e2e")
            let fine = world.run(Self.e2e + ["--runs", "/work/e2e", "--out-dir", beside, "--dry-run"])
            #expect(fine.exit == 0, "\(beside) \(fine.stderr)")
        }
    }

    /// --overwrite would rename the folder away just before the run, and core.run empties it: an --out-dir that
    /// is, or holds, the working directory, the tools tree, the toolkit, the library's folder or the Python's is
    /// refused before anything is created, in a dry run too; so is an empty value, which would stand for the cwd.
    /// A library folder named by its path is a protected folder of the line as well, and that refusal comes first.
    @Test func e2eRefusesAnOutDirThatTheRunNeeds() {
        let lib = ["e2e", "gcpw", "--lib", "/data/libs/cg", "--rfsim", FakeWorld.rfsim]
        let cases: [(line: [String], tail: [String])] = [
            (Self.e2e, ["--out-dir", "."]), (Self.e2e, ["--out-dir", ""]),
            // above the tools tree and the toolkit
            (Self.e2e, ["--out-dir", "/work"]), (Self.e2e, ["--out-dir", FakeWorld.rfsim]),
            (Self.e2e, ["--out-dir", "/work/alias"]),
            (lib, ["--out-dir", "/data/libs"]), (lib, ["--out-dir", "/data/libs/cg"]),
            (Self.e2e, ["--out-dir", "/opt/py"]),
        ]
        for (line, tail) in cases {
            for extra in [[], ["--overwrite"], ["--overwrite", "--dry-run"]] {
                let world = FakeWorld()
                world.system.addLibraryFolder("/data/libs/cg", FakeLibrary.cg29.files)
                world.system.addLink("/work/alias", to: FakeWorld.repo)
                let before = world.system.allPaths
                let run = world.run(line + tail + extra)
                #expect(world.system.allPaths == before, "\(tail) \(extra)")
                #expect(world.system.spawned.isEmpty, "\(tail)")
                if line == lib {
                    #expect(run.exit == 2 && run.errorCodes == ["protected_path"], "\(tail) \(extra) \(run.stderr)")
                    #expect(run.issue("errors", "protected_path")?["field"]?.string == "--out-dir", "\(tail)")
                    continue
                }
                #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(tail) \(extra) \(run.stderr)")
                #expect(run.issue("errors", "usage")?["field"]?.string == "--out-dir", "\(tail)")
                // the empty value is named as such, not as the working directory it would stand for
                let message = run.issue("errors", "usage")?["message"]?.string ?? ""
                #expect(message.contains("empty") == (tail[1] == ""), "\(tail): \(message)")
                #expect(world.system.spawned.isEmpty, "\(tail)")
            }
        }
        // a folder inside the tree, or beside the library's, holds none of them
        for fine in [FakeWorld.repo + "/out", "/data/libs/out", "/work/rf"] {
            let world = FakeWorld()
            world.system.addLibraryFolder("/data/libs/cg", FakeLibrary.cg29.files)
            let run = world.run(lib + ["--out-dir", fine, "--dry-run"])
            #expect(run.exit == 0, "\(fine) \(run.stderr)")
        }
    }

    /// The same when the name of RUNS, of the tools tree or of the toolkit passes through a link inside the
    /// --out-dir while the real folder lies outside: the rename would take the name away just before the run.
    @Test func e2eRefusesAnOutDirThatHoldsANeededFolderByItsName() {
        let base = ["e2e", "gcpw", "--lib", "cg29"]
        let cases: [[String]] = [
            ["--rfsim", FakeWorld.rfsim, "--runs", "/work/c/out/runslink", "--out-dir", "/work/c/out"],
            // a link beside the out-dir leads into it, and a link in there leads to the tree
            ["--rfsim", FakeWorld.rfsim, "--repo", "/work/a/link/repo", "--out-dir", "/work/c/out"],
            ["--rfsim", "/work/c/out/toolkit", "--out-dir", "/work/c/out"],
        ]
        func world() -> FakeWorld {
            let world = FakeWorld()
            world.system.addFile("/work/c/out/old.txt", "kept\n")
            world.system.addDirectory("/work/elsewhere/runs")
            world.system.addLink("/work/c/out/runslink", to: "/work/elsewhere/runs")
            world.system.addLink("/work/a/link", to: "/work/c/out")
            world.system.addLink("/work/c/out/repo", to: FakeWorld.repo)
            world.system.addLink("/work/c/out/toolkit", to: FakeWorld.rfsim)
            return world
        }
        for tail in cases {
            for extra in [["--overwrite"], ["--overwrite", "--dry-run"], []] {
                let world = world()
                let before = world.system.allPaths
                let run = world.run(base + tail + extra)
                #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(tail) \(extra): \(run.stderr)")
                #expect(run.issue("errors", "usage")?["field"]?.string == "--out-dir", "\(tail)")
                #expect(world.system.allPaths == before && world.system.spawned.isEmpty, "\(tail) \(extra)")
            }
        }
        // the links alone, with the run's folders named by their own paths, refuse nothing
        let fine = world().run(base + ["--rfsim", FakeWorld.rfsim, "--out-dir", "/work/c/out", "--overwrite",
                                       "--dry-run"])
        #expect(fine.exit == 0, "\(fine.stderr)")
        #expect(fine.warningCodes.contains("output_backed_up"))
    }

    static let quietLine = #"FDTDKIT_QUIET {"cpu": 12.0, "busy": [], "late": false}"#

    /// An --out-dir that was absent at plan time and is filled during the quiet wait is looked at again before the
    /// run, which would empty it: refused without --overwrite (5, nothing run), kept as a backup with it.
    @Test func e2eLooksAtTheOutDirAgainAfterTheWait() {
        func world() -> FakeWorld {
            let world = FakeWorld()
            let system = world.system
            var quiet = FakeToolRun(lines: [Self.quietLine])
            quiet.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
            quiet.during = { _ in
                if !system.fileExists("/work/out" + Self.stamp) { system.addFile("/work/out/result.json", "theirs\n") }
            }
            system.update { $0.spawn = quiet.handler(system) }
            return world
        }
        let plain = world()
        let refused = plain.run(Self.e2e + ["--out-dir", "/work/out", "--quiet", "60"])
        #expect(refused.exit == 5 && refused.errorCodes == ["would_overwrite"], "\(refused.stderr)")
        #expect(refused.issue("errors", "would_overwrite")?["field"]?.string == "--out-dir")
        #expect(plain.system.readFile("/work/out/result.json") == Data("theirs\n".utf8))
        // only the quiet helper ran
        #expect(plain.system.spawned.count == 1)

        let over = world()
        let run = over.run(Self.e2e + ["--out-dir", "/work/out", "--overwrite", "--quiet", "60"])
        #expect(run.warningCodes.contains("output_backed_up"), "\(run.stderr)")
        #expect(over.system.readFile("/work/out" + Self.stamp + "/result.json") == Data("theirs\n".utf8))
        #expect(over.system.spawned.count == 2)
    }

    /// The same second look for the folders the run needs: an --out-dir that became a link to RUNS during the
    /// wait holds the run folder, so nothing is renamed and no run starts.
    @Test func e2eRefusesAnOutDirThatBecameAHolderDuringTheWait() {
        let world = FakeWorld()
        let system = world.system
        system.addFile("/work/sub/result.json", "old\n")
        var quiet = FakeToolRun(lines: [Self.quietLine])
        quiet.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        quiet.during = { _ in
            try? system.removeItem("/work/sub")
            system.addLink("/work/sub", to: FakeWorld.runs)
        }
        system.update { $0.spawn = quiet.handler(system) }
        let run = world.run(Self.e2e + ["--out-dir", "/work/sub", "--overwrite", "--quiet", "60"])
        #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(run.stderr)")
        #expect(run.issue("errors", "usage")?["field"]?.string == "--out-dir")
        #expect(!system.fileExists(FakeWorld.runs + Self.stamp) && !system.fileExists("/work/sub" + Self.stamp))
        #expect(system.isDirectory(FakeWorld.runFolder("e2e")))
        #expect(!run.warningCodes.contains("output_backed_up"))
        #expect(system.spawned.count == 1)
    }

    /// A job that cannot be resolved fails before the rename: the old --out-dir stays in its place.
    @Test func e2eResolvesTheJobBeforeTheRename() throws {
        struct Unresolvable: FdtdBackend {
            func resolve(_ job: FdtdJob, host: String) throws -> FdtdInvocation {
                throw FdtdError(.spawnFailed, "job \(job.id) cannot be resolved")
            }
            func run(_ invocation: FdtdInvocation, control: FdtdStopController,
                     onLine: (@Sendable (String) -> Void)?) throws -> FdtdJobResult {
                throw FdtdError(.spawnFailed, "nothing runs here")
            }
        }
        let world = FakeWorld()
        world.system.addFile("/work/out/result.json", "old\n")
        let session = FdtdSession(context: world.context(stdout: TextCollector(), stderr: TextCollector()),
                                  command: .e2e, arguments: ["e2e"])
        var common = FdtdCommonOptions()
        common.overwrite = true
        common.rfsim = FakeWorld.rfsim
        try session.begin(common)
        let library = try session.resolveLibrary("cg29")
        let job = FdtdJob.e2e(model: .gcpw, library: library, floor: "0", db: "-60", hold: "0.5", outDir: "/work/out")
        #expect(throws: FdtdError.self) {
            _ = try E2ECommand.prepareOutDir("/work/out", job: job, backend: Unresolvable(), needed: [],
                                             session: session)
        }
        #expect(world.system.readFile("/work/out/result.json") == Data("old\n".utf8))
        #expect(!world.system.fileExists("/work/out" + Self.stamp))
        // with a backend that resolves it, the same call renames the folder
        _ = try session.discoverRfsim(required: true)
        let backend = try session.localBackend(runFolder: session.plannedRunFolder(), libraries: [library])
        let kept = try E2ECommand.prepareOutDir("/work/out", job: job, backend: backend, needed: [],
                                                session: session)
        #expect(kept == "/work/out" + Self.stamp)
        #expect(world.system.readFile("/work/out" + Self.stamp + "/result.json") == Data("old\n".utf8))
    }

    // MARK: Live: signals and captures

    /// A SIGHUP that was ignored when the CLI started (nohup) is no stop request: no handler call while installed,
    /// and still ignored afterwards. INT and TERM are stop requests whatever was inherited: a script's `cmd &` starts
    /// with SIGINT ignored, and `kill -INT` must still stop it.
    @Test func onlyAnInheritedIgnoredHangupStaysIgnored() {
        #expect(LiveSignalSource.leftIgnored == [SIGHUP])
        #expect(Set(LiveSignalSource.signals) == [SIGINT, SIGTERM, SIGHUP])
        // SIGUSR2 stands for both kinds: nothing else in the test process uses it
        let before = signal(SIGUSR2, SIG_IGN)
        defer { signal(SIGUSR2, before) }
        let ignored = unsafeBitCast(SIG_IGN, to: Int.self)
        let calls = Mutex(0)
        let count: @Sendable (Int32) -> Void = { _ in calls.withLock { $0 += 1 } }
        let left = LiveSignalInstallation(signals: [SIGUSR2], leftIgnored: [SIGUSR2], handler: count)
        kill(getpid(), SIGUSR2)
        Thread.sleep(forTimeInterval: 0.3)
        #expect(calls.withLock { $0 } == 0)
        left.restore()
        #expect(SignalTests.handlerBits(SIGUSR2).0 == ignored)
        // not in the list (INT, TERM): the handler is called although the signal was ignored at the start
        let taken = LiveSignalInstallation(signals: [SIGUSR2], leftIgnored: [], handler: count)
        kill(getpid(), SIGUSR2)
        let deadline = Date().addingTimeInterval(5)
        while calls.withLock({ $0 }) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        #expect(calls.withLock { $0 } == 1)
        taken.restore()
        #expect(SignalTests.handlerBits(SIGUSR2).0 == ignored)
    }

    /// A captured child that exits while a process it started still holds the pipes: the capture returns after its
    /// short wait, and what is left of the child's group is ended, since no later stop would reach it.
    @Test func captureEndsWhatTheChildLeftInItsGroup() throws {
        _ = LiveChild.prepared
        let request = FdtdCaptureRequest(argv: ["/bin/sh", "-c", "sleep 300 & echo $!"], cwd: "/",
                                         environment: ["PATH": "/usr/bin:/bin"], timeoutSeconds: 30)
        let started = Date()
        let result = FdtdSpawner.capture(request, stop: nil)
        #expect(result.exit == 0)
        #expect(Date().timeIntervalSince(started) < 15)
        let straggler = try #require(pid_t(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
        let deadline = Date().addingTimeInterval(5)
        while kill(straggler, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let gone = kill(straggler, 0) != 0 && errno == ESRCH
        #expect(gone)
        if !gone { _ = kill(straggler, SIGKILL) }
    }
}
