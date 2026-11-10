// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 PlanTests (5.2, 10, 12): each command's dry-run jobs and invocations against Fixtures/plans/NAME.json,
// with the launcher wrapper, the control fd, cwd and the environment checked again structurally; the overwrite
// refusals and the planned backups. FDTDKIT_UPDATE_PLANS=1 rewrites the golden files (review them against 5.2).
import Foundation
import Testing
@testable import fdtdKit

@Suite struct PlanTests {
    static let update = ProcessInfo.processInfo.environment["FDTDKIT_UPDATE_PLANS"] == "1"

    /// (golden name, arguments, expected exit).
    static let cases: [(String, [String], Int32)] = [
        ("bench", ["bench", "patch", "--nrts", "2000", "--config", "cg18@multithreaded:4", "--config",
                   "cg29@multithreaded:8", "--knob", "OPENEMS_FUSED=0", "--tag", "plan", "--dry-run"], 0),
        ("ab", ["ab", "notch", "--scale", "3", "--nrts", "2000", "--config", "stock@multithreaded:4", "--config",
                "cg29@multithreaded:4", "--rounds", "3", "--record", "/work/ab.txt", "--append", "--dry-run"], 0),
        ("check", ["check", "cg29", "cg27", "--stock", "stock", "--extra", "cg29@metal-diamond:0", "--lite", "--tag",
                   "plan", "--rfsim", FakeWorld.rfsim, "--dry-run"], 0),
        ("validate_tag", ["validate", "--lib", "cg29", "--engine", "multithreaded", "--threads", "4", "--quick",
                          "--case", "slab", "--case", "lines", "--knob", "OPENEMS_FUSED=0", "--tag", "plan",
                          "--dry-run"], 0),
        ("validate", ["validate", "--dry-run"], 0),
        ("debye", ["debye-check", "cg29", "--ref", "cg18", "--threads", "4", "--dry-run"], 0),
        ("diamond", ["diamond-check", "cg29", "--dry-run"], 0),
        ("e2e", ["e2e", "gcpw", "--lib", "cg29", "--rfsim", FakeWorld.rfsim, "--dry-run"], 0),
        ("run", ["run", "/work/board.py", "--lib", "cg29", "--engine", "multithreaded", "--threads", "4", "--nodumps",
                 "--dry-run", "--", "--length", "50"], 0),
    ]

    static func world() -> FakeWorld {
        let world = FakeWorld()
        world.system.addFile("/work/board.py", "import openEMS\n")
        return world
    }

    /// The part of the envelope a golden file holds.
    static func plan(_ run: CLIRun) -> FdtdJSONValue {
        .object(["exit": .number(Double(run.exit)), "status": run.envelope["status"] ?? .null,
                 "jobs": run.envelope["jobs"] ?? .null, "invocations": run.envelope["invocations"] ?? .null])
    }

    @Test(arguments: cases.map { $0.0 })
    func goldenPlan(name: String) throws {
        let (_, arguments, exit) = try #require(Self.cases.first { $0.0 == name })
        let run = Self.world().run(arguments)
        #expect(run.exit == exit, "\(run.stderr)")
        let plan = Self.plan(run)
        let path = TestPaths.fixture("plans/\(name).json")
        if Self.update {
            try FileManager.default.createDirectory(atPath: TestPaths.fixture("plans"), withIntermediateDirectories: true)
            try FdtdJSON.encode(plan).write(to: URL(fileURLWithPath: path))
        }
        let golden = try FdtdJSON.decode(FdtdJSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(plan == golden, "the plan differs from plans/\(name).json (FDTDKIT_UPDATE_PLANS=1 rewrites it)")
    }

    /// ab runs a sampler check before and after abtest, so its dry run plans both (and runs neither).
    @Test func abDryRunPlansBothSamplerChecks() throws {
        let (_, arguments, _) = try #require(Self.cases.first { $0.0 == "ab" })
        let run = Self.world().run(arguments)
        #expect(run.exit == 0, "\(run.stderr)")
        let roles = run.envelope["invocations"]?.array?.compactMap { $0["role"]?.string }
        #expect(roles == ["sampler-check", "ab", "sampler-check"])
        #expect(run.envelope["invocations"]?.array?.allSatisfy { $0["ran"]?.bool == false } == true)
        let checks = try #require(run.result["samplerChecks"]?.array)
        #expect(checks.count == 2)
        #expect(checks.allSatisfy { $0["invalidReason"]?.string == "dry run: the sampler check did not run" })
    }

    /// A refused ab records what would have run, as its dry run does: the sampler check before, abtest and the check
    /// after, with abtest the only job; in a dry run and in a real one (an existing --record without --append).
    @Test func aRefusedAbPlansBothSamplerChecks() throws {
        var arguments = try #require(Self.cases.first { $0.0 == "ab" }).1
        arguments.removeAll { $0 == "--append" }
        let planned = Self.world().run(arguments)
        #expect(planned.exit == 0, "\(planned.stderr)")
        for dryRun in [true, false] {
            let world = Self.world()
            world.system.addFile("/work/ab.txt", "# old\n")
            let run = world.run(dryRun ? arguments : arguments.filter { $0 != "--dry-run" })
            #expect(run.exit == 5 && run.errorCodes == ["would_overwrite"], "dry run \(dryRun): \(run.stderr)")
            let roles = run.envelope["invocations"]?.array?.compactMap { $0["role"]?.string }
            #expect(roles == ["sampler-check", "ab", "sampler-check"], "dry run \(dryRun)")
            #expect(run.envelope["jobs"] == planned.envelope["jobs"], "dry run \(dryRun)")
            #expect(run.envelope["invocations"] == planned.envelope["invocations"], "dry run \(dryRun)")
            // nothing ran: no tool, and no sampler check
            #expect(world.system.spawned.isEmpty, "dry run \(dryRun)")
            #expect(!world.system.captures.contains { $0.argv.contains(FdtdSnippets.load) }, "dry run \(dryRun)")
        }
    }

    /// LCH(ROLE): `[PY, -u, -B, RUN/fdtdkit_run.py, --repo, R, --control-fd, 3, --report, RUN/launcher-ROLE.json]`.
    static func launcherPrefix(_ role: String, command: String) -> [String] {
        let folder = FakeWorld.runFolder(command)
        return [FakeWorld.python, "-u", "-B", folder + "/fdtdkit_run.py", "--repo", FakeWorld.repo, "--control-fd",
                "3", "--report", folder + "/launcher-\(role).json"]
    }

    static func invocation(_ run: CLIRun, _ role: String) throws -> FdtdJSONValue {
        try #require(run.envelope["invocations"]?.array?.first { $0["role"]?.string == role }, "\(role)")
    }

    static func argv(_ value: FdtdJSONValue) -> [String] { value["argv"]?.array?.compactMap { $0.string } ?? [] }

    @Test func launcherWrapperCwdAndEnvironment() throws {
        // (role, command, launcher flags + mode, the tool's argv head, cwd, DYLD set)
        let expected: [(String, String, [String], [String], String, String?)] = [
            ("bench", "bench", ["exec", "--"], [FakeWorld.python, "-W", "ignore", FakeWorld.repo + "/bench/bench.py"],
             FakeWorld.repo, nil),
            ("ab", "ab", ["exec", "--"], [FakeWorld.python, "-W", "ignore", FakeWorld.repo + "/bench/abtest.py"],
             FakeWorld.repo, nil),
            ("check", "check", ["exec", "--"], ["/bin/zsh", "-f", FakeWorld.repo + "/bench/check.sh", "plan"],
             FakeWorld.repo, nil),
            ("validate", "validate_tag", ["--load", "script", "--"],
             [FakeWorld.repo + "/bench/validation/run_validation.py"], FakeWorld.runFolder("validate"),
             FakeWorld.snaps + "/cg29"),
            ("debye", "debye", ["--load", "exec", "--"],
             ["/bin/zsh", "-f", FakeWorld.repo + "/scripts/checks/debye_check.sh", FakeWorld.snaps + "/cg29",
              FakeWorld.snaps + "/cg18"], FakeWorld.runFolder("debye-check"), nil),
            ("diamond", "diamond", ["--load", "exec", "--"],
             ["/bin/zsh", "-f", FakeWorld.repo + "/scripts/checks/diamond_check.sh", FakeWorld.snaps + "/cg29"],
             FakeWorld.runFolder("diamond-check"), nil),
            ("e2e", "e2e", ["--load", "--calls", "script", "--"],
             [FakeWorld.repo + "/scripts/e2e/run_one.py", "gcpw", "0", "-60", "0.5",
              FakeWorld.runFolder("e2e") + "/e2e"], FakeWorld.runFolder("e2e"), FakeWorld.snaps + "/cg29"),
            ("run", "run", ["--load", "--calls", "--engine", "multithreaded", "--threads", "4", "--nodumps", "script",
                            "--"], ["/work/board.py", "--length", "50"], FakeWorld.repo, FakeWorld.snaps + "/cg29"),
        ]
        for (role, name, flags, head, cwd, dyld) in expected {
            let (_, arguments, _) = try #require(Self.cases.first { $0.0 == name })
            let run = Self.world().run(arguments)
            let job = try Self.invocation(run, role)
            let command = arguments[0]
            let argv = Self.argv(job)
            let prefix = Self.launcherPrefix(role, command: command)
            #expect(Array(argv.prefix(prefix.count)) == prefix, "\(role)")
            #expect(Array(argv.dropFirst(prefix.count).prefix(flags.count)) == flags, "\(role)")
            #expect(Array(argv.dropFirst(prefix.count + flags.count).prefix(head.count)) == head, "\(role)")
            #expect(job["cwd"]?.string == cwd, "\(role)")
            #expect(job["envSet"]?["DYLD_LIBRARY_PATH"]?.string == dyld, "\(role)")
            #expect(job["envSet"]?["PYTHONDONTWRITEBYTECODE"]?.string == "1", "\(role)")
            let removed = job["envRemoved"]?.array ?? []
            #expect(removed.contains { $0["name"]?.string == "DYLD_LIBRARY_PATH"
                                       && $0["value"]?.string == "/opt/elsewhere/lib" }, "\(role)")
            #expect(job["ran"]?.bool == false && job["exit"] == .null, "\(role)")
            // nothing was spawned and no run folder was made
            #expect(run.envelope["runFolder"] == .null, "\(role)")
        }
    }

    @Test func toolEnvironmentPerCommand() throws {
        let bench = try Self.invocation(Self.world().run(Self.cases[0].1), "bench")
        #expect(bench["envSet"]?["OPENEMS_BENCH_SNAPS"]?.string == FakeWorld.snaps)
        let benchArgv = Self.argv(bench)
        #expect(benchArgv.suffix(4) == ["--tag", "plan", "--out", FakeWorld.repo + "/results"])
        #expect(benchArgv.contains("cg18@multithreaded:4#OPENEMS_FUSED=0"))

        let ab = try Self.invocation(Self.world().run(Self.cases[1].1), "ab")
        #expect(Self.argv(ab).suffix(2) == ["--out", "/work/ab.txt"])

        let check = try Self.invocation(Self.world().run(Self.cases[2].1), "check")
        #expect(check["envSet"]?["LITE"]?.string == "1")
        #expect(check["envSet"]?["STOCK"]?.string == "stock")
        #expect(check["envSet"]?["EXTRA"]?.string == "cg29@metal-diamond:0")
        #expect(check["envSet"]?["OPENEMS_BENCH_RUNS"]?.string == FakeWorld.runFolder("check") + "/runs")
        #expect(check["envSet"]?["RFSIM_PATH"]?.string == FakeWorld.rfsim)
        #expect(Self.argv(check).suffix(3) == ["plan", "cg29", "cg27"])

        let validate = try Self.invocation(Self.world().run(Self.cases[3].1), "validate")
        #expect(validate["envSet"]?["VALIDATION_ENGINE"]?.string == "multithreaded")
        #expect(validate["envSet"]?["VALIDATION_THREADS"]?.string == "4")
        #expect(validate["envSet"]?["OPENEMS_FUSED"]?.string == "0")
        let validateArgv = Self.argv(validate)
        #expect(validateArgv.contains("--quick"))
        #expect(validateArgv.suffix(3) == ["--cases", "slab", "lines"])

        let debye = try Self.invocation(Self.world().run(Self.cases[5].1), "debye")
        #expect(debye["envSet"]?["THREADS"]?.string == "4")
        #expect(debye["envSet"]?["TMPDIR"]?.string == FakeWorld.runFolder("debye-check") + "/tmp")

        let e2e = try Self.invocation(Self.world().run(Self.cases[7].1), "e2e")
        #expect(e2e["envSet"]?["RFSIM_PATH"]?.string == FakeWorld.rfsim)
        #expect(e2e["envSet"]?["E2E_ENGINE"] == nil)
    }

    /// The plan does not depend on --output: whether --output's protected-folder check or rfsim's discovery builds the
    /// base environment first, every invocation keeps the toolkit $RFSIM_PATH names (set again, not removed).
    @Test func thePlanDoesNotDependOnOutput() throws {
        var plans: [FdtdJSONValue] = []
        for output in [[], ["--output", "/work/e2e.json"]] {
            var world = Self.world()
            world.environment["RFSIM_PATH"] = FakeWorld.rfsim
            let run = world.run(["e2e", "gcpw", "--lib", "cg29", "--quiet", "60", "--dry-run"] + output)
            #expect(run.exit == 0, "\(run.stderr)")
            for role in ["quiet", "e2e"] {
                let job = try Self.invocation(run, role)
                #expect(job["envSet"]?["RFSIM_PATH"]?.string == FakeWorld.rfsim, "\(role) \(output)")
                let removed = job["envRemoved"]?.array ?? []
                #expect(!removed.contains { $0["name"]?.string == "RFSIM_PATH" }, "\(role) \(output)")
            }
            plans.append(.object(["jobs": run.envelope["jobs"] ?? .null,
                                  "invocations": run.envelope["invocations"] ?? .null,
                                  "rfsim": run.envelope["rfsim"] ?? .null]))
        }
        #expect(plans.count == 2 && plans[0] == plans[1])
    }

    @Test func refusedDiamondCheckOnALibraryWithoutTheTuner() {
        let run = Self.world().run(["diamond-check", "cg27", "--dry-run"])
        #expect(run.exit == 3)
        #expect(run.errorCodes == ["library_lacks_feature"])
        #expect(run.issue("errors", "library_lacks_feature")?["hint"]?.string
                == "diamond_check.sh tests the tiling tuner: cg28 or later")
        #expect(run.issue("errors", "library_lacks_feature")?["message"]?.string?.contains("OPENEMS_DIAMOND_TUNE") == true)
        // a refused library costs no probe
        #expect(run.envelope["invocations"]?.array?.isEmpty == true)
    }

    @Test func overwriteRefusalsAndPlannedBackups() throws {
        let table = FakeWorld.repo + "/results/patch_s1_n2000_plan.txt"
        let benchArgs = Self.cases[0].1
        let refusedWorld = Self.world()
        refusedWorld.system.addFile(table, "# patch_s1_n2000  2026-11-05 10:00\n")
        let refused = refusedWorld.run(benchArgs)
        #expect(refused.exit == 5)
        #expect(refused.status == "refused")
        #expect(refused.errorCodes == ["would_overwrite"])
        // the refusal still records what was planned
        #expect(refused.envelope["jobs"]?.array?.isEmpty == false)

        let planned = Self.world()
        planned.system.addFile(table, "# patch_s1_n2000  2026-11-05 10:00\n")
        let run = planned.run(benchArgs + ["--overwrite"])
        #expect(run.exit == 0)
        let backup = try #require(run.issue("warnings", "output_backed_up"))
        #expect(backup["message"]?.string?.contains("\(table).previous-\(FakeWorld.stamp)") == true)
        // a dry run copies nothing
        #expect(!planned.system.fileExists(table + ".previous-" + FakeWorld.stamp))

        // check's tables, validate's json/md and e2e's --out-dir refuse the same way
        let checkWorld = Self.world()
        checkWorld.system.addFile(FakeWorld.repo + "/results/notch_s1_n16000_plan.txt", "x\n")
        #expect(checkWorld.run(Self.cases[2].1).exit == 5)
        let validateWorld = Self.world()
        validateWorld.system.addFile(FakeWorld.repo + "/results/validation_plan.json", "{}\n")
        #expect(validateWorld.run(Self.cases[3].1).exit == 5)
        let e2eWorld = Self.world()
        e2eWorld.system.addFile("/work/out/result.json", "{}\n")
        let e2eArgs = ["e2e", "gcpw", "--rfsim", FakeWorld.rfsim, "--out-dir", "/work/out", "--dry-run"]
        #expect(e2eWorld.run(e2eArgs).exit == 5)
        let e2eOverwrite = e2eWorld.run(e2eArgs + ["--overwrite"])
        #expect(e2eOverwrite.exit == 0)
        #expect(e2eOverwrite.issue("warnings", "output_backed_up")?["message"]?.string?
            .contains("/work/out.previous-\(FakeWorld.stamp)") == true)
        // an ab record is appended to, never replaced
        let abWorld = Self.world()
        abWorld.system.addFile("/work/ab.txt", "# old\n")
        var abArgs = Self.cases[1].1
        abArgs.removeAll { $0 == "--append" }
        let abRefused = abWorld.run(abArgs)
        #expect(abRefused.exit == 5)
        #expect(abRefused.issue("errors", "would_overwrite")?["hint"]?.string == "--append")
    }

    /// A table that is a symbolic link (real files): the backup is a file of its own with the old bytes, so the tool's
    /// write through the link leaves it alone (FileManager.copyItem alone would copy the link).
    @Test func backupOfASymlinkedTableKeepsTheOldBytes() throws {
        let temp = try TempFolder("backup-link")
        defer { temp.remove() }
        try temp.write("kept/table.txt", Data("old\n".utf8))
        try FileManager.default.createDirectory(atPath: temp.file("results"), withIntermediateDirectories: true)
        let link = temp.file("results/patch_s1_n2000_t.txt")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: temp.file("kept/table.txt"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let backup = try FdtdOutputs.backup(link, mode: .copy, now: FakeWorld.start, timeZone: utc, system: LiveSystem())
        #expect(backup == link + ".previous-" + FakeWorld.stamp)
        // bench.py's open(fn, 'w') goes through the link
        try Data("new\n".utf8).write(to: URL(fileURLWithPath: link))
        let type = try FileManager.default.attributesOfItem(atPath: backup)[.type] as? FileAttributeType
        #expect(type == .typeRegular)
        #expect(try TestPaths.text(backup) == "old\n")
        #expect(try TestPaths.text(temp.file("kept/table.txt")) == "new\n")
    }

    /// A real (fake) bench run with --overwrite: the old table is copied next to itself before bench writes it.
    @Test func overwriteBackupNextToTheOriginal() throws {
        let world = Self.world()
        let table = FakeWorld.repo + "/results/patch_s1_n2000_plan.txt"
        world.system.addFile(table, "# patch_s1_n2000  2026-11-05 10:00\nold\n")
        let variants = try TestPaths.lines(TestPaths.fixture("bench_variants.txt"))
        let rows = [variants[1], variants[2]].map {
            $0.replacingOccurrences(of: "stock@multithreaded:4", with: "cg18@multithreaded:4#OPENEMS_FUSED=0")
        }
        let log = "Create FDTD engine (compressed SSE + multi-threading)\n"
        var tool = FakeToolRun(lines: ["# patch_s1_n2000  load avg 3.42"] + rows
                               + ["IDENTICAL: every run of 1 config equals the reference", "wrote \(table)"])
        tool.files = ["runs/patch_s1_n2000/cg18_multithreaded_t4_OPENEMS_FUSED_0/rep0/openEMS.log": log,
                      "runs/patch_s1_n2000/cg29_multithreaded_t8_OPENEMS_FUSED_0/rep0/openEMS.log": log]
        tool.absoluteFiles = [table: "# patch_s1_n2000  2026-11-06 12:00\nnew\n"]
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        world.system.update { $0.spawn = tool.handler(world.system) }
        var arguments = Self.cases[0].1
        arguments.removeAll { $0 == "--dry-run" }
        let run = world.run(arguments + ["--overwrite"])
        let backup = table + ".previous-" + FakeWorld.stamp
        #expect(world.system.contents(backup) == "# patch_s1_n2000  2026-11-05 10:00\nold\n", "\(run.stderr)")
        #expect(world.system.contents(table)?.hasSuffix("new\n") == true)
        #expect(run.warningCodes.contains("output_backed_up"))
        let output = try #require(run.envelope["outputs"]?.array?.first { $0["path"]?.string == table })
        #expect(output["backup"]?.string == backup)
        #expect(output["existedBefore"]?.bool == true)
        #expect(output["sha256"]?.string == FdtdLibraries.sha256(Data("# patch_s1_n2000  2026-11-06 12:00\nnew\n".utf8)))
    }
}
