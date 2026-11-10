// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 LauncherTests (section 13): the embedded launcher run by a real python3 against Fixtures/fake_openEMS (a
// binding stand-in whose Run prints its kw, changes into sim_path and steps until NrTS or SetAbort), with a stand-in
// usage.py and libinfo.py: injection order, overridden and lost options, sim paths, redirected stdout, the report,
// exit codes, sys.argv and sys.path[0], stops through the control pipe or its EOF, and exec mode; and the python probe
// against the same binding without package metadata.
import Foundation
import Testing
@testable import fdtdKit

/// A launcher, a tools tree with stand-in usage.py and libinfo.py, the fake binding on PYTHONPATH, a scripts folder and a
/// cwd apart from it, all in one temporary folder.
struct LauncherRig {
    static let usage = """
        class Sampler:
            def __init__(self):
                self.cpu1 = {1: 0.5, 2: 0.25}
                self.gpu1 = {}
                self.util = [3.0]

            def stop(self):
                return dict(cpu_self=101.0, cpu_other=12.5, gpu_self=0.0, gpu_other=1.0, wall=0.5, gpu_dev=3.0, busy=[])

        """
    static let libinfo = "def loaded_libs():\n    return ['/fake/lib/libopenEMS.0.dylib']\n"

    let temp: TempFolder
    let python: String
    var launcher: String { temp.file("run/fdtdkit_run.py") }
    var repo: String { temp.file("repo") }
    var cwd: String { temp.file("cwd") }
    var report: String { temp.file("run/launcher-run.json") }

    /// `fixed`: the binding variant without `opt = ""` (no option ends the list).
    init(_ label: String, fixed: Bool = false) throws {
        temp = try TempFolder("launcher-" + label)
        python = TestPython.path ?? "/usr/bin/false"
        try temp.write("run/fdtdkit_run.py", Data(FdtdLauncherSource.source.utf8))
        try temp.write("repo/bench/usage.py", Data(Self.usage.utf8))
        try temp.write("repo/bench/libinfo.py", Data(Self.libinfo.utf8))
        for name in ["__init__.py", "openEMS.py", "openEMS.pyx"] {
            var text = try TestPaths.text(TestPaths.fixture("fake_openEMS/openEMS/" + name))
            if fixed, name == "openEMS.pyx" { text = text.replacingOccurrences(of: "opt = \"\"", with: "continue") }
            try temp.write("site/openEMS/" + name, Data(text.utf8))
        }
        try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
    }

    func script(_ body: String, name: String = "main.py") throws -> String {
        try temp.write("scripts/" + name, Data(body.utf8))
        return temp.file("scripts/" + name)
    }

    struct Run {
        var child: LiveChild.Result
        /// The report as JSON, .null when none was written.
        var report: FdtdJSONValue
        var reportData: Data?

        var calls: [FdtdJSONValue] { report["calls"]?.array ?? [] }
        var exit: Int32? { child.outcome.exit }

        /// The fake binding's FAKE_RUN objects, in order.
        var fakeRuns: [FdtdJSONValue] {
            child.lines.filter { $0.hasPrefix("FAKE_RUN ") }.compactMap {
                try? FdtdJSON.decode(FdtdJSONValue.self, from: Data($0.dropFirst(9).utf8))
            }
        }
    }

    /// `pythonPath`: PYTHONPATH instead of the rig's site folder alone.
    func run(_ flags: [String], mode: String = "script", _ command: [String], on prefix: String? = nil,
             pythonPath: String? = nil, trigger: (@Sendable (FdtdStopController) -> Void)? = nil) -> Run {
        let argv = FdtdLauncherSource.argvPrefix(python: python, launcher: launcher, repo: repo, report: report)
            + flags + [mode, "--"] + command
        var environment = LiveChild.baseEnvironment
        environment["PYTHONPATH"] = pythonPath ?? temp.file("site")
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        try? FileManager.default.removeItem(atPath: report)
        let child = LiveChild.run(argv, cwd: cwd, environment: environment, controlPipe: true,
                                  log: temp.file("run/tool.log"), on: prefix, trigger: trigger)
        let data = FileManager.default.contents(atPath: report)
        let value = data.flatMap { try? FdtdJSON.decode(FdtdJSONValue.self, from: $0) } ?? .null
        return Run(child: child, report: value, reportData: data)
    }
}

@Suite struct LauncherSourceTests {
    @Test func theEmbeddedSourceIsTheFileByteForByte() throws {
        let path = TestPaths.repo + "/Sources/fdtdKit/Python/fdtdkit_run.py"
        let file = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(Data(FdtdLauncherSource.source.utf8) == file)
    }
}

@Suite(.enabled(if: TestPython.path != nil, "needs a framework or Homebrew python3"))
struct LauncherTests {
    static let callKeys: Set<String> = ["index", "simPath", "setupOnly", "options", "applied", "overridden",
                                        "optionsLost", "stdoutRedirected", "wallSeconds", "load", "loadCounts",
                                        "stopRequested", "probeEnd"]
    static let reportKeys: Set<String> = ["mode", "target", "argv", "exit", "interrupted", "exception", "wallSeconds",
                                          "load", "loadCounts", "libraries", "dyld", "python", "binding", "calls"]

    static func keys(_ value: FdtdJSONValue?) -> Set<String> { Set(value?.object?.keys.map { $0 } ?? []) }

    static func strings(_ value: FdtdJSONValue?) -> [String: String] {
        (value?.object ?? [:]).compactMapValues { $0.string }
    }

    /// The python probe against a binding without package metadata (a build tree on PYTHONPATH; -S hides every
    /// site-packages folder): the import counts, the version is left out, the pyx is still read.
    @Test func theProbeTakesABindingWithoutMetadata() throws {
        let rig = try LauncherRig("probe")
        defer { rig.temp.remove() }
        try rig.temp.write("site/numpy/__init__.py", Data("__version__ = '0.0'\n".utf8))
        var environment = LiveChild.baseEnvironment
        environment["PYTHONPATH"] = rig.temp.file("site")
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        let argv = [rig.python, "-S", "-B", "-c", FdtdSnippets.probe, rig.repo + "/bench/libinfo.py"]
        let child = LiveChild.run(argv, cwd: rig.cwd, environment: environment, log: rig.temp.file("run/probe.log"))
        #expect(child.outcome.exit == 0, "\(child.lines)")
        let tag = FdtdSnippets.probeTag + " "
        let line = try #require(child.lines.first { $0.hasPrefix(tag) }, "\(child.lines)")
        let probe = try FdtdJSON.decode(FdtdJSONValue.self, from: Data(line.dropFirst(tag.count).utf8))
        #expect(probe["importError"] == nil, "\(probe)")
        #expect(probe["numpy"]?.string == "0.0")
        #expect(probe["openemsModule"]?.string?.hasPrefix(rig.temp.file("site/openEMS/")) == true)
        #expect(probe["openemsVersion"] == nil)
        #expect(probe["legacyEmptyOption"]?.bool == true)
    }

    /// The python probe's line with PYTHONPATH `path` (-S hides every site-packages folder of the Mac).
    static func probe(_ rig: LauncherRig, path: String) throws -> FdtdJSONValue {
        try rig.temp.write("site/numpy/__init__.py", Data("__version__ = '0.0'\n".utf8))
        var environment = LiveChild.baseEnvironment
        environment["PYTHONPATH"] = path
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        let argv = [rig.python, "-S", "-B", "-c", FdtdSnippets.probe, rig.repo + "/bench/libinfo.py"]
        let child = LiveChild.run(argv, cwd: rig.cwd, environment: environment, log: rig.temp.file("run/probe.log"))
        #expect(child.outcome.exit == 0, "\(child.lines)")
        let tag = FdtdSnippets.probeTag + " "
        let line = try #require(child.lines.first { $0.hasPrefix(tag) }, "\(child.lines)")
        return try FdtdJSON.decode(FdtdJSONValue.self, from: Data(line.dropFirst(tag.count).utf8))
    }

    /// Package metadata named openEMS in `folder` (a dist-info with a RECORD of the package's files).
    static func metadata(_ rig: LauncherRig, in folder: String, version: String) throws {
        let info = folder + "/openEMS-\(version).dist-info/"
        try rig.temp.write(info + "METADATA", Data("Metadata-Version: 2.1\nName: openEMS\nVersion: \(version)\n".utf8))
        try rig.temp.write(info + "RECORD", Data("openEMS/__init__.py,,\nopenEMS/openEMS.py,,\n".utf8))
    }

    /// The metadata's version counts only when its files lie in the imported package's folder: metadata of another
    /// copy, found first by its name, gives no version, in the probe and in the launcher alike.
    @Test func theBindingsVersionNeedsMetadataOfTheImportedCopy() throws {
        let rig = try LauncherRig("version")
        defer { rig.temp.remove() }
        let script = try rig.script("print('DONE', flush=True)\n")
        // another copy's metadata, earlier on the path than the binding that is imported
        try Self.metadata(rig, in: "other", version: "9.9.9")
        let mixed = rig.temp.file("other") + ":" + rig.temp.file("site")
        let foreign = try Self.probe(rig, path: mixed)
        #expect(foreign["importError"] == nil, "\(foreign)")
        #expect(foreign["openemsModule"]?.string?.hasPrefix(rig.temp.file("site/openEMS/")) == true)
        #expect(foreign["openemsVersion"] == nil, "\(foreign)")
        let foreignRun = rig.run([], [script], pythonPath: mixed)
        #expect(foreignRun.exit == 0, "\(foreignRun.child.lines)")
        #expect(foreignRun.report["binding"]?["version"] == .null, "\(foreignRun.report)")
        #expect(foreignRun.report["binding"]?["legacyEmptyOption"]?.bool == true)
        // the imported copy's own metadata
        try Self.metadata(rig, in: "site", version: "1.2.3")
        let own = try Self.probe(rig, path: rig.temp.file("site"))
        #expect(own["openemsVersion"]?.string == "1.2.3", "\(own)")
        let ownRun = rig.run([], [script])
        #expect(ownRun.report["binding"]?["version"]?.string == "1.2.3", "\(ownRun.report)")
    }

    /// The probe's legacyEmptyOption follows the launcher's rule: true unless a pyx beside the binding can be read
    /// and lacks the line, also for a pyx that cannot be read and for a package that does not import openEMS.openEMS
    /// itself.
    @Test func theProbeAndTheLauncherAgreeOnTheLegacyBinding() throws {
        let script = "from openEMS.openEMS import openEMS\nprint('DONE', flush=True)\n"
        // a pyx that cannot be read (a folder of that name)
        let unreadable = try LauncherRig("legacy-unreadable")
        defer { unreadable.temp.remove() }
        try FileManager.default.removeItem(atPath: unreadable.temp.file("site/openEMS/openEMS.pyx"))
        try FileManager.default.createDirectory(atPath: unreadable.temp.file("site/openEMS/openEMS.pyx"),
                                                withIntermediateDirectories: false)
        let probe = try Self.probe(unreadable, path: unreadable.temp.file("site"))
        #expect(probe["legacyEmptyOption"]?.bool == true, "\(probe)")
        let run = unreadable.run([], [try unreadable.script(script)])
        #expect(run.report["binding"]?["legacyEmptyOption"]?.bool == true, "\(run.report)")
        // a package whose __init__ imports nothing: the fixed binding's pyx still decides
        let bare = try LauncherRig("legacy-bare", fixed: true)
        defer { bare.temp.remove() }
        try bare.temp.write("site/openEMS/__init__.py", Data("# imports nothing\n".utf8))
        let bareProbe = try Self.probe(bare, path: bare.temp.file("site"))
        #expect(bareProbe["importError"] == nil, "\(bareProbe)")
        #expect(bareProbe["legacyEmptyOption"]?.bool == false, "\(bareProbe)")
        let bareRun = bare.run([], [try bare.script(script)])
        #expect(bareRun.report["binding"]?["legacyEmptyOption"]?.bool == false, "\(bareRun.report)")
    }

    /// The rfsim probe against toolkits that lack values: each one missing, or no finite number, is null, and the
    /// probe still prints its line.
    @Test func theRfsimProbeTakesAToolkitWithoutItsValues() throws {
        let temp = try TempFolder("rfsim-probe")
        defer { temp.remove() }
        func probe(_ toolkit: String) throws -> FdtdRfsimProbe {
            var environment = LiveChild.baseEnvironment
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["RFSIM_MIN_CELL"] = "0.02"
            let argv = [TestPython.path ?? "/usr/bin/false", "-S", "-B", "-c", FdtdSnippets.rfsim, temp.file(toolkit)]
            let child = LiveChild.run(argv, cwd: temp.file(toolkit), environment: environment,
                                      log: temp.file(toolkit + ".log"))
            #expect(child.outcome.exit == 0, "\(child.lines)")
            let tag = FdtdSnippets.rfsimTag + " "
            let line = try #require(child.lines.first { $0.hasPrefix(tag) }, "\(child.lines)")
            return try FdtdJSON.decode(FdtdRfsimProbe.self, from: Data(line.dropFirst(tag.count).utf8))
        }
        func toolkit(_ name: String, core: String, launch: String?) throws {
            try temp.write(name + "/rfsim/__init__.py", Data())
            try temp.write(name + "/rfsim/openems/__init__.py", Data())
            try temp.write(name + "/rfsim/openems/core.py", Data(core.utf8))
            if let launch { try temp.write(name + "/rfsim/openems/launch.py", Data(launch.utf8)) }
        }
        try toolkit("full", core: "PROBE_END_DB = -60\nPROBE_END_HOLD = 0.5\nZ_MULT = 4\n",
                    launch: "MIN_CELL = 0.05\nP0 = dict(min_cell=0.02)\n")
        let full = try probe("full")
        #expect(full.core == temp.file("full/rfsim/openems/core.py"))
        #expect(full.probeEndDb == -60 && full.probeEndHold == 0.5 && full.zMult == 4)
        #expect(full.minCell == 0.05 && full.minCellEffective == 0.02)
        #expect(full.env == ["RFSIM_MIN_CELL": "0.02"])
        // an older toolkit: no hold, no z rule, no launch module
        try toolkit("old", core: "PROBE_END_DB = -60\n", launch: nil)
        let old = try probe("old")
        #expect(old.probeEndDb == -60)
        #expect(old.probeEndHold == nil && old.zMult == nil && old.minCell == nil && old.minCellEffective == nil)
        // values that are no finite numbers, and a P0 without the key
        try toolkit("odd", core: "PROBE_END_DB = None\nPROBE_END_HOLD = float('nan')\nZ_MULT = 'four'\n",
                    launch: "P0 = {}\n")
        let odd = try probe("odd")
        #expect(odd.probeEndDb == nil && odd.probeEndHold == nil && odd.zMult == nil)
        #expect(odd.minCell == nil && odd.minCellEffective == nil)
    }

    @Test func injectionOverridesTheReportAndTheCLIsReader() throws {
        let rig = try LauncherRig("inject")
        defer { rig.temp.remove() }
        let script = try rig.script("""
            import json, os, sys
            print('ARGV ' + json.dumps(sys.argv), flush=True)
            print('PATH0 ' + sys.path[0], flush=True)
            from openEMS import openEMS
            f = openEMS(NrTS=2)
            f.Run('sim', verbose=3, numthreads=8, Engine='sse', disable_dumps=False, foo=1)
            f.Run(os.path.join(os.getcwd(), 'sim2'), setup_only=True)
            print('DONE', flush=True)
            """)
        let run = rig.run(["--load", "--calls", "--engine", "multithreaded", "--threads", "4", "--nodumps"],
                          [script, "a", "b c"])
        #expect(run.exit == 0, "\(run.child.lines)")
        // sys.argv and sys.path[0] as `python3 SCRIPT ARGS` gives them
        #expect(run.child.lines.contains("ARGV " + #"["\#(script)", "a", "b c"]"#))
        #expect(run.child.lines.contains("PATH0 " + rig.temp.file("scripts")))
        // the CLI's options first, then the script's own; every spelling of an injected one dropped
        let fake = run.fakeRuns
        #expect(fake.count == 2)
        let kw = fake.first?["kw"]?.array?.compactMap { pair in pair.array?.compactMap { $0.string } }
        #expect(kw == [["engine", "'multithreaded'"], ["numThreads", "4"], ["disable_dumps", "True"],
                       ["verbose", "3"], ["foo", "1"]])
        #expect(fake.first?["sim_path"]?.string == rig.cwd + "/sim")
        // markers in order around each call, on the original stdout
        let kinds = run.child.lines.filter { $0.hasPrefix("FDTDKIT_") || $0.hasPrefix("FAKE_RUN") || $0 == "DONE" }
            .map { $0.hasPrefix("FAKE_RUN") ? "FAKE_RUN" : $0 }
        #expect(kinds == ["FDTDKIT_CALL_BEGIN 0", "FAKE_RUN", "FDTDKIT_CALL_END 0", "FDTDKIT_CALL_BEGIN 1",
                          "FAKE_RUN", "FDTDKIT_CALL_END 1", "DONE"])

        let report = run.report
        #expect(Self.keys(report) == Self.reportKeys)
        #expect(report["mode"]?.string == "script")
        #expect(report["target"]?.string == script)
        #expect(report["argv"]?.array?.compactMap { $0.string } == [script, "a", "b c"])
        #expect(report["exit"]?.double == 0)
        #expect(report["interrupted"]?.bool == false)
        #expect(report["exception"] == .null)
        #expect(report["dyld"] == .null)
        #expect(report["libraries"]?.array?.compactMap { $0.string } == ["/fake/lib/libopenEMS.0.dylib"])
        #expect(report["binding"]?["legacyEmptyOption"]?.bool == true)
        #expect(report["python"]?["executable"]?.string?.isEmpty == false)
        #expect(report["load"]?["cpu_other"]?.double == 12.5)
        #expect(report["loadCounts"]?["processesSeen"]?.double == 2)
        #expect(report["loadCounts"]?["utilSamples"]?.double == 1)
        #expect((report["wallSeconds"]?.double ?? 0) > 0)

        let calls = run.calls
        #expect(calls.count == 2)
        let first = try #require(calls.first)
        #expect(Self.keys(first) == Self.callKeys)
        #expect(first["index"]?.double == 0)
        #expect(first["simPath"]?.string == rig.cwd + "/sim")
        #expect(first["setupOnly"]?.bool == false)
        #expect(Self.strings(first["applied"]) == ["engine": "'multithreaded'", "numThreads": "4",
                                                   "disable_dumps": "True"])
        #expect(Self.strings(first["options"]) == ["engine": "'multithreaded'", "numThreads": "4",
                                                   "disable_dumps": "True", "verbose": "3", "foo": "1"])
        let overridden = first["overridden"]?.object?.mapValues { Self.strings($0) }
        #expect(overridden == ["numthreads": ["script": "8", "cli": "4"],
                               "Engine": ["script": "'sse'", "cli": "'multithreaded'"],
                               "disable_dumps": ["script": "False", "cli": "True"]])
        #expect(first["optionsLost"]?.array?.isEmpty == true)
        #expect(first["stdoutRedirected"]?.bool == false)
        #expect(first["stopRequested"]?.bool == false)
        #expect(first["load"]?["cpu_self"]?.double == 101)
        #expect(first["probeEnd"]?.object?.keys.sorted() == ["OPENEMS_PROBE_END_DB", "OPENEMS_PROBE_END_HOLD"])
        #expect(calls.last?["setupOnly"]?.bool == true)
        #expect(calls.last?["simPath"]?.string == rig.cwd + "/sim2")

        // the CLI reads this report and this log as they are
        let data = try #require(run.reportData)
        let parsed = try FdtdParsers.launcherReport(data)
        #expect(parsed.calls.count == 2)
        #expect(parsed.calls[0].overridden["Engine"] == FdtdOverride(script: "'sse'", cli: "'multithreaded'"))
        let built = FdtdCalls.build(report: parsed, toolLog: run.child.log, engine: .multithreaded,
                                    thresholds: FdtdThresholds(warnCpu: 100, warnGpu: 10))
        #expect(!built.rebuilt)
        #expect(built.calls.count == 2)
        #expect(built.calls[0].engineConfirmed == true)
        #expect(built.calls[0].timesteps == 2)
    }

    @Test func optionsLostOnTheLegacyBindingOnly() throws {
        let body = """
            from openEMS import openEMS
            class Zero:
                def __eq__(self, other):
                    return other == 0
                def __repr__(self):
                    return 'Zero()'
            f = openEMS(NrTS=0)
            f.Run('s1', disable_dumps=False, foo=1)
            f.Run('s2', disable_dumps=0.0, foo=1)
            f.Run('s3', z=Zero(), foo=1, bar=2)
            f.Run('s4', verbose=0, foo=1)
            f.Run('s5', verbose=False, foo=1)
            f.Run('s6', flag=True, foo=1)
            """
        let legacy = try LauncherRig("lost")
        defer { legacy.temp.remove() }
        let run = legacy.run(["--calls"], [try legacy.script(body)])
        #expect(run.exit == 0, "\(run.child.lines)")
        let lost = run.calls.map { $0["optionsLost"]?.array?.compactMap { $0.string } ?? ["?"] }
        #expect(lost == [["foo"], ["foo"], ["foo", "bar"], [], ["foo"], []])
        #expect(run.report["binding"]?["legacyEmptyOption"]?.bool == true)

        let fixed = try LauncherRig("kept", fixed: true)
        defer { fixed.temp.remove() }
        let other = fixed.run(["--calls"], [try fixed.script(body)])
        #expect(other.exit == 0)
        #expect(other.calls.count == 6)
        #expect(other.calls.allSatisfy { $0["optionsLost"]?.array?.isEmpty == true })
        #expect(other.report["binding"]?["legacyEmptyOption"]?.bool == false)
    }

    @Test func simPathsAndRedirectedStdout() throws {
        let rig = try LauncherRig("paths")
        defer { rig.temp.remove() }
        let script = try rig.script("""
            import os
            from openEMS import openEMS
            os.makedirs('deeper', exist_ok=True)
            os.chdir('deeper')
            f = openEMS(NrTS=0)
            f.Run('sim')
            fd = os.open('redirected.txt', os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
            saved = os.dup(1)
            os.dup2(fd, 1)
            f.Run('sim2')
            os.dup2(saved, 1)
            print('BACK', flush=True)
            """)
        let run = rig.run(["--calls"], [script])
        #expect(run.exit == 0, "\(run.child.lines)")
        let calls = run.calls
        #expect(calls.map { $0["simPath"]?.string } == [rig.cwd + "/deeper/sim", rig.cwd + "/deeper/sim2"])
        #expect(calls.map { $0["stdoutRedirected"]?.bool } == [false, true])
        // Run changed into sim_path itself (not sim/sim)
        #expect(run.fakeRuns.first?["cwd"]?.string == rig.cwd + "/deeper/sim")
        #expect(run.fakeRuns.count == 1)
        #expect(run.child.lines.contains("FDTDKIT_CALL_BEGIN 1") && run.child.lines.contains("FDTDKIT_CALL_END 1"))
        #expect(run.child.lines.last == "BACK")
        let redirected = try TestPaths.text(rig.cwd + "/deeper/redirected.txt")
        #expect(redirected.contains("FAKE_RUN ") && !redirected.contains("FDTDKIT_"))
    }

    @Test(arguments: [
        ("raise SystemExit(3)", Int32(3), nil as String?, false),
        ("import sys\nsys.exit('bye now')", 1, nil, false),
        ("raise ValueError('bad value')", 1, "ValueError: bad value", false),
        ("pass", 0, nil, false),
        ("raise KeyboardInterrupt", 130, nil, true),
    ])
    func exitCodesAndExceptions(body: String, exit: Int32, exception: String?, interrupted: Bool) throws {
        let rig = try LauncherRig("exit")
        defer { rig.temp.remove() }
        let script = try rig.script(body + "\n")
        let run = rig.run([], [script])
        #expect(run.exit == exit)
        #expect(run.report["exit"]?.double == Double(exit))
        #expect(run.report["exception"]?.string == exception)
        #expect(run.report["interrupted"]?.bool == interrupted)
        if exception != nil {
            // the traceback starts at the script's own frame
            #expect(run.child.lines.contains("Traceback (most recent call last):"))
            #expect(run.child.lines.contains { $0.contains(script) })
            #expect(!run.child.lines.contains { $0.contains("fdtdkit_run.py") || $0.contains("runpy") })
        }
        if body.contains("bye now") { #expect(run.child.lines.contains("bye now")) }
    }

    @Test func stopDuringARunAbortsItAndGives130() throws {
        let rig = try LauncherRig("stop-run")
        defer { rig.temp.remove() }
        let script = try rig.script("""
            from openEMS import openEMS
            f = openEMS(NrTS=3000)
            f.Run('sim')
            print('AFTER RUN', flush=True)
            """)
        let run = rig.run(["--calls"], [script], on: "Create FDTD engine") { stop in stop.signalArrived(SIGINT) }
        #expect(run.exit == 130, "\(run.child.lines)")
        #expect(run.child.seconds < 15)
        #expect(run.child.outcome.interrupted && !run.child.outcome.killed)
        #expect(run.child.lines.contains { $0.hasPrefix("RunFDTD: simulation aborted after") })
        #expect(!run.child.lines.contains("AFTER RUN"))
        #expect(run.child.lines.contains("FDTDKIT_CALL_END 0"))
        #expect(run.report["interrupted"]?.bool == true)
        #expect(run.report["exit"]?.double == 130)
        #expect(run.calls.count == 1)
        #expect(run.calls.first?["stopRequested"]?.bool == true)
    }

    @Test func stopInPythonCodeInterruptsAndNoNewRunStarts() throws {
        let rig = try LauncherRig("stop-python")
        defer { rig.temp.remove() }
        let script = try rig.script("""
            import time
            from openEMS import openEMS
            print('WAITING', flush=True)
            try:
                while True:
                    time.sleep(0.01)
            except KeyboardInterrupt:
                print('CAUGHT', flush=True)
            f = openEMS(NrTS=3000)
            f.Run('sim')
            print('RAN', flush=True)
            """)
        let run = rig.run(["--calls"], [script], on: "WAITING") { stop in stop.signalArrived(SIGTERM) }
        #expect(run.exit == 130, "\(run.child.lines)")
        #expect(run.child.seconds < 15)
        #expect(run.child.lines.contains("CAUGHT"))
        // after a stop no FDTD.Run starts
        #expect(!run.child.lines.contains { $0.hasPrefix("FAKE_RUN") || $0.hasPrefix("FDTDKIT_CALL_BEGIN") })
        #expect(!run.child.lines.contains("RAN"))
        #expect(run.report["interrupted"]?.bool == true)
        #expect(run.calls.isEmpty)
    }

    @Test func eofOnTheControlPipeIsAStop() throws {
        let rig = try LauncherRig("stop-eof")
        defer { rig.temp.remove() }
        let script = try rig.script("from openEMS import openEMS\nopenEMS(NrTS=3000).Run('sim')\n")
        let run = rig.run(["--calls"], [script], on: "Create FDTD engine") { stop in stop.closeControlPipe() }
        #expect(run.exit == 130, "\(run.child.lines)")
        #expect(run.child.seconds < 15)
        #expect(run.report["interrupted"]?.bool == true)
        #expect(run.calls.first?["stopRequested"]?.bool == true)
        #expect(run.child.lines.contains { $0.hasPrefix("RunFDTD: simulation aborted after") })
    }

    @Test func execModePassesTheExitThrough() throws {
        let rig = try LauncherRig("exec-exit")
        defer { rig.temp.remove() }
        let run = rig.run(["--load"], mode: "exec", ["/bin/sh", "-c", "echo hello; exit 7"])
        #expect(run.exit == 7)
        #expect(run.child.lines.contains("hello"))
        let report = run.report
        #expect(Self.keys(report) == Self.reportKeys)
        #expect(report["mode"]?.string == "exec")
        #expect(report["exit"]?.double == 7)
        #expect(report["interrupted"]?.bool == false)
        #expect(report["libraries"]?.array?.isEmpty == true)
        #expect(report["binding"] == .null)
        #expect(report["calls"]?.array?.isEmpty == true)
        #expect(report["load"]?["cpu_other"]?.double == 12.5)
        let missing = rig.run([], mode: "exec", [rig.temp.file("no-such-tool")])
        #expect(missing.exit == 127)
        #expect(missing.report["exception"]?.string?.hasPrefix("FileNotFoundError") == true)
    }

    @Test func execModeStopSendsTermToTheGroupAndTheReportIsWritten() throws {
        let rig = try LauncherRig("exec-stop")
        defer { rig.temp.remove() }
        let run = rig.run([], mode: "exec", [rig.python, "-u", "-c", "import time\nprint('READY')\ntime.sleep(30)"],
                          on: "READY") { stop in stop.signalArrived(SIGINT) }
        #expect(run.exit == 128 + SIGTERM, "\(run.child.lines)")
        #expect(run.child.seconds < 15)
        #expect(run.child.outcome.interrupted && !run.child.outcome.killed)
        #expect(run.report["exit"]?.double == Double(128 + SIGTERM))
        #expect(run.report["interrupted"]?.bool == true)
    }
}
