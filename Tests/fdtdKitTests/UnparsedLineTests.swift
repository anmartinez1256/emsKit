// SPDX-License-Identifier: GPL-3.0-or-later

// PLAN 4.1, the rule that closed the guard attack of 2026-11-10 (CHANGELOG.md): a line that did not parse writes no
// file, renames nothing, probes nothing and starts no child. Its envelope goes to stdout, and a stderr line says that
// --output is not written. Nothing of such a line is read back, so no spelling of an option can matter.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct UnparsedLineTests {
    static let custom = OpenItemTests.custom
    static let ownSnaps = "/custom/snaps"

    /// One line per command that parses as it stands.
    static let lines: [[String]] = [
        ["info"], ["load"], ["bench", "patch", "--config", "multithreaded:4"],
        ["ab", "patch", "--config", "cg29@multithreaded:4", "--config", "stock@multithreaded:4"],
        ["check", "cg29", "--tag", "t", "--lite"], ["validate"], ["debye-check", "cg29"], ["diamond-check", "cg29"],
        ["e2e", "gcpw"], ["run", "/work/board.py"],
    ]

    /// A new file, an existing one, and files inside each kind of protected folder: the prefix that PATH's Python
    /// names, the default prefix, the default snapshot folder, and a snapshot folder that only the line names.
    static let targets = [
        "/work/out/new.json", "/work/out/old.json", custom + "/new.json", custom + "/lib/libopenEMS.0.dylib",
        FakeWorld.installed + "/libnf2ff.0.dylib", FakeWorld.snaps + "/cg29/libopenEMS.0.dylib",
        FakeWorld.snaps + "/new.json", ownSnaps + "/cg29/libopenEMS.0.dylib", ownSnaps + "/cg29/new.json",
    ]

    /// What makes the line a usage error: an unknown option, and the spellings of a discovery option that the
    /// attack rounds used (other letter case, a longer or shorter name, --name=VALUE, one dash, given twice, no
    /// value).
    static let unknown: [[String]] = [
        ["--frob"], ["--SNAPS", ownSnaps], ["--snapshots", ownSnaps], ["--snapshot", ownSnaps],
        ["--snaps-dir", ownSnaps], ["--snap", ownSnaps], ["--snaps=" + ownSnaps], ["-snaps", ownSnaps],
        ["--snaps", ownSnaps, "--snaps", ownSnaps], ["--snaps"], ["--snaps", ""],
        ["--py", DiscoveryOptionTests.otherPython], ["--python-path", DiscoveryOptionTests.otherPython],
        ["--PYTHON", DiscoveryOptionTests.otherPython], ["--python=" + DiscoveryOptionTests.otherPython],
        ["-python", DiscoveryOptionTests.otherPython], ["--pyton", DiscoveryOptionTests.otherPython],
        ["--python", DiscoveryOptionTests.otherPython, "--python", FakeWorld.python],
        ["--repo=" + FakeWorld.repo], ["--repo", FakeWorld.repo, "--repo", FakeWorld.repo], ["--repo", ""],
        ["-rfsim=" + FakeWorld.rfsim], ["--rfsim", FakeWorld.rfsim, "--rfsim", FakeWorld.rfsim],
        // a correct discovery option beside the unknown one changes nothing either
        ["--frob", "--snaps", ownSnaps, "--python", DiscoveryOptionTests.otherPython],
    ]

    static func world() -> FakeWorld {
        let world = DiscoveryOptionTests.world()
        world.system.addLibraryFolder(ownSnaps + "/cg29", FakeLibrary.cg29.files)
        world.system.addFile("/work/out/old.json", "old\n")
        world.system.addFile("/work/board.py", "import openEMS\n")
        return world
    }

    /// Every path with its bytes.
    static func contents(_ world: FakeWorld) -> [String: Data?] {
        Dictionary(uniqueKeysWithValues: world.system.allPaths.map { ($0, world.system.readFile($0)) })
    }

    /// Runs `line` and expects what rule 1 promises.
    static func expectNothingHappens(_ line: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        let world = world()
        let before = contents(world)
        let run = world.run(line)
        let text = "\(line): \(run.errorCodes) \(run.stderr)"
        let comment = Comment(rawValue: text)
        #expect(run.exit == 64, comment, sourceLocation: sourceLocation)
        #expect(run.errorCodes == ["usage"] && run.warningCodes.isEmpty, comment, sourceLocation: sourceLocation)
        #expect(contents(world) == before, comment, sourceLocation: sourceLocation)
        #expect(world.system.captures.isEmpty && world.system.spawned.isEmpty, comment, sourceLocation: sourceLocation)
        #expect(world.system.caffeinated.isEmpty && world.signals.installs == 0, comment,
                sourceLocation: sourceLocation)
        // the envelope is on stdout, whole, and names no output
        let printed = try? FdtdJSON.decode(FdtdJSONValue.self, from: Data(run.stdout.utf8))
        #expect(printed != nil && printed == run.envelope, comment, sourceLocation: sourceLocation)
        #expect(run.envelope["schema"]?.string == "emskit.fdtd.\(line[0])/1", comment, sourceLocation: sourceLocation)
        #expect(run.envelope["outputs"]?.array?.isEmpty == true, comment, sourceLocation: sourceLocation)
        #expect(run.stderr.contains("--output is not written: the line was not understood"), comment,
                sourceLocation: sourceLocation)
    }

    /// Each of the ten commands, an unknown option, and --output FILE with and without --overwrite: FILE new,
    /// existing, and inside a protected folder.
    @Test(arguments: lines)
    func anUnknownOptionWithOutputChangesNothing(line: [String]) {
        for target in Self.targets {
            for overwrite in [[], ["--overwrite"]] {
                Self.expectNothingHappens(line + ["--frob", "--output", target] + overwrite)
            }
        }
        // the order on the line does not matter
        Self.expectNothingHappens(line + ["--overwrite", "--output", Self.targets[3], "--frob"])
    }

    /// The spellings that earlier versions tried to read a discovery option from: none is read now, so each ends
    /// the same way, whatever folder it would have named.
    @Test(arguments: lines)
    func noSpellingOfADiscoveryOptionIsReadBack(line: [String]) {
        let library = Self.ownSnaps + "/cg29/libopenEMS.0.dylib"
        let second = DiscoveryOptionTests.other + "/lib/libopenEMS.0.dylib"
        for tail in Self.unknown {
            // the folder that the token would have named: the snapshots for one kind, the second prefix otherwise
            let named = tail.contains { $0.lowercased().contains("py") } ? second : library
            Self.expectNothingHappens(line + ["--overwrite", "--output", named] + tail)
            Self.expectNothingHappens(line + tail + ["--output", Self.ownSnaps + "/cg29/new.json"])
        }
    }

    /// Tokens after `--`: a usage error by themselves on every command but run, where they are the script's and a
    /// usage error before them still stops the line.
    @Test(arguments: lines)
    func tokensAfterTheDoubleDash(line: [String]) {
        let after = ["--", "--snaps", Self.ownSnaps, "--python", DiscoveryOptionTests.otherPython]
        for target in [Self.ownSnaps + "/cg29/libopenEMS.0.dylib", Self.ownSnaps + "/cg29/new.json"] {
            for overwrite in [[], ["--overwrite"]] {
                let frob = line[0] == "run" ? ["--frob"] : []
                Self.expectNothingHappens(line + frob + ["--output", target] + overwrite + after)
            }
        }
    }

    /// check.sh's and the validation suite's bad --tag is found by the parser too (exit 2): the same rule.
    @Test func aTagThatTheParserRefusesWritesNoFile() {
        for line in [["check", "cg29", "--tag", "a/b", "--lite"], ["validate", "--tag", "-x"]] {
            let world = Self.world()
            let before = Self.contents(world)
            let run = world.run(line + ["--overwrite", "--output", "/work/out/old.json"])
            #expect(run.exit == 2 && run.errorCodes == ["tag_invalid"], "\(line): \(run.stderr)")
            #expect(Self.contents(world) == before && world.system.captures.isEmpty, "\(line)")
            #expect(run.stdout.contains("\"tag_invalid\"") && run.stderr.contains("--output is not written"))
        }
    }

    /// The control: the same lines without the unknown option parse, and the union rule of section 10.2 decides.
    @Test func theSameLinesParsedFollowTheUnionRule() {
        for line in [["info"], ["bench", "patch", "--config", "multithreaded:4", "--dry-run"]] {
            let refused = Self.world()
            let before = Self.contents(refused)
            let inside = refused.run(line + ["--snaps", Self.ownSnaps, "--overwrite", "--output",
                                             Self.ownSnaps + "/cg29/libopenEMS.0.dylib"])
            #expect(inside.exit == 2 && Set(inside.errorCodes) == ["protected_path"], "\(line): \(inside.stderr)")
            #expect(Self.contents(refused) == before, "\(line)")
            let written = Self.world()
            let run = written.run(line + ["--snaps", Self.ownSnaps, "--output", "/work/out/new.json"])
            #expect(run.exit == 0, "\(line): \(run.stderr)")
            #expect(written.system.readFile("/work/out/new.json") == run.data, "\(line)")
            #expect(run.stdout.isEmpty && written.signals.installs == 1, "\(line)")
        }
    }
}
