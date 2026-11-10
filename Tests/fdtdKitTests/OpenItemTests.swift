// SPDX-License-Identifier: GPL-3.0-or-later

// The items that the reviews of 2026-11-09 and 2026-11-10 had left open, closed on 2026-11-10 (CHANGELOG.md): a
// stop during the installed library's probe and the protected folders, the one rule for records taken from the
// snapshot index, info's stop handling and the warning for a knob given with two values. Their Python side (the
// rfsim probe's defaults, the binding's version and legacyEmptyOption) is in LauncherTests.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct OpenItemTests {
    static let custom = "/opt/custom"

    /// A Mac whose Python loads openEMS from a prefix that no default names.
    static func customPrefix() -> FakeWorld {
        let world = FakeWorld()
        world.system.addLibraryFolder(custom + "/lib", FakeLibrary.cg29.files)
        world.system.update { b in
            b.probeLibraries = FdtdLibraries.fileNames.map { custom + "/lib/" + $0 }
        }
        return world
    }

    // MARK: The protected folders after a stop

    /// Ctrl-C during the installed library's probe leaves the prefix unknown: an --output inside it is then not
    /// written (130, the envelope on stdout), where the same line without the stop is refused (2).
    @Test func aStopDuringTheInstalledProbeLetsNoOutputThrough() {
        let output = Self.custom + "/envelope.json"
        let plain = Self.customPrefix()
        let refused = plain.run(["load", "--seconds", "1", "--output", output])
        #expect(refused.exit == 2, "\(refused.stderr)")
        #expect(refused.errorCodes == ["protected_path"])

        let world = Self.customPrefix()
        world.system.update {
            $0.signalDuringSnippet = (FdtdSnippets.probe, SIGINT)
            $0.killAfterStop = true
        }
        let run = world.run(["load", "--seconds", "1", "--output", output])
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(run.errorCodes.allSatisfy { $0 == "interrupted" } && !run.errorCodes.isEmpty, "\(run.errorCodes)")
        #expect(!world.system.fileExists(output))
        #expect(run.stdout.contains("\"interrupted\""))
        #expect(world.system.spawned.isEmpty)
        #expect(!world.system.fileExists(FakeWorld.runs + "/emskit-fdtd"))
    }

    /// The same stop with every target inside a folder that is known all the same: the refusal stays a refusal.
    @Test func aStopDuringTheInstalledProbeStillRefusesAKnownFolder() {
        let world = Self.customPrefix()
        world.system.update {
            $0.signalDuringSnippet = (FdtdSnippets.probe, SIGINT)
            $0.killAfterStop = true
        }
        let run = world.run(["load", "--seconds", "1", "--output", FakeWorld.snaps + "/envelope.json"])
        #expect(run.errorCodes.contains("protected_path"), "\(run.stderr)")
        #expect(!world.system.fileExists(FakeWorld.snaps + "/envelope.json"))
    }

    /// An answer cut short by a stop is not kept: the list is asked again, and a list found before the stop is kept.
    @Test func aCutShortAnswerIsNotKeptForTheRestOfTheCommand() throws {
        let world = Self.customPrefix()
        world.system.update { $0.killAfterStop = true }
        let context = world.context(stdout: TextCollector(), stderr: TextCollector())
        let session = FdtdSession(context: context, command: .load, arguments: ["load"])
        session.stop.signalArrived(SIGINT)
        let first = session.protectedFolders()
        #expect(first.cutShort)
        #expect(!first.roots.contains { $0.path == Self.custom })
        #expect(session.memo.protectedRoots == nil)
        #expect(session.protectedFolders().cutShort)

        let before = FdtdSession(context: context, command: .load, arguments: ["load"])
        let known = before.protectedFolders()
        #expect(!known.cutShort && known.roots.contains { $0.path == Self.custom })
        before.stop.signalArrived(SIGINT)
        let after = before.protectedFolders()
        #expect(!after.cutShort && after.roots == known.roots)

        // a Python without openEMS answers the same after a stop: that is no answer cut short
        let none = FakeWorld()
        none.system.update { $0.importError = "ModuleNotFoundError: No module named 'openEMS'" }
        let other = FdtdSession(context: none.context(stdout: TextCollector(), stderr: TextCollector()),
                                command: .load, arguments: ["load"])
        _ = try? other.probePython(dyld: nil, snapshotNeeded: false)
        other.stop.signalArrived(SIGINT)
        #expect(!other.protectedFolders().cutShort)
    }

    /// A --rfsim that names no toolkit stops the base environment, not the probe that finds the installed prefix:
    /// an --output inside that prefix is refused as without it, and nothing there is renamed or
    /// written.
    @Test func aBadRfsimLeavesTheInstalledPrefixProtected() {
        let library = Self.custom + "/lib/libopenEMS.0.dylib"
        let envelope = Self.custom + "/envelope.json"
        let lines: [[String]] = [
            ["load", "--seconds", "1", "--rfsim", "/nope", "--overwrite", "--output", library],
            ["info", "--rfsim", "/nope", "--overwrite", "--output", library],
            ["info", "--rfsim", "/nope", "--output", envelope],
            ["load", "--seconds", "1", "--rfsim", "/nope", "--output", envelope],
        ]
        for line in lines {
            let world = Self.customPrefix()
            let before = world.system.allPaths
            let bytes = world.system.readFile(library)
            let run = world.run(line)
            #expect(run.errorCodes.contains("protected_path"), "\(line): \(run.errorCodes)")
            #expect(run.exit == 2, "\(line): \(run.exit)")
            #expect(world.system.allPaths == before, "\(line)")
            #expect(world.system.readFile(library) == bytes, "\(line)")
            // one probe found the prefix, without RFSIM_PATH
            let probes = world.system.captures.filter { $0.argv.contains(FdtdSnippets.probe) }
            #expect(probes.count == 1 && probes.allSatisfy { $0.environment["RFSIM_PATH"] == nil }, "\(line)")
        }
        // a stop during that probe is no answer either: nothing is written (130)
        let world = Self.customPrefix()
        world.system.update {
            $0.signalDuringSnippet = (FdtdSnippets.probe, SIGINT)
            $0.killAfterStop = true
        }
        let run = world.run(["load", "--seconds", "1", "--rfsim", "/nope", "--output", envelope])
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(!world.system.fileExists(envelope))
    }

    // MARK: Records from the index

    /// The record taken from the index is the one the files give, for a snapshot by its name and by its path, and
    /// for an incomplete one; a folder outside the index is read.
    @Test func aRecordFromTheIndexEqualsTheOneFromTheFiles() throws {
        let world = FakeWorld()
        world.system.addLibraryFolder("/work/build/lib", FakeLibrary.cg27.files)
        let system = world.system
        let index = FdtdLibraries.index(snaps: FakeWorld.snaps, system: system)
        for spec in ["cg29", FakeWorld.snaps + "/cg27", "broken", "/work/build/lib"] {
            let location = try FdtdLibraries.locate(spec, snaps: FakeWorld.snaps, installedDir: nil, cwd: "/",
                                                    home: FakeWorld.home, system: system)
            let reads = system.chunkReads(location.dir + "/libopenEMS.0.dylib")
            let record = FdtdLibraries.record(location, index: index, system: system)
            let held = index.entry(at: location.dir) != nil
            #expect(held == (spec != "/work/build/lib"), "\(spec)")
            #expect(system.chunkReads(location.dir + "/libopenEMS.0.dylib") == reads + (held ? 0 : 1), "\(spec)")
            #expect(record == FdtdLibraries.identify(location, index: index, system: system), "\(spec)")
            #expect(record.spec == spec)
        }
        // only the same bytes of a path find the entry
        #expect(index.entry(at: FakeWorld.snaps + "/cg29/") == nil)
        #expect(index.entry(at: FakeWorld.snaps + "/CG29") == nil)
        // a name typed in another Unicode form is equal as a String, yet another path
        world.system.addLibraryFolder(FakeWorld.snaps + "/caf\u{00E9}", FakeLibrary.cg27.files)
        let accented = FdtdLibraries.index(snaps: FakeWorld.snaps, system: system)
        #expect(accented.entry(at: FakeWorld.snaps + "/caf\u{00E9}") != nil)
        #expect(accented.entry(at: FakeWorld.snaps + "/cafe\u{0301}") == nil)
    }

    /// info reads a snapshot named with --lib once, by its name and by its path; so does a command that resolves a
    /// LIB given as a path into SNAPS.
    @Test func aLibInTheIndexIsReadOnce() throws {
        let world = FakeWorld()
        let byPath = FakeWorld.snaps + "/cg27"
        let run = world.run(["info", "--lib", "cg29", "--lib", byPath])
        #expect(run.exit == 0, "\(run.stderr)")
        for folder in ["cg29", "cg27"] {
            for name in FdtdLibraries.fileNames {
                #expect(world.system.chunkReads(FakeWorld.snaps + "/\(folder)/\(name)") == 1, "\(folder)/\(name)")
            }
        }
        let listed = try #require(run.result["snapshots"]?.array)
        #expect(listed.map { $0["spec"]?.string } == ["cg29", byPath])
        #expect(listed.map { $0["kind"]?.string } == ["snapshot", "path"])
        #expect(listed[1]["versionString"]?.string == FakeLibrary.cg27.version)

        let other = FakeWorld()
        other.system.addFile("/work/board.py", "print('x')\n")
        let dry = other.run(["run", "/work/board.py", "--lib", FakeWorld.snaps + "/cg29", "--dry-run"])
        #expect(dry.exit == 0, "\(dry.stderr)")
        for name in FdtdLibraries.fileNames {
            #expect(other.system.chunkReads(FakeWorld.snaps + "/cg29/\(name)") == 1, "\(name)")
        }
    }

    // MARK: info and a stop

    /// info handles signals: Ctrl-C during its probe ends it as interrupted (130) after that step, with no warning for
    /// the child that the stop ended and no later child.
    @Test func infoStopsOnASignal() {
        let world = FakeWorld()
        world.system.update {
            $0.signalDuringSnippet = (FdtdSnippets.probe, SIGINT)
            $0.killAfterStop = true
        }
        let run = world.run(["info"])
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(run.errorCodes == ["interrupted"])
        // only the note on the inherited DYLD variable, as on every run of this world
        #expect(run.warningCodes == ["env_removed"], "\(run.warningCodes)")
        #expect(run.envelope["result"] == .null)
        #expect(world.signals.installs == 1 && world.signals.restores == 1)
        let captures = world.system.captures
        #expect(!captures.contains { $0.argv.first == "/usr/sbin/lsof" })
        #expect(captures.filter { $0.argv.contains(FdtdSnippets.probe) }.count == 1)
        // a signal after the probe answered: the step's result stays, the next step does not start
        let later = FakeWorld()
        later.system.update { $0.signalAfterSnippet = (FdtdSnippets.rfsim, SIGTERM) }
        var environment = later
        environment.environment["RFSIM_PATH"] = FakeWorld.rfsim
        let second = environment.run(["info"])
        #expect(second.exit == 130, "\(second.stderr)")
        #expect(second.errorCodes == ["interrupted"])
        #expect(!later.system.captures.contains { $0.argv.first == "/usr/sbin/lsof" })
    }

    // MARK: A knob given twice

    /// validate, e2e and run keep the last of two values for one knob and say so; the same value twice is no news.
    @Test func aKnobGivenWithTwoValuesWarns() throws {
        func settings(_ texts: [String]) throws -> [FdtdKnobSetting] {
            try texts.map { try FdtdKnobs.parse($0, field: "--knob") }
        }
        let twice = try settings(["OPENEMS_FUSED=0", "OPENEMS_QOS=2", "OPENEMS_FUSED=1"])
        let issues = FdtdKnobs.repeated(twice)
        #expect(issues.map(\.code) == [.knobIgnored])
        #expect(issues.first?.message.contains("OPENEMS_FUSED is given as 0, then 1") == true)
        #expect(issues.first?.message.contains("OPENEMS_QOS") == false)
        #expect(FdtdKnobs.environment(twice)["OPENEMS_FUSED"] == "1")
        #expect(FdtdKnobs.repeated(try settings(["OPENEMS_FUSED=0", "OPENEMS_FUSED=0"])).isEmpty)

        let world = FakeWorld()
        world.system.addFile("/work/board.py", "print('x')\n")
        let line = ["run", "/work/board.py", "--lib", "cg29", "--dry-run", "--knob", "OPENEMS_FUSED=0"]
        let run = world.run(line + ["--knob", "OPENEMS_FUSED=1"])
        #expect(run.exit == 0, "\(run.stderr)")
        let warning = try #require(run.issue("warnings", "knob_ignored"), "\(run.warningCodes)")
        #expect(warning["message"]?.string?.contains("OPENEMS_FUSED") == true)
        #expect(warning["field"]?.string == "--knob")
        #expect(!world.run(line).warningCodes.contains("knob_ignored"))

        // the engine's own warnings are about the value that reaches it: a tile that a later --knob replaced is
        // not judged, the one that replaces it is
        func tiles(_ first: String, _ second: String) -> [String] {
            let diamond = ["run", "/work/board.py", "--lib", "cg29", "--engine", "metal-diamond", "--dry-run"]
            let run = world.run(diamond + ["--knob", "OPENEMS_DIAMOND_TILE=" + first, "--knob",
                                           "OPENEMS_DIAMOND_TILE=" + second])
            #expect(run.exit == 0, "\(run.stderr)")
            let ignored = run.envelope["warnings"]?.array?.filter { $0["code"]?.string == "knob_ignored" } ?? []
            return ignored.compactMap { $0["message"]?.string }
        }
        let replaced = tiles("4:4", "8:8")
        #expect(replaced.count == 1 && replaced[0].contains("the last value, 8:8, is used"), "\(replaced)")
        let kept = tiles("8:8", "4:4")
        #expect(kept.count == 2 && kept[1] == "OPENEMS_DIAMOND_TILE=4:4 is ignored at K=4: the engine needs "
                + "M >= 7 (2K-1)", "\(kept)")
    }
}
