// SPDX-License-Identifier: GPL-3.0-or-later

// The guards that tie a result to the library it names (S1, spec 6.2): library_not_loaded in the probe and in the
// verdicts of run, validate and e2e (dyld reports real paths, a LIB is kept as given), knob_unsupported and
// engine_unsupported for every CFG and --knob, check's --extra among them, and the field of a SNAP that check.sh's
// configs cannot carry.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct LoadedLibraryTests {
    static let cg29 = FakeWorld.snaps + "/cg29"
    static let rfsim = ["--rfsim", FakeWorld.rfsim]

    /// The three file names in `dir`.
    static func images(_ dir: String) -> [String] { FdtdLibraries.fileNames.map { dir + "/" + $0 } }

    /// The three files of cg29, libopenEMS replaced by the installed one: what dyld loads when it cannot use the
    /// snapshot's file.
    static let mixed = images(cg29).map { path in
        FdtdPaths.basename(path).hasPrefix("libopenEMS.") ? FakeWorld.installed + "/libopenEMS.0.37.0.dylib" : path
    }

    /// A world with /work/link -> SNAPS/cg29 and a script.
    static func world() -> FakeWorld {
        let world = FakeWorld()
        world.system.addLink("/work/link", to: cg29)
        world.system.addFile("/work/board.py", "import openEMS\n")
        return world
    }

    static func probe(_ libraries: [String]) throws -> FdtdProbeResult {
        let value: FdtdJSONValue = .object([
            "executable": .string(FakeWorld.python), "realPath": .string(FakeWorld.pythonReal),
            "version": .string("3.14.6"), "libraries": .array(libraries.map { .string($0) }),
        ])
        return try FdtdJSON.decode(FdtdProbeResult.self, from: JSONEncoder().encode(value))
    }

    static func notLoaded(_ verdict: FdtdVerdict) -> Bool { verdict.errors.contains { $0.code == .libraryNotLoaded } }

    // MARK: The shared rule and the probe

    @Test func anImageLiesInTheFolderAsGivenOrByRealPath() {
        let system = Self.world().system
        let image = Self.cg29 + "/libopenEMS.0.dylib"
        #expect(FdtdDiscovery.lies(image, in: Self.cg29, system: system))
        #expect(FdtdDiscovery.lies(image, in: Self.cg29 + "/", system: system))
        // dyld's real path against a folder named through a link, and the other way round
        #expect(FdtdDiscovery.lies(image, in: "/work/link", system: system))
        #expect(FdtdDiscovery.lies("/work/link/libopenEMS.0.dylib", in: Self.cg29, system: system))
        #expect(!FdtdDiscovery.lies(FakeWorld.installed + "/libopenEMS.0.dylib", in: Self.cg29, system: system))
        // a folder whose name only starts alike
        #expect(!FdtdDiscovery.lies(Self.cg29 + "b/libopenEMS.0.dylib", in: Self.cg29, system: system))
    }

    /// A folder whose three names are links to files in another folder: dyld reports those files, and they are the
    /// folder's. A file elsewhere that no name of the folder leads to is still not.
    @Test func anImageBehindALinkedNameLiesInTheFolder() throws {
        let world = Self.world()
        let system = world.system
        system.addLibraryFolder("/work/real", FakeLibrary.cg29.files)
        system.addDirectory("/work/farm")
        for name in FdtdLibraries.fileNames { system.addLink("/work/farm/" + name, to: "../real/" + name) }
        system.addFile("/work/real/libopenEMS.9.dylib", FakeLibrary.cg29.openEMS, executable: true)
        for name in FdtdLibraries.fileNames {
            #expect(FdtdDiscovery.lies("/work/real/" + name, in: "/work/farm", system: system), "\(name)")
        }
        #expect(!FdtdDiscovery.lies("/work/real/libopenEMS.9.dylib", in: "/work/farm", system: system))
        #expect(!FdtdDiscovery.lies(Self.cg29 + "/libopenEMS.0.dylib", in: "/work/farm", system: system))
        #expect(!FdtdDiscovery.lies("/work/gone/libopenEMS.0.dylib", in: "/work/farm", system: system))
        try FdtdDiscovery.requireLoaded(try Self.probe(Self.images("/work/real")), from: "/work/farm", system: system)
        // validate, e2e and run accept the folder
        let run = world.run(["validate", "--lib", "/work/farm", "--dry-run"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(!run.errorCodes.contains("library_not_loaded"))
    }

    /// bench.py takes the real path of each loaded library and wants it in the real LIB folder, after the first
    /// simulation: bench, ab and check refuse a folder of links to files elsewhere before anything runs, in a dry
    /// run too. Links that stay inside the folder, and a link to the folder itself, are fine.
    @Test func benchAbAndCheckRefuseAFolderOfLinksElsewhere() {
        func world() -> FakeWorld {
            let world = Self.world()
            let system = world.system
            system.addLibraryFolder("/work/real", FakeLibrary.cg29.files)
            system.addDirectory("/work/farm")
            for name in FdtdLibraries.fileNames { system.addLink("/work/farm/" + name, to: "../real/" + name) }
            // one name leaves the folder, the others are the folder's own files
            system.addLibraryFolder("/work/mixed", FakeLibrary.cg29.files)
            try? system.removeItem("/work/mixed/libnf2ff.0.dylib")
            system.addLink("/work/mixed/libnf2ff.0.dylib", to: "/work/real/libnf2ff.0.dylib")
            return world
        }
        let config = "@multithreaded:4"
        for farm in ["/work/farm", "/work/mixed"] {
            let lines: [[String]] = [
                ["bench", "notch", "--config", farm + config],
                ["bench", "notch", "--config", "multithreaded:4", "--config", farm + config, "--dry-run"],
                ["ab", "notch", "--config", "cg29" + config, "--config", farm + config, "--dry-run"],
                ["check", farm, "--tag", "t", "--lite", "--dry-run"],
                ["check", "cg29", "--stock", farm, "--tag", "t", "--lite"],
                ["check", "cg29", "--extra", farm + config, "--tag", "t", "--lite", "--dry-run"],
            ]
            for line in lines {
                let world = world()
                let run = world.run(line)
                #expect(run.exit == 2 && run.errorCodes == ["library_incomplete"], "\(line) \(run.stderr)")
                let message = run.issue("errors", "library_incomplete")?["message"]?.string ?? ""
                #expect(message.contains("/work/real/") && message.contains("bench.py"), "\(line): \(message)")
                #expect(world.system.spawned.isEmpty, "\(line)")
            }
        }
        // the folder by a link, and names that are links inside the folder (the installed layout)
        let fine = world()
        fine.system.addLibraryFolder("/work/own", FakeLibrary.cg29.files)
        fine.system.addFile("/work/own/libopenEMS.0.37.0.dylib", FakeLibrary.cg29.openEMS, executable: true)
        try? fine.system.removeItem("/work/own/libopenEMS.0.dylib")
        fine.system.addLink("/work/own/libopenEMS.0.dylib", to: "libopenEMS.0.37.0.dylib")
        for lib in ["/work/link", "/work/own"] {
            let run = fine.run(["bench", "notch", "--config", lib + config, "--dry-run"])
            #expect(run.exit == 0, "\(lib) \(run.stderr)")
        }
    }

    @Test func requireLoadedNamesTheFileFromElsewhere() throws {
        let system = Self.world().system
        try FdtdDiscovery.requireLoaded(try Self.probe(Self.images(Self.cg29)), from: Self.cg29, system: system)
        try FdtdDiscovery.requireLoaded(try Self.probe(Self.images(Self.cg29)), from: "/work/link", system: system)
        do {
            try FdtdDiscovery.requireLoaded(try Self.probe(Self.mixed), from: Self.cg29, system: system)
            Issue.record("a libopenEMS from the installed folder passed")
        } catch let e as FdtdError {
            #expect(e.issues.map(\.code) == [.libraryNotLoaded])
            #expect(e.issues.first?.message.contains("libopenEMS came from " + FakeWorld.installed) == true)
        }
        let two = Self.images(Self.cg29).filter { !$0.contains("libnf2ff") }
        do {
            try FdtdDiscovery.requireLoaded(try Self.probe(two), from: Self.cg29, system: system)
            Issue.record("a probe without libnf2ff passed")
        } catch let e as FdtdError {
            #expect(e.issues.first?.message.contains("no libnf2ff was loaded") == true)
        }
    }

    /// validate, e2e and run refuse before the run when the probe took a file from another folder.
    @Test func aSnapshotTheProbeDidNotLoadIsRefusedBeforeTheRun() {
        let commands: [[String]] = [["validate", "--lib", "cg29"], ["e2e", "gcpw", "--lib", "cg29"] + Self.rfsim,
                                    ["run", "/work/board.py", "--lib", "cg29"]]
        for arguments in commands {
            let world = Self.world()
            #expect(world.run(arguments + ["--dry-run"]).exit == 0, "\(arguments)")
            world.system.update { $0.probeLibraries = Self.mixed }
            let run = world.run(arguments + ["--dry-run"])
            #expect(run.exit == 4, "\(arguments)")
            #expect(run.errorCodes == ["library_not_loaded"], "\(arguments)")
            #expect(run.issue("errors", "library_not_loaded")?["field"]?.string == "--lib")
        }
    }

    // MARK: The verdicts

    @Test func runVerdictChecksTheLoadedLibraries() {
        let system = Self.world().system
        func verdict(_ libraries: [String], _ dir: String) -> FdtdVerdict {
            FdtdVerdicts.run(exit: 0, exception: nil, calls: [], engine: nil, libraries: libraries, targetDir: dir,
                             system: system)
        }
        #expect(verdict(Self.images(Self.cg29), Self.cg29).passed)
        // the report has dyld's real paths, --lib named the folder through a link
        #expect(verdict(Self.images(Self.cg29), "/work/link").passed)
        #expect(verdict([], Self.cg29).passed)
        let foreign = verdict(Self.mixed, Self.cg29)
        #expect(!foreign.passed && Self.notLoaded(foreign))
        #expect(foreign.errors.first?.message.contains(FakeWorld.installed + "/libopenEMS.0.37.0.dylib") == true)
        #expect(Self.notLoaded(verdict(Self.images(Self.cg29 + "b"), Self.cg29)))
    }

    @Test func validateVerdictChecksTheLoadedLibraries() {
        let system = Self.world().system
        func verdict(_ libraries: [String], _ dir: String) -> FdtdVerdict {
            let runs = ["slab": [FdtdValidationRun(run: "slab_ref", engine: "compressed SSE + multi-threading")]]
            let report = FdtdValidationReport(meta: ["libraries": .array(libraries.map { .string($0) })], timings: [:],
                                              runs: runs,
                                              results: [FdtdValidationCheck(caseName: "slab", quantity: "q",
                                                                            passed: true)])
            return FdtdVerdicts.validate(exit: 0, report: report, expectedDir: dir, engine: .multithreaded,
                                         home: FakeWorld.home, system: system)
        }
        // the suite writes the home folder as ~
        let own = Self.images("~/opt/openEMS-dev/snap/cg29")
        #expect(verdict(own, Self.cg29).passed)
        #expect(verdict(own, "/work/link").passed)
        #expect(Self.notLoaded(verdict([], Self.cg29)))
        let foreign = verdict(own.dropLast() + ["~/opt/openEMS/lib/libnf2ff.0.dylib"], Self.cg29)
        #expect(Self.notLoaded(foreign))
        #expect(foreign.errors.first?.message.contains("from " + FakeWorld.installed + ", not only") == true)
        // the suite replaces the home folder's text anywhere in a path: a folder beside the home folder whose
        // name starts like it, and one that holds the home path further down
        for dir in [FakeWorld.home + "2/snap/cg", "/Volumes/x" + FakeWorld.home + "/snap/cg"] {
            system.addLibraryFolder(dir, FakeLibrary.cg29.files)
            let written = Self.images(dir.replacingOccurrences(of: FakeWorld.home, with: "~"))
            #expect(written.allSatisfy { !$0.hasPrefix("~/") && $0.contains("~") })
            #expect(verdict(written, dir).passed, "\(dir)")
            #expect(Self.notLoaded(verdict(written, Self.cg29)), "\(dir)")
        }
    }

    @Test func e2eVerdictChecksTheLoadedLibraries() {
        let system = Self.world().system
        func verdict(_ libraries: [String]?, _ dir: String, interrupted: Bool = false) -> FdtdVerdict {
            FdtdVerdicts.e2e(exit: 0, result: .object([:]), resultJsonExists: true, calls: [], engine: nil,
                             interrupted: interrupted, libraries: libraries, targetDir: dir, system: system)
        }
        #expect(!Self.notLoaded(verdict(Self.images(Self.cg29), Self.cg29)))
        #expect(!Self.notLoaded(verdict(Self.images(Self.cg29), "/work/link")))
        #expect(Self.notLoaded(verdict(Self.mixed, Self.cg29)))
        // no launcher report is its own finding, and an interrupted run gives no error here
        #expect(!Self.notLoaded(verdict(nil, Self.cg29)))
        #expect(verdict(Self.mixed, Self.cg29, interrupted: true).errors.isEmpty)
    }

    // MARK: The commands

    /// An e2e run of `--lib LIB` whose launcher report lists `libraries`.
    static func e2e(_ lib: String, libraries: [String]) -> CLIRun {
        let world = Self.world()
        let result = #"RESULT {"model": "gcpw", "t_build": 0.5, "t_run": 4.5, "t_post": 0.5, "t_total": 5.5}"#
        let lines = ["FDTDKIT_CALL_BEGIN 0", "Create FDTD engine (compressed SSE + multi-threading)",
                     "Time for 34300 iterations with 241995.00 cells : 4.40 sec", "FDTDKIT_CALL_END 0", result]
        let valid = FakeSystem.load(cpuOther: 40, gpuOther: 2, cpuSelf: 390, wall: 4.6)
        var tool = FakeToolRun(lines: lines, absoluteFiles: [FakeWorld.runFolder("e2e") + "/e2e/result.json": "{}"])
        tool.report = FakeToolRun.report(mode: "script", argv: ["run_one.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: valid)], load: valid,
                                         libraries: libraries)
        world.system.update { $0.spawn = tool.handler(world.system) }
        return world.run(["e2e", "gcpw", "--lib", lib] + rfsim)
    }

    @Test func e2eReportsALibraryFromAnotherFolder() {
        let own = Self.e2e("cg29", libraries: Self.images(Self.cg29))
        #expect(own.exit == 0 && own.status == "ok", "\(own.stderr)")
        // dyld's real paths for a folder named through a link
        let linked = Self.e2e("/work/link", libraries: Self.images(Self.cg29))
        #expect(linked.exit == 0 && linked.status == "ok", "\(linked.stderr)")
        // dyld took the installed libopenEMS: the times are not the snapshot's
        let foreign = Self.e2e("cg29", libraries: Self.mixed)
        #expect(foreign.exit == 4)
        #expect(foreign.errorCodes == ["library_not_loaded"])
        let none = Self.e2e("cg29", libraries: [])
        #expect(none.exit == 4)
        #expect(none.errorCodes == ["library_not_loaded"])
    }

    /// A run of the script with `--lib LIB` whose launcher report lists `libraries` and one FDTD.Run call.
    static func script(_ lib: String, libraries: [String]) -> CLIRun {
        let world = Self.world()
        let lines = ["FDTDKIT_CALL_BEGIN 0", "Create FDTD engine (compressed SSE + multi-threading)",
                     "Time for 34300 iterations with 241995.00 cells : 4.40 sec", "FDTDKIT_CALL_END 0"]
        let valid = FakeSystem.load(cpuOther: 40, gpuOther: 2, cpuSelf: 390, wall: 4.6)
        var tool = FakeToolRun(lines: lines)
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: valid)], load: valid,
                                         libraries: libraries)
        world.system.update { $0.spawn = tool.handler(world.system) }
        return world.run(["run", "/work/board.py", "--lib", lib])
    }

    @Test func runReportsALibraryFromAnotherFolder() {
        let own = Self.script("cg29", libraries: Self.images(Self.cg29))
        #expect(own.exit == 0 && own.status == "ok", "\(own.stderr)")
        let linked = Self.script("/work/link", libraries: Self.images(Self.cg29))
        #expect(linked.exit == 0 && linked.status == "ok", "\(linked.stderr)")
        let foreign = Self.script("cg29", libraries: Self.mixed)
        #expect(foreign.exit == 4)
        #expect(foreign.errorCodes == ["library_not_loaded"])
        let none = Self.script("cg29", libraries: [])
        #expect(none.exit == 4)
        #expect(none.errorCodes == ["library_not_loaded"])
    }

    // MARK: Knobs and engines the library lacks

    /// cg18 has neither OPENEMS_FLAGS nor metal-diamond: the knob or the engine would do nothing there.
    @Test func aKnobOrEngineTheLibraryLacksIsRefused() {
        let bench = ["bench", "patch", "--nrts", "2000", "--dry-run", "--config"]
        let cases: [([String], String)] = [
            (bench + ["cg18@multithreaded:4#OPENEMS_FLAGS=0"], "knob_unsupported"),
            (bench + ["cg18@multithreaded:4", "--knob", "OPENEMS_FLAGS=0"], "knob_unsupported"),
            (bench + ["cg18@metal-diamond"], "engine_unsupported"),
            (["validate", "--lib", "cg18", "--knob", "OPENEMS_FLAGS=0", "--dry-run"], "knob_unsupported"),
            (["validate", "--lib", "cg18", "--engine", "metal-diamond", "--dry-run"], "engine_unsupported"),
            (["run", "/work/board.py", "--lib", "cg18", "--knob", "OPENEMS_FLAGS=0", "--dry-run"], "knob_unsupported"),
            (["run", "/work/board.py", "--lib", "cg18", "--engine", "metal-diamond", "--dry-run"],
             "engine_unsupported"),
            (["e2e", "gcpw", "--lib", "cg18", "--engine", "metal-diamond", "--dry-run"] + Self.rfsim,
             "engine_unsupported"),
        ]
        for (arguments, code) in cases {
            let run = Self.world().run(arguments)
            #expect(run.exit == 3, "\(arguments)")
            #expect(run.errorCodes == [code], "\(arguments)")
        }
        // the same on a library that has both
        #expect(Self.world().run(bench + ["cg29@metal-diamond#OPENEMS_FLAGS=0"]).exit == 0)
        #expect(Self.world().run(["validate", "--lib", "cg29", "--engine", "metal-diamond", "--knob",
                                  "OPENEMS_FLAGS=0", "--dry-run"]).exit == 0)
    }

    // MARK: check

    static func check(_ more: [String], snapshot: String = "cg29", world: FakeWorld = FakeWorld()) -> CLIRun {
        world.run(["check", snapshot, "--tag", "extra", "--lite", "--dry-run"] + rfsim + more)
    }

    /// An --extra is matched against its own library as a bench CFG is, in a dry run too.
    @Test func checkExtrasAreMatchedAgainstTheirLibrary() {
        let knob = Self.check(["--extra", "cg18@multithreaded:4#OPENEMS_FLAGS=0"])
        #expect(knob.exit == 3)
        #expect(knob.errorCodes == ["knob_unsupported"])
        let engine = Self.check(["--extra", "cg18@metal-diamond"])
        #expect(engine.exit == 3)
        #expect(engine.errorCodes == ["engine_unsupported"])
        let missing = Self.check(["--extra", "typo@multithreaded:4"])
        #expect(missing.exit == 2)
        #expect(missing.errorCodes == ["library_not_found"])
        let incomplete = Self.check(["--extra", "broken@multithreaded:4"])
        #expect(incomplete.exit == 2)
        #expect(incomplete.errorCodes == ["library_incomplete"])
        // the installed library (cg18's build) for a bare CFG
        #expect(Self.check(["--extra", "multithreaded:4#OPENEMS_FLAGS=0"]).errorCodes == ["knob_unsupported"])
    }

    @Test func checkExtrasAddTheirLibrariesToTheUsedList() throws {
        func specs(_ run: CLIRun) -> [String] {
            run.envelope["libraries"]?.array?.compactMap { $0["spec"]?.string } ?? []
        }
        let plain = Self.check([])
        #expect(plain.exit == 0, "\(plain.stderr)")
        #expect(specs(plain) == ["cg29", "stock"])
        let run = Self.check(["--extra", "cg27@multithreaded:4", "--extra", "cg29@multithreaded:2", "--extra",
                              "multithreaded:4"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(specs(run) == ["cg29", "stock", "cg27", "installed"])
        // the concurrency scan asks for the extra's file as for the SNAPs' (a folder outside SNAPS is in no other list)
        let world = FakeWorld()
        world.system.addLibraryFolder("/work/build", FakeLibrary.cg27.files)
        let extra = Self.check(["--extra", "/work/build@multithreaded:4"], world: world)
        #expect(extra.exit == 0, "\(extra.stderr)")
        #expect(specs(extra) == ["cg29", "stock", "/work/build"])
        let scanB = try #require(world.system.captures.last {
            $0.argv.first == "/usr/sbin/lsof" && $0.argv.contains("--")
        })
        #expect(scanB.argv.contains("/work/build/libopenEMS.0.dylib"))
        // a library named twice (SNAP and an extra, SNAP and --stock) is used once: the scan lists its file once
        for more in [["--extra", "cg29@multithreaded:2"], ["--stock", "cg29"]] {
            let twice = FakeWorld()
            let doubled = Self.check(more, world: twice)
            #expect(doubled.exit == 0, "\(more) \(doubled.stderr)")
            let scan = try #require(twice.system.captures.last {
                $0.argv.first == "/usr/sbin/lsof" && $0.argv.contains("--")
            })
            let file = FakeWorld.snaps + "/cg29/libopenEMS.0.dylib"
            #expect(scan.argv.filter { $0 == file }.count == 1, "\(more) \(scan.argv)")
        }
    }

    /// With the installed library as SNAP and reference, an extra's snapshot is the one folder that needs DYLD, so
    /// the probe must prove with it that this Python keeps the variable.
    @Test func checkProbesWithAnExtrasSnapshotFolder() {
        let world = FakeWorld()
        let arguments = ["check", "installed", "--stock", "installed", "--tag", "extra", "--lite", "--dry-run"]
            + Self.rfsim + ["--extra", "cg27@multithreaded:4"]
        let kept = world.run(arguments)
        #expect(kept.exit == 0, "\(kept.stderr)")
        let probes = world.system.captures.filter { $0.argv.contains(FdtdSnippets.probe) }
        #expect(probes.contains { $0.environment["DYLD_LIBRARY_PATH"] == FakeWorld.snaps + "/cg27" })
        let stripping = FakeWorld()
        stripping.system.update { $0.dyldKept = false }
        let stripped = stripping.run(arguments)
        #expect(stripped.exit == 3, "\(stripped.stderr)")
        #expect(stripped.errorCodes == ["python_strips_dyld"])
    }

    /// A SNAP or --stock folder that check.sh's configs cannot carry is refused under its own field.
    @Test func aSnapThatAConfigCannotCarryIsReportedUnderItsField() {
        let world = FakeWorld()
        world.system.addLibraryFolder("/work/my snaps/cg29", FakeLibrary.cg29.files)
        world.system.addLibraryFolder("/work/a#b", FakeLibrary.stock.files)
        world.system.addLibraryFolder(FakeWorld.snaps + "/odd,name", FakeLibrary.cg29.files)
        let cases: [(String, [String], String)] = [("/work/my snaps/cg29", [], "SNAP"), ("odd,name", [], "SNAP"),
                                                   ("cg29", ["--stock", "/work/a#b"], "--stock")]
        for (snapshot, more, field) in cases {
            let run = Self.check(more, snapshot: snapshot, world: world)
            #expect(run.exit == 2, "\(snapshot) \(more)")
            #expect(run.errorCodes == ["config_invalid"], "\(snapshot) \(more)")
            #expect(run.issue("errors", "config_invalid")?["field"]?.string == field, "\(snapshot) \(more)")
        }
        #expect(FdtdBenchConfigs.carries(lib: "cg29") && FdtdBenchConfigs.carries(lib: "/work/snaps/cg29"))
        for lib in ["", "-x", "a b", "a@b", "a#b", "a,b", "a;b", "a\tb"] {
            #expect(!FdtdBenchConfigs.carries(lib: lib), "\(lib)")
        }
    }
}
