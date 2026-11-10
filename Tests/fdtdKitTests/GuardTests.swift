// SPDX-License-Identifier: GPL-3.0-or-later

// The rules a mutation could switch off without a failing test (the second review's critic): the verdicts of ab,
// validate, debye-check, diamond-check, e2e and run with failing inputs, directly and through each command; the
// sampler-count validity rule (S4) in load, run and validate; load_unavailable; validate's unchanged-JSON guard; a
// launcher without a report; a child that cannot start; --keep-runs; bench's row count beside its summary; info with a
// --rfsim that names no toolkit; tools_modified in a tools tree below the top level of its repository.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct FailingVerdictTests {
    static func codes(_ verdict: FdtdVerdict) -> [FdtdCode] { verdict.errors.map(\.code) }

    // MARK: ab

    static func abConfig(_ index: Int, tolerant: Bool = false, diffs: [String]) -> FdtdABConfigResult {
        let identical = diffs.allSatisfy { $0 == "identical" || $0 == "reference" }
        return FdtdABConfigResult(index: index, config: "c", label: "cg29@x:\(index)", tolerant: tolerant, diffs: diffs,
                                  identical: identical)
    }

    static func abSummaries(_ indices: [Int]) -> [FdtdParsedABSummary] {
        indices.map {
            FdtdParsedABSummary(config: $0, label: "l", medianMcs: 1, minMcs: 1, maxMcs: 1, ratio: 1, minRatio: 1,
                                maxRatio: 1, othersCpu: 1, othersGpu: 1, diffs: "identical", line: "")
        }
    }

    @Test func abFailsOnADifferingRunAndOnAFailedTool() {
        let reference = Self.abConfig(0, diffs: ["reference", "identical"])
        let same = Self.abConfig(1, diffs: ["identical", "identical"])
        func verdict(_ configs: [FdtdABConfigResult], exit: Int32? = 0, summaries: [Int] = [0, 1],
                     exact: Bool = false) -> FdtdVerdict {
            FdtdVerdicts.ab(abtestExit: exit, configs: configs, summaries: Self.abSummaries(summaries), exact: exact)
        }
        let ok = verdict([reference, same])
        #expect(ok.passed && ok.errors.isEmpty && ok.warnings.isEmpty)
        // a run that differs from the reference
        let differing = verdict([reference, Self.abConfig(1, diffs: ["identical", "probes rel 1.2e-03"])])
        #expect(!differing.passed)
        #expect(Self.codes(differing) == [.mismatch])
        // the tool failed or never ended
        #expect(Self.codes(verdict([reference, same], exit: 1)) == [.toolFailed])
        #expect(!verdict([reference, same], exit: nil).passed)
        // a config without its summary line
        #expect(Self.codes(verdict([reference, same], summaries: [0])) == [.toolOutputUnparsed])
        // a tolerant config: a warning without --exact, not_exact with it, mismatch for a PROBLEM
        let tolerant = Self.abConfig(1, tolerant: true, diffs: ["probes rel 4.5e-07"])
        let lenient = verdict([reference, tolerant])
        #expect(lenient.passed)
        #expect(lenient.warnings.map(\.code).contains(.tolerantRows))
        let strict = verdict([reference, tolerant], exact: true)
        #expect(!strict.passed)
        #expect(Self.codes(strict) == [.notExact])
        let problem = Self.abConfig(1, tolerant: true, diffs: ["PROBLEM: port_ut1 has 3 samples, the reference 9"])
        #expect(Self.codes(verdict([reference, problem])) == [.mismatch])
        // a kept run of the reference that differs from its first one
        #expect(Self.codes(verdict([Self.abConfig(0, diffs: ["reference", "probes rel 1e-9"]), same])) == [.mismatch])
    }

    // MARK: validate

    static func validation(checks: [Bool] = [true, true],
                           engine: String = "compressed SSE + multi-threading") -> FdtdValidationReport {
        let libraries = LoadedLibraryTests.images(LoadedLibraryTests.cg29)
        let results = checks.enumerated().map { k, passed in
            FdtdValidationCheck(caseName: "slab", quantity: "q\(k)", error: passed ? 0.001 : 0.5, tol: 0.01,
                                passed: passed)
        }
        return FdtdValidationReport(meta: ["libraries": .array(libraries.map { .string($0) })], timings: [:],
                                    runs: ["slab": [FdtdValidationRun(run: "slab_ref", engine: engine)]],
                                    results: results)
    }

    @Test func validateFailsOnAFailedCheckAndOnAFailedSuite() {
        let system = FakeWorld().system
        func verdict(_ report: FdtdValidationReport?, exit: Int32? = 0,
                     engine: FdtdEngine = .multithreaded) -> FdtdVerdict {
            FdtdVerdicts.validate(exit: exit, report: report, expectedDir: LoadedLibraryTests.cg29, engine: engine,
                                  home: FakeWorld.home, system: system)
        }
        #expect(verdict(Self.validation()).passed)
        let failed = verdict(Self.validation(checks: [true, false]), exit: 1)
        #expect(!failed.passed)
        #expect(Self.codes(failed) == [.validationFailed])
        #expect(failed.errors.first?.message == "slab: q1 failed (error 0.5, tolerance 0.01)")
        // every failed check is named, also when the suite exits 0
        #expect(Self.codes(verdict(Self.validation(checks: [false, false]))) == [.validationFailed, .validationFailed])
        // no JSON, a JSON without checks, a non-zero exit although every check passed, no exit at all
        #expect(Self.codes(verdict(nil, exit: 1)) == [.toolFailed])
        #expect(Self.codes(verdict(Self.validation(checks: []))) == [.toolOutputUnparsed])
        #expect(Self.codes(verdict(Self.validation(), exit: 3)) == [.toolFailed])
        #expect(Self.codes(verdict(Self.validation(), exit: nil)) == [.toolFailed])
        // the runs of a case show another engine; cylindrical runs are left out
        #expect(Self.codes(verdict(Self.validation(engine: "compressed SSE"))) == [.engineNotConfirmed])
        #expect(Self.codes(verdict(Self.validation(), engine: .metalDiamond)) == [.engineNotConfirmed])
        #expect(verdict(Self.validation(engine: "cylindrical multi-grid"), engine: .metalDiamond).passed)
    }

    // MARK: debye-check, diamond-check

    @Test func debyeFailsOnFailDifferentAndAFailedScript() throws {
        let pass = FdtdParsers.debyeOutput(try TestPaths.text(TestPaths.fixture("debye_output.txt")))
        #expect(FdtdVerdicts.debye(exit: 0, parsed: pass).passed)
        let fail = FdtdParsers.debyeOutput(try TestPaths.text(TestPaths.fixture("debye_output_ref.txt")))
        let failed = FdtdVerdicts.debye(exit: 1, parsed: fail)
        #expect(!failed.passed)
        #expect(Self.codes(failed) == [.scriptCheckFailed])
        #expect(failed.errors.first?.message.contains("sse-compressed, SNAP vs REF DIFFERENT") == true)
        // a FAIL line fails whatever the exit status says
        #expect(Self.codes(FdtdVerdicts.debye(exit: 0, parsed: fail)) == [.scriptCheckFailed])
        // PASS beside a non-zero exit, beside a DIFFERENT comparison, and without any comparison
        #expect(Self.codes(FdtdVerdicts.debye(exit: 1, parsed: pass)) == [.toolFailed])
        #expect(Self.codes(FdtdVerdicts.debye(exit: nil, parsed: pass)) == [.toolFailed])
        var mixed = pass
        mixed.comparisons[1].identical = false
        #expect(Self.codes(FdtdVerdicts.debye(exit: 0, parsed: mixed)) == [.verdictDisagrees])
        var bare = pass
        bare.comparisons = []
        #expect(Self.codes(FdtdVerdicts.debye(exit: 0, parsed: bare)) == [.verdictDisagrees])
        // no verdict line, and a run that exported nothing
        var silent = pass
        silent.passed = nil
        silent.verdictLine = nil
        #expect(Self.codes(FdtdVerdicts.debye(exit: 0, parsed: silent)) == [.toolFailed])
        let missing = FdtdParsers.debyeOutput("debye_check.sh: no exported fields from /x (basic): the run failed")
        #expect(Self.codes(FdtdVerdicts.debye(exit: 1, parsed: missing)) == [.toolFailed])
    }

    static let diamondFail = ["== pec, 41,37,30 lines, 400 timesteps ", "  K=1: IDENTICAL", "  K=2: DIFFERENT",
                              "FAIL: 1 of 2 comparisons differ"]

    @Test func diamondFailsOnFailDifferentAndAFailedRun() throws {
        let pass = FdtdParsers.diamondOutput(try TestPaths.text(TestPaths.fixture("diamond_pass.txt")))
        #expect(FdtdVerdicts.diamond(exit: 0, parsed: pass).passed)
        let fail = FdtdParsers.diamondOutput(Self.diamondFail.joined(separator: "\n"))
        let failed = FdtdVerdicts.diamond(exit: 1, parsed: fail)
        #expect(!failed.passed)
        #expect(Self.codes(failed) == [.scriptCheckFailed])
        #expect(failed.errors.first?.message.contains("K=2 DIFFERENT") == true)
        #expect(Self.codes(FdtdVerdicts.diamond(exit: 0, parsed: fail)) == [.scriptCheckFailed])
        // PASS beside a non-zero exit, a DIFFERENT comparison, a GPU path that did not run, an unfinished tuning
        #expect(Self.codes(FdtdVerdicts.diamond(exit: 1, parsed: pass)) == [.toolFailed])
        var mixed = pass
        mixed.comparisons[3].identical = false
        #expect(Self.codes(FdtdVerdicts.diamond(exit: 0, parsed: mixed)) == [.verdictDisagrees])
        var noGpu = pass
        noGpu.gpuPathMissing = ["pec, 41,37,30 lines, 400 timesteps: K=4"]
        #expect(Self.codes(FdtdVerdicts.diamond(exit: 0, parsed: noGpu)) == [.verdictDisagrees])
        var untuned = pass
        untuned.tuningUnfinished = true
        #expect(Self.codes(FdtdVerdicts.diamond(exit: 0, parsed: untuned)) == [.verdictDisagrees])
        var bare = pass
        bare.comparisons = []
        #expect(Self.codes(FdtdVerdicts.diamond(exit: 0, parsed: bare)) == [.verdictDisagrees])
        // a failed run (the fixture's Metal run) and an output without a verdict line
        let broken = FdtdParsers.diamondOutput(try TestPaths.text(TestPaths.fixture("diamond_fail.txt")))
        #expect(Self.codes(FdtdVerdicts.diamond(exit: 1, parsed: broken)) == [.toolFailed])
        var silent = pass
        silent.passed = nil
        silent.verdictLine = nil
        #expect(Self.codes(FdtdVerdicts.diamond(exit: 0, parsed: silent)) == [.toolFailed])
    }

    // MARK: e2e, run

    static let multithreaded = "Create FDTD engine (compressed SSE + multi-threading)"

    static func call(_ create: String? = multithreaded, redirected: Bool = false) -> FdtdCall {
        var call = FdtdCall(index: 0)
        call.createLine = create
        call.stdoutRedirected = redirected
        return call
    }

    @Test func e2eFailsOnAFailedToolAndAnUnconfirmedEngine() {
        let system = FakeWorld().system
        let images = LoadedLibraryTests.images(LoadedLibraryTests.cg29)
        func verdict(exit: Int32? = 0, result: FdtdJSONValue? = .object([:]), json: Bool = true,
                     calls: [FdtdCall] = [Self.call()], engine: FdtdEngine? = nil,
                     interrupted: Bool = false) -> FdtdVerdict {
            FdtdVerdicts.e2e(exit: exit, result: result, resultJsonExists: json, calls: calls, engine: engine,
                             interrupted: interrupted, libraries: images, targetDir: LoadedLibraryTests.cg29,
                             system: system)
        }
        #expect(verdict().passed)
        #expect(verdict(engine: .multithreaded).passed)
        for failing in [verdict(exit: 1), verdict(exit: nil), verdict(result: nil), verdict(json: false)] {
            #expect(!failing.passed)
            #expect(Self.codes(failing) == [.toolFailed])
        }
        // no call, a call of another engine, a call without a Create line
        #expect(Self.codes(verdict(calls: [])) == [.engineNotConfirmed])
        #expect(Self.codes(verdict(engine: .metalDiamond)) == [.engineNotConfirmed])
        #expect(Self.codes(verdict(calls: [Self.call("Create FDTD engine (Metal, diamond-blocked)")]))
                == [.engineNotConfirmed])
        #expect(Self.codes(verdict(calls: [Self.call(nil)])) == [.engineNotConfirmed])
        // a stop leaves the tool's exit to finish(), the engine of the calls made still counts
        #expect(verdict(exit: nil, result: nil, json: false, interrupted: true).passed)
        #expect(Self.codes(verdict(engine: .metalDiamond, interrupted: true)) == [.engineNotConfirmed])
    }

    @Test func runFailsOnAnExceptionAnExitAndAnUnconfirmedEngine() {
        let system = FakeWorld().system
        let images = LoadedLibraryTests.images(LoadedLibraryTests.cg29)
        func verdict(exit: Int32? = 0, exception: String? = nil, calls: [FdtdCall] = [Self.call()],
                     engine: FdtdEngine? = .multithreaded) -> FdtdVerdict {
            FdtdVerdicts.run(exit: exit, exception: exception, calls: calls, engine: engine, libraries: images,
                             targetDir: LoadedLibraryTests.cg29, system: system)
        }
        #expect(verdict().passed && verdict().warnings.isEmpty)
        let raised = verdict(exit: 1, exception: "ValueError: no mesh")
        #expect(!raised.passed)
        #expect(Self.codes(raised) == [.scriptFailed])
        #expect(raised.errors.first?.message == "the script raised ValueError: no mesh")
        #expect(Self.codes(verdict(exit: 3)) == [.scriptFailed])
        #expect(Self.codes(verdict(exit: nil)) == [.scriptFailed])
        // --engine against the calls: another engine, no Create line; a redirected stdout is only a warning
        #expect(Self.codes(verdict(engine: .metalDiamond)) == [.engineNotConfirmed])
        #expect(Self.codes(verdict(calls: [Self.call(nil)])) == [.engineNotConfirmed])
        let hidden = verdict(calls: [Self.call(nil, redirected: true)])
        #expect(hidden.passed)
        #expect(hidden.warnings.map(\.code) == [.engineNotObservable])
        // without --engine the Create line is not judged; a script without a call passes with a warning
        #expect(verdict(calls: [Self.call(nil)], engine: nil).passed)
        let idle = verdict(calls: [], engine: nil)
        #expect(idle.passed)
        #expect(idle.warnings.map(\.code) == [.noOpenemsCall])
    }

    // MARK: The commands with a failing tool

    static let valid = FakeSystem.load(cpuOther: 40, gpuOther: 2, cpuSelf: 390, wall: 4.6)

    static func run(_ tool: FakeToolRun, _ arguments: [String], world: FakeWorld = PlanTests.world()) -> CLIRun {
        world.system.update { $0.spawn = tool.handler(world.system) }
        return world.run(arguments)
    }

    @Test func debyeCheckExitsOneOnFail() throws {
        var tool = FakeToolRun(lines: try TestPaths.lines(TestPaths.fixture("debye_output_ref.txt")))
        tool.exit = 1
        tool.report = FakeToolRun.report(mode: "exec", argv: ["/bin/zsh"], exit: 1, load: Self.valid)
        let failed = Self.run(tool, ["debye-check", "cg29", "--ref", "cg18"])
        #expect(failed.exit == 1, "\(failed.stderr)")
        #expect(failed.status == "fail")
        #expect(failed.errorCodes == ["script_check_failed"])
        #expect(failed.result["verdictLine"]?.string == "FAIL: at least one comparison differs")
        var passing = FakeToolRun(lines: try TestPaths.lines(TestPaths.fixture("debye_output.txt")))
        passing.report = FakeToolRun.report(mode: "exec", argv: ["/bin/zsh"], exit: 0, load: Self.valid)
        let ok = Self.run(passing, ["debye-check", "cg29"])
        #expect(ok.exit == 0 && ok.status == "ok", "\(ok.stderr)")
    }

    @Test func diamondCheckExitsOneOnFail() throws {
        var tool = FakeToolRun(lines: Self.diamondFail)
        tool.exit = 1
        tool.report = FakeToolRun.report(mode: "exec", argv: ["/bin/zsh"], exit: 1, load: Self.valid)
        let failed = Self.run(tool, ["diamond-check", "cg29"])
        #expect(failed.exit == 1, "\(failed.stderr)")
        #expect(failed.errorCodes == ["script_check_failed"])
        #expect(failed.result["different"]?.array?.compactMap(\.string)
                == ["pec, 41,37,30 lines, 400 timesteps: K=2"])
        // a PASS line beside a DIFFERENT comparison is the script disagreeing with itself
        var odd = tool
        odd.lines[3] = "PASS: every comparison is identical"
        odd.exit = 0
        odd.report = FakeToolRun.report(mode: "exec", argv: ["/bin/zsh"], exit: 0, load: Self.valid)
        let disagreeing = Self.run(odd, ["diamond-check", "cg29"])
        #expect(disagreeing.exit == 4)
        #expect(disagreeing.errorCodes == ["verdict_disagrees"])
        var passing = FakeToolRun(lines: try TestPaths.lines(TestPaths.fixture("diamond_pass.txt")))
        passing.report = FakeToolRun.report(mode: "exec", argv: ["/bin/zsh"], exit: 0, load: Self.valid)
        let ok = Self.run(passing, ["diamond-check", "cg29"])
        #expect(ok.exit == 0 && ok.status == "ok", "\(ok.stderr)")
    }

    /// The suite's JSON for one case with `checks` (passed or not) and a case time.
    static func validationJSON(_ checks: [Bool], note: String = "") -> String {
        let libraries = FdtdLibraries.fileNames.map { "\"~/opt/openEMS-dev/snap/cg29/\($0)\"" }.joined(separator: ", ")
        let results = checks.enumerated().map { k, passed in
            "{\"case\": \"slab\", \"quantity\": \"q\(k)\", \"value\": 0.5, \"reference\": 0.0, \"error\": 0.5, "
                + "\"tol\": 0.01, \"kind\": \"abs\", \"passed\": \(passed), \"note\": \"\(note)\"}"
        }.joined(separator: ", ")
        return """
            {"meta": {"engine": "multithreaded", "libraries": [\(libraries)], "quick": true},
             "timings": {"slab": 1.7},
             "runs": {"slab": [{"run": "slab_ref", "engine": "compressed SSE + multi-threading", "threads": "4"}]},
             "results": [\(results)]}
            """
    }

    static let validate = ["validate", "--lib", "cg29", "--engine", "multithreaded", "--quick", "--case", "slab"]
    static let suite = FakeWorld.repo + "/bench/validation/run_validation.py"

    @Test func validateExitsOneOnAFailedCheck() {
        var tool = FakeToolRun(lines: ["slab: slab_ref", "1 of 2 checks passed."])
        tool.files = ["validation/validation_\(FakeWorld.stamp).json": Self.validationJSON([true, false])]
        tool.exit = 1
        tool.report = FakeToolRun.report(mode: "script", argv: [Self.suite], exit: 1, load: Self.valid)
        let failed = Self.run(tool, Self.validate)
        #expect(failed.exit == 1, "\(failed.stderr)")
        #expect(failed.status == "fail")
        #expect(failed.errorCodes == ["validation_failed"])
        #expect(failed.result["passed"]?.double == 1 && failed.result["checks"]?.double == 2)
        #expect(failed.result["failed"]?.array?.first?["quantity"]?.string == "q1")
        // the suite ended without writing its JSON
        var silent = tool
        silent.files = [:]
        let unread = Self.run(silent, Self.validate)
        #expect(unread.exit == 4)
        #expect(unread.errorCodes == ["tool_failed"])
    }

    @Test func runExitsOneWhenTheScriptRaisesOrExits() {
        let libraries = LoadedLibraryTests.images(LoadedLibraryTests.cg29)
        var tool = FakeToolRun(lines: ["FDTDKIT_CALL_BEGIN 0", Self.multithreaded, "FDTDKIT_CALL_END 0"])
        tool.exit = 1
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 1,
                                         calls: [FakeToolRun.call(index: 0, load: Self.valid)], load: Self.valid,
                                         libraries: libraries, exception: "ValueError: no mesh")
        let raised = Self.run(tool, ["run", "/work/board.py", "--lib", "cg29"])
        #expect(raised.exit == 1, "\(raised.stderr)")
        #expect(raised.status == "fail")
        #expect(raised.errorCodes == ["script_failed"])
        #expect(raised.result["exception"]?.string == "ValueError: no mesh")
        tool.exit = 3
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 3,
                                         calls: [FakeToolRun.call(index: 0, load: Self.valid)], load: Self.valid,
                                         libraries: libraries)
        let exited = Self.run(tool, ["run", "/work/board.py", "--lib", "cg29"])
        #expect(exited.exit == 1)
        #expect(exited.errorCodes == ["script_failed"])
        // --engine against a script that ran another engine
        tool.exit = 0
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: Self.valid)], load: Self.valid,
                                         libraries: libraries)
        let other = Self.run(tool, ["run", "/work/board.py", "--lib", "cg29", "--engine", "metal-diamond"])
        #expect(other.exit == 4)
        #expect(other.errorCodes == ["engine_not_confirmed"])
    }

    @Test func abExitsOneOnADifferingRun() {
        let record = """
            # notch_s1_n16000  2026-11-06 12:00  load avg 3.10  1 rounds, interleaved
            r0 c0   1877.3 MC/s  others cpu   47% gpu   3%  reference
            r0 c1   1601.2 MC/s  others cpu   52% gpu   2%  probes rel 1.2e-03
            # summary notch_s1_n16000: median MC/s [min-max], median paired ratio to c0 [min-max], others cpu/gpu median, result
            c0 cg29@multithreaded:4   1877.3 [1877-1877]  x1.000 [1.000-1.000]  others 47%/3%  identical,reference
            c1 cg29@multithreaded:8   1601.2 [1601-1601]  x0.853 [0.853-0.853]  others 52%/2%  probes rel 1.2e-03

            """
        var tool = FakeToolRun(lines: record.split(separator: "\n").map(String.init))
        tool.files = ["abtest.txt": record,
                      "runs/ab_notch_s1_n16000/c0/r0/openEMS.log": Self.multithreaded + "\n",
                      "runs/ab_notch_s1_n16000/c1/r0/openEMS.log": Self.multithreaded + "\n"]
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        let arguments = ["ab", "notch", "--config", "cg29@multithreaded:4", "--config", "cg29@multithreaded:8",
                         "--rounds", "1"]
        let differing = Self.run(tool, arguments)
        #expect(differing.exit == 1, "\(differing.stderr)")
        #expect(differing.status == "fail")
        #expect(differing.errorCodes == ["mismatch"])
        // the same record with an identical c1 passes
        let same = record.replacingOccurrences(of: "probes rel 1.2e-03", with: "identical")
        tool.lines = same.split(separator: "\n").map(String.init)
        tool.files["abtest.txt"] = same
        let ok = Self.run(tool, arguments)
        #expect(ok.exit == 0 && ok.status == "ok", "\(ok.stderr)")
        // abtest itself failed
        tool.exit = 1
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 1)
        let broken = Self.run(tool, arguments)
        #expect(broken.exit == 4)
        #expect(broken.errorCodes == ["tool_failed"])
    }

    @Test func e2eExitsFourWithoutAResult() {
        let lines = ["FDTDKIT_CALL_BEGIN 0", Self.multithreaded,
                     "Time for 34300 iterations with 241995.00 cells : 4.40 sec", "FDTDKIT_CALL_END 0"]
        var tool = FakeToolRun(lines: lines)
        tool.exit = 1
        tool.report = FakeToolRun.report(mode: "script", argv: ["run_one.py"], exit: 1,
                                         calls: [FakeToolRun.call(index: 0, load: Self.valid)], load: Self.valid,
                                         libraries: LoadedLibraryTests.images(LoadedLibraryTests.cg29))
        let run = Self.run(tool, ["e2e", "gcpw", "--lib", "cg29", "--rfsim", FakeWorld.rfsim])
        #expect(run.exit == 4, "\(run.stderr)")
        #expect(run.status == "error")
        #expect(Set(run.errorCodes) == ["tool_failed"])
        #expect(run.errorCodes.count == 3)
    }
}

@Suite struct GuardTests {
    static let thresholds = FdtdThresholds(warnCpu: 150, warnGpu: 10)
    static let valid = FailingVerdictTests.valid

    // MARK: The sampler counts (S4)

    /// A failed ps or ioreg reads as an idle Mac: only the counts tell the two apart.
    @Test func aSamplerThatSawNothingGivesNoValidLoad() throws {
        let result = try FdtdJSON.decode(FdtdSamplerResult.self, from: JSONEncoder().encode(Self.valid))
        func load(_ processes: Int, _ samples: Int) -> FdtdLoad {
            let counts = FdtdLoadCounts(processesSeen: processes, gpuClientsSeen: 8, utilSamples: samples)
            return FdtdLoads.fromSampler(result, counts: counts, thresholds: Self.thresholds)
        }
        #expect(load(400, 6).valid && load(400, 6).invalidReason == nil)
        #expect(load(1, 1).valid)
        let blind = load(0, 6)
        #expect(!blind.valid && !blind.loaded)
        #expect(blind.invalidReason == "the sampler saw no processes (ps gave no sample)")
        #expect(!load(400, 0).valid)
        #expect(load(400, 0).invalidReason?.contains("ioreg") == true)
        #expect(!FdtdLoads.fromSampler(result, counts: nil, thresholds: Self.thresholds).valid)
        let none = FdtdLoadCounts(processesSeen: 400, gpuClientsSeen: 8, utilSamples: 6)
        #expect(!FdtdLoads.fromSampler(nil, counts: none, thresholds: Self.thresholds).valid)
        #expect(!FdtdLoads.shows(blind) && FdtdLoads.shows(load(400, 6)))
    }

    /// `load` on a Mac whose LOAD helper reports these counts.
    static func load(processes: Double, samples: Double) -> CLIRun {
        let world = FakeWorld()
        let value: FdtdJSONValue = .object(["load": FakeSystem.load(cpuOther: 52, gpuOther: 1),
                                            "processesSeen": .number(processes), "gpuClientsSeen": .number(9),
                                            "utilSamples": .number(samples)])
        var tool = FakeToolRun(lines: [FakeSystem.line(FdtdSnippets.loadTag, value).trimmingCharacters(in: .newlines)])
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        return FailingVerdictTests.run(tool, ["load", "--seconds", "1"], world: world)
    }

    @Test func loadWithoutAValidSampleIsLoadUnavailable() {
        let ok = Self.load(processes: 412, samples: 2)
        #expect(ok.exit == 0, "\(ok.stderr)")
        #expect(ok.envelope["load"]?["valid"]?.bool == true)
        #expect(ok.stderr.contains("load: others cpu 52%"))
        for (processes, samples) in [(0.0, 2.0), (412.0, 0.0)] {
            let run = Self.load(processes: processes, samples: samples)
            #expect(run.exit == 4, "\(processes) \(samples)")
            #expect(run.errorCodes == ["load_unavailable"], "\(processes) \(samples)")
            #expect(run.envelope["load"]?["valid"]?.bool == false)
            #expect(!run.stderr.contains("load: others cpu"), "\(run.stderr)")
        }
    }

    /// `report` with the counts of its whole-run load and of every call's load replaced.
    static func counts(_ report: FdtdJSONValue, processes: Double, samples: Double) -> FdtdJSONValue {
        guard case .object(var fields) = report else { return report }
        let counts: FdtdJSONValue = .object(["processesSeen": .number(processes), "gpuClientsSeen": .number(8),
                                             "utilSamples": .number(samples)])
        fields["loadCounts"] = counts
        if case .array(let calls)? = fields["calls"] {
            fields["calls"] = .array(calls.map { call in
                guard case .object(var one) = call else { return call }
                one["loadCounts"] = counts
                return .object(one)
            })
        }
        return .object(fields)
    }

    /// A passing `run` of one FDTD.Run call whose samplers report these counts.
    static func script(processes: Double, samples: Double, _ extra: [String] = []) -> (FakeWorld, CLIRun) {
        let world = PlanTests.world()
        let lines = ["FDTDKIT_CALL_BEGIN 0", FailingVerdictTests.multithreaded,
                     "Time for 34300 iterations with 241995.00 cells : 4.40 sec", "FDTDKIT_CALL_END 0"]
        var tool = FakeToolRun(lines: lines, files: ["runs/x.txt": "bulky\n"])
        let report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                        calls: [FakeToolRun.call(index: 0, load: valid)], load: valid,
                                        libraries: LoadedLibraryTests.images(LoadedLibraryTests.cg29))
        tool.report = counts(report, processes: processes, samples: samples)
        return (world, FailingVerdictTests.run(tool, ["run", "/work/board.py", "--lib", "cg29"] + extra, world: world))
    }

    @Test func aCallSpeedNeedsASamplerThatSawTheMac() throws {
        let (_, seen) = Self.script(processes: 400, samples: 3)
        #expect(seen.exit == 0, "\(seen.stderr)")
        let call = try #require(seen.result["calls"]?.array?.first)
        #expect(call["load"]?["valid"]?.bool == true)
        #expect(call["mcs"]?.double != nil && call["seconds"]?.double == 4.4)
        #expect(seen.envelope["load"]?["valid"]?.bool == true)
        #expect(!seen.warningCodes.contains("load_missing"))
        for (processes, samples) in [(0.0, 3.0), (400.0, 0.0)] {
            let (_, blind) = Self.script(processes: processes, samples: samples)
            #expect(blind.exit == 0, "\(blind.stderr)")
            let withheld = try #require(blind.result["calls"]?.array?.first)
            #expect(withheld["load"]?["valid"]?.bool == false)
            #expect(withheld["mcs"] == .null && withheld["seconds"] == .null, "\(processes) \(samples)")
            #expect(blind.envelope["load"]?["valid"]?.bool == false)
            #expect(blind.warningCodes.contains("load_missing"))
            #expect(!blind.stderr.contains("MC/s"), "\(blind.stderr)")
        }
    }

    @Test func validateCaseTimesNeedASamplerThatSawTheMac() {
        func validate(processes: Double, samples: Double) -> CLIRun {
            var tool = FakeToolRun(lines: ["slab: slab_ref", "1 of 1 checks passed."])
            tool.files = ["validation/validation_\(FakeWorld.stamp).json": FailingVerdictTests.validationJSON([true])]
            let report = FakeToolRun.report(mode: "script", argv: [FailingVerdictTests.suite], exit: 0,
                                            load: Self.valid)
            tool.report = Self.counts(report, processes: processes, samples: samples)
            return FailingVerdictTests.run(tool, FailingVerdictTests.validate)
        }
        let seen = validate(processes: 400, samples: 6)
        #expect(seen.exit == 0, "\(seen.stderr)")
        #expect(seen.result["timings"]?["slab"]?.double == 1.7)
        #expect(seen.stderr.contains("validate: case times slab 1.7 s"), "\(seen.stderr)")
        for (processes, samples) in [(0.0, 6.0), (400.0, 0.0)] {
            let blind = validate(processes: processes, samples: samples)
            #expect(blind.exit == 0, "\(blind.stderr)")
            #expect(blind.result["timings"] == .null, "\(processes) \(samples)")
            #expect(blind.warningCodes.contains("load_missing"))
            #expect(blind.stderr.contains("validate: case times withheld"), "\(blind.stderr)")
            #expect(!blind.stderr.contains("slab 1.7 s"))
        }
    }

    // MARK: validate's JSON must be this run's

    /// With --tag and --overwrite the old files stay in place until the suite writes them: a suite that leaves the
    /// old JSON as it was has not validated anything, whatever that file says.
    @Test func validateDoesNotTakeAnOldJSONForThisRuns() {
        let json = FakeWorld.repo + "/results/validation_old.json"
        let arguments = FailingVerdictTests.validate + ["--tag", "old", "--overwrite"]
        func validate(_ files: [String: String]) -> CLIRun {
            let world = PlanTests.world()
            world.system.addFile(json, FailingVerdictTests.validationJSON([true]))
            var tool = FakeToolRun(lines: ["slab: slab_ref"], absoluteFiles: files)
            tool.report = FakeToolRun.report(mode: "script", argv: [FailingVerdictTests.suite], exit: 0,
                                             load: Self.valid)
            return FailingVerdictTests.run(tool, arguments, world: world)
        }
        let stale = validate([:])
        #expect(stale.exit == 4, "\(stale.stderr)")
        #expect(stale.errorCodes == ["tool_failed"])
        #expect(stale.result["json"] == .null)
        #expect(stale.result["checks"]?.double == 0)
        // the same bytes written again are no new result either; other bytes are
        #expect(validate([json: FailingVerdictTests.validationJSON([true])]).exit == 4)
        let fresh = validate([json: FailingVerdictTests.validationJSON([true], note: "this run")])
        #expect(fresh.exit == 0, "\(fresh.stderr)")
        #expect(fresh.result["json"]?.string == json)
        #expect(fresh.result["checks"]?.double == 1)
    }

    // MARK: The child

    @Test func aLauncherWithoutAReportIsAnError() {
        let lines = ["FDTDKIT_CALL_BEGIN 0", FailingVerdictTests.multithreaded, "FDTDKIT_CALL_END 0"]
        let run = FailingVerdictTests.run(FakeToolRun(lines: lines), ["run", "/work/board.py", "--lib", "cg29"])
        #expect(run.exit == 4, "\(run.stderr)")
        #expect(run.status == "error")
        #expect(run.errorCodes == ["launcher_failed"])
        #expect(run.issue("errors", "launcher_failed")?["message"]?.string?.contains("left no readable report") == true)
        #expect(run.envelope["load"]?["valid"]?.bool == false)
        #expect(run.envelope["keptRuns"]?.bool == true)
    }

    @Test func aChildThatCannotStartIsSpawnFailed() throws {
        // FakeSystem spawns nothing without a handler
        let world = PlanTests.world()
        let run = world.run(["run", "/work/board.py", "--lib", "cg29"])
        #expect(run.exit == 4, "\(run.stderr)")
        #expect(run.errorCodes == ["spawn_failed"])
        let message = run.issue("errors", "spawn_failed")?["message"]?.string ?? ""
        #expect(message.contains("could not start: FakeSystem spawns nothing"), "\(message)")
        let invocation = try #require(run.envelope["invocations"]?.array?.last)
        #expect(invocation["ran"]?.bool == false)
    }

    /// The check scripts reach python3 through zsh: their pre-probe must show the three files of LIB, as the direct
    /// probe of validate, e2e and run does.
    @Test func theZshPreProbeMustLoadTheLibrary() {
        for arguments in [["debye-check", "cg29", "--dry-run"], ["diamond-check", "cg29", "--dry-run"]] {
            #expect(FakeWorld().run(arguments).exit == 0, "\(arguments)")
            let world = FakeWorld()
            world.system.update { $0.probeLibraries = LoadedLibraryTests.mixed }
            let run = world.run(arguments)
            #expect(run.exit == 4, "\(arguments)")
            #expect(run.errorCodes == ["library_not_loaded"], "\(arguments)")
            #expect(world.system.spawned.isEmpty)
        }
    }

    // MARK: --keep-runs

    @Test func keepRunsKeepsTheRunData() throws {
        let bulky = FakeWorld.runFolder("run") + "/runs/x.txt"
        let (cleaned, plain) = Self.script(processes: 400, samples: 3)
        #expect(plain.exit == 0, "\(plain.stderr)")
        #expect(plain.envelope["keptRuns"]?.bool == false)
        #expect(!cleaned.system.fileExists(bulky))
        let (kept, run) = Self.script(processes: 400, samples: 3, ["--keep-runs"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.envelope["keptRuns"]?.bool == true)
        #expect(kept.system.contents(bulky) == "bulky\n")
        #expect(kept.system.isDirectory(FakeWorld.runFolder("run") + "/runs"))
    }

    // MARK: bench's rows beside its summary

    static let during = "others  45%  during 7.9 s: self cpu 99% gpu>=0.00 s, others cpu 52% gpu 2%, gpu dev 2%"
    static let benchRows = [
        "cg29@multithreaded:4  1877.3 MC/s  2.29 s  16000 TS x 0.268 MC  \(during)  [ref]  openEMS v0.37.0-44-g074a687",
        "cg29@multithreaded:8  1601.2 MC/s  2.68 s  16000 TS x 0.268 MC  \(during)  probes rel=0.0e+00  "
            + "S11: max|dS|=0.0e+00 max dB=0.0e+00  openEMS v0.37.0-44-g074a687",
    ]

    /// `bench notch` of two configs whose bench.py prints `rows` between its header and `summary`.
    static func bench(rows: [String], summary: String, _ extra: [String] = [],
                      during: (@Sendable (FdtdStopController) -> Void)? = nil) -> CLIRun {
        var tool = FakeToolRun(lines: ["# notch_s1_n16000  load avg 3.42"] + rows + [summary])
        tool.during = during
        let log = FailingVerdictTests.multithreaded + "\n"
        tool.files = ["runs/notch_s1_n16000/cg29_multithreaded_t4/rep0/openEMS.log": log,
                      "runs/notch_s1_n16000/cg29_multithreaded_t8/rep0/openEMS.log": log]
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        return FailingVerdictTests.run(tool, ["bench", "notch", "--config", "cg29@multithreaded:4", "--config",
                                              "cg29@multithreaded:8"] + extra, world: FakeWorld())
    }

    /// A summary line over rows the CLI cannot read confirms no engine and compares nothing.
    @Test func benchSummaryNeedsARowPerConfig() {
        let identical = "IDENTICAL: every run of 1 config equals the reference"
        let ok = Self.bench(rows: Self.benchRows, summary: identical)
        #expect(ok.exit == 0 && ok.status == "ok", "\(ok.stderr)")
        #expect(ok.result["rows"]?.array?.count == 2)
        let unreadable = "cg29@multithreaded:8  1601.2 megacells per second"
        for rows in [[], [Self.benchRows[0]], [Self.benchRows[0], unreadable]] {
            let run = Self.bench(rows: rows, summary: identical)
            #expect(run.exit == 4, "\(rows.count) rows: \(run.stderr)")
            #expect(run.errorCodes == ["tool_output_unparsed"], "\(rows.count) rows")
            let message = run.issue("errors", "tool_output_unparsed")?["message"]?.string ?? ""
            #expect(message.contains("\(rows.isEmpty ? 0 : 1) readable row"), "\(message)")
            #expect(message.hasSuffix("for 2 configs"), "\(message)")
        }
        // more rows than configs: a doubled or foreign row is no row per config either
        let doubled = Self.bench(rows: Self.benchRows + [Self.benchRows[1]], summary: identical)
        #expect(doubled.exit == 4, "\(doubled.stderr)")
        #expect(doubled.errorCodes.contains("tool_output_unparsed"))
        let counts = doubled.envelope["errors"]?.array?.compactMap { $0["message"]?.string } ?? []
        #expect(counts.contains { $0.hasSuffix("3 readable rows for 2 configs") }, "\(counts)")
        // a stop after the summary: the envelope says interrupted, not that a finished bench lacks rows
        let stopped = Self.bench(rows: [Self.benchRows[0]], summary: identical, during: { $0.signalArrived(SIGINT) })
        #expect(stopped.exit == 130, "\(stopped.stderr)")
        #expect(stopped.errorCodes == ["interrupted"])
        // --exact has no row to look at either
        let nothing = "NOTHING REQUIRED TO MATCH: every compared config is tolerant (cg29@multithreaded:8)"
        let exact = Self.bench(rows: [], summary: nothing, ["--exact"])
        #expect(exact.exit == 4)
        #expect(exact.errorCodes == ["tool_output_unparsed"])
        #expect(exact.warningCodes.contains("nothing_verified"))
        // the run folder is looked at whatever the rows say
        var tool = FakeToolRun(lines: ["# notch_s1_n16000  load avg 3.42", identical])
        tool.report = FakeToolRun.report(mode: "exec", argv: [FakeWorld.python], exit: 0)
        let bare = FailingVerdictTests.run(tool, ["bench", "notch", "--config", "cg29@multithreaded:4", "--config",
                                                  "cg29@multithreaded:8"], world: FakeWorld())
        #expect(bare.errorCodes == ["tool_output_unparsed", "tool_output_unparsed"])
    }

    @Test func exactWithoutAComparedRowVerifiesNothing() {
        let nothing = FdtdBenchSummary(kind: "NOTHING REQUIRED TO MATCH", line: "NOTHING REQUIRED TO MATCH")
        let reference = VerdictTests.row("cg29@multithreaded:4", reference: true, exact: nil)
        let empty = FdtdVerdicts.bench(summary: nothing, rows: [reference], exact: true, benchExit: 0)
        #expect(empty.warnings.map(\.code) == [.nothingVerified])
        let compared = VerdictTests.row("cg29@metal-diamond:0", tolerant: true, exact: true)
        let verified = FdtdVerdicts.bench(summary: nothing, rows: [reference, compared], exact: true, benchExit: 0)
        #expect(verified.passed && verified.warnings.isEmpty)
    }

    // MARK: info with a --rfsim that names no toolkit

    @Test func infoShowsTheInstalledLibraryBesideABadRfsim() throws {
        let plain = FakeWorld().run(["info"])
        #expect(plain.result["installed"]?["dir"]?.string == FakeWorld.installed)
        let run = FakeWorld().run(["info", "--rfsim", "/nope"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.result["installed"]?["dir"]?.string == FakeWorld.installed)
        #expect(run.result["installed"] == plain.result["installed"])
        #expect(run.envelope["python"]?["openemsVersion"]?.string == "0.0.36")
        #expect(run.warningCodes.filter { $0 == "rfsim_not_found" }.count == 1)
        #expect(run.issue("warnings", "rfsim_not_found")?["field"]?.string == "--rfsim")
        #expect(!run.warningCodes.contains("library_not_found"))
        #expect(run.envelope["rfsim"] == .null)
        // a toolkit named by --rfsim is still probed after the Python probe, as without the option's check
        let world = FakeWorld()
        let good = world.run(["info", "--rfsim", FakeWorld.rfsim])
        #expect(good.exit == 0)
        #expect(good.envelope["rfsim"]?["path"]?.string == FakeWorld.rfsim)
        #expect(!good.warningCodes.contains("rfsim_not_found"))
        let captures = world.system.captures
        let python = try #require(captures.firstIndex { $0.argv.contains(FdtdSnippets.probe) })
        let toolkit = try #require(captures.firstIndex { $0.argv.contains(FdtdSnippets.rfsim) })
        #expect(python < toolkit)
        #expect(captures.filter { $0.argv.contains(FdtdSnippets.rfsim) }.count == 1)
    }

    // MARK: tools_modified

    @Test func toolsModifiedReadsPathsBelowTheTopLevel() throws {
        let status = [" M bench/bench.py", "R  scripts/e2e/old.py -> scripts/e2e/new.py", "?? notes.txt",
                      " M \"scripts/checks/a b.sh\"", " M paper/emskit.tex"]
        #expect(FdtdDiscovery.modifiedTools(status) == ["bench/bench.py", "scripts/e2e/old.py", "scripts/e2e/new.py",
                                                         "scripts/checks/a b.sh"])
        let nested = [" M vendor/emsKit/bench/bench.py", " M bench/other.py", "?? vendor/emsKit/notes.txt",
                      "R  bench/moved.py -> vendor/emsKit/scripts/checks/moved.py"]
        #expect(FdtdDiscovery.modifiedTools(nested, prefix: "vendor/emsKit/") == ["bench/bench.py",
                                                                                 "scripts/checks/moved.py"])
        // the top level of a repository: the status of the whole tree, as before
        let top = FakeWorld()
        top.system.update { $0.gitStatus = status.joined(separator: "\n") + "\n" }
        let plain = top.run(["info"])
        #expect(plain.warningCodes.contains("tools_modified"))
        #expect(plain.envelope["repo"]?["toolsModified"]?.array?.count == 4)
        #expect(plain.envelope["repo"]?["dirty"]?.bool == true)
        let whole = try #require(top.system.captures.first { $0.argv.contains("status") })
        #expect(whole.argv == ["/usr/bin/git", "-C", FakeWorld.repo, "-c", "core.quotePath=false", "status",
                               "--porcelain"])
        // a tools tree kept inside another repository: git names the paths from that repository's top level
        let world = FakeWorld()
        world.system.update {
            $0.gitPrefix = "vendor/emsKit/"
            $0.gitStatus = " M vendor/emsKit/bench/bench.py\n"
        }
        let run = world.run(["info"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.envelope["repo"]?["toolsModified"]?.array?.compactMap(\.string) == ["bench/bench.py"])
        let warning = run.issue("warnings", "tools_modified")?["message"]?.string
        #expect(warning == "the tools have uncommitted changes: bench/bench.py")
        let scoped = try #require(world.system.captures.first { $0.argv.contains("status") })
        #expect(scoped.argv == ["/usr/bin/git", "-C", FakeWorld.repo, "-c", "core.quotePath=false", "status",
                                "--porcelain", "--", "."])
        // a folder name outside ASCII: git would write it in octal escapes, which the prefix never matches, so the
        // status is asked with unquoted paths (the fake git quotes like the real one when it is not)
        #expect(FakeSystem.cQuoted(" M übung/kit/bench/bench.py\n")
                == " M \"\\303\\274bung/kit/bench/bench.py\"\n")
        let umlaut = FakeWorld()
        umlaut.system.update {
            $0.gitPrefix = "übung/kit/"
            $0.gitStatus = " M übung/kit/bench/bench.py\n M \"übung/kit/scripts/checks/a b.sh\"\n"
        }
        let named = umlaut.run(["info"])
        #expect(named.envelope["repo"]?["toolsModified"]?.array?.compactMap(\.string)
                == ["bench/bench.py", "scripts/checks/a b.sh"])
        #expect(named.warningCodes.contains("tools_modified"))
        // a clean tree in either place gives no warning
        #expect(!FakeWorld().run(["info"]).warningCodes.contains("tools_modified"))
    }
}
