// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 14 items that no other suite holds: S3 (no command writes under the installed prefix or the snapshot directory),
// S4's echo rule (no raw tool line with a speed or a run time reaches stderr) and S8's tolerant rows (never proof
// except under --exact, never counted by check); check's verdict and guard (6.3); gpu_fallback from the logs (4.4).
import Foundation
import Testing
@testable import fdtdKit

@Suite struct EchoFilterTests {
    /// Real tool lines (fixtures and openEMS's own formats) that carry a speed or a run time.
    @Test func speedAndTimeLinesStayInTheLog() throws {
        let variants = try TestPaths.lines(TestPaths.fixture("bench_variants.txt"))
        let record = try TestPaths.lines(TestPaths.fixture("abtest_record.txt"))
        let log = try TestPaths.lines(TestPaths.fixture("tool_log.txt"))
        let e2e = try TestPaths.lines(TestPaths.fixture("e2e_output.txt"))
        var hidden = Array(variants.dropFirst().prefix(6))
        hidden += record.filter { $0.hasPrefix("r0 c") || $0.hasPrefix("# redo ") }
        hidden += record.filter { $0.wholeMatch(of: #/c\d+ .*/#) != nil }
        hidden += log.filter { $0.contains("Speed:") || $0.hasPrefix("Time for ") || $0.hasPrefix("FDTDKIT_") }
        hidden += e2e.filter { $0.hasPrefix("RESULT {") }
        hidden += [
            "15 of 15 checks passed. Case times (s): {'slab': 3.1, 'cavity': 8.2}",
            "setup timing: operator CalcEC: 0.0421 s",
            "Fused sweep timing (OPENEMS_FUSED_STAT), 4 threads, 2000 timesteps, ms per thread (sweep / wait 1 / "
                + "line before the slab / wait 2):",
            "  thread 0: 812.3 / 12.1 / 30.2 / 9.8  (waits 2.6 %)",
        ]
        #expect(hidden.count >= 20)
        for line in hidden { #expect(!FdtdEchoFilter.passes(line), "\(line)") }
    }

    @Test func otherLinesAreEchoed() {
        for line in ["Create FDTD engine (compressed SSE + multi-threading)",
                     "RunFDTD: simulation aborted after 41538 timesteps (-3.00dB)",
                     "IDENTICAL: every run of 2 configs equals the reference",
                     "Time for the next step: see the log", "  thread 2 started",
                     "c1 is the second config", "== reference /Users/tester/opt/openEMS-dev/snap/cg18: sse-compressed"] {
            #expect(FdtdEchoFilter.passes(line), "\(line)")
        }
    }
}

@Suite struct VerdictTests {
    static func row(_ label: String, reference: Bool = false, tolerant: Bool = false, exact: Bool?) -> FdtdBenchRow {
        var row = FdtdBenchRow(label: label, config: label, lib: "cg29", engine: tolerant ? "metal-diamond" : "multithreaded")
        row.reference = reference
        row.tolerant = tolerant
        row.exact = exact
        if let exact { row.probesRel = exact ? 0 : 1.7e-6 }
        return row
    }

    static let rows = [row("cg29@multithreaded:4", reference: true, exact: nil),
                       row("cg29@metal-diamond:0", tolerant: true, exact: false)]

    @Test func aTolerantRowIsNoProofWithoutExact() {
        let identical = FdtdBenchSummary(kind: "IDENTICAL", line: "IDENTICAL: every run of 2 configs equals the reference")
        let plain = FdtdVerdicts.bench(summary: identical, rows: Self.rows, exact: false, benchExit: 0)
        #expect(plain.passed)
        #expect(plain.warnings.map(\.code) == [.tolerantRows])
        let exact = FdtdVerdicts.bench(summary: identical, rows: Self.rows, exact: true, benchExit: 0)
        #expect(!exact.passed)
        #expect(exact.errors.map(\.code) == [.notExact])
        let nothing = FdtdBenchSummary(kind: "NOTHING REQUIRED TO MATCH", line: "NOTHING REQUIRED TO MATCH")
        let tolerantOnly = FdtdVerdicts.bench(summary: nothing, rows: Self.rows, exact: false, benchExit: 0)
        #expect(tolerantOnly.passed)
        #expect(tolerantOnly.warnings.map(\.code).contains(.nothingVerified))
        // under --exact the tolerant rows are verified, so nothing_verified does not apply
        var matching = Self.rows
        matching[1].exact = true
        matching[1].probesRel = 0
        let verified = FdtdVerdicts.bench(summary: nothing, rows: matching, exact: true, benchExit: 0)
        #expect(verified.passed && verified.warnings.isEmpty)
    }

    // MARK: check (spec 6.3)

    static let checkLabels = CheckCommand.models.map(\.label)

    /// A model block as check's guard sees it: the reference row, `counted` exact rows of cg29 and `extra`, every
    /// engine confirmed; `kind` nil leaves the block without its summary.
    static func checkModel(_ label: String, kind: String? = "IDENTICAL", counted: Int = 3,
                           extra: FdtdBenchRow? = nil) -> FdtdCheckModel {
        var model = FdtdCheckModel(label: label, name: label)
        model.summary = kind.map { FdtdBenchSummary(kind: $0, line: $0 + ": ...") }
        var rows = [row("stock@multithreaded:8", reference: true, exact: nil)]
        rows += (0..<counted).map { row("cg29@multithreaded:\($0 + 1)", exact: true) }
        if let extra { rows.append(extra) }
        model.rows = rows.map { row in
            var confirmed = row
            confirmed.engineConfirmed = true
            return confirmed
        }
        return model
    }

    /// The check verdict of `final` over `models`, lite with one SNAP (3 counted rows per model).
    static func check(_ final: String, _ models: [FdtdCheckModel], rfsimFound: Bool = true) -> FdtdVerdict {
        FdtdVerdicts.check(finalLine: FdtdParsers.checkFinal(final), models: models, expectedExactRows: 3,
                           acceptance: true, referenceSpec: "stock", allowPartial: !rfsimFound, rfsimFound: rfsimFound)
    }

    /// check.sh counts any bench.py exit 2 as FAIL, an argument error too, which prints no block (F4): only a MISMATCH
    /// block for every model FAIL names, with every model run, is a failed comparison.
    @Test func checkFailNeedsAMismatchBlockPerNamedModel() {
        let none = Self.check("check.sh t: FAIL: " + Self.checkLabels.joined(separator: " "), [])
        #expect(none.errors.map(\.code) == [.toolOutputUnparsed])
        #expect(none.errors.first?.message.contains("0 of 6 models printed a block") == true)
        var models = Self.checkLabels.map { Self.checkModel($0) }
        models[0] = Self.checkModel("patch_x5", kind: "MISMATCH")
        models[3] = Self.checkModel("notch", kind: "MISMATCH")
        let failed = Self.check("check.sh t: FAIL: patch_x5 notch", models)
        #expect(!failed.passed)
        #expect(failed.errors.map(\.code) == [.checkFailed])
        // a named model whose block says IDENTICAL, or a model that printed no block
        let identical = Self.check("check.sh t: FAIL: patch_x5 patch", models)
        #expect(identical.errors.map(\.code) == [.toolOutputUnparsed])
        #expect(identical.errors.first?.message.contains("no MISMATCH block for patch;") == true)
        let missing = Self.check("check.sh t: FAIL: patch_x5", Array(models.prefix(5)))
        #expect(missing.errors.map(\.code) == [.toolOutputUnparsed])
    }

    @Test func checkGuardBesideTheFinalLine() {
        let all = Self.checkLabels.map { Self.checkModel($0) }
        let identical = "check.sh t: ALL IDENTICAL (6 models)"
        let ok = Self.check(identical, all)
        #expect(ok.passed && ok.errors.isEmpty && !ok.partial)
        // one counted row short
        var short = all
        short[2] = Self.checkModel("patch", counted: 2)
        let fewer = Self.check(identical, short)
        #expect(fewer.errors.map(\.code) == [.verdictDisagrees])
        #expect(fewer.errors.first?.message.contains("patch has 2 counted rows, expected 3") == true)
        // a block without its summary
        var unsummarized = all
        unsummarized[1] = Self.checkModel("notch_x3", kind: nil)
        #expect(Self.check(identical, unsummarized).errors.map(\.code) == [.toolOutputUnparsed])
        // S8: a tolerant extra that is not exact passes and is not counted; counted, it would fail the guard
        let extra = Self.row("cg29@metal-diamond:0", tolerant: true, exact: false)
        let tolerant = Self.check(identical, Self.checkLabels.map { Self.checkModel($0, extra: extra) })
        #expect(tolerant.passed && tolerant.errors.isEmpty)
        var plain = extra
        plain.tolerant = false
        let counted = Self.check(identical, Self.checkLabels.map { Self.checkModel($0, extra: plain) })
        #expect(counted.errors.map(\.code) == [.verdictDisagrees])
        // PARTIAL although rfsim was found; without rfsim the same line passes as partial
        let partial = "check.sh t: PARTIAL: no differences on 4 of 6 models (RFSIM_PATH is not set: kgcpw and ksma skipped)"
        #expect(Self.check(partial, Array(all.prefix(4))).errors.map(\.code) == [.verdictDisagrees])
        let four = Self.check(partial, Array(all.prefix(4)), rfsimFound: false)
        #expect(four.passed && four.partial)
    }

    /// A fake check.sh run of `check cg29 --tag t --lite`: a bench block per model in `blocks` (the reference and cg29's
    /// three lite configs, then the tolerant `extra` when given; the models in `mismatch` with a differing
    /// cg29@multithreaded:4), each row's rep0/openEMS.log with the multithreaded Create line (`extraLog` for the
    /// extra), then `final`.
    static func checkTool(blocks: [FdtdCheckModelSpec], mismatch: Set<String>, final: String, exit: Int32,
                          extra: String? = nil, extraLog: String = "") -> FakeToolRun {
        var tool = FakeToolRun()
        let during = "during 6.4 s: self cpu 430% gpu>=0.00 s, others cpu 49% gpu 5%, gpu dev 5%"
        let same = "probes rel=0.0e+00  S11: max|dS|=0.0e+00 max dB=0.0e+00  openEMS v0.37.0-44-g074a687"
        let differs = "probes rel=1.2e-03  S11: max|dS|=3.0e-04 max dB=1.0e-03  openEMS v0.37.0-44-g074a687"
        let tolerant = "probes rel=0.0e+00  S11: max|dS|=0.0e+00 max dB=0.0e+00  (tolerant)  openEMS v0.37.0-44-g074a687"
        for model in blocks {
            var labels = ["stock@multithreaded:\(model.referenceThreads)", "cg29@multithreaded:4", "cg29@multithreaded:8",
                          "cg29@fastest"]
            if let extra { labels.append(extra) }
            let differing = mismatch.contains(model.label)
            tool.lines.append("# \(model.name)  load avg 4.10")
            for (k, label) in labels.enumerated() {
                let tail = k == 0 ? "[ref]  openEMS v0.37.0" : label == extra ? tolerant : (k == 1 && differing ? differs : same)
                tool.lines.append("\(label)  1846.4 MC/s  5.11 s  1200 TS x 7.863 MC  others  46%  \(during)  \(tail)")
            }
            tool.lines.append(differing ? "MISMATCH: cg29@multithreaded:4"
                                        : "IDENTICAL: every run of \(labels.count - 1) configs equals the reference")
            for (label, sub) in zip(labels, FdtdBenchConfigs.runSubfolders(labels)) {
                tool.files["runs/\(model.name)/\(sub)/rep0/openEMS.log"] = label == extra
                    ? extraLog : "Create FDTD engine (compressed SSE + multi-threading)\n"
            }
        }
        tool.lines.append(final)
        tool.exit = exit
        tool.report = FakeToolRun.report(mode: "exec", argv: ["/bin/zsh"], exit: exit)
        return tool
    }

    @Test func checkRunFailsOnlyOnAMismatchBlock() throws {
        let arguments = ["check", "cg29", "--tag", "t", "--lite", "--rfsim", FakeWorld.rfsim]
        let world = FakeWorld()
        let tool = Self.checkTool(blocks: CheckCommand.models, mismatch: ["notch"], final: "check.sh t: FAIL: notch",
                                  exit: 2)
        world.system.update { $0.spawn = tool.handler(world.system) }
        let mismatch = world.run(arguments)
        #expect(mismatch.exit == 1, "\(mismatch.stderr)")
        #expect(mismatch.status == "fail")
        #expect(mismatch.errorCodes == ["check_failed"])
        #expect(mismatch.result["verdict"]?.string == "FAIL")
        #expect(mismatch.result["models"]?.array?.count == 6)

        // bench.py refused its arguments for every model: argparse exits 2 before the block header
        let unread = FakeWorld()
        var refused = FakeToolRun(lines: ["usage: bench.py [-h] [--scale SCALE] --nrts NRTS [--configs CONFIGS ...]",
                                          "bench.py: error: argument --tag: expected one argument",
                                          "check.sh t: FAIL: " + Self.checkLabels.joined(separator: " ")])
        refused.exit = 2
        refused.report = FakeToolRun.report(mode: "exec", argv: ["/bin/zsh"], exit: 2)
        unread.system.update { $0.spawn = refused.handler(unread.system) }
        let run = unread.run(arguments)
        #expect(run.exit == 4, "\(run.stderr)")
        #expect(run.status == "error")
        #expect(run.errorCodes == ["tool_output_unparsed"])
    }

    /// A block's summary over fewer rows than configs confirms nothing for the missing one, also when it is a row
    /// that the count of exact rows leaves out: a tolerant --extra, or the reference of a lite block.
    @Test func checkNeedsARowPerConfig() {
        let arguments = ["check", "cg29", "--tag", "t", "--lite", "--rfsim", FakeWorld.rfsim]
        let final = "check.sh t: ALL IDENTICAL (6 models)"
        let extra = "cg29@metal-diamond:0"
        let metal = "Create FDTD engine (Metal, diamond-blocked)\n"
        func run(_ tool: FakeToolRun, _ more: [String] = []) -> CLIRun {
            let world = FakeWorld()
            world.system.update { $0.spawn = tool.handler(world.system) }
            return world.run(arguments + more)
        }
        let whole = Self.checkTool(blocks: CheckCommand.models, mismatch: [], final: final, exit: 0, extra: extra,
                                   extraLog: metal)
        let ok = run(whole, ["--extra", extra])
        #expect(ok.exit == 0 && ok.errorCodes.isEmpty, "\(ok.stderr)")
        // the tolerant extra's row is missing from every block
        var withoutExtra = whole
        withoutExtra.lines.removeAll { $0.hasPrefix(extra) }
        let dropped = run(withoutExtra, ["--extra", extra])
        #expect(dropped.exit == 4 && dropped.status == "error", "\(dropped.stderr)")
        #expect(dropped.errorCodes == Array(repeating: "tool_output_unparsed", count: 6))
        let messages = dropped.envelope["errors"]?.array?.compactMap { $0["message"]?.string } ?? []
        #expect(messages.first == "check model patch_x5: bench.py printed a summary line, but 4 readable rows "
                + "for 5 configs", "\(messages)")
        #expect(dropped.result["exactRows"]?.double == 18)
        // the reference row of one lite block is missing
        var withoutReference = Self.checkTool(blocks: CheckCommand.models, mismatch: [], final: final, exit: 0)
        let k = withoutReference.lines.firstIndex { $0.contains("[ref]") } ?? 0
        withoutReference.lines.remove(at: k)
        let unreferenced = run(withoutReference)
        #expect(unreferenced.exit == 4, "\(unreferenced.stderr)")
        #expect(unreferenced.errorCodes == ["tool_output_unparsed"])
        #expect(unreferenced.issue("errors", "tool_output_unparsed")?["message"]?.string?
            .hasSuffix("3 readable rows for 4 configs") == true)
        // a stop after the summary: interrupted, not a finished block that lacks rows
        var stopped = withoutReference
        stopped.during = { $0.signalArrived(SIGINT) }
        let interrupted = run(stopped)
        #expect(interrupted.exit == 130 && interrupted.errorCodes == ["interrupted"], "\(interrupted.stderr)")
    }
}

/// Spec 4.4: a metal-diamond run whose log shows the CPU loops gives gpu_fallback in every command that reads the
/// logs, although its Create line confirms the engine.
@Suite struct GpuFallbackTests {
    // cg29 runs UPML on the GPU (since cg21); TFSF still has no GPU version there
    static let fallback = "Engine_Metal_Diamond: the extension \"Total-Field/Scattered-Field Extension\" has no GPU "
        + "version here, running the CPU loops"
    static let metal = "Create FDTD engine (Metal, diamond-blocked)\n"
    static let multithreaded = "Create FDTD engine (compressed SSE + multi-threading)\n"

    @Test func benchRow() throws {
        let world = FakeWorld()
        let during = "others  45%  during 7.9 s: self cpu 99% gpu>=0.00 s, others cpu 52% gpu 2%, gpu dev 2%"
        var tool = FakeToolRun(lines: [
            "# notch_s1_n16000  load avg 3.42",
            "cg29@multithreaded:4  1877.3 MC/s  2.29 s  16000 TS x 0.268 MC  \(during)  [ref]  openEMS v0.37.0-44-g074a687",
            "cg29@metal-diamond:0  601.2 MC/s  7.13 s  16000 TS x 0.268 MC  \(during)  probes rel=0.0e+00  "
                + "S11: max|dS|=0.0e+00 max dB=0.0e+00  (tolerant)  openEMS v0.37.0-44-g074a687",
            "NOTHING REQUIRED TO MATCH: every compared config is tolerant (cg29@metal-diamond:0)",
        ])
        tool.files = ["runs/notch_s1_n16000/cg29_multithreaded_t4/rep0/openEMS.log": Self.multithreaded,
                      "runs/notch_s1_n16000/cg29_metal-diamond_t0/rep0/openEMS.log": Self.metal + Self.fallback + "\n"]
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["bench", "notch", "--config", "cg29@multithreaded:4", "--config", "cg29@metal-diamond:0"])
        #expect(run.exit == 0, "\(run.stderr)")
        let rows = try #require(run.result["rows"]?.array)
        #expect(rows.map { $0["engineConfirmed"]?.bool } == [true, true])
        let fallbacks = run.envelope["warnings"]?.array?.filter { $0["code"]?.string == "gpu_fallback" } ?? []
        #expect(fallbacks.map { $0["message"]?.string } == [
            "cg29@metal-diamond:0: the metal-diamond engine ran the CPU loops instead of the GPU"])
    }

    @Test func checkExtra() throws {
        let world = FakeWorld()
        let extra = "cg29@metal-diamond:0"
        let tool = VerdictTests.checkTool(blocks: CheckCommand.models, mismatch: [],
                                          final: "check.sh t: ALL IDENTICAL (6 models)", exit: 0, extra: extra,
                                          extraLog: Self.metal + Self.fallback + "\n")
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["check", "cg29", "--tag", "t", "--lite", "--rfsim", FakeWorld.rfsim, "--extra", extra])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.errorCodes.isEmpty)
        #expect(run.result["exactRows"]?.double == 18)
        let fallbacks = run.envelope["warnings"]?.array?.filter { $0["code"]?.string == "gpu_fallback" } ?? []
        #expect(fallbacks.map { $0["message"]?.string } == CheckCommand.models.map {
            "\($0.label) \(extra): the metal-diamond engine ran the CPU loops instead of the GPU"
        })
    }

    @Test func abConfig() throws {
        let world = FakeWorld()
        let record = """
            # notch_s1_n16000  2026-11-06 12:00  load avg 3.10  1 rounds, interleaved
            r0 c0   1877.3 MC/s  others cpu   47% gpu   3%  reference
            r0 c1    601.2 MC/s  others cpu   52% gpu   2%  probes rel 4.5e-07
            # summary notch_s1_n16000: median MC/s [min-max], median paired ratio to c0 [min-max], others cpu/gpu median, result
            c0 cg29@multithreaded:4   1877.3 [1877-1877]  x1.000 [1.000-1.000]  others 47%/3%  identical,reference
            c1 cg29@metal-diamond:0    601.2 [601-601]  x0.320 [0.320-0.320]  others 52%/2%  probes rel 4.5e-07

            """
        var tool = FakeToolRun(lines: record.split(separator: "\n").map(String.init))
        let compile = "Engine_Metal_Diamond: kernel compilation failed: program_source:812:5: use of undeclared identifier"
        tool.files = ["abtest.txt": record,
                      "runs/ab_notch_s1_n16000/c0/r0/openEMS.log": Self.multithreaded,
                      "runs/ab_notch_s1_n16000/c1/r0/openEMS.log": Self.metal + compile + "\n"]
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["ab", "notch", "--config", "cg29@multithreaded:4", "--config", "cg29@metal-diamond:0",
                             "--rounds", "1"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(!run.errorCodes.contains("engine_not_confirmed"))
        let fallback = try #require(run.issue("warnings", "gpu_fallback"))
        #expect(fallback["message"]?.string
                == "c1 cg29@metal-diamond:0 (r0): the metal-diamond engine ran the CPU loops instead of the GPU")
    }

    @Test func validationRun() throws {
        let world = FakeWorld()
        let libraries = FdtdLibraries.fileNames.map { "\"~/opt/openEMS-dev/snap/cg29/\($0)\"" }.joined(separator: ", ")
        let json = """
            {"meta": {"tag": "\(FakeWorld.stamp)", "engine": "metal-diamond", "libraries": [\(libraries)], "quick": true},
             "timings": {"slab": 1.7},
             "runs": {"slab": [{"run": "slab_ref", "engine": "Metal, diamond-blocked", "threads": "0"}]},
             "results": [{"case": "slab", "quantity": "max |R - R_exact|", "value": 0.001, "reference": 0.0,
                          "error": 0.001, "tol": 0.01, "kind": "abs", "passed": true, "note": ""}]}
            """
        var tool = FakeToolRun(lines: ["slab: slab_ref", Self.fallback, "1 of 1 checks passed."])
        tool.files = ["validation/validation_\(FakeWorld.stamp).json": json]
        tool.report = FakeToolRun.report(mode: "script", argv: [FakeWorld.repo + "/bench/validation/run_validation.py"],
                                         exit: 0, load: FakeSystem.load(cpuOther: 40, gpuOther: 2, cpuSelf: 99, wall: 3))
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["validate", "--lib", "cg29", "--engine", "metal-diamond", "--quick", "--case", "slab"])
        #expect(run.exit == 0, "\(run.stderr)")
        let fallback = try #require(run.issue("warnings", "gpu_fallback"))
        #expect(fallback["message"]?.string
                == "the validation suite (1 run): the metal-diamond engine ran the CPU loops instead of the GPU")
        // a log without a fallback line gives none
        let other = FakeWorld()
        var plain = tool
        plain.lines = ["slab: slab_ref", "1 of 1 checks passed."]
        other.system.update { $0.spawn = plain.handler(other.system) }
        let quiet = other.run(["validate", "--lib", "cg29", "--engine", "metal-diamond", "--quick", "--case", "slab"])
        #expect(quiet.exit == 0, "\(quiet.stderr)")
        #expect(!quiet.warningCodes.contains("gpu_fallback"))
    }
}

@Suite struct NoInstallTests {
    /// Every file and folder under ~/opt of the fake Mac (the installed prefix and the snapshot directory).
    static func protected(_ system: FakeSystem) -> [String: Data] {
        var state: [String: Data] = [:]
        for path in system.allPaths where path.hasPrefix(FakeWorld.home + "/opt") {
            state[path] = system.readFile(path) ?? Data("<folder>".utf8)
        }
        return state
    }

    @Test func noCommandWritesUnderThePrefixOrTheSnapshots() throws {
        for (name, arguments, _) in PlanTests.cases {
            for overwrite in [false, true] {
                let world = PlanTests.world()
                let before = Self.protected(world.system)
                _ = world.run(arguments + (overwrite ? ["--overwrite"] : []))
                #expect(Self.protected(world.system) == before, "\(name)")
            }
        }
        // a run that spawns: run folder, launcher, report and envelope copy all go elsewhere
        let world = PlanTests.world()
        let before = Self.protected(world.system)
        var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0", "FDTDKIT_CALL_END 0"])
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: .null)],
                                         libraries: FdtdLibraries.fileNames.map { FakeWorld.snaps + "/cg29/" + $0 })
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["run", "/work/board.py", "--lib", "cg29", "--keep-runs"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(Self.protected(world.system) == before)
        let folder = try #require(run.envelope["runFolder"]?.string)
        #expect(folder.hasPrefix(FakeWorld.runs + "/emskit-fdtd/"))
        #expect(world.system.isRegularFile(folder + "/fdtdkit_run.py"))
        #expect(world.system.isRegularFile(folder + "/envelope.json"))
    }

    // MARK: S3 at plan time: protected_path

    /// The fake Mac's installed prefix (the folder above FakeWorld.installed).
    static let prefix = FakeWorld.home + "/opt/openEMS"

    /// `arguments` on a fresh fake Mac (changed by `setup` first), which must be refused before anything is created,
    /// renamed or spawned: exit 2 with protected_path errors only, the first naming `field` and `root`, ~/opt as it
    /// was.
    @discardableResult
    static func refused(_ arguments: [String], field: String?, root: String,
                        setup: (inout FakeWorld) -> Void = { _ in }) -> CLIRun {
        var world = PlanTests.world()
        setup(&world)
        let before = protected(world.system)
        let run = world.run(arguments)
        let label = arguments.joined(separator: " ")
        #expect(run.exit == 2, "\(label): \(run.stderr)")
        #expect(run.status == "error", "\(label)")
        #expect(!run.errorCodes.isEmpty && run.errorCodes.allSatisfy { $0 == "protected_path" },
                "\(label): \(run.errorCodes)")
        let issue = run.issue("errors", "protected_path")
        #expect(issue?["field"]?.string == field, "\(label)")
        #expect(issue?["message"]?.string?.contains(root) == true, "\(label): \(issue?["message"] ?? .null)")
        #expect(issue?["hint"]?.string?.contains(root) == true, "\(label)")
        #expect(world.system.spawned.isEmpty, "\(label)")
        #expect(run.envelope["runFolder"] == .null, "\(label)")
        #expect(protected(world.system) == before, "\(label)")
        return run
    }

    /// --output inside the installed prefix, or holding it, is refused before finish() could rename or write it; a link
    /// or `..` does not hide it, and the refused envelope goes to stdout.
    @Test func outputsInOrAboveAProtectedFolderAreRefused() throws {
        Self.refused(["info", "--output", FakeWorld.installed + "/x.json"], field: "--output", root: Self.prefix)
        // with --overwrite, finish() would rename the installed library away and write its backup beside it
        let dylib = FakeWorld.installed + "/libopenEMS.0.37.0.dylib"
        let renamed = Self.refused(["info", "--output", dylib, "--overwrite"], field: "--output", root: Self.prefix)
        let named = renamed.envelope["errors"]?.array?.compactMap { $0["message"]?.string } ?? []
        #expect(named.count == 2, "\(named)")
        #expect(named.last?.hasPrefix("the backup of --output \(dylib).previous-\(FakeWorld.stamp) lies inside") == true)
        #expect(renamed.stdout.contains("\"protected_path\""))
        // a folder above the prefix (it holds the prefix and SNAPS), in a run command's dry run too
        Self.refused(["info", "--output", FakeWorld.home + "/opt", "--overwrite"], field: "--output", root: Self.prefix)
        let holds = Self.refused(["diamond-check", "cg29", "--output", FakeWorld.home + "/opt", "--overwrite",
                                  "--dry-run"], field: "--output", root: Self.prefix)
        let message = holds.issue("errors", "protected_path")?["message"]?.string ?? ""
        #expect(message.contains("\(FakeWorld.home)/opt holds the installed openEMS prefix \(Self.prefix)"), "\(message)")
        // a symbolic link in /tmp to the lib folder, and a relative path with ..
        let linked = Self.refused(["info", "--output", "/tmp/handy/x.json"], field: "--output", root: Self.prefix) {
            $0.system.addLink("/tmp/handy", to: FakeWorld.installed)
        }
        let shown = linked.issue("errors", "protected_path")?["message"]?.string ?? ""
        #expect(shown.contains("/tmp/handy/x.json (\(FakeWorld.installed)/x.json) lies inside"), "\(shown)")
        Self.refused(["info", "--output", "../../Users/tester/opt/openEMS/lib/../x.json"], field: "--output",
                     root: Self.prefix)
    }

    /// --record, --out-dir, --results and a --tag table in a protected folder are refused, before would_overwrite, and
    /// in a real run before anything is renamed.
    @Test func namedOutputsInAProtectedFolderAreRefused() throws {
        let ab = ["ab", "notch", "--scale", "3", "--nrts", "2000", "--config", "stock@multithreaded:4", "--config",
                  "cg29@multithreaded:4", "--rounds", "1"]
        Self.refused(ab + ["--record", Self.prefix + "/ab.txt", "--dry-run"], field: "--record", root: Self.prefix)
        // the snapshot cg29 itself, which would otherwise be would_overwrite (5), a planned rename (--overwrite
        // --dry-run) and a real one (--overwrite)
        let e2e = ["e2e", "gcpw", "--lib", "cg29", "--rfsim", FakeWorld.rfsim, "--out-dir", FakeWorld.snaps + "/cg29"]
        for extra in [["--dry-run"], ["--overwrite", "--dry-run"], ["--overwrite"]] {
            Self.refused(e2e + extra, field: "--out-dir", root: FakeWorld.snaps)
        }
        let bench = ["bench", "patch", "--nrts", "2000", "--config", "cg29@multithreaded:4", "--tag", "t"]
        for results in [FakeWorld.snaps, FakeWorld.snaps + "/cg29"] {
            Self.refused(bench + ["--results", results, "--dry-run"], field: "--results", root: FakeWorld.snaps)
        }
        Self.refused(["validate", "--lib", "cg29", "--tag", "t", "--results", FakeWorld.snaps + "/cg29", "--dry-run"],
                     field: "--results", root: FakeWorld.snaps)
        // a table that is a dangling link into the prefix: bench.py's open(fn, 'w') would create its target there
        let table = "patch_s1_n2000_t.txt"
        Self.refused(bench + ["--dry-run"], field: "--tag", root: Self.prefix) {
            $0.system.addLink(FakeWorld.repo + "/results/" + table, to: Self.prefix + "/" + table)
        }
    }

    /// --runs, $OPENEMS_BENCH_RUNS and an EXPORT_* knob folder in a protected folder are refused: no run folder, scratch
    /// folder or export is made there.
    @Test func runFoldersInAProtectedFolderAreRefused() throws {
        Self.refused(["diamond-check", "cg29", "--runs", FakeWorld.snaps + "/runs", "--dry-run"], field: "--runs",
                     root: FakeWorld.snaps)
        // a real run would make RUNS/emskit-fdtd/... in the snapshot folder
        Self.refused(["debye-check", "cg29", "--runs", FakeWorld.snaps], field: "--runs", root: FakeWorld.snaps)
        // `..`, `.` and a trailing slash; a link in /tmp to the snapshot folder
        Self.refused(["diamond-check", "cg29", "--runs", "../../Users/tester/opt/openEMS-dev/./snap/", "--dry-run"],
                     field: "--runs", root: FakeWorld.snaps)
        Self.refused(["run", "/work/board.py", "--lib", "cg29", "--runs", "/tmp/snaplink/x", "--dry-run"],
                     field: "--runs", root: FakeWorld.snaps) {
            $0.system.addLink("/tmp/snaplink", to: FakeWorld.snaps)
        }
        // load has no --runs: RUNS from the environment, whose emskit-fdtd folder would stay behind
        Self.refused(["load", "--seconds", "1"], field: nil, root: FakeWorld.snaps) {
            $0.environment["OPENEMS_BENCH_RUNS"] = FakeWorld.snaps + "/runs"
        }
        Self.refused(["run", "/work/board.py", "--lib", "cg29", "--knob",
                      "OPENEMS_EXPORT_FIELDS=" + FakeWorld.snaps + "/cg29", "--dry-run"], field: "--knob",
                     root: FakeWorld.snaps)
    }

    static let noOpenEMS = "ModuleNotFoundError: No module named 'openEMS'"

    /// Without the probe's answer the defaults stay protected: a Python that cannot import openEMS, a --repo that is
    /// not a tools tree (no probe at all), and a $HOME that names another folder (the account's home folder from the
    /// password database still gives ~/opt/openEMS and SNAPS). info would otherwise rename the library away.
    @Test func theDefaultsStayProtectedWithoutTheProbe() throws {
        let dylib = FakeWorld.installed + "/libopenEMS.0.37.0.dylib"
        Self.refused(["info", "--output", dylib, "--overwrite"], field: "--output", root: Self.prefix) {
            $0.system.update { $0.importError = Self.noOpenEMS }
        }
        Self.refused(["info", "--repo", "/work/notatree", "--output", dylib, "--overwrite"], field: "--output",
                     root: Self.prefix) {
            $0.system.addDirectory("/work/notatree")
        }
        let snapshot = FakeWorld.snaps + "/cg29/libopenEMS.0.dylib"
        for output in [dylib, snapshot] {
            let root = output == dylib ? Self.prefix : FakeWorld.snaps
            Self.refused(["info", "--output", output, "--overwrite"], field: "--output", root: root) {
                $0.environment["HOME"] = "/Users/other"
                $0.system.addDirectory("/Users/other")
                $0.system.update { $0.importError = Self.noOpenEMS }
            }
        }
    }

    /// A file a tool writes in place that is another name (a hard link) of a file in a protected folder is refused:
    /// bench.py's open(fn, 'w') and abtest's open(out, 'a') would change that file. A second name elsewhere passes.
    @Test func hardLinksIntoAProtectedFolderAreRefused() throws {
        let base = FakeWorld.snaps + "/cg29/BASE"
        let table = "/work/res/patch_s1_n2000_t1.txt"
        let bench = ["bench", "patch", "--nrts", "2000", "--config", "cg29@multithreaded:4", "--tag", "t1", "--results",
                     "/work/res", "--overwrite"]
        for extra in [["--dry-run"], []] {
            let run = Self.refused(bench + extra, field: "--tag", root: FakeWorld.snaps) {
                $0.system.addFile(base, "v0.37.0-45-g1620939\n")
                $0.system.addHardLink(table, to: base)
            }
            let message = run.issue("errors", "protected_path")?["message"]?.string ?? ""
            #expect(message.contains("the table \(table) is also \(base) (a hard link) in the snapshot folder"),
                    "\(message)")
        }
        let check = ["check", "cg29", "--tag", "t", "--lite", "--rfsim", FakeWorld.rfsim, "--overwrite", "--dry-run"]
        Self.refused(check, field: "--tag", root: Self.prefix) {
            $0.system.addHardLink(FakeWorld.repo + "/results/notch_s1_n16000_t.txt",
                                  to: FakeWorld.installed + "/libnf2ff.0.dylib")
        }
        let ab = ["ab", "notch", "--scale", "3", "--nrts", "2000", "--config", "stock@multithreaded:4", "--config",
                  "cg29@multithreaded:4", "--rounds", "1", "--record", "/work/ab.txt", "--append", "--dry-run"]
        Self.refused(ab, field: "--record", root: FakeWorld.snaps) {
            $0.system.addFile(base, "v0.37.0-45-g1620939\n")
            $0.system.addHardLink("/work/ab.txt", to: base)
        }
        Self.refused(["validate", "--lib", "cg29", "--tag", "t", "--results", "/work/res", "--overwrite", "--dry-run"],
                     field: "--tag", root: FakeWorld.snaps) {
            $0.system.addFile(base, "v0.37.0-45-g1620939\n")
            $0.system.addHardLink("/work/res/validation_t.md", to: base)
        }
        let world = PlanTests.world()
        world.system.addFile("/work/kept/table.txt", "# patch_s1_n2000  2026-11-05 10:00\n")
        world.system.addHardLink(table, to: "/work/kept/table.txt")
        let elsewhere = world.run(bench + ["--dry-run"])
        #expect(elsewhere.exit == 0 && elsewhere.errorCodes.isEmpty, "\(elsewhere.stderr)")
    }

    /// check.sh's bench.py writes beside the real folder of check.sh: a REPO whose bench/ is a link into SNAPS is
    /// refused, and a table that exists beside an ordinary linked bench folder is would_overwrite.
    @Test func checkTablesGoBesideTheRealBenchFolder() throws {
        let check = ["check", "cg29", "--tag", "t", "--lite", "--rfsim", FakeWorld.rfsim, "--repo", "/work/copy",
                     "--dry-run"]
        func linkedTree(_ world: inout FakeWorld, tools: String) {
            for marker in FdtdDiscovery.markers {
                let body = marker == "bench/bench.py" ? "line += '  ' + usage.fmt(r['use'])\n" : "# \(marker)\n"
                world.system.addFile((marker.hasPrefix("bench/") ? tools : "/work/copy") + "/" + marker, body)
            }
            world.system.addLink("/work/copy/bench", to: tools + "/bench")
        }
        Self.refused(check, field: "--repo", root: FakeWorld.snaps) {
            linkedTree(&$0, tools: FakeWorld.snaps + "/tools")
        }
        var world = PlanTests.world()
        linkedTree(&world, tools: "/work/tools")
        world.system.addFile("/work/tools/results/patch_s5_n1200_t.txt", "# patch_s5_n1200\n")
        let run = world.run(check)
        #expect(run.exit == 5 && run.errorCodes == ["would_overwrite"], "\(run.stderr)")
        let message = run.issue("errors", "would_overwrite")?["message"]?.string ?? ""
        #expect(message.contains("/work/tools/results/patch_s5_n1200_t.txt"), "\(message)")
    }

    /// The fake Mac with the installed prefix on another volume, reached through the link ~/opt/openEMS (the name dyld
    /// and the probe use), and no SNAPS under ~/opt.
    static func installBehindALink(_ world: inout FakeWorld) {
        let system = world.system
        let moved = "/Volumes/X/openEMS/lib"
        let names = ["libopenEMS.0.37.0.dylib", "libCSXCAD.0.dylib", "libnf2ff.0.dylib"]
        let files = names.map { (name: $0, data: system.readFile(FakeWorld.installed + "/" + $0) ?? Data()) }
        try? system.removeItem(Self.prefix)
        try? system.removeItem(FakeWorld.home + "/opt/openEMS-dev")
        for file in files { system.addFile(moved + "/" + file.name, file.data, executable: true) }
        system.addLink(moved + "/libopenEMS.0.dylib", to: "libopenEMS.0.37.0.dylib")
        system.addLink(Self.prefix, to: "/Volumes/X/openEMS")
    }

    /// A folder above the name a protected folder is used by holds it, even when its real path lies elsewhere:
    /// renaming ~/opt would cut the path dyld and the Python module load the installed library through.
    @Test func aFolderAboveTheNameOfAProtectedFolderHoldsIt() throws {
        let run = Self.refused(["info", "--output", FakeWorld.home + "/opt", "--overwrite"], field: "--output",
                               root: Self.prefix) { Self.installBehindALink(&$0) }
        let message = run.issue("errors", "protected_path")?["message"]?.string ?? ""
        let expected = "\(FakeWorld.home)/opt holds the installed openEMS prefix \(Self.prefix)"
        #expect(message.contains(expected), "\(message)")
    }

    /// finish() looks at --output again after the tools ran: a folder on its path that became a link into the prefix
    /// meanwhile is refused then, nothing is written there, the envelope goes to stdout and the run folder is kept.
    @Test func outputIsCheckedAgainBeforeItIsWritten() throws {
        let world = PlanTests.world()
        world.system.addDirectory("/work/out")
        let before = Self.protected(world.system)
        let system = world.system
        var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0", "FDTDKIT_CALL_END 0"])
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: .null)],
                                         libraries: FdtdLibraries.fileNames.map { FakeWorld.snaps + "/cg29/" + $0 })
        tool.during = { _ in
            try? system.removeItem("/work/out")
            system.addLink("/work/out", to: FakeWorld.installed)
        }
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["run", "/work/board.py", "--lib", "cg29", "--output", "/work/out/run.json"])
        #expect(run.exit == 2, "\(run.stderr)")
        #expect(run.errorCodes == ["protected_path"])
        let message = run.issue("errors", "protected_path")?["message"]?.string ?? ""
        #expect(message.contains("/work/out/run.json (\(FakeWorld.installed)/run.json) lies inside"), "\(message)")
        #expect(run.stdout.contains("\"protected_path\""))
        #expect(!world.system.fileExists(FakeWorld.installed + "/run.json"))
        #expect(Self.protected(world.system) == before)
        // an error keeps the run folder as it is (no cleanup), as any other does
        #expect(run.envelope["keptRuns"]?.bool == true)
    }

    /// check's own call site: --runs in SNAPS (dry and real) and a table that is a dangling link into the prefix.
    @Test func checkOutputsInAProtectedFolderAreRefused() throws {
        let check = ["check", "cg29", "--tag", "t", "--lite", "--rfsim", FakeWorld.rfsim]
        for extra in [["--dry-run"], []] {
            Self.refused(check + ["--runs", FakeWorld.snaps + "/x"] + extra, field: "--runs", root: FakeWorld.snaps)
        }
        let table = "patch_s5_n1200_t.txt"
        Self.refused(check + ["--dry-run"], field: "--tag", root: Self.prefix) {
            $0.system.addLink(FakeWorld.repo + "/results/" + table, to: Self.prefix + "/" + table)
        }
    }

    /// --out-dir and --record are replaced or written as a whole, so one that holds SNAPS is refused as well.
    @Test func anOutDirOrRecordThatHoldsAProtectedFolderIsRefused() throws {
        let above = FakeWorld.home + "/opt/openEMS-dev"
        let e2e = ["e2e", "gcpw", "--lib", "cg29", "--rfsim", FakeWorld.rfsim, "--out-dir", above, "--overwrite"]
        let ab = ["ab", "notch", "--scale", "3", "--nrts", "2000", "--config", "stock@multithreaded:4", "--config",
                  "cg29@multithreaded:4", "--rounds", "1", "--record", above, "--append", "--dry-run"]
        for (arguments, field) in [(e2e + ["--dry-run"], "--out-dir"), (e2e, "--out-dir"), (ab, "--record")] {
            let run = Self.refused(arguments, field: field, root: FakeWorld.snaps)
            let message = run.issue("errors", "protected_path")?["message"]?.string ?? ""
            #expect(message.contains("\(above) holds the snapshot folder \(FakeWorld.snaps)"), "\(message)")
        }
    }

    /// A real load on the fake Mac: the LOAD helper's line and a launcher report.
    static func load(_ world: FakeWorld, _ extra: [String] = []) -> CLIRun {
        let value: FdtdJSONValue = .object(["load": FakeSystem.load(cpuOther: 52, gpuOther: 1),
                                            "processesSeen": .number(412), "gpuClientsSeen": .number(9),
                                            "utilSamples": .number(2)])
        var tool = FakeToolRun(lines: [FakeSystem.line(FdtdSnippets.loadTag, value).trimmingCharacters(in: .newlines)])
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        world.system.update { $0.spawn = tool.handler(world.system) }
        return world.run(["load", "--seconds", "1"] + extra)
    }

    /// A refused load records its planned invocation in the scratch folder a real load writes to
    /// (`.<stamp>-load-<pid>`), the one the protected-folder check looked at, not a run folder load never makes.
    @Test func aRefusedLoadPlansInTheScratchFolder() throws {
        let runs = FakeWorld.snaps + "/runs"
        let run = Self.refused(["load", "--seconds", "1"], field: nil, root: FakeWorld.snaps) {
            $0.environment["OPENEMS_BENCH_RUNS"] = runs
        }
        let invocation = try #require(run.envelope["invocations"]?.array?.first)
        let argv = invocation["argv"]?.array?.compactMap(\.string) ?? []
        let scratch = runs + "/emskit-fdtd/.\(FakeWorld.stamp)-load-\(FakeWorld.pid)"
        #expect(argv.contains(scratch + "/" + FdtdLauncherSource.fileName), "\(argv)")
        #expect(!argv.contains { $0.contains("/\(FakeWorld.stamp)-load-") }, "\(argv)")
    }

    /// A protected folder that cannot be found stops nothing: load with a Python that cannot import openEMS (no
    /// installed library from the probe), and with a --snaps folder that does not exist.
    @Test func aMissingProtectedFolderStopsNothing() throws {
        let world = FakeWorld()
        world.system.update { $0.importError = Self.noOpenEMS }
        let other = FakeWorld()
        for run in [Self.load(world), Self.load(other, ["--snaps", "/tmp/missing-snaps"])] {
            #expect(run.exit == 0 && !run.errorCodes.contains("protected_path"), "\(run.stderr)")
            #expect(run.envelope["load"]?["valid"]?.bool == true, "\(run.stderr)")
        }
    }

    /// A sibling whose name only starts with the same letters, a folder above SNAPS that is only written into, ordinary
    /// folders, and every planned command with its default locations pass.
    @Test func neighboursOrdinaryFoldersAndDefaultsPass() throws {
        let world = PlanTests.world()
        world.system.addDirectory(FakeWorld.home + "/opt/openEMS-other")
        world.system.addDirectory("/work/out")
        for path in [FakeWorld.home + "/opt/openEMS-other/info.json", FakeWorld.home + "/opt/openEMS.json"] {
            let run = world.run(["info", "--output", path])
            #expect(run.exit == 0, "\(path): \(run.stderr)")
            #expect(world.system.isRegularFile(path), "\(path)")
        }
        let bench = ["bench", "patch", "--nrts", "2000", "--config", "cg29@multithreaded:4", "--tag", "t", "--dry-run"]
        for extra in [["--results", "/work/out", "--runs", "/work/runs"],
                      ["--results", FakeWorld.home + "/opt/openEMS-dev", "--runs", FakeWorld.snaps + "-old"]] {
            let run = world.run(bench + extra)
            #expect(run.exit == 0 && run.errorCodes.isEmpty, "\(extra): \(run.stderr)")
        }
        for (name, arguments, exit) in PlanTests.cases {
            let run = PlanTests.world().run(arguments)
            #expect(run.exit == exit && !run.errorCodes.contains("protected_path"), "\(name): \(run.stderr)")
        }
    }

    /// The installed prefix is the folder above lib/; a library in ~/lib protects ~/lib, never the home folder, and the
    /// account's home folder counts as much as $HOME.
    @Test func thePrefixIsTheFolderAboveLib() {
        let system = FakeSystem()
        for dir in [FakeWorld.installed, FakeWorld.home + "/lib", "/opt/odd/libs", "/Users/account/lib"] {
            system.addDirectory(dir)
        }
        func prefix(_ folder: String) -> String {
            FdtdProtectedPaths.prefix(of: folder, homes: [FakeWorld.home, "/Users/account"], system: system)
        }
        #expect(prefix(FakeWorld.installed) == Self.prefix)
        #expect(prefix(FakeWorld.home + "/lib") == FakeWorld.home + "/lib")
        #expect(prefix("/Users/account/lib") == "/Users/account/lib")
        #expect(prefix("/opt/odd/libs") == "/opt/odd/libs")
    }

    /// getpwuid_r's buffer starts at sysconf's size and doubles on ERANGE up to the limit, so that a long password
    /// entry still gives the account's home folder (an unknown one would leave its spelling of ~ unprotected).
    @Test func theAccountHomeLookupGrowsItsBuffer() {
        #expect(FdtdPasswordDatabase.startSize(suggested: 16384) == 16384)
        #expect(FdtdPasswordDatabase.startSize(suggested: -1) == FdtdPasswordDatabase.fallbackSize)
        let long = "/Users/" + String(repeating: "h", count: 9000)
        var sizes: [Int] = []
        // an entry of about 9 KB: ERANGE at 4096 and 8192 bytes, found at 16384
        let home = FdtdPasswordDatabase.home(startSize: 4096) { entry, buffer, size, found in
            sizes.append(size)
            guard size > long.utf8.count else { return ERANGE }
            long.withCString { _ = strcpy(buffer, $0) }
            entry.pointee.pw_dir = buffer
            found.pointee = entry
            return 0
        }
        #expect(home == long)
        #expect(sizes == [4096, 8192, 16384])
        // ERANGE at every size ends at the limit; another error or no entry ends at once
        sizes = []
        let tooLong = FdtdPasswordDatabase.home(startSize: 4096, limit: 32768) { _, _, size, _ in
            sizes.append(size)
            return ERANGE
        }
        #expect(tooLong == nil && sizes == [4096, 8192, 16384, 32768])
        sizes = []
        let failed = FdtdPasswordDatabase.home(startSize: 4096) { _, _, size, _ in
            sizes.append(size)
            return EIO
        }
        let noEntry = FdtdPasswordDatabase.home(startSize: 4096) { _, _, size, _ in
            sizes.append(size)
            return 0
        }
        #expect(failed == nil && noEntry == nil && sizes == [4096, 4096])
        // the live lookup reads the password database, not $HOME
        #expect(LiveSystem().accountHome() == NSHomeDirectoryForUser(NSUserName()))
    }

    /// The real file system, with stand-in roots in a temporary folder (never ~/opt): letter case, links, dangling
    /// links and `..` after a link are judged by file identity; a sibling with the same first letters is not inside.
    @Test func realFoldersAreComparedByIdentity() throws {
        let temp = try TempFolder("protected")
        defer { temp.remove() }
        try temp.write("prefix/lib/libopenEMS.0.dylib", Data("lib\n".utf8))
        try temp.write("snap/cg29/libopenEMS.0.dylib", Data("lib\n".utf8))
        try temp.write("prefix-old/kept.txt", Data("kept\n".utf8))
        let files = FileManager.default
        try files.createSymbolicLink(atPath: temp.file("into"), withDestinationPath: temp.file("prefix/lib"))
        try files.createSymbolicLink(atPath: temp.file("later.txt"), withDestinationPath: temp.file("snap/new.txt"))
        let roots = [FdtdProtectedRoot(name: "the installed openEMS prefix", path: temp.file("prefix")),
                     FdtdProtectedRoot(name: "the snapshot folder", path: temp.file("snap"))]
        func refused(_ path: String, replaced: Bool = true) -> FdtdIssue? {
            let target = FdtdWriteTarget(label: "--output", field: "--output", path: path, replaced: replaced)
            return FdtdProtectedPaths.refusal(target, roots: roots, system: LiveSystem())
        }
        // APFS is case-insensitive unless it was formatted otherwise; then the other spelling is another folder
        let caseInsensitive = files.fileExists(atPath: temp.path + "/PREFIX/LIB")
        #expect((refused(temp.path + "/PREFIX/LIB/x.json")?.code == .protectedPath) == caseInsensitive)
        #expect(refused(temp.path + "/Snap", replaced: false) != nil || !caseInsensitive)
        // a link to the lib folder, a dangling link into SNAPS, and `..` after a link (a raw EXPORT_* value is not
        // folded first): the kernel's walk, not the spelling
        let linked = refused(temp.file("into/x.json"))?.message ?? ""
        #expect(linked.contains("(\(temp.file("prefix/lib/x.json"))) lies inside"), "\(linked)")
        #expect(refused(temp.file("later.txt"))?.message.contains("the snapshot folder") == true)
        #expect(refused(temp.file("into/../x.json"), replaced: false) != nil)
        // is, inside, holds (only when renamed or replaced)
        #expect(refused(temp.file("snap"), replaced: false)?.message.contains(" is the snapshot folder ") == true)
        #expect(refused(temp.file("snap/cg29/new/x.json"), replaced: false) != nil)
        #expect(refused(temp.path)?.message.contains(" holds the installed openEMS prefix ") == true)
        #expect(refused(temp.path, replaced: false) == nil)
        // neighbours
        #expect(refused(temp.file("prefix-old/x.json")) == nil)
        #expect(refused(temp.file("prefix.json")) == nil)
        #expect(refused(temp.file("other/new/x.json")) == nil)
    }
}
