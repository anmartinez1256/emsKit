// SPDX-License-Identifier: GPL-3.0-or-later

// The fourth review of 2026-11-10 (CHANGELOG.md), PLAN 10.2 and 4.1: the protected folders are the union of what
// discovery finds with the line's options (--repo, --python, --rfsim, --snaps) and what it finds with all of them
// ignored, so that an option can add a protected folder and never take one away; and every option whose value is a
// path refuses an empty value, and a folder where it takes a FILE.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct DiscoveryOptionTests {
    static let custom = OpenItemTests.custom
    static let library = custom + "/lib/libopenEMS.0.dylib"
    static let other = "/opt/other"
    static let otherPython = other + "/bin/python3"

    /// OpenItemTests' Mac (PATH's Python loads openEMS from /opt/custom/lib, a prefix that no default names), and a
    /// second Python that loads it from /opt/other/lib.
    static func world() -> FakeWorld {
        let world = OpenItemTests.customPrefix()
        world.system.addFile(otherPython, "#!python\n", executable: true)
        world.system.addLibraryFolder(other + "/lib", FakeLibrary.cg27.files)
        world.system.update { b in
            b.probeLibrariesOf[otherPython] = FdtdLibraries.fileNames.map { other + "/lib/" + $0 }
        }
        return world
    }

    static func probes(_ world: FakeWorld) -> [FdtdCaptureRequest] {
        world.system.captures.filter { $0.argv.contains(FdtdSnippets.probe) }
    }

    // MARK: An option that does not resolve

    /// A --repo, --python, --rfsim or --snaps that names nothing ends the command, but the prefix that the line
    /// without it protects stays protected: an --output inside it is refused and nothing there is renamed or written.
    @Test(arguments: [["--repo", "/nope"], ["--repo", "/work/emsKitt"], ["--python", "/nope/python3"],
                      ["--python", "/opt/py/bin/pythn3"], ["--rfsim", "/nope"], ["--snaps", "/nope"]])
    func anOptionThatNamesNothingLeavesThePrefixProtected(option: [String]) {
        let envelope = Self.custom + "/envelope.json"
        let bench = ["bench", "patch", "--config", "multithreaded:4", "--dry-run"]
        let lines: [[String]] = [
            ["info", "--output", envelope], ["info", "--overwrite", "--output", Self.library],
            ["load", "--seconds", "1", "--output", envelope], bench + ["--output", envelope],
            bench + ["--overwrite", "--output", Self.library],
            // a snapshot folder that only the default discovery names
            ["info", "--overwrite", "--output", FakeWorld.snaps + "/cg29/libopenEMS.0.dylib"],
        ]
        for line in lines {
            let world = Self.world()
            let before = world.system.allPaths
            let bytes = world.system.readFile(Self.library)
            let run = world.run(line + option)
            // with --overwrite the planned backup is refused as well
            #expect(Set(run.errorCodes) == ["protected_path"], "\(line) \(option): \(run.errorCodes) \(run.stderr)")
            #expect(run.exit == 2, "\(line) \(option)")
            #expect(run.issue("errors", "protected_path")?["field"]?.string == "--output", "\(line) \(option)")
            #expect(world.system.allPaths == before, "\(line) \(option)")
            #expect(world.system.readFile(Self.library) == bytes, "\(line) \(option)")
            #expect(world.system.spawned.isEmpty)
            #expect(run.stdout.contains("\"protected_path\""))
        }
    }

    /// A correct --python (or --repo) of a second installation keeps protecting that installation's prefix when
    /// another discovery option on the line names nothing: the options count one by one. The prefix of the plain
    /// line stays protected beside it.
    @Test(arguments: [["--rfsim", "/nope"], ["--repo", "/nope"], ["--repo", "/work/emsKitt"],
                      ["--rfsim", "/nope", "--repo", "/nope"]])
    func aCorrectOptionBesideOneThatNamesNothingKeepsItsPrefix(bad: [String]) {
        let second = Self.other + "/lib/libopenEMS.0.dylib"
        let bench = ["bench", "patch", "--config", "multithreaded:4", "--dry-run"]
        let lines: [[String]] = [
            ["info", "--output", Self.other + "/lib/e.json"], ["info", "--overwrite", "--output", second],
            bench + ["--overwrite", "--output", second], bench + ["--output", Self.other + "/e.json"],
            ["info", "--overwrite", "--output", Self.library],
        ]
        for line in lines {
            let world = Self.world()
            let before = world.system.allPaths
            let bytes = world.system.readFile(second)
            let run = world.run(line + ["--python", Self.otherPython] + bad)
            #expect(Set(run.errorCodes) == ["protected_path"], "\(line) \(bad): \(run.errorCodes) \(run.stderr)")
            #expect(run.exit == 2, "\(line) \(bad)")
            #expect(world.system.allPaths == before, "\(line) \(bad)")
            #expect(world.system.readFile(second) == bytes, "\(line) \(bad)")
            // the second installation's Python in the tree that is left, then the plain line
            #expect(Self.probes(world).map { $0.argv[0] } == [Self.otherPython, FakeWorld.python], "\(line) \(bad)")
            #expect(world.system.spawned.isEmpty)
        }
        // nothing else is refused for it: a folder outside both prefixes is written, with the option's own error
        let world = Self.world()
        let run = world.run(["info", "--python", Self.otherPython, "--output", "/work/e.json"] + bad)
        #expect(!run.errorCodes.contains("protected_path"), "\(bad): \(run.stderr)")
        #expect(world.system.readFile("/work/e.json") == run.data, "\(bad)")
    }

    /// A correct --repo beside a --python that names nothing, started outside every tools tree: the walk finds no
    /// tree, the line's own does, and PATH's Python is asked there.
    @Test func aCorrectRepoBesideAPythonThatNamesNothing() {
        for output in [["--output", Self.custom + "/lib/e.json"], ["--overwrite", "--output", Self.library]] {
            var world = Self.world()
            world.system.addDirectory("/elsewhere")
            world.cwd = "/elsewhere"
            let before = world.system.allPaths
            let line = ["info", "--python", "/opt/py/bin/pythn3", "--repo", FakeWorld.repo]
            let run = world.run(line + output)
            #expect(Set(run.errorCodes) == ["protected_path"], "\(output): \(run.errorCodes) \(run.stderr)")
            #expect(world.system.allPaths == before, "\(output)")
            #expect(Self.probes(world).map { $0.argv[0] } == [FakeWorld.python], "\(output)")
            #expect(Self.probes(world).map(\.cwd) == [FakeWorld.repo], "\(output)")
        }
    }

    /// The probe of the line without its options respects a stop: cut short, it lets nothing through (130), and the
    /// file is not written.
    @Test func aStopDuringTheProbeWithoutTheOptionsLetsNothingThrough() {
        let envelope = Self.custom + "/envelope.json"
        // the only probe of this line is the one without --repo
        let world = Self.world()
        world.system.update {
            $0.signalDuringSnippet = (FdtdSnippets.probe, SIGINT)
            $0.killAfterStop = true
        }
        let run = world.run(["load", "--seconds", "1", "--repo", "/nope", "--output", envelope])
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(!world.system.fileExists(envelope))
        #expect(run.stdout.contains("\"interrupted\""))
        // the line's own probe answered, the stop ends the second one: a folder that neither names is not written
        let later = Self.world()
        later.system.addDirectory("/work/out")
        later.system.update {
            $0.signalAfterSnippet = (FdtdSnippets.probe, SIGINT)
            $0.killAfterStop = true
        }
        let second = later.run(["load", "--seconds", "1", "--python", Self.otherPython, "--output", "/work/out/e.json"])
        #expect(second.exit == 130, "\(second.stderr)")
        #expect(second.errorCodes.allSatisfy { $0 == "interrupted" } && !second.errorCodes.isEmpty)
        #expect(!later.system.fileExists("/work/out/e.json"))
        #expect(Self.probes(later).count == 2)
        // ... and one that the answered probe names is refused as ever
        let known = Self.world()
        known.system.update {
            $0.signalAfterSnippet = (FdtdSnippets.probe, SIGINT)
            $0.killAfterStop = true
        }
        let refused = known.run(["load", "--seconds", "1", "--python", Self.otherPython, "--output",
                                 Self.other + "/e.json"])
        #expect(refused.errorCodes.contains("protected_path"), "\(refused.stderr)")
        #expect(!known.system.fileExists(Self.other + "/e.json"))
    }

    // MARK: An option that resolves

    /// A --python with a library of its own adds that prefix; the prefix of PATH's Python stays protected beside
    /// it. The second probe changes nothing the command uses or records.
    @Test func anOptionAddsItsFoldersToThoseOfTheDefaults() throws {
        for line in [["info"], ["bench", "patch", "--config", "multithreaded:4", "--dry-run"]] {
            for folder in [Self.custom, Self.other] {
                let world = Self.world()
                let before = world.system.allPaths
                let run = world.run(line + ["--python", Self.otherPython, "--output", folder + "/e.json"])
                #expect(run.errorCodes.contains("protected_path"), "\(line) \(folder): \(run.stderr)")
                #expect(world.system.allPaths == before, "\(line) \(folder)")
            }
        }
        let world = Self.world()
        let session = FdtdSession(context: world.context(stdout: TextCollector(), stderr: TextCollector()),
                                  command: .info, arguments: ["info"])
        var common = FdtdCommonOptions()
        common.python = Self.otherPython
        try session.begin(common)
        // the command's own discovery first, then the list: the second probe leaves no trace in what it found
        #expect(try session.installedLibraryDir() == Self.other + "/lib")
        let before = try FdtdJSON.encode(session.envelope)
        let roots = session.protectedFolders().roots.map(\.path)
        #expect(roots.contains(Self.custom) && roots.contains(Self.other), "\(roots)")
        #expect(try FdtdJSON.encode(session.envelope) == before)
        #expect(session.memo.python == Self.otherPython && session.memo.probes.count == 1)
        #expect(try session.installedLibraryDir() == Self.other + "/lib")
        #expect(Self.probes(world).map { $0.argv[0] } == [Self.otherPython, FakeWorld.python])
    }

    /// The two probes are told apart by the Python as named, not by its real path: a venv's python3 is a link to
    /// its base Python and still loads its own packages. Such a --python that is a link to PATH's python is asked,
    /// PATH's python too, and both prefixes are protected. The link lies beside PATH's python, so that the name is
    /// the only difference between the two children (the child's PATH starts with the Python's folder).
    @Test func aPythonThatIsALinkToPathsPythonIsAnotherPython() {
        let venv = FdtdPaths.dirname(FakeWorld.python) + "/python3-venv"
        func world() -> FakeWorld {
            let world = Self.world()
            world.system.addLink(venv, to: FakeWorld.python)
            world.system.update { b in
                b.probeLibrariesOf[venv] = FdtdLibraries.fileNames.map { Self.other + "/lib/" + $0 }
            }
            return world
        }
        #expect(world().system.realPath(venv) == world().system.realPath(FakeWorld.python))
        let probe = { (python: String) in
            FdtdInstalledProbe(python: python, repo: FakeWorld.repo, environment: ["PATH": "/opt/py/bin"],
                               system: world().system)
        }
        #expect(probe(venv) != probe(FakeWorld.python) && probe(venv) == probe(venv))
        for target in [Self.custom + "/e.json", Self.library, Self.other + "/e.json",
                       Self.other + "/lib/libopenEMS.0.dylib"] {
            for overwrite in [[], ["--overwrite"]] {
                let world = world()
                let before = world.system.allPaths
                let run = world.run(["info", "--python", venv, "--output", target] + overwrite)
                #expect(Set(run.errorCodes) == ["protected_path"], "\(target): \(run.errorCodes) \(run.stderr)")
                #expect(run.exit == 2 && world.system.allPaths == before, "\(target) \(overwrite)")
                #expect(Self.probes(world).map { $0.argv[0] } == [venv, FakeWorld.python], "\(target)")
            }
        }
        // outside both prefixes the line is an ordinary info, still with the two probes
        let world = world()
        let run = world.run(["info", "--python", venv, "--output", "/work/e.json"])
        #expect(run.exit == 0 && world.system.readFile("/work/e.json") == run.data, "\(run.stderr)")
        #expect(Self.probes(world).map { $0.argv[0] } == [venv, FakeWorld.python])
    }

    /// A line whose options name what discovery finds without them pays no second probe; neither does a line
    /// without any of them. An option that names something else costs one more probe.
    @Test func optionsThatNameTheDefaultsPayNoSecondProbe() {
        let same = ["--repo", FakeWorld.repo, "--python", FakeWorld.python, "--snaps", FakeWorld.snaps]
        let output = ["--output", "/work/e.json"]
        let plain = Self.world().run(["info"])
        for line in [["info"], ["info"] + same, ["info", "--snaps", "/elsewhere"]] {
            let world = Self.world()
            let run = world.run(line + output)
            #expect(world.system.fileExists("/work/e.json"), "\(line): \(run.stderr)")
            #expect(Self.probes(world).count == 1, "\(line)")
            if line.first == "info", !line.contains("/elsewhere") {
                #expect(run.result == plain.result && run.envelope["python"] == plain.envelope["python"], "\(line)")
            }
        }
        // --rfsim is the same child with or without $RFSIM_PATH: `import openEMS` does not read the toolkit
        var named = Self.world()
        named.environment["RFSIM_PATH"] = FakeWorld.rfsim
        _ = named.run(["info", "--rfsim", FakeWorld.rfsim] + output)
        #expect(Self.probes(named).count == 1)
        let toolkit = Self.world()
        let run = toolkit.run(["info", "--rfsim", FakeWorld.rfsim] + output)
        #expect(Self.probes(toolkit).map { $0.environment["RFSIM_PATH"] } == [FakeWorld.rfsim])
        #expect(run.envelope["python"] == plain.envelope["python"])
        #expect(run.result["installed"] == plain.result["installed"])
        let dry = ["--dry-run", "--allow-concurrent", "--rfsim", FakeWorld.rfsim]
        for line in [["bench", "kgcpw", "--config", "multithreaded:4"], ["e2e", "gcpw"]] {
            let everyday = Self.world()
            let planned = everyday.run(line + dry + ["--output", "/work/e.json"])
            #expect(planned.exit == 0, "\(line): \(planned.stderr)")
            #expect(Self.probes(everyday).count == 1, "\(line)")
        }
        // --repo that names the walk's tree through a link, or by another spelling, is the same tree
        for tree in ["/work/treelink", "/work/../work/emsKit", FakeWorld.repo + "/"] {
            let linked = Self.world()
            linked.system.addLink("/work/treelink", to: FakeWorld.repo)
            let through = linked.run(["info", "--repo", tree] + output)
            #expect(linked.system.fileExists("/work/e.json"), "\(tree): \(through.stderr)")
            #expect(Self.probes(linked).count == 1, "\(tree)")
        }
        // another tree, another Python and another PYTHONPATH each stay a second child
        let copy = Self.world()
        for marker in FdtdDiscovery.markers {
            copy.system.addFile("/work/copy/" + marker, copy.system.readFile(FakeWorld.repo + "/" + marker) ?? Data())
        }
        _ = copy.run(["info", "--repo", "/work/copy"] + output)
        #expect(Self.probes(copy).map(\.cwd) == ["/work/copy", FakeWorld.repo])
        // a line that did not parse probes nothing at all, with --output or without
        for tail in [[], output] {
            let usage = Self.world()
            _ = usage.run(["bench", "patch", "--frob", "--python", Self.otherPython] + tail)
            #expect(usage.system.captures.isEmpty && !usage.system.fileExists("/work/e.json"), "\(tail)")
        }
    }

    /// A parsed line names its discovery options one by one (the union rule reads them from here).
    @Test func theDiscoveryOptionsOfAParsedLine() throws {
        let parsed = try FdtdOptions.parse(.info, ["--snaps", "/s", "--python", "/p"])
        #expect(parsed.common.discoveryGiven == ["python", "snaps"])
        #expect(try FdtdOptions.parse(.info, []).common.discoveryGiven.isEmpty)
    }
}

extension DiscoveryOptionTests {
    // MARK: The library folders of the line

    static let folder = "/work/dir"
    static let build = "/work/build"

    /// /work/dir holds no library (a file in a subfolder), /work/build holds a complete one.
    static func libraryWorld() -> FakeWorld {
        let world = FakeWorld()
        world.system.addDirectory(folder + "/cgX")
        world.system.addFile(folder + "/cgX/e.json", "old\n")
        world.system.addLibraryFolder(build, FakeLibrary.cg29.files)
        return world
    }

    /// A slip makes a folder a SNAP (an option left without its value takes the next option as its value, or
    /// `snaps` without its dashes): the line parses, the folder is no library and the command ends with exit 2. Its
    /// --output inside that folder is refused all the same, with and without --overwrite, in a dry run too.
    @Test func aFolderThatASlipMakesALibraryIsProtected() {
        let lines: [[String]] = [
            ["check", "cg29", "--tag", "t", "--stock", "-snaps", Self.folder],
            ["check", "cg29", "snaps", Self.folder, "--tag", "t"],
            ["check", "cg29", "snaps", "/work/emsKit/../dir/", "--tag", "t"],
        ]
        for line in lines {
            for target in [Self.folder + "/cgX/e.json", Self.folder + "/new.json", Self.folder + "/cgX"] {
                for extra in [[], ["--overwrite"], ["--dry-run"], ["--overwrite", "--dry-run"]] {
                    let world = Self.libraryWorld()
                    let before = world.system.allPaths
                    let run = world.run(line + ["--output", target] + extra)
                    let what = "\(line) \(target) \(extra): \(run.errorCodes) \(run.stderr)"
                    #expect(run.exit == 2 && Set(run.errorCodes) == ["protected_path"], "\(what)")
                    #expect(run.issue("errors", "protected_path")?["field"]?.string == "--output", "\(what)")
                    #expect(world.system.allPaths == before, "\(what)")
                    #expect(world.system.readFile(Self.folder + "/cgX/e.json") == Data("old\n".utf8), "\(what)")
                    #expect(world.system.spawned.isEmpty && Self.probes(world).count <= 1, "\(what)")
                }
            }
        }
    }

    /// Every way a line names a library by its path: an --output inside the folder is refused (2), one beside it is
    /// not, whether the folder holds a library (/work/build) or not (/work/dir).
    @Test func everyLibraryNamedByItsPathIsProtected() throws {
        for lib in [Self.build, Self.folder] {
            let lines: [[String]] = [
                ["bench", "patch", "--config", lib + "@multithreaded:4"],
                ["bench", "patch", "--config", "multithreaded:4", "--config", lib + "@multithreaded:8#OPENEMS_QOS=0"],
                ["ab", "patch", "--config", "cg29@multithreaded:4", "--config", lib + "@multithreaded:4"],
                ["check", lib, "--tag", "t"], ["check", "cg29", "--tag", "t", "--stock", lib],
                ["check", "cg29", "--tag", "t", "--extra", lib + "@multithreaded:4"],
                ["validate", "--lib", lib], ["e2e", "gcpw", "--lib", lib], ["run", "/work/board.py", "--lib", lib],
                ["debye-check", lib], ["debye-check", "cg29", "--ref", lib], ["diamond-check", lib],
                ["info", "--lib", lib],
            ]
            for line in lines {
                // info runs nothing and has no dry run
                let dry = line[0] == "info" ? [] : ["--dry-run"]
                for extra in [dry, dry + ["--overwrite"]] {
                    let world = Self.libraryWorld()
                    world.system.addFile(lib + "/e.json", "old\n")
                    let before = world.system.allPaths
                    let inside = world.run(line + ["--output", lib + "/e.json"] + extra)
                    let what = "\(line) \(extra): \(inside.errorCodes) \(inside.stderr)"
                    #expect(inside.exit == 2 && Set(inside.errorCodes) == ["protected_path"], "\(what)")
                    #expect(world.system.allPaths == before, "\(what)")
                    #expect(world.system.readFile(lib + "/e.json") == Data("old\n".utf8), "\(what)")
                }
                let world = Self.libraryWorld()
                let beside = world.run(line + ["--output", "/work/e.json"] + dry)
                #expect(!beside.errorCodes.contains("protected_path"), "\(line): \(beside.stderr)")
                #expect(world.system.fileExists("/work/e.json"), "\(line)")
            }
        }
        // the LIB of a CFG ends at the last '@' before the first '#' (spec 5.2): a folder with '@' in its path counts
        let at = "/work/a@b/lib"
        let parsed = try FdtdOptions.parse(.bench, ["patch", "--config", at + "@sse#OPENEMS_QOS=0"])
        #expect(parsed.options.librarySpecs == [at])
        let odd = Self.libraryWorld()
        odd.system.addDirectory(at)
        let inside = odd.run(["bench", "patch", "--config", at + "@multithreaded:4", "--output", at + "/e.json",
                              "--dry-run"])
        #expect(inside.exit == 2 && inside.errorCodes.contains("protected_path"), "\(inside.stderr)")
        #expect(!odd.system.fileExists(at + "/e.json"))
        // the everyday line: a build folder as the library, the envelope beside it
        let world = Self.libraryWorld()
        let bench = ["bench", "patch", "--config", Self.build + "@multithreaded:4", "--dry-run"]
        #expect(world.run(bench + ["--output", Self.build + "/e.json"]).errorCodes == ["protected_path"])
        let fine = world.run(bench + ["--output", "/work/e.json"])
        #expect(fine.exit == 0 && fine.errorCodes.isEmpty, "\(fine.stderr)")
    }

    /// The same two slips with DIR as a bare relative name (`--snaps mysnaps` meant): the name is read as a snapshot
    /// name, so the folder of that name in the working directory is protected too and --output inside it is refused.
    @Test func aBareFolderThatASlipMakesALibraryIsProtected() {
        let dir = FakeWorld.repo + "/mysnaps"
        let lines: [[String]] = [
            ["check", "cg29", "--tag", "t", "--stock", "-snaps", "mysnaps"],
            ["check", "cg29", "snaps", "mysnaps", "--tag", "t"],
        ]
        for line in lines {
            for target in ["mysnaps/slip.json", "./mysnaps/cgX/e.json", dir + "/new.json", "mysnaps/cgX"] {
                for extra in [[], ["--overwrite"], ["--dry-run"], ["--overwrite", "--dry-run"]] {
                    let world = Self.bareWorld("mysnaps")
                    let before = world.system.allPaths
                    let run = world.run(line + ["--output", target] + extra)
                    let what = "\(line) \(target) \(extra): \(run.errorCodes) \(run.stderr)"
                    #expect(run.exit == 2 && Set(run.errorCodes) == ["protected_path"], "\(what)")
                    #expect(run.issue("errors", "protected_path")?["field"]?.string == "--output", "\(what)")
                    #expect(world.system.allPaths == before, "\(what)")
                    #expect(world.system.readFile(dir + "/cgX/e.json") == Data("old\n".utf8), "\(what)")
                    #expect(world.system.spawned.isEmpty && Self.probes(world).count <= 1, "\(what)")
                }
            }
        }
    }

    /// The bare-name rule adds a root only for a folder that exists in the working directory, and never for the
    /// words that are no snapshot name; an --output elsewhere is written as before when ./NAME exists.
    @Test func aSnapshotNameProtectsOnlyAFolderOfThatNameInTheWorkingDirectory() throws {
        let name = "a folder named like a library of this line"
        func named(_ world: FakeWorld, _ libraries: [String]) throws -> [String] {
            let session = FdtdSession(context: world.context(stdout: TextCollector(), stderr: TextCollector()),
                                      command: .check, arguments: ["check"])
            try session.begin(FdtdCommonOptions(), libraries: libraries)
            return session.protectedFolders().roots.filter { $0.name == name }.map(\.path)
        }
        // no folder of that name in the working directory: nothing extra
        #expect(try named(Self.libraryWorld(), ["cg29", "stock", "mysnaps", "installed"]).isEmpty)
        // the folder exists: it is listed; `installed`, the empty word, `.`, `..` and '-' names add nothing
        let world = Self.bareWorld("cg29")
        for word in ["installed", "-x"] { world.system.addDirectory(FakeWorld.repo + "/" + word) }
        #expect(try named(world, ["cg29", "installed", "", ".", "..", "-x", "nope"]) == [FakeWorld.repo + "/cg29"])
        for word in ["installed", "", ".", "..", "-x", "a/b", "./cg29"] {
            #expect(!FdtdLibraries.isSnapshotName(word), "\(word)")
        }
        for word in ["cg29", "stock", "~", "a@b"] { #expect(FdtdLibraries.isSnapshotName(word), "\(word)") }
        // an envelope elsewhere is written as before, inside ./cg29 it is refused
        let bench = ["bench", "patch", "--config", "cg29@multithreaded:4", "--dry-run"]
        let fine = Self.bareWorld("cg29").run(bench + ["--output", "/work/e.json"])
        #expect(fine.exit == 0 && fine.errorCodes.isEmpty, "\(fine.stderr)")
        let beside = Self.bareWorld("cg29")
        let besideRun = beside.run(bench + ["--output", "cg29.json"])
        #expect(besideRun.exit == 0 && beside.system.fileExists(FakeWorld.repo + "/cg29.json"), "\(besideRun.stderr)")
        let inside = Self.bareWorld("cg29")
        #expect(inside.run(bench + ["--output", "cg29/e.json"]).errorCodes == ["protected_path"])
        #expect(!inside.system.fileExists(FakeWorld.repo + "/cg29/e.json"))
        // without a folder of that name the same line is not a protected path (the folder is only missing)
        let plain = Self.libraryWorld().run(bench + ["--output", "cg29/e.json"])
        #expect(!plain.errorCodes.contains("protected_path"), "\(plain.stderr)")
    }

    /// libraryWorld with a folder `name` in the working directory that holds no library (a file in a subfolder).
    static func bareWorld(_ name: String) -> FakeWorld {
        let world = libraryWorld()
        world.system.addDirectory(FakeWorld.repo + "/" + name + "/cgX")
        world.system.addFile(FakeWorld.repo + "/" + name + "/cgX/e.json", "old\n")
        return world
    }

    /// The other write targets follow the same list: a record, a table folder and an --out-dir inside a library
    /// folder of the line, or holding it.
    @Test func theOtherTargetsOfALineWithALibraryFolder() {
        let lines: [([String], String)] = [
            (["ab", "patch", "--config", "cg29@multithreaded:4", "--config", Self.build + "@multithreaded:4",
              "--record", Self.build + "/ab.txt"], "--record"),
            (["validate", "--lib", Self.build, "--tag", "t", "--results", Self.build], "--results"),
            (["e2e", "gcpw", "--lib", Self.build, "--rfsim", FakeWorld.rfsim, "--out-dir", Self.build + "/out"],
             "--out-dir"),
            (["e2e", "gcpw", "--lib", Self.build, "--rfsim", FakeWorld.rfsim, "--out-dir", "/work"], "--out-dir"),
            (["run", "/work/board.py", "--lib", Self.build, "--runs", Self.build + "/runs"], "--runs"),
        ]
        for (line, field) in lines {
            let world = Self.libraryWorld()
            world.system.addFile("/work/board.py", "pass\n")
            let before = world.system.allPaths
            let run = world.run(line + ["--dry-run"])
            let what = "\(line): \(run.errorCodes) \(run.stderr)"
            #expect(run.exit == 2 && Set(run.errorCodes) == ["protected_path"], "\(what)")
            #expect(run.issue("errors", "protected_path")?["field"]?.string == field, "\(what)")
            #expect(world.system.allPaths == before && world.system.spawned.isEmpty, "\(what)")
        }
    }

    /// A path that is no folder protects nothing: the usual library_not_found, and the envelope is written where
    /// --output says, also below the missing name's parent. A snapshot name adds no folder either.
    @Test func aLibraryPathThatIsNoFolderProtectsNothing() throws {
        for lib in ["/work/nope", "/work/dir/cgX/e.json", "/work/dir/nope"] {
            let world = Self.libraryWorld()
            let run = world.run(["validate", "--lib", lib, "--output", "/work/dir/new.json", "--dry-run"])
            #expect(run.exit == 2 && run.errorCodes == ["library_not_found"], "\(lib) \(run.stderr)")
            #expect(world.system.fileExists("/work/dir/new.json"), "\(lib)")
        }
        let world = Self.libraryWorld()
        let session = FdtdSession(context: world.context(stdout: TextCollector(), stderr: TextCollector()),
                                  command: .check, arguments: ["check"])
        let parsed = try FdtdOptions.parse(.check, ["cg29", Self.folder, "./nope", "--tag", "t", "--stock", "stock",
                                                    "--extra", Self.build + "@sse#OPENEMS_QOS=0"])
        #expect(parsed.options.librarySpecs == ["cg29", Self.folder, "./nope", "stock", Self.build])
        try session.begin(parsed.common, libraries: parsed.options.librarySpecs)
        let named = session.protectedFolders().roots.filter { $0.name == "a library folder of this line" }
        #expect(named.map { $0.path } == [Self.folder, Self.build])
    }
}

@Suite struct PathOptionTests {
    static let ab = ["ab", "patch", "--config", "cg29@multithreaded:4", "--config", "cg29@multithreaded:8"]

    /// pathValued is the list of the options that take a DIR, a FILE or a PATH, over every command.
    @Test func everyPathOptionIsListed() {
        var paths: Set<String> = []
        for command in FdtdCommandName.allCases {
            for (name, kind) in FdtdOptions.spec(for: command).options where kind != .flag {
                if ["DIR", "FILE", "PATH"].contains(FdtdOptions.metavar(name)) { paths.insert(name) }
            }
        }
        #expect(paths == FdtdOptions.pathValued)
        #expect(paths == ["repo", "python", "snaps", "rfsim", "runs", "output", "hosts", "results", "record",
                          "out-dir", "build"])
    }

    /// An empty value (an unset shell variable) would stand for the working directory: a usage error for every
    /// option that takes a path, before anything is probed.
    @Test func anEmptyPathIsAUsageError() {
        let bench = ["bench", "patch", "--config", "cg29@multithreaded:4"]
        let lines: [(line: [String], option: String)] = [
            (["info"], "repo"), (["info"], "python"), (["info"], "snaps"), (["info"], "rfsim"), (["info"], "output"),
            (["info"], "build"), (["load"], "output"), (bench, "runs"), (bench + ["--tag", "t"], "results"),
            (bench, "hosts"), (["validate", "--tag", "t"], "results"), (Self.ab, "record"),
            (Self.ab + ["--append"], "record"), (Self.ab, "runs"),
            (["e2e", "gcpw", "--rfsim", FakeWorld.rfsim], "out-dir"), (["e2e", "gcpw"], "runs"),
            (["e2e", "gcpw"], "rfsim"), (["run", "/work/board.py"], "runs"), (["check", "cg29", "--tag", "t"], "repo"),
            (["debye-check", "cg29"], "python"), (["diamond-check", "cg29"], "snaps"),
        ]
        for (line, option) in lines {
            for dry in [[], ["--dry-run"]] where dry.isEmpty || !["info", "load"].contains(line[0]) {
                let world = FakeWorld()
                let before = world.system.allPaths
                let run = world.run(line + ["--" + option, ""] + dry)
                #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(line) --\(option): \(run.stderr)")
                let issue = run.issue("errors", "usage")
                #expect(issue?["field"]?.string == "--" + option, "\(line) --\(option)")
                #expect(issue?["message"]?.string?.contains("the value is empty") == true, "\(line) --\(option)")
                #expect(world.system.allPaths == before, "\(line) --\(option)")
                #expect(world.system.captures.isEmpty && world.system.spawned.isEmpty, "\(line) --\(option)")
            }
        }
    }

    /// ab's --record goes through --output's checks: a folder is a usage error whatever --append says (abtest.py
    /// would fail to open it only after all rounds), and its folder must exist.
    @Test func aRecordThatIsAFolderIsRefused() {
        for folder in ["/work/rec", "/work/full"] {
            for extra in [[], ["--append"], ["--dry-run"], ["--append", "--dry-run"]] {
                let world = FakeWorld()
                world.system.addDirectory("/work/rec")
                world.system.addFile("/work/full/old.txt", "x\n")
                let before = world.system.allPaths
                let run = world.run(Self.ab + ["--record", folder] + extra)
                #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(folder) \(extra): \(run.stderr)")
                let issue = run.issue("errors", "usage")
                #expect(issue?["field"]?.string == "--record", "\(folder) \(extra)")
                #expect(issue?["message"]?.string?.contains("is a folder") == true, "\(folder) \(extra)")
                #expect(world.system.allPaths == before && world.system.spawned.isEmpty, "\(folder) \(extra)")
            }
        }
        let world = FakeWorld()
        world.system.addDirectory("/work/rec")
        let missing = world.run(Self.ab + ["--record", "/work/none/ab.txt", "--dry-run"])
        #expect(missing.exit == 2 && missing.errorCodes == ["folder_missing"], "\(missing.stderr)")
        #expect(missing.issue("errors", "folder_missing")?["field"]?.string == "--record")
        let fine = world.run(Self.ab + ["--record", "/work/rec/ab.txt", "--dry-run"])
        #expect(fine.exit == 0, "\(fine.stderr)")
        #expect(fine.result["recordFile"]?.string == "/work/rec/ab.txt")
        // a folder in a protected folder is named as that first, as for --output
        let inside = world.run(Self.ab + ["--record", FakeWorld.snaps + "/cg29", "--dry-run"])
        #expect(inside.errorCodes == ["protected_path"], "\(inside.stderr)")
    }

    /// A folder where the other options take a file: each is refused before anything runs.
    @Test func aFolderWhereAFileIsTaken() {
        let world = FakeWorld()
        world.system.addDirectory("/work/dir")
        let bench = ["bench", "patch", "--config", "cg29@multithreaded:4", "--dry-run"]
        let output = world.run(bench + ["--output", "/work/dir", "--overwrite"])
        #expect(output.exit == 64 && output.errorCodes == ["usage"], "\(output.stderr)")
        let python = world.run(bench + ["--python", "/work/dir"])
        #expect(python.exit == 3 && python.errorCodes == ["python_not_found"], "\(python.stderr)")
        let hosts = world.run(["validate", "--dry-run", "--hosts", "/work/dir"])
        #expect(hosts.exit == 2 && hosts.errorCodes == ["hosts_file_missing"], "\(hosts.stderr)")
        let script = world.run(["run", "/work/dir", "--lib", "cg29", "--dry-run"])
        #expect(script.exit == 2 && script.errorCodes == ["script_not_found"], "\(script.stderr)")
        #expect(world.system.spawned.isEmpty && world.system.isDirectory("/work/dir"))
    }
}
