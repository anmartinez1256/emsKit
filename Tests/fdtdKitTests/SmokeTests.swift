// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.2 smoke runs: the real tools, Python and libraries of this Mac through FdtdCLI.run in process, with the fake
// signal source. They run only with EMSKIT_FDTD_SMOKE=1, alone and serially:
//   EMSKIT_FDTD_SMOKE=1 EMSKIT_FDTD_RFSIM=DIR DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift test --filter fdtdKitTests.SmokeTests --no-parallel
// EMSKIT_FDTD_RFSIM=DIR enables the runs that need the rfsim toolkit. Every run gets --allow-concurrent (other
// sessions share the Mac); every speed or run time in an envelope must carry a valid load with the others' CPU and
// GPU use, and each is logged with it. A speed is never a pass/fail criterion; bit-identity verdicts are.
import Foundation
import Synchronization
import Testing
@testable import fdtdKit

enum Smoke {
    static let environment = ProcessInfo.processInfo.environment
    static let requested = environment["EMSKIT_FDTD_SMOKE"] == "1"
    static let rfsim = environment["EMSKIT_FDTD_RFSIM"].flatMap { $0.isEmpty ? nil : $0 }
    static let repo = TestPaths.repo
    static let box = repo + "/scripts/cache_valley/box.py"
    /// Spec 4.2's identities: libopenEMS sha256 prefix, version string and LC_UUID prefix.
    static let stock = (sha: "7eaaee52", version: "v0.37.0", uuid: "B1A89DA1")
    static let cg29 = (sha: "3c859d81", version: "v0.37.0-44-g074a687", uuid: "40BC8CFF")
    /// The installed libopenEMS as section 4.2 records it: cg18's build until 2026-11-06, cg29's until 2026-11-11 and
    /// cg31's since, each in other bytes than the snapshot's file.
    static let installs = [(sha: "819179a2", uuid: "24C8A7F2", build: "cg18"),
                           (sha: "0d81372e", uuid: "40BC8CFF", build: "cg29"),
                           (sha: "23630ed6", uuid: "499C07FD", build: "cg31")]
    /// The knobs that came after cg29 (patches 0029 to 0038, and the tiled sweep's three of patch 0040): cg29's
    /// libopenEMS does not have them.
    static let afterCg29: Set<String> = ["OPENEMS_DIAMOND_MERGE", "OPENEMS_DIAMOND_MURMERGE", "OPENEMS_DIAMOND_EVEN",
                                         "OPENEMS_DIAMOND_FASTIDX", "OPENEMS_DIAMOND_TGFLAG", "OPENEMS_DIAMOND_PML4",
                                         "OPENEMS_DIAMOND_PML3", "OPENEMS_DIAMOND_CAND", "OPENEMS_TBLOCK",
                                         "OPENEMS_TBLOCK_W", "OPENEMS_TBLOCK_HOOKS"]

    /// Spec 16.2: only through `--filter ...SmokeTests --no-parallel`, so that no other suite runs beside these runs
    /// and loads the Mac they measure. swift test hands both options to the testing helper this code runs in.
    static let alone: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        var filters: [String] = []
        for (index, argument) in arguments.enumerated() {
            if argument == "--filter", index + 1 < arguments.count { filters.append(arguments[index + 1]) }
            if argument.hasPrefix("--filter=") { filters.append(String(argument.dropFirst("--filter=".count))) }
        }
        let smokeOnly = !filters.isEmpty && filters.allSatisfy { $0.contains("SmokeTests") }
        return smokeOnly && arguments.contains("--no-parallel")
    }()

    /// Mirrors the CLI's stderr to the test log as it comes.
    static func sink(_ collector: TextCollector) -> FdtdSink {
        FdtdSink { text in
            collector.sink.write(text)
            FileHandle.standardError.write(Data(text.utf8))
        }
    }

    /// `emskit fdtd ARGS` on this Mac, in the tools tree, with `signals` (a fresh fake source by default).
    static func run(_ arguments: [String], environment extra: [String: String] = [:],
                    signals: FakeSignalSource = FakeSignalSource()) -> CLIRun {
        _ = LiveChild.prepared
        let out = TextCollector()
        let err = TextCollector()
        var context = FdtdContext.live()
        context.cwd = repo
        context.signals = signals
        context.stdout = out.sink
        context.stderr = sink(err)
        for (name, value) in extra { context.environment[name] = value }
        FileHandle.standardError.write(Data(("smoke: emskit fdtd " + arguments.joined(separator: " ") + "\n").utf8))
        let (exit, data) = FdtdCLI.run(arguments: arguments, context: context)
        return CLIRun(exit: exit, data: data, stdout: out.value, stderr: err.value)
    }

    static func log(_ text: String) { print("smoke: " + text) }

    static func format(_ value: Double) -> String { String(format: "%.1f", value) }

    /// A load with its others' figures, or nil when it is not valid or lacks them.
    static func others(_ load: FdtdJSONValue?) -> (cpu: Double, gpu: Double)? {
        guard let load, load["valid"]?.bool == true, let cpu = load["othersCpuPercent"]?.double,
              let gpu = load["othersGpuPercent"]?.double else { return nil }
        return (cpu, gpu)
    }

    static func othersText(_ cpu: Double, _ gpu: Double) -> String {
        "others cpu \(Int(cpu.rounded()))% gpu \(Int(gpu.rounded()))%"
    }

    static func figure(_ value: FdtdJSONValue?) -> Double? {
        guard let value, value != .null else { return nil }
        return value.double
    }

    /// Spec 8 and S4 on the real tools' output: a line with a speed or a run time reaches stderr only as the CLI's own
    /// line, and the CLI prints a speed only with the others' load beside it (or as withheld).
    static func checkEcho(_ run: CLIRun, _ label: String) {
        let markers = ["MC/s", "MCells/s", "MCell/s", "Speed:", "Case times (s)"]
        for line in run.stderr.split(separator: "\n").map(String.init) {
            let timed = markers.contains { line.contains($0) } || line.hasPrefix("RESULT {")
                || line.contains(/Time for \d+ iterations/)
            guard timed else { continue }
            #expect(line.hasPrefix("emskit fdtd: "), "\(label): a tool line with a figure was echoed: \(line)")
            #expect(line.contains("others cpu") || line.contains("speed withheld"), "\(label): \(line)")
        }
    }

    /// Every speed or run time of the envelope has a valid load with others' CPU and GPU; each is logged with it.
    static func checkLoads(_ run: CLIRun, _ label: String) {
        checkEcho(run, label)
        let result = run.result
        func expectLoad(_ what: String, _ load: FdtdJSONValue?) {
            let found = others(load)
            #expect(found != nil, "\(label): \(what) has no valid load: \(load ?? .null)")
            if let found { log("\(label): \(what) (\(othersText(found.cpu, found.gpu)))") }
        }
        for row in result["rows"]?.array ?? [] {
            guard let mcs = figure(row["mcs"]) else { continue }
            expectLoad("\(row["label"]?.string ?? "row") \(format(mcs)) MC/s", row["load"])
        }
        for call in result["calls"]?.array ?? [] {
            guard let mcs = figure(call["mcs"]) else { continue }
            expectLoad("call \(call["index"]?.double.map { Int($0) } ?? -1) \(format(mcs)) MC/s", call["load"])
        }
        for model in result["models"]?.array ?? [] {
            for row in model["rows"]?.array ?? [] {
                guard let mcs = figure(row["mcs"]) else { continue }
                expectLoad("\(model["label"]?.string ?? "model") \(row["label"]?.string ?? "row") \(format(mcs)) MC/s",
                           row["load"])
            }
        }
        for abRun in result["runs"]?.array ?? [] where abRun.object != nil && abRun["round"] != nil {
            guard let mcs = figure(abRun["mcs"]) else { continue }
            let cpu = figure(abRun["othersCpu"])
            let gpu = figure(abRun["othersGpu"])
            #expect(abRun["loadValid"]?.bool == true && cpu != nil && gpu != nil, "\(label): ab run \(abRun)")
            let round = abRun["round"]?.double.map { Int($0) } ?? -1
            let config = abRun["config"]?.double.map { Int($0) } ?? -1
            log("\(label): ab r\(round) c\(config) \(format(mcs)) MC/s (\(othersText(cpu ?? -1, gpu ?? -1)))")
        }
        // run times carry the whole-run load; any other whole-run load is logged too
        let times = figure(result["result"]?["t_run"]) != nil || (result["timings"].map { $0 != .null } ?? false)
            || run.envelope["command"]?.string == "load"
        if times {
            expectLoad("the whole run", run.envelope["load"])
        } else if let found = others(run.envelope["load"]) {
            log("\(label): the whole run (\(othersText(found.cpu, found.gpu)))")
        }
    }

    /// Standard output of `argv`, run without a shell.
    static func capture(_ argv: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    struct ProcessLine: Sendable, CustomStringConvertible {
        var pid: Int32
        var ppid: Int32
        var pgid: Int32
        var command: String

        /// The pid, the program and its first script, e.g. `83439 Python bench.py`.
        var description: String {
            let words = command.split(separator: " ").map(String.init)
            let program = words.first.map(FdtdPaths.basename) ?? "?"
            let script = words.dropFirst().first { $0.hasSuffix(".py") }.map { " " + FdtdPaths.basename($0) } ?? ""
            return "\(pid) \(program)\(script)"
        }
    }

    /// `ps -Ao pid=,ppid=,pgid=,command=`, without the ps process itself.
    static func processTable() -> [ProcessLine] {
        capture(["/bin/ps", "-Ao", "pid=,ppid=,pgid=,command="]).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3)
            guard fields.count == 4, let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
                  let pgid = Int32(fields[2]) else { return nil }
            let command = fields[3].trimmingCharacters(in: .whitespaces)
            return command.hasPrefix("/bin/ps ") ? nil : ProcessLine(pid: pid, ppid: ppid, pgid: pgid, command: command)
        }
    }

    /// The process group of the launcher this test process spawned, as `table` shows it ([] when none runs). The
    /// launcher leads its group (spec 11), so its pid is the group id.
    static func launcherGroup(_ table: [ProcessLine]) -> [ProcessLine] {
        let own = getpid()
        guard let launcher = table.first(where: {
            $0.ppid == own && $0.pid == $0.pgid && $0.command.contains(FdtdLauncherSource.fileName)
        }) else { return [] }
        return table.filter { $0.pgid == launcher.pgid }
    }

    /// Lines of the process table that contain `token`, this test process excluded.
    static func processes(containing token: String) -> [ProcessLine] {
        processTable().filter { $0.command.contains(token) && $0.pid != getpid() }
    }

    /// Triggers `signals` after `seconds` on another thread, and remembers when and which launcher group ran then.
    final class Trigger: Sendable {
        private struct State: Sendable {
            var fired: Date? = nil
            var group: [ProcessLine] = []
        }

        private let state = Mutex(State())

        init(_ signals: FakeSignalSource, after seconds: Double, signo: Int32 = SIGINT) {
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
                let group = Smoke.launcherGroup(Smoke.processTable())
                state.withLock { $0 = State(fired: Date(), group: group) }
                signals.trigger(signo)
            }
        }

        var at: Date? { state.withLock { $0.fired } }
        /// The launcher's process group just before the trigger.
        var group: [ProcessLine] { state.withLock { $0.group } }
    }
}

@Suite(.serialized, .enabled(if: Smoke.requested, "set EMSKIT_FDTD_SMOKE=1 (and run with --no-parallel)"),
       .enabled(if: Smoke.alone, "run alone and serially: swift test --filter fdtdKitTests.SmokeTests --no-parallel"))
struct SmokeTests {
    // 1
    @Test func versionHelpAndNoArguments() {
        let version = Smoke.run(["--version"])
        #expect(version.exit == 0 && version.data == nil)
        let head = Smoke.capture(["/usr/bin/git", "-C", Smoke.repo, "rev-parse", "--short", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!head.isEmpty)
        #expect(version.stdout == "{\"fdtdKit\": \"0.1.0\", \"repoHead\": \"\(head)\"}\n", "\(version.stdout)")
        let help = Smoke.run(["--help"])
        #expect(help.exit == 0 && help.data == nil && !help.stdout.isEmpty)
        let none = Smoke.run([])
        #expect(none.exit == 64 && none.data == nil && none.stdout.isEmpty && !none.stderr.isEmpty)
    }

    // 2
    @Test func infoIdentities() throws {
        let run = Smoke.run(["info"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.envelope["python"]?["dyldKept"]?.bool == true)
        let snapshots = run.result["snapshots"]?.array ?? []
        func libopenEMS(_ library: FdtdJSONValue?) -> FdtdJSONValue? {
            library?["files"]?.array?.first { $0["name"]?.string == "libopenEMS.0.dylib" }
        }
        func strings(_ value: FdtdJSONValue?) -> [String] { value?.array?.compactMap { $0.string } ?? [] }
        for (spec, identity) in [("stock", Smoke.stock), ("cg29", Smoke.cg29)] {
            let library = snapshots.first { $0["spec"]?.string == spec }
            #expect(library?["complete"]?.bool == true, "\(spec)")
            #expect(library?["versionString"]?.string == identity.version, "\(spec)")
            #expect(libopenEMS(library)?["sha256"]?.string?.hasPrefix(identity.sha) == true, "\(spec)")
            #expect(libopenEMS(library)?["uuid"]?.string?.hasPrefix(identity.uuid) == true, "\(spec)")
            #expect(strings(library?["sameBytes"]).contains(spec) && strings(library?["sameBuild"]).contains(spec),
                    "\(spec)")
        }
        // section 4.2: stock has the five CPU engines and no knob; cg29 adds the GPU engines and has the 30 knobs of
        // its time (29 in libopenEMS, NF2FF_LEGACY in libnf2ff), not the eight of patches 0029 to 0038
        let stock = snapshots.first { $0["spec"]?.string == "stock" }
        #expect(Set(strings(stock?["engines"])) == Set(FdtdEngine.cpuEngines.map(\.rawValue)))
        let stockKnobs = strings(stock?["knobs"])
        #expect(stockKnobs.isEmpty, "\(stockKnobs)")
        let cg29 = snapshots.first { $0["spec"]?.string == "cg29" }
        #expect(Set(strings(cg29?["engines"])) == Set(FdtdEngine.allCases.map(\.rawValue)))
        #expect(Set(strings(cg29?["knobs"])) == Set(FdtdKnobs.registry.map(\.name)).subtracting(Smoke.afterCg29))
        let installed = run.result["installed"]
        let installedSha = libopenEMS(installed)?["sha256"]?.string
        if let known = Smoke.installs.first(where: { installedSha?.hasPrefix($0.sha) == true }) {
            #expect(libopenEMS(installed)?["uuid"]?.string?.hasPrefix(known.uuid) == true)
            let fileBuilds = strings(libopenEMS(installed)?["sameBuild"])
            let libraryBuilds = strings(installed?["sameBuild"])
            #expect(fileBuilds.contains(known.build) && libraryBuilds.contains(known.build),
                    "\(fileBuilds) \(libraryBuilds)")
        } else {
            Smoke.log("info: the installed libopenEMS is none of section 4.2's installs; its sameBuild check is skipped")
        }
    }

    // 3
    @Test func loadTwoSeconds() {
        let run = Smoke.run(["load", "--seconds", "2"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(Smoke.others(run.envelope["load"]) != nil)
        Smoke.checkLoads(run, "load")
    }

    // 4
    @Test func benchStockAgainstCg29() throws {
        let run = Smoke.run(["bench", "patch", "--nrts", "2000", "--config", "stock@multithreaded:4", "--config",
                             "cg29@multithreaded:4", "--allow-concurrent"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        #expect(run.result["summary"]?["kind"]?.string == "IDENTICAL")
        let rows = run.result["rows"]?.array ?? []
        #expect(rows.count == 2)
        for row in rows {
            #expect(row["engineConfirmed"]?.bool == true, "\(row["label"] ?? .null)")
            #expect(row["load"]?["valid"]?.bool == true, "\(row["label"] ?? .null)")
        }
        #expect(rows.first?["reference"]?.bool == true && rows.last?["exact"]?.bool == true)
        Smoke.checkLoads(run, "bench")
    }

    // 5
    @Test func abStockAgainstCg29() throws {
        let run = Smoke.run(["ab", "patch", "--nrts", "2000", "--rounds", "2", "--config", "stock@multithreaded:4",
                             "--config", "cg29@multithreaded:4", "--allow-concurrent"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        let configs = run.result["configs"]?.array ?? []
        #expect(configs.count == 2)
        let c1 = configs.first { $0["index"]?.double == 1 }
        let diffs = c1?["diffs"]?.array?.compactMap { $0.string } ?? []
        #expect(!diffs.isEmpty && diffs.allSatisfy { $0 == "identical" }, "\(diffs)")
        let checks = run.result["samplerChecks"]?.array ?? []
        #expect(checks.count == 2)
        #expect(checks.allSatisfy { $0["valid"]?.bool == true })
        for config in configs {
            guard let median = Smoke.figure(config["medianMcs"]) else { continue }
            let cpu = Smoke.figure(config["othersCpuMedian"])
            let gpu = Smoke.figure(config["othersGpuMedian"])
            #expect(cpu != nil && gpu != nil)
            Smoke.log("ab: \(config["label"]?.string ?? "?") median \(Smoke.format(median)) MC/s "
                + "(\(Smoke.othersText(cpu ?? -1, gpu ?? -1)))")
        }
        Smoke.checkLoads(run, "ab")
    }

    // 6
    @Test func benchExactAgainstTheGPUEngine() throws {
        let run = Smoke.run(["bench", "patch", "--nrts", "2000", "--config", "cg29@multithreaded:4", "--config",
                             "cg29@metal-diamond:0", "--knob", "OPENEMS_FTZ=1", "--exact", "--allow-concurrent"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        let rows = run.result["rows"]?.array ?? []
        #expect(rows.count == 2)
        // FTZ=1 makes c0 tolerant, so every row is; --exact still wants each compared row identical
        #expect(rows.allSatisfy { $0["tolerant"]?.bool == true })
        let compared = rows.filter { $0["reference"]?.bool != true }
        #expect(compared.count == 1)
        for row in compared { #expect(row["exact"]?.bool == true, "\(row["label"] ?? .null)") }
        #expect(run.warningCodes.contains("not_bit_identical_to_stock"))
        Smoke.checkLoads(run, "bench gpu")
    }

    // 7
    @Test func validateQuick() throws {
        let run = Smoke.run(["validate", "--lib", "cg29", "--quick", "--case", "slab", "--case", "lines",
                             "--allow-concurrent"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        let checks = Smoke.figure(run.result["checks"])
        #expect(checks != nil && checks == Smoke.figure(run.result["passed"]))
        #expect(run.result["failed"]?.array?.isEmpty == true)
        // meta.libraries as the suite writes them (~ for the home folder)
        let libraries = run.result["libraries"]?.array?.compactMap { $0.string } ?? []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = Set(libraries.map { FdtdPaths.dirname($0.hasPrefix("~/") ? home + $0.dropFirst(1) : $0) })
        #expect(folders == [home + "/opt/openEMS-dev/snap/cg29"], "\(libraries)")
        Smoke.checkLoads(run, "validate")
    }

    // 8
    @Test func debyeCheck() throws {
        let run = Smoke.run(["debye-check", "cg29", "--allow-concurrent"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        #expect(run.result["verdictLine"]?.string?.contains("PASS") == true)
        let comparisons = run.result["comparisons"]?.array ?? []
        #expect(comparisons.count == 2)
        #expect(comparisons.allSatisfy { $0["identical"]?.bool == true })
        Smoke.checkLoads(run, "debye-check")
    }

    // 9
    @Test(.enabled(if: Smoke.rfsim != nil, "set EMSKIT_FDTD_RFSIM=DIR")) func e2eGcpw() throws {
        let run = Smoke.run(["e2e", "gcpw", "--lib", "cg29", "--rfsim", Smoke.rfsim ?? "", "--allow-concurrent"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        let calls = (run.result["calls"]?.array ?? []).filter { $0["setupOnly"]?.bool != true }
        #expect(calls.count == 1)
        #expect(calls.first?["stop"]?["kind"]?.string == "probeEnd")
        #expect(Smoke.figure(calls.first?["mcs"]) != nil)
        Smoke.checkLoads(run, "e2e")
    }

    // 10
    @Test func runBoxOnTheCPUEngine() throws {
        let temp = try TempFolder("smoke-box")
        defer { temp.remove() }
        let run = Smoke.run(["run", Smoke.box, "--lib", "cg29", "--threads", "4", "--allow-concurrent", "--",
                             "60", "60", "20", "600", "4", temp.file("box")])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        let calls = run.result["calls"]?.array ?? []
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect((call["load"]?["selfCpuPercent"]?.double ?? 0) >= 50)
        // box.py asks for multithreaded itself; engineConfirmed is set only for an --engine (spec 2.10), so the
        // Create line is checked with the CLI's own rule
        #expect(call["options"]?["engine"]?.string == "'multithreaded'")
        #expect(call["applied"]?["numThreads"]?.string == "4")
        let create = try #require(call["createLine"]?.string)
        let parsed = try #require(FdtdParsers.openEMSFacts([create]).creates.first)
        #expect(FdtdEngine.multithreaded.accepts(parsed), "\(create)")
        // box.py passes the same 4 threads: replaced without the warning, which is for a differing value only
        #expect(!run.warningCodes.contains("option_overridden"))
        Smoke.checkLoads(run, "run box")
    }

    // 11
    @Test func runBoxOnTheDiamondEngine() throws {
        let temp = try TempFolder("smoke-box2")
        defer { temp.remove() }
        let run = Smoke.run(["run", Smoke.box, "--lib", "cg29", "--engine", "metal-diamond", "--allow-concurrent", "--",
                             "60", "60", "20", "600", "0", temp.file("box2")])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        #expect(run.warningCodes.contains("option_overridden"))
        #expect(!run.warningCodes.contains("gpu_fallback"))
        let call = try #require(run.result["calls"]?.array?.first)
        #expect(call["createLine"]?.string?.contains("(Metal, diamond-blocked)") == true)
        #expect(call["engineConfirmed"]?.bool == true)
        #expect(call["applied"]?["engine"]?.string == "'metal-diamond'")
        #expect(call["overridden"]?["engine"]?["cli"]?.string == "'metal-diamond'")
        Smoke.checkLoads(run, "run box metal-diamond")
    }

    // 12
    @Test func refusalsAndPlans() throws {
        // as written, without --dry-run: the library check refuses before anything runs or is created
        let unsupported = Smoke.run(["bench", "patch", "--config", "cg18@metal-diamond:0", "--allow-concurrent"])
        #expect(unsupported.exit == 3, "\(unsupported.stderr)")
        #expect(unsupported.errorCodes.contains("engine_unsupported"))
        #expect(unsupported.envelope["runFolder"] == .null)
        #expect((unsupported.envelope["invocations"]?.array ?? []).allSatisfy { $0["ran"]?.bool == false })

        let ftz = Smoke.run(["bench", "patch", "--config", "cg29@multithreaded:4", "--allow-concurrent", "--dry-run"],
                            environment: ["OPENEMS_FTZ": "1"])
        #expect(ftz.exit == 0, "\(ftz.stderr)")
        #expect(ftz.warningCodes.contains("env_removed"))
        let bench = ftz.envelope["invocations"]?.array?.first { $0["role"]?.string == "bench" }
        #expect(bench?["envSet"]?["OPENEMS_FTZ"] == nil)
        #expect(bench?["envRemoved"]?.array?.contains { $0["name"]?.string == "OPENEMS_FTZ" } == true)

        // without rfsim check plans the four models it can run (--allow-partial)
        let rfsim = Smoke.rfsim.map { ["--rfsim", $0] } ?? ["--allow-partial"]
        let existing = Smoke.run(["check", "cg29", "--tag", "cg29", "--lite", "--allow-concurrent", "--dry-run"] + rfsim)
        #expect(existing.exit == 5, "\(existing.stderr)")
        #expect(existing.errorCodes.contains("would_overwrite"))

        let partial = Smoke.run(["check", "cg29", "--stock", "cg18", "--tag", "smoke", "--lite", "--allow-concurrent",
                                 "--dry-run"] + rfsim)
        #expect(partial.exit == 0, "\(partial.stderr)")
        #expect(partial.status == "partial")
        #expect(partial.result["reference"]?["acceptance"]?.bool == false)
        #expect(partial.warningCodes.contains("reference_not_stock"))

        let lacking = Smoke.run(["diamond-check", "cg27", "--allow-concurrent", "--dry-run"])
        #expect(lacking.exit == 3)
        #expect(lacking.errorCodes.contains("library_lacks_feature"))

        for arguments in [["check", "cg29", "--tag", "smoke", "--lite", "--allow-concurrent", "--dry-run"] + rfsim,
                          ["diamond-check", "cg29", "--allow-concurrent", "--dry-run"]] {
            let plan = Smoke.run(arguments)
            #expect(plan.exit == 0, "\(arguments): \(plan.stderr)")
            #expect(plan.status == (arguments[0] == "check" && Smoke.rfsim == nil ? "partial" : "ok"), "\(arguments)")
            #expect(plan.envelope["dryRun"]?.bool == true)
            #expect(plan.envelope["runFolder"] == .null)
            let invocations = plan.envelope["invocations"]?.array ?? []
            #expect(!invocations.isEmpty)
            // only the read-only probes ran
            let tools: Set<String> = ["bench", "ab", "check", "validate", "debye", "diamond", "e2e", "run"]
            #expect(invocations.filter { tools.contains($0["role"]?.string ?? "") }.allSatisfy { $0["ran"]?.bool == false })
        }
        // a dry run writes no table
        let tables = (try? FileManager.default.contentsOfDirectory(atPath: Smoke.repo + "/results")) ?? []
        #expect(!tables.contains { $0.hasSuffix("_smoke.txt") }, "\(tables.filter { $0.hasSuffix("_smoke.txt") })")
    }

    // 13
    @Test func aStopEndsARunScriptWithItsReport() throws {
        let temp = try TempFolder("smoke-box3")
        defer { temp.remove() }
        let out = temp.file("box3")
        let signals = FakeSignalSource()
        let trigger = Smoke.Trigger(signals, after: 3)
        let run = Smoke.run(["run", Smoke.box, "--lib", "cg29", "--allow-concurrent", "--",
                             "60", "60", "20", "200000", "4", out], signals: signals)
        let fired = try #require(trigger.at, "the run ended before the trigger: \(run.stderr)")
        let after = Date().timeIntervalSince(fired)
        Smoke.log("stop: run box returned \(String(format: "%.1f", after)) s after the trigger")
        #expect(after < 10)
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(run.status == "interrupted")
        let calls = run.result["calls"]?.array ?? []
        #expect(calls.count == 1)
        #expect(calls.first?["stop"]?["kind"]?.string == "aborted")
        #expect(calls.first?["stopRequested"]?.bool == true)
        #expect(!run.warningCodes.contains("report_rebuilt"))
        // an interrupted run keeps its folder (S9), with the launcher's report
        let folder = try #require(run.envelope["runFolder"]?.string)
        #expect(run.envelope["keptRuns"]?.bool == true)
        #expect(FileManager.default.fileExists(atPath: folder + "/launcher-run.json"))
        // the launcher's whole process group, as it ran at the trigger, is gone
        let group = trigger.group
        let leader = try #require(group.first, "no launcher of this test was running at the trigger")
        Smoke.log("stop: the group at the trigger: " + group.map(\.description).joined(separator: " | "))
        let left = Smoke.processTable().filter { $0.pgid == leader.pgid }
        #expect(left.isEmpty, "\(left)")
        #expect(Smoke.processes(containing: out).isEmpty, "\(Smoke.processes(containing: out))")
        Smoke.checkLoads(run, "stop run")
    }

    @Test func aStopEndsBenchAndItsRunners() throws {
        let signals = FakeSignalSource()
        let trigger = Smoke.Trigger(signals, after: 3)
        let run = Smoke.run(["bench", "notch", "--scale", "3", "--nrts", "20000", "--config", "cg29@multithreaded:4",
                             "--allow-concurrent"], signals: signals)
        let fired = try #require(trigger.at, "bench ended before the trigger: \(run.stderr)")
        Smoke.log("stop: bench returned \(String(format: "%.1f", Date().timeIntervalSince(fired))) s after the trigger")
        #expect(run.exit == 130, "\(run.stderr)")
        #expect(run.status == "interrupted")
        // bench.py ran in the launcher's group at the trigger, and nothing of that group is left
        let group = trigger.group
        let leader = try #require(group.first, "no launcher of this test was running at the trigger")
        Smoke.log("stop: the group at the trigger: " + group.map(\.description).joined(separator: " | "))
        #expect(group.contains { $0.pid != $0.pgid && $0.command.contains("bench/bench.py") }, "\(group)")
        let runner = group.contains { $0.command.contains("bench/runner.py") }
        Smoke.log("stop: runner.py \(runner ? "was" : "was not yet") running at the trigger")
        let left = Smoke.processTable().filter { $0.pgid == leader.pgid }
        #expect(left.isEmpty, "\(left)")
        // an interrupted run keeps its folder (S9): the launcher's report, and bench's runs/ once a runner started
        // (bench.py makes the rep folder before it starts runner.py)
        let folder = try #require(run.envelope["runFolder"]?.string)
        #expect(run.envelope["keptRuns"]?.bool == true)
        #expect(FileManager.default.fileExists(atPath: folder + "/launcher-bench.json"))
        if runner { #expect(FileManager.default.fileExists(atPath: folder + "/runs")) }
        let tools = Smoke.processes(containing: folder).filter {
            $0.command.contains("bench.py") || $0.command.contains("runner.py")
        }
        #expect(tools.isEmpty, "\(tools)")
        Smoke.checkLoads(run, "stop bench")
    }
}
