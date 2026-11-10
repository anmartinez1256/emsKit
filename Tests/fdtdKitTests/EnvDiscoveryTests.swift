// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 EnvTests (S2: no hidden defaults; F1: no DYLD on zsh) and DiscoveryTests (section 3) on the fake Mac.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct EnvTests {
    static let removed = ["OPENEMS_FTZ", "DYLD_LIBRARY_PATH", "VALIDATION_ENGINE", "PYTHONNOUSERSITE", "PYTHONSAFEPATH",
                          "PYTHONOPTIMIZE", "PYTHONWARNINGS", "MallocGuardEdges"]
    static let inherited: [String: String] = [
        "HOME": FakeWorld.home, "LANG": "en_US.UTF-8", "PATH": "/usr/bin:/opt/py/bin:/bin", "OPENEMS_FTZ": "1",
        "DYLD_LIBRARY_PATH": "/opt/elsewhere/lib", "VALIDATION_ENGINE": "basic", "PYTHONNOUSERSITE": "1",
        "PYTHONSAFEPATH": "1", "PYTHONOPTIMIZE": "2", "PYTHONWARNINGS": "ignore", "MallocGuardEdges": "1",
        "PYTHONPATH": "/work/py", "PYTHONUSERBASE": "/work/userbase", "RFSIM_PROBE_END_DB": "-80",
        "RFSIM_PATH": "/old/rfsim",
    ]

    @Test func removesKeepsAndSets() throws {
        var warnings: [FdtdIssue] = []
        let env = FdtdChildEnv.base(inherited: Self.inherited, python: FakeWorld.python, rfsimPath: FakeWorld.rfsim,
                                    warnings: &warnings)
        for name in Self.removed {
            #expect(env.environment[name] == nil, "\(name)")
            #expect(env.envRemoved.contains { $0.name == name && $0.value == Self.inherited[name] }, "\(name)")
        }
        let codes = warnings.map { $0.code }
        #expect(codes.contains(.envRemoved) && codes.contains(.pythonEnvKept) && codes.contains(.rfsimEnv))
        let removedText = try #require(warnings.first { $0.code == .envRemoved }).message
        #expect(removedText.contains("OPENEMS_FTZ=1") && removedText.contains("MallocGuardEdges=1"))
        for name in ["PYTHONPATH", "PYTHONUSERBASE", "RFSIM_PROBE_END_DB", "HOME", "LANG"] {
            #expect(env.environment[name] == Self.inherited[name], "\(name)")
            #expect(env.envSet[name] == nil, "\(name)")
        }
        // RFSIM_PATH comes from discovery only
        #expect(env.environment["RFSIM_PATH"] == FakeWorld.rfsim)
        #expect(env.envSet["RFSIM_PATH"] == FakeWorld.rfsim)
        #expect(env.environment["PATH"] == "/opt/py/bin:/usr/bin:/bin")
        #expect(env.environment["PYTHONDONTWRITEBYTECODE"] == "1")
        #expect(env.envSet["PYTHONDONTWRITEBYTECODE"] == "1")
    }

    @Test func rfsimPathWithoutDiscoveryAndPathPrefix() {
        var warnings: [FdtdIssue] = []
        let env = FdtdChildEnv.base(inherited: Self.inherited, python: FakeWorld.python, rfsimPath: nil,
                                    warnings: &warnings)
        #expect(env.environment["RFSIM_PATH"] == nil)
        #expect(env.envRemoved.contains(FdtdEnvEntry(name: "RFSIM_PATH", value: "/old/rfsim")))
        #expect(FdtdChildEnv.prefixPath("/opt/py/bin", "/opt/py/bin:/usr/bin") == "/opt/py/bin:/usr/bin")
        #expect(FdtdChildEnv.prefixPath("/opt/py/bin", "/usr/bin:/opt/py/bin:/bin") == "/opt/py/bin:/usr/bin:/bin")
        #expect(FdtdChildEnv.prefixPath("/opt/py/bin", nil) == "/opt/py/bin")
        // the same environment for zsh has no DYLD at all
        let withDyld = env.adding(["DYLD_LIBRARY_PATH": "/x"])
        #expect(withDyld.forZsh.environment.keys.allSatisfy { !$0.hasPrefix("DYLD_") })
        #expect(withDyld.forZsh.envSet["DYLD_LIBRARY_PATH"] == nil)
    }

    @Test func inheritedKnobIsRemovedFromThePlannedBench() throws {
        var world = FakeWorld()
        world.environment["OPENEMS_FTZ"] = "1"
        let run = world.run(["bench", "patch", "--config", "stock@multithreaded:4", "--config",
                             "cg29@multithreaded:4", "--dry-run"])
        #expect(run.exit == 0)
        #expect(run.warningCodes.contains("env_removed"))
        let bench = try #require(run.envelope["invocations"]?.array?.first { $0["role"]?.string == "bench" })
        let removed = bench["envRemoved"]?.array?.compactMap { $0["name"]?.string } ?? []
        #expect(removed.contains("OPENEMS_FTZ") && removed.contains("DYLD_LIBRARY_PATH"))
        #expect(bench["envSet"]?["OPENEMS_FTZ"] == nil)
        // every Python and zsh probe ran without the inherited knob (git, lsof and ps read no OPENEMS_*)
        let probes = world.system.captures.filter { $0.argv.first != "/usr/bin/git" }
        #expect(!probes.isEmpty)
        #expect(probes.allSatisfy { $0.environment["OPENEMS_FTZ"] == nil })
    }

    @Test func noDyldOnZshButOnDirectPythonChildren() throws {
        let world = FakeWorld()
        let check = world.run(["check", "cg29", "--tag", "envtest", "--lite", "--rfsim", FakeWorld.rfsim, "--dry-run"])
        #expect(check.exit == 0, "\(check.stderr)")
        let checkJob = try #require(check.envelope["invocations"]?.array?.first { $0["role"]?.string == "check" })
        #expect(checkJob["argv"]?.array?.contains { $0.string == "/bin/zsh" } == true)
        #expect(checkJob["envSet"]?.object?.keys.contains { $0.hasPrefix("DYLD_") } == false)

        let debye = FakeWorld()
        let plan = debye.run(["debye-check", "cg29", "--dry-run"])
        #expect(plan.exit == 0, "\(plan.stderr)")
        let zsh = debye.system.captures.filter { $0.argv.first == "/bin/zsh" }
        #expect(zsh.count == 1)
        #expect(zsh.allSatisfy { $0.environment.keys.allSatisfy { !$0.hasPrefix("DYLD_") } })
        #expect(zsh.first?.argv[5] == FakeWorld.snaps + "/cg29")
        let job = try #require(plan.envelope["invocations"]?.array?.first { $0["role"]?.string == "debye" })
        #expect(job["envSet"]?.object?.keys.contains { $0.hasPrefix("DYLD_") } == false)

        // validate runs the suite as a direct Python child: DYLD is set there
        let validate = FakeWorld().run(["validate", "--lib", "cg29", "--dry-run"])
        #expect(validate.exit == 0, "\(validate.stderr)")
        let suite = try #require(validate.envelope["invocations"]?.array?.first { $0["role"]?.string == "validate" })
        #expect(suite["envSet"]?["DYLD_LIBRARY_PATH"]?.string == FakeWorld.snaps + "/cg29")
    }
}

@Suite struct DiscoveryTests {
    static func root(_ run: CLIRun) -> String? { run.envelope["repo"]?["root"]?.string }

    @Test func repoFromOptionCwdAndExecutable() {
        var byOption = FakeWorld()
        byOption.cwd = "/"
        byOption.executablePath = "/nowhere/emskit"
        #expect(Self.root(byOption.run(["validate", "--dry-run", "--repo", FakeWorld.repo])) == FakeWorld.repo)

        var byCwd = FakeWorld()
        byCwd.cwd = FakeWorld.repo + "/bench/validation"
        #expect(Self.root(byCwd.run(["validate", "--dry-run"])) == FakeWorld.repo)

        var byExecutable = FakeWorld()
        byExecutable.cwd = "/"
        byExecutable.executablePath = FakeWorld.repo + "/.build/release/emskit"
        byExecutable.system.addFile(byExecutable.executablePath, "bin", executable: true)
        #expect(Self.root(byExecutable.run(["validate", "--dry-run"])) == FakeWorld.repo)

        var none = FakeWorld()
        none.cwd = "/"
        let missing = none.run(["validate", "--dry-run"])
        #expect(missing.exit == 2)
        #expect(missing.errorCodes == ["repo_not_found"])
        let incomplete = none.run(["validate", "--dry-run", "--repo", "/work"])
        #expect(incomplete.errorCodes == ["tool_missing"])
    }

    @Test func olderHarnessIsSkippedAndTheWalkGoesOn() throws {
        var world = FakeWorld()
        let old = FakeWorld.repo + "/sibling"
        world.system.addFile(old + "/bench/bench.py", "print(line)\n")
        world.system.addFile(old + "/bench/check.sh", "#!/bin/zsh\n")
        world.cwd = old + "/bench"
        let run = world.run(["validate", "--dry-run"])
        #expect(Self.root(run) == FakeWorld.repo)
        let skipped = try #require(run.issue("warnings", "tools_tree_skipped"))
        #expect(skipped["message"]?.string?.contains("older harness") == true)
    }

    @Test func systemPythonIsSkipped() throws {
        var world = FakeWorld()
        world.environment["PATH"] = "/usr/bin:/opt/py/bin:/bin"
        let run = world.run(["validate", "--dry-run"])
        #expect(run.exit == 0)
        #expect(run.warningCodes.contains("python_skipped"))
        #expect(run.envelope["python"]?["path"]?.string == FakeWorld.python)

        var onlySystem = FakeWorld()
        onlySystem.environment["PATH"] = "/usr/bin:/bin"
        #expect(onlySystem.run(["validate", "--dry-run"]).errorCodes == ["python_not_found"])
    }

    @Test func pythonThatStripsDyld() {
        let world = FakeWorld()
        world.system.update { $0.dyldKept = false }
        let run = world.run(["validate", "--lib", "cg29", "--python", "/usr/bin/python3", "--dry-run"])
        #expect(run.exit == 3)
        #expect(run.errorCodes == ["python_strips_dyld"])
        #expect(run.envelope["python"]?["dyldKept"]?.bool == false)
    }

    @Test func pythonNameMismatch() throws {
        let world = FakeWorld()
        world.system.addFile("/opt/other/bin/python3.13", "#!python\n", executable: true)
        world.system.addFile("/opt/other/bin/python3", "#!other\n", executable: true)
        let run = world.run(["debye-check", "cg29", "--python", "/opt/other/bin/python3.13", "--dry-run"])
        #expect(run.exit == 3)
        #expect(run.errorCodes == ["python_name_mismatch"])
        #expect(run.issue("errors", "python_name_mismatch")?["hint"]?.string == "--python /opt/other/bin/python3")
        // the CLI's own python3 by name is fine
        #expect(FakeWorld().run(["debye-check", "cg29", "--dry-run"]).exit == 0)
    }

    @Test func incompleteSnapshot() {
        let run = FakeWorld().run(["bench", "patch", "--config", "broken@multithreaded:4", "--config",
                                   "cg29@multithreaded:4", "--dry-run"])
        #expect(run.exit == 2)
        #expect(run.errorCodes == ["library_incomplete"])
    }

    @Test func rfsimFromOptionOrEnvironment() {
        let byOption = FakeWorld().run(["e2e", "gcpw", "--rfsim", FakeWorld.rfsim, "--dry-run"])
        #expect(byOption.exit == 0, "\(byOption.stderr)")
        #expect(byOption.envelope["rfsim"]?["path"]?.string == FakeWorld.rfsim)
        #expect(byOption.envelope["rfsim"]?["head"]?.string == "fed9876")

        var byEnvironment = FakeWorld()
        byEnvironment.environment["RFSIM_PATH"] = FakeWorld.rfsim
        #expect(byEnvironment.run(["e2e", "gcpw", "--dry-run"]).envelope["rfsim"]?["path"]?.string == FakeWorld.rfsim)

        var elsewhere = FakeWorld()
        elsewhere.environment["RFSIM_PATH"] = "/nowhere"
        let refused = elsewhere.run(["e2e", "gcpw", "--dry-run"])
        #expect(refused.exit == 2)
        #expect(refused.errorCodes == ["rfsim_not_found"])
        #expect(FakeWorld().run(["e2e", "gcpw", "--dry-run"]).errorCodes == ["rfsim_not_found"])
    }

    /// rfsim_not_found says what the search looked at and why it took nothing: --rfsim given or not, RFSIM_PATH set,
    /// empty or not, and what the folder named lacks; info gives the same text in its warning.
    @Test func rfsimNotFoundSaysWhatWasLookedAt() {
        func message(_ run: CLIRun, _ key: String = "errors") -> String {
            run.issue(key, "rfsim_not_found")?["message"]?.string ?? ""
        }
        let none = FakeWorld().run(["e2e", "gcpw", "--dry-run"])
        #expect(message(none) == "the rfsim toolkit is needed, and none was found: "
                + "--rfsim was not given and RFSIM_PATH is not set")
        #expect(none.issue("errors", "rfsim_not_found")?["hint"]?.string == "--rfsim DIR, the folder that holds rfsim/")
        var empty = FakeWorld()
        empty.environment["RFSIM_PATH"] = ""
        #expect(message(empty.run(["e2e", "gcpw", "--dry-run"]))
                .hasSuffix(": --rfsim was not given and RFSIM_PATH is empty"))

        var stale = FakeWorld()
        stale.environment["RFSIM_PATH"] = "/nowhere"
        let refused = stale.run(["e2e", "gcpw", "--dry-run"])
        #expect(message(refused) == "--rfsim was not given, and RFSIM_PATH /nowhere is not a folder")
        let info = stale.run(["info"])
        #expect(info.exit == 0, "\(info.stderr)")
        #expect(message(info, "warnings") == "no rfsim toolkit: --rfsim was not given, and RFSIM_PATH /nowhere is not a folder")
        #expect(info.issue("warnings", "rfsim_not_found")?["hint"]?.string == "--rfsim DIR")

        let world = FakeWorld()
        world.system.addFile("/work/half/rfsim/README", "no openems/ here\n")
        let half = world.run(["e2e", "gcpw", "--rfsim", "/work/half", "--dry-run"])
        #expect(message(half) == "--rfsim /work/half has rfsim/ but no rfsim/openems/core.py")
        #expect(half.issue("errors", "rfsim_not_found")?["field"]?.string == "--rfsim")
        let repo = world.run(["e2e", "gcpw", "--rfsim", FakeWorld.repo, "--dry-run"])
        #expect(message(repo) == "--rfsim \(FakeWorld.repo) has no rfsim/ folder")
    }

    @Test func existingRunFolderGetsASuffix() throws {
        let system = FakeWorld().system
        let utc = try #require(TimeZone(identifier: "UTC"))
        let first = try FdtdRunFolders.create(base: FakeWorld.runs, command: .bench, pid: 4242, now: FakeWorld.start,
                                              timeZone: utc, system: system)
        #expect(first.path == FakeWorld.runFolder("bench"))
        let second = try FdtdRunFolders.create(base: FakeWorld.runs, command: .bench, pid: 4242, now: FakeWorld.start,
                                               timeZone: utc, system: system)
        #expect(second.path == FakeWorld.runFolder("bench") + "-2")
        #expect(system.isDirectory(first.path) && system.isDirectory(second.path))
    }
}
