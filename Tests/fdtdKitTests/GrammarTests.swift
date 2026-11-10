// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 GrammarTests: the README examples parse; the usage errors exit 64 with an envelope and the hint; no command
// or an unknown one prints usage on stderr with no envelope.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct GrammarTests {
    /// The `    emskit fdtd ...` lines of the README section.
    static func readmeExamples() throws -> [[String]] {
        let readme = try TestPaths.text(TestPaths.repo + "/README.md")
        let section = try #require(TextRules.section(of: readme))
        return section.split(separator: "\n").compactMap { line -> [String]? in
            guard line.hasPrefix("    emskit fdtd ") else { return nil }
            return line.dropFirst("    emskit fdtd ".count).split(separator: " ").map(String.init)
        }
    }

    @Test func everyUsageExampleParses() throws {
        let examples = try Self.readmeExamples()
        #expect(examples.count >= 7)
        for words in examples {
            let command = try #require(FdtdCommandName(rawValue: words[0]), "\(words)")
            #expect(throws: Never.self, "\(words)") { _ = try FdtdOptions.parse(command, Array(words.dropFirst())) }
        }
    }

    @Test(arguments: [
        (["bench", "patch", "--confg", "x"], "--config"),
        (["bench", "patch", "--config=x"], "--config x"),
        (["bench", "patch", "--config", "a", "--config", "b", "--exact", "yes"], "--exact takes no value"),
        (["bench", "patch", "--config", "a", "--tag", "t1", "--tag", "t2"], "give --tag once"),
        (["ab", "patch", "--config", "a", "--config", "b", "--run-redo", "2"], "abtest.py redoes every run when --quiet is 0"),
        (["ab", "patch", "--config", "a", "--config", "b", "--quiet-gpu", "5"], "abtest waits for GPU <= 10 % itself and has no flag for it"),
        (["e2e", "gcpw", "--floor", "0.05"], "leave --floor out for gcpw"),
        (["check", "cg29", "--tag", "x", "--lite", "--quiet-max", "60"], "leave out --lite or --quiet-max"),
        (["check", "cg29", "--tag", "x", "--knob", "OPENEMS_FTZ=1"], "check.sh fixes these"),
        (["bench", "patch", "--config", "a", "--nodes", "2"], "leave --nodes out"),
        (["check", "cg29", "--tag", "x", "--nodes", "2", "--hosts", "f"], "--nodes N or --hosts FILE"),
        (["check", "cg29", "--tag", "x", "--distribute", "runs"], nil),
        (["ab", "patch", "--config", "a", "--config", "b", "--record", "f.txt", "--overwrite"], "--append, or a new --record FILE"),
        (["bench", "patch", "--scale", "2", "--config", "a"], "--nrts N"),
        (["bench", "patch", "--scale", "1.2345678", "--nrts", "10", "--config", "a"], "at most six significant digits"),
    ] as [([String], String?)])
    func usageErrorsExit64(arguments: [String], hint: String?) throws {
        let run = FakeWorld().run(arguments)
        #expect(run.exit == 64)
        #expect(run.status == "error")
        #expect(run.errorCodes == ["usage"])
        let issue = try #require(run.issue("errors", "usage"))
        if let hint {
            #expect(issue["hint"]?.string == hint)
            #expect(run.stderr.contains("(hint: \(hint))"))
        }
        #expect(run.envelope["schema"]?.string == "emskit.fdtd.\(arguments[0])/1")
        // nothing ran and nothing was planned
        #expect(run.envelope["jobs"]?.array?.isEmpty == true)
    }

    /// bench.py and run_validation.py (argparse) read a --tag value that starts with '-' as an option and exit 2 before
    /// they print anything, so check would read that as a failed comparison: such a tag is refused before any probe.
    @Test func tagStartingWithADashIsRefused() {
        let cases: [[String]] = [["check", "cg29", "--tag", "-x", "--lite"],
                                 ["bench", "patch", "--config", "cg29@multithreaded:4", "--tag", "-5"],
                                 ["validate", "--tag", "-x"]]
        for arguments in cases {
            let world = FakeWorld()
            let run = world.run(arguments)
            #expect(run.exit == 2, "\(arguments)")
            #expect(run.errorCodes == ["tag_invalid"], "\(arguments)")
            #expect(run.envelope["invocations"]?.array?.isEmpty == true, "\(arguments)")
            #expect(world.system.captures.isEmpty && world.system.spawned.isEmpty, "\(arguments)")
        }
        for tag in ["cg29", "cg29-lite.2", "_x", ".x", "5"] { #expect(FdtdOptions.isTag(tag), "\(tag)") }
        for tag in ["-x", "-", "", "a b", "a/b", "x="] { #expect(!FdtdOptions.isTag(tag), "\(tag)") }
    }

    /// bench.py's argparse reads a LIB that starts with '-' as an option (check.sh hands snapshot names to it), so
    /// every LIB form refuses one before anything is spawned, even when SNAPS has a folder of that name; the folder
    /// is still reached by its path, which the hint gives: in SNAPS for a name, below the cwd for a relative path.
    @Test func libraryStartingWithADashIsRefused() throws {
        let rfsim = ["--rfsim", FakeWorld.rfsim]
        let cases: [([String], String)] = [
            (["check", "cg29", "--stock", "-x", "--tag", "t", "--lite", "--dry-run"] + rfsim, "library_not_found"),
            (["check", "cg29", "--extra", "-x@multithreaded:4", "--tag", "t", "--lite", "--dry-run"] + rfsim,
             "config_invalid"),
            (["bench", "patch", "--config", "-x@multithreaded:4", "--dry-run"], "config_invalid"),
            (["ab", "patch", "--config", "cg29@multithreaded:4", "--config", "-x@multithreaded:4", "--dry-run"],
             "config_invalid"),
            (["validate", "--lib", "-x", "--dry-run"], "library_not_found"),
            (["e2e", "gcpw", "--lib", "-x", "--dry-run"] + rfsim, "library_not_found"),
            (["run", "/work/board.py", "--lib", "-x", "--dry-run"], "library_not_found"),
            (["debye-check", "cg29", "--ref", "-x", "--dry-run"], "library_not_found"),
        ]
        func world() -> FakeWorld {
            let world = FakeWorld()
            world.system.addLibraryFolder(FakeWorld.snaps + "/-x", FakeLibrary.cg29.files)
            world.system.addLibraryFolder(FakeWorld.repo + "/-y/lib", FakeLibrary.cg29.files)
            world.system.addFile("/work/board.py", "import openEMS\n")
            return world
        }
        let rule = "so no LIB may start with '-'"
        let snapshotHint = "the folder by its path, \(FakeWorld.snaps)/-x"
        for (arguments, code) in cases {
            let world = world()
            let run = world.run(arguments)
            #expect(run.exit == 2, "\(arguments): \(run.stderr)")
            #expect(run.errorCodes == [code], "\(arguments)")
            #expect(run.envelope["invocations"]?.array?.isEmpty == true, "\(arguments)")
            #expect(world.system.spawned.isEmpty, "\(arguments)")
            guard code == "library_not_found" else { continue }
            // every command states the one rule, and names the snapshot folder of that name by its path
            let issue = run.issue("errors", code)
            #expect(issue?["message"]?.string?.hasSuffix(rule) == true, "\(arguments): \(issue ?? .null)")
            #expect(issue?["hint"]?.string == snapshotHint, "\(arguments)")
        }
        // info lists what it can: the refusal is a warning there
        let info = world().run(["info", "--lib", "-x"])
        #expect(info.exit == 0 && info.warningCodes.contains("library_not_found"), "\(info.stderr)")
        #expect(info.result["snapshots"]?.array?.isEmpty == true)
        #expect(info.issue("warnings", "library_not_found")?["hint"]?.string == snapshotHint)
        // the hint works: the snapshot folder by its path, and a relative path below the cwd (the repo) with ./
        for (lib, hinted) in [("-x", FakeWorld.snaps + "/-x"), ("-y/lib", "./-y/lib")] {
            let refused = world().run(["validate", "--lib", lib, "--dry-run"])
            let hint = try #require(refused.issue("errors", "library_not_found")?["hint"]?.string, "\(lib)")
            #expect(hint == "the folder by its path, \(hinted)", "\(lib)")
            let byPath = world().run(["validate", "--lib", hinted, "--dry-run"])
            #expect(byPath.exit == 0, "\(lib): \(byPath.stderr)")
        }
    }

    /// -h and -help after a command are a usage error like every single-dash word, and the hint says --help
    /// instead of a path ./-h (also where another option is as near, bench's --hold).
    @Test func aSingleDashHelpRequestIsToldTheSpelling() throws {
        for arguments in [["info", "-h"], ["bench", "-help"], ["info", "-help"], ["bench", "-h"], ["e2e", "-help"]] {
            let run = FakeWorld().run(arguments)
            #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(arguments)")
            #expect(run.issue("errors", "usage")?["hint"]?.string == "--help", "\(arguments): \(run.stderr)")
            #expect(!run.stderr.contains("./-h"), "\(arguments): \(run.stderr)")
        }
        // a name of that spelling still gets the path hint
        let other = FakeWorld().run(["info", "-q"])
        let pathHint = "a folder or a script of that name by its path, ./-q"
        #expect(other.issue("errors", "usage")?["hint"]?.string == pathHint)
    }

    /// A positional that starts with '-' is a usage error on every command: `check cgD --tag t -snaps DIR` must not
    /// read -snaps and DIR as two more SNAPs (and then write --output inside DIR), and no LIB, MODEL or SCRIPT of
    /// that spelling is accepted either. The folder or script of that name is still reached by its path.
    @Test(arguments: [
        ["check", "cg29", "--tag", "t", "--lite", "-snaps", "/custom/snaps"],
        ["check", "cg29", "--tag", "t", "-python=/opt/other/bin/python3"], ["check", "-x", "--tag", "t", "--lite"],
        ["check", "cg29", "-", "--tag", "t"],
        ["bench", "-patch", "--config", "multithreaded:4"], ["bench", "-snaps=/custom/snaps", "--config", "a"],
        ["ab", "-patch", "--config", "a", "--config", "b"], ["e2e", "-gcpw"], ["e2e", "-rfsim=/work/rfsim"],
        ["run", "-board.py"], ["run", "-snaps=/custom/snaps", "--", "x"], ["run", "-"],
        ["debye-check", "-x"], ["debye-check", "-snaps=/custom/snaps"], ["diamond-check", "-x"],
        ["validate", "-quick"], ["info", "-snaps", "/custom/snaps"], ["load", "-seconds"],
    ])
    func aPositionalStartingWithADashIsAUsageError(line: [String]) throws {
        for tail in [[], ["--dry-run"], ["--output", "/custom/snaps/cg29/e.json"],
                     ["--overwrite", "--output", "/custom/snaps/cg29/libopenEMS.0.dylib"]] {
            // --dry-run is no option of info and load; the line is a usage error either way
            let world = FakeWorld()
            world.system.addLibraryFolder("/custom/snaps/cg29", FakeLibrary.cg29.files)
            world.system.addLibraryFolder(FakeWorld.snaps + "/-x", FakeLibrary.cg29.files)
            world.system.addFile("/work/emsKit/-board.py", "import openEMS\n")
            let before = world.system.allPaths
            let bytes = world.system.readFile("/custom/snaps/cg29/libopenEMS.0.dylib")
            // the tail goes before run's `--`
            let cut = line.firstIndex(of: "--") ?? line.count
            let run = world.run(Array(line[..<cut]) + tail + Array(line[cut...]))
            #expect(run.exit == 64 && run.errorCodes == ["usage"], "\(line) \(tail): \(run.stderr)")
            #expect(run.stdout.contains("\"usage\""), "\(line) \(tail)")
            #expect(world.system.allPaths == before, "\(line) \(tail)")
            #expect(world.system.readFile("/custom/snaps/cg29/libopenEMS.0.dylib") == bytes, "\(line) \(tail)")
            #expect(world.system.captures.isEmpty && world.system.spawned.isEmpty, "\(line) \(tail)")
        }
        let command = try #require(FdtdCommandName(rawValue: line[0]))
        #expect(throws: FdtdError.self) { _ = try FdtdOptions.parse(command, Array(line.dropFirst())) }
    }

    /// The message names the token, and the hint the option that was meant or the path form; a value of an option
    /// may still start with one dash, and so may anything after run's `--`.
    @Test func theDashPositionalsHintAndWhatStaysAllowed() throws {
        let meant = FakeWorld().run(["check", "cg29", "--tag", "t", "-snaps", "/custom/snaps"])
        let issue = try #require(meant.issue("errors", "usage"))
        #expect(issue["field"]?.string == "-snaps" && issue["hint"]?.string == "--snaps")
        #expect(issue["message"]?.string?.contains("no SNAP may start with '-'") == true)
        let path = FakeWorld().run(["run", "-board.py"])
        #expect(path.issue("errors", "usage")?["hint"]?.string?.hasSuffix("./-board.py") == true)
        let e2e = try FdtdOptions.parse(.e2e, ["gcpw", "--probe-end", "-60"])
        #expect(e2e.options == .e2e(FdtdE2EOptions(model: .gcpw, probeEnd: .db(-60))))
        guard case .run(let options) = try FdtdOptions.parse(.run, ["./-board.py", "--", "-x", "-", "--y"]).options
        else {
            Issue.record("run did not parse")
            return
        }
        #expect(options.script == "./-board.py" && options.scriptArguments == ["-x", "-", "--y"])
    }

    @Test func e2eUnknownModelExits64() {
        let run = FakeWorld().run(["e2e", "foo"])
        #expect(run.exit == 64)
        #expect(run.errorCodes == ["usage"])
    }

    @Test func noCommandAndUnknownCommandPrintUsageOnStderr() {
        for arguments in [[], ["frob"]] as [[String]] {
            let run = FakeWorld().run(arguments)
            #expect(run.exit == 64)
            #expect(run.data == nil)
            #expect(run.stdout.isEmpty)
            #expect(run.stderr.contains("usage: emskit fdtd COMMAND"))
        }
        #expect(FakeWorld().run(["frob"]).stderr.hasPrefix("emskit fdtd: unknown command 'frob'"))
    }

    @Test func versionAndHelp() throws {
        let world = FakeWorld()
        let version = world.run(["--version"])
        #expect(version.exit == 0)
        #expect(version.data == nil)
        #expect(version.stdout == "{\"fdtdKit\": \"0.1.0\", \"repoHead\": \"abc1234\"}\n")
        let help = world.run(["bench", "--help"])
        #expect(help.exit == 0)
        #expect(help.stdout.hasPrefix("usage: emskit fdtd bench MODEL --config CFG"))
        #expect(world.run(["--version", "x"]).exit == 64)
    }

    @Test func missingValueAndStrayPositional() throws {
        let missing = FakeWorld().run(["bench", "patch", "--config"])
        #expect(missing.exit == 64)
        #expect(missing.issue("errors", "usage")?["hint"]?.string == "--config CFG")
        let stray = FakeWorld().run(["load", "extra"])
        #expect(stray.exit == 64)
        #expect(stray.issue("errors", "usage")?["message"]?.string == "unexpected argument 'extra'")
    }
}
