// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 ParserTests: every row and summary of the real result tables parses, and the constructed outputs of
// Fixtures/ (printed with the tools' own format strings) give the expected fields.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct ParserTests {
    static let thresholds = FdtdThresholds(warnCpu: 150, warnGpu: 10)

    /// REPO/results/*SUFFIX.txt.
    static func resultTables(_ suffix: String) throws -> [String] {
        let dir = TestPaths.repo + "/results"
        return try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(suffix) }.sorted()
            .map { dir + "/" + $0 }
    }

    @Test(arguments: ["_cg29.txt", "_cg28gpu.txt", "_step1.txt"])
    func everyResultTableLineParses(suffix: String) throws {
        let files = try Self.resultTables(suffix)
        #expect(files.count >= 4)
        for file in files {
            let lines = try TestPaths.lines(file)
            let bench = FdtdParsers.benchOutput(lines.joined(separator: "\n"))
            let name = FdtdPaths.basename(file)
            #expect(bench.name != nil, "\(name)")
            // stdout copies carry the summary without the `# ` of a tag file, and Python's warnings (left out)
            let rows = lines.filter { !$0.hasPrefix("#") && $0.contains(" MC/s ") }
            for line in lines where !line.hasPrefix("#") && !line.contains(" MC/s ") {
                #expect(FdtdParsers.benchSummary(line) != nil || line.contains("Warning") || line.hasPrefix("  "),
                        "\(name): \(line)")
            }
            #expect(bench.rows.count == rows.count, "\(name)")
            for line in rows {
                let row = try #require(FdtdParsers.benchRow(line), "\(name): \(line)")
                #expect(row.mcs > 0 && row.timesteps > 0, "\(name): \(line)")
                let load = FdtdLoads.fromBenchRow(row, thresholds: Self.thresholds)
                if suffix == "_step1.txt" {
                    // the first tables were written before bench printed the during part
                    #expect(load == nil, "\(name): \(line)")
                } else if suffix == "_cg29.txt" {
                    #expect(load?.valid == true, "\(name): \(line)")
                    #expect(row.during?.gpuDevicePercent != nil, "\(name): \(line)")
                }
            }
            // the summary lines (tag files write them as `# SUMMARY`); free comment lines are skipped
            for line in lines where line.hasPrefix("# ") {
                let summary = FdtdParsers.benchSummary(line)
                let isHeader = line.wholeMatch(of: #/# \S+  \d{4}-\d\d-\d\d \d\d:\d\d/#) != nil
                    || line.wholeMatch(of: #/# \S+  load avg [\d.]+/#) != nil
                #expect(summary != nil || isHeader || bench.skipped.contains(line), "\(name): \(line)")
            }
            if suffix == "_cg29.txt" { #expect(bench.summary != nil, "\(name)") }
        }
    }

    @Test func realRowWithBusyQuietWaitAndAutoPick() throws {
        let lines = try TestPaths.lines(TestPaths.repo + "/results/patch_s5_n1200_cg29.txt")
        let line = try #require(lines.first { $0.hasPrefix("cg29@fastest ") })
        let row = try #require(FdtdParsers.benchRow(line))
        #expect(row.label == "cg29@fastest")
        #expect(row.busyBefore == ["swiftpm-testing-:760"])
        #expect(row.quietWaitTimedOut)
        #expect(row.autoPickedThreads == 6)
        #expect(row.repeats == 2)
        #expect(row.during?.busy == ["swiftpm-testing-:569/0"])
        #expect(row.during?.othersCpuPercent == 609)
        #expect(row.openemsVersion == "v0.37.0-44-g074a687")
    }

    @Test func benchVariants() throws {
        let bench = FdtdParsers.benchOutput(try TestPaths.text(TestPaths.fixture("bench_variants.txt")))
        #expect(bench.name == "notch_s1_n16000")
        #expect(bench.rows.count == 6)
        let rows = bench.rows
        // the reference: a busy list with spaces and gpu items, no comparison on a single run
        #expect(rows[0].reference)
        #expect(rows[0].busyBefore == ["WindowServer:23", "gpu Code Helper (Ren:3/12"])
        #expect(rows[0].during?.busy == ["Google Chrome He:41/0", "Code Helper (Ren:3/12"])
        #expect(rows[0].during?.gpuDevicePercent == 14)
        #expect(rows[0].probesRel == nil)
        #expect(rows[0].openemsVersion == "v0.37.0")
        #expect(FdtdLoads.fromBenchRow(rows[0], thresholds: Self.thresholds)?.valid == true)
        // no gpu dev: the load is not valid
        #expect(rows[1].during?.gpuDevicePercent == nil)
        let noDev = try #require(FdtdLoads.fromBenchRow(rows[1], thresholds: Self.thresholds))
        #expect(!noDev.valid)
        #expect(noDev.invalidReason?.contains("gpu dev") == true)
        #expect(rows[1].sparams.map { $0.name } == ["S11", "S21"])
        #expect(rows[1].sparams[1].belowFloor && rows[1].sparams[1].equal)
        #expect(rows[1].exact)
        // tolerant
        #expect(rows[2].tolerant)
        #expect(rows[2].probesRel == 1.7e-6)
        #expect(!rows[2].exact)
        #expect(rows[2].during?.selfGpuSecondsAtLeast == 2.13)
        // probes rel=inf with a PROBLEM and no S fields; self cpu 0% over 3 s
        #expect(rows[3].probesRel == .infinity)
        #expect(rows[3].problems == ["port_ut1 NaN/inf differ"])
        #expect(rows[3].sparams.isEmpty)
        let idle = try #require(FdtdLoads.fromBenchRow(rows[3], thresholds: Self.thresholds))
        #expect(!idle.valid)
        #expect(idle.invalidReason?.contains("self cpu 0% over 3 s") == true)
        // S11 inf
        #expect(rows[4].sparams[0].maxAbsDiff == .infinity)
        #expect(rows[4].sparams[0].maxDb == .infinity)
        #expect(rows[4].during?.busy == ["corespotlightd:35/0"])
        // differs below -40 dB, the quiet wait, the auto-picked threads
        #expect(rows[5].sparams[1].differsBelowFloor)
        #expect(!rows[5].exact)
        #expect(rows[5].quietWaitTimedOut)
        #expect(rows[5].autoPickedThreads == 6)
        #expect(rows[5].othersCpuBefore == 280)
        #expect(bench.summary?.kind == "MISMATCH")
        #expect(bench.summary?.line == "MISMATCH: cg29@multithreaded:8, cg27@multithreaded:4, cg29@fastest")
    }

    @Test func benchTagFileNotes() throws {
        let bench = FdtdParsers.benchOutput(try TestPaths.text(TestPaths.fixture("bench_tagfile.txt")))
        #expect(bench.name == "patch_s1_n300")
        #expect(bench.rows.count == 3)
        #expect(bench.rows[0].zeroFiles == FdtdZeroFiles(zero: 2, total: 4))
        #expect(bench.rows[0].repeats == 2)
        #expect(bench.rows[0].sparamNote == "S-params skipped: 1 probe sample, raise --nrts")
        #expect(bench.rows[2].sparamNote == "S-params not computed (--no-sparams)")
        #expect(bench.summary == FdtdBenchSummary(kind: "IDENTICAL",
                                                  line: "IDENTICAL: every run of 3 configs equals the reference"))
    }

    @Test func usageFmtTexts() throws {
        let lines = try TestPaths.lines(TestPaths.fixture("usage_fmt.txt"))
        let parsed = lines.map { FdtdParsers.usageFmt($0) }
        #expect(parsed.allSatisfy { $0 != nil })
        #expect(parsed[0] == FdtdUsageFmt(wallSeconds: 17.4, selfCpuPercent: 396, selfGpuSecondsAtLeast: 0,
                                          othersCpuPercent: 218, othersGpuPercent: 5, gpuDevicePercent: 5))
        #expect(parsed[1]?.busy == ["swiftpm-testing-:68/0"])
        #expect(parsed[2]?.gpuDevicePercent == nil)
        #expect(parsed[2]?.selfGpuSecondsAtLeast == 2.13)
        #expect(parsed[3]?.busy == ["Google Chrome He:41/0", "Code Helper (Ren:3/12"])
        #expect(parsed[3]?.gpuDevicePercent == nil)
        #expect(FdtdParsers.usageFmt("others cpu 3%") == nil)
    }

    @Test func abtestRecord() throws {
        let ab = FdtdParsers.abtestOutput(try TestPaths.text(TestPaths.fixture("abtest_record.txt")))
        let header = try #require(ab.header)
        #expect(header == FdtdParsedABHeader(name: "kgcpw_s1_n15000", date: "2026-11-05 03:51", rounds: 4,
                                             quietPercent: 150))
        #expect(ab.runs.count == 15)
        #expect(ab.runs.filter { $0.redo }.count == 3)
        let missing = try #require(ab.runs.first { $0.round == 1 && $0.config == 0 })
        #expect(missing.othersCpu == -1 && missing.othersGpu == -1)
        let load = FdtdLoads.fromAbtestRun(missing, samplerChecksValid: true, thresholds: Self.thresholds)
        #expect(!load.valid)
        #expect(load.othersCpuPercent == nil)
        #expect(ab.runs.first { $0.round == 1 && $0.config == 6 }?.diff == "probes rel inf")
        #expect(ab.runs.first { $0.round == 0 && $0.config == 0 }?.diff == "reference")
        #expect(ab.notes.count == 2)
        #expect(ab.notes[0] == FdtdParsedABNote(round: 3, text: "redo 1 of 3 (a run saw the others at 173 % CPU, 4 % GPU)"))
        #expect(ab.notes[1].config == 3)
        #expect(ab.summaryHeader?.hasPrefix("median MC/s [min-max]") == true)
        #expect(ab.summaries.map { $0.config } == [0, 3, 6])
        let c6 = ab.summaries[2]
        #expect(c6.label == "cg29@metal-diamond:0")
        #expect(c6.medianMcs == 2112.7 && c6.minMcs == 2102 && c6.maxMcs == 2117)
        #expect(c6.ratio == 7.401 && c6.minRatio == 7.36 && c6.maxRatio == 7.453)
        #expect(c6.othersCpu == 66 && c6.othersGpu == 2)
        #expect(c6.diffs == "probes rel 4.5e-07")
        #expect(ab.summaries[0].diffs == "identical,reference")
    }

    @Test func checkOutputAndFinalLines() throws {
        let check = FdtdParsers.checkOutput(try TestPaths.text(TestPaths.fixture("check_output.txt")))
        #expect(check.blocks.map { $0.name } == ["patch_s5_n1200", "notch_s3_n2000"])
        #expect(check.blocks[0].rows.count == 4)
        #expect(check.blocks[0].summary?.kind == "IDENTICAL")
        #expect(check.blocks[0].wrote == "/work/emsKit/results/patch_s5_n1200_smoke.txt")
        #expect(check.blocks[1].rows.count == 2)
        #expect(check.blocks[1].summary == nil)
        #expect(check.finalLine?.kind == .benchStopped)
        #expect(check.finalLine?.benchExit == 1)
        #expect(check.finalLine?.detail == "notch_x3")

        let finals = try TestPaths.lines(TestPaths.fixture("check_finals.txt")).map { FdtdParsers.checkFinal($0) }
        #expect(finals.map { $0?.kind } == [.allIdentical, .partial, .fail, .benchStopped])
        #expect(finals.allSatisfy { $0?.tag == "smoke" })
        #expect(finals[0]?.models == 6)
        #expect(finals[1]?.detail.hasPrefix("no differences on 4 of 6 models") == true)
        #expect(finals[2]?.detail == "patch_x5 notch")
        #expect(FdtdParsers.checkFinal("check.sh smoke: something else") == nil)
    }

    @Test func debyeOutputs() throws {
        let plain = FdtdParsers.debyeOutput(try TestPaths.text(TestPaths.fixture("debye_output.txt")))
        #expect(plain.runs == ["/Users/tester/opt/openEMS-dev/snap/cg29: basic / sse-compressed / multithreaded(4)"])
        #expect(plain.comparisons == [FdtdScriptComparison(title: "basic vs sse-compressed", identical: true),
                                      FdtdScriptComparison(title: "sse-compressed vs multithreaded", identical: true)])
        #expect(plain.passed == true)
        #expect(plain.verdictLine == "PASS: every comparison is identical")

        let withRef = FdtdParsers.debyeOutput(try TestPaths.text(TestPaths.fixture("debye_output_ref.txt")))
        #expect(withRef.runs.count == 2)
        #expect(withRef.runs[1] == "reference /Users/tester/opt/openEMS-dev/snap/cg18: sse-compressed")
        #expect(withRef.comparisons.map { $0.title } == ["basic vs sse-compressed", "sse-compressed vs multithreaded",
                                                     "sse-compressed, SNAP vs REF"])
        #expect(withRef.comparisons.map { $0.identical } == [true, true, false])
        #expect(withRef.passed == false)
        #expect(!withRef.noExportedFields)
        let missing = FdtdParsers.debyeOutput("debye_check.sh: no exported fields from /x (basic): the run failed")
        #expect(missing.noExportedFields)
        #expect(missing.passed == nil)
    }

    @Test func diamondOutputs() throws {
        let pass = FdtdParsers.diamondOutput(try TestPaths.text(TestPaths.fixture("diamond_pass.txt")))
        #expect(pass.boxes.count == 9)
        #expect(pass.comparisons.count == 54)
        #expect(pass.comparisons.allSatisfy { $0.identical })
        #expect(pass.boxes[0] == "pec, 41,37,30 lines, 400 timesteps")
        #expect(pass.comparisons[5].label == "K=4, tile 7,0, 96 threads, batch 3")
        #expect(pass.passed == true)

        let fail = FdtdParsers.diamondOutput(try TestPaths.text(TestPaths.fixture("diamond_fail.txt")))
        #expect(fail.boxes.count == 3)
        #expect(fail.comparisons.filter { !$0.identical }.map { $0.label } == ["K=2"])
        #expect(fail.gpuPathMissing == ["pec, 41,37,30 lines, 400 timesteps: K=4"])
        #expect(fail.tuningUnfinished)
        #expect(fail.runFailed == ["Metal"])
        #expect(fail.comparisons.contains { $0.label == "tuned, batch 8 (K=3 tiles 8,6 after 612 steps)" })
        // diamond_compare.py's own lines are not comparisons
        #expect(fail.comparisons.count == 15)
        #expect(fail.passed == nil)
    }

    @Test func e2eResultLine() throws {
        let text = try TestPaths.text(TestPaths.fixture("e2e_output.txt"))
        let result = try #require(FdtdParsers.e2eResult(text))
        #expect(result["model"]?.string == "gcpw")
        #expect(result["db"]?.string == "-60")
        #expect(result["hold"]?.double == 0.5)
        #expect(result["cells"]?.double == 241995)
        #expect(result["t_run"]?.double == 5.945446875062771)
        #expect(FdtdParsers.e2eResult("RESULT not json") == nil)
        #expect(FdtdParsers.e2eResult(#"RESULT {"t_run": NaN}"#)?["t_run"]?.double?.isNaN == true)
        let facts = FdtdParsers.openEMSFacts(text.components(separatedBy: "\n"))
        #expect(facts.creates.map { $0.parenthesis } == ["Metal, diamond-blocked"])
        #expect(facts.stop == FdtdRunStop(kind: .probeEnd, timesteps: 34300))
        #expect(facts.timesteps == 34300 && facts.cells == 241995 && facts.seconds == 5.71)
        #expect(abs((facts.mcs ?? 0) - 1453.7) < 0.1)
    }

    @Test func toolLogSegmentsAndOpenEMSLines() throws {
        let segments = FdtdParsers.callSegments(try TestPaths.text(TestPaths.fixture("tool_log.txt")))
        #expect(segments.map { $0.index } == [0, 1, 2, 3, 4, 5, 6])
        #expect(segments.map { $0.ended } == [true, true, true, true, true, true, false])
        let facts = segments.map { FdtdParsers.openEMSFacts($0.lines) }
        #expect(facts[0].stop?.kind == .probeEnd)
        #expect(facts[0].creates.map { $0.line } == ["Create FDTD engine (Metal, diamond-blocked)"])
        #expect(facts[1].threadsFixed == 4)
        #expect(facts[1].stop == FdtdRunStop(kind: .maxTimesteps, timesteps: 15000))
        #expect(facts[1].creates.map { $0.parenthesis } == ["compressed SSE + multi-threading"])
        #expect(facts[2].threadsPicked == 6)
        #expect(facts[2].stop == FdtdRunStop(kind: .energy, timesteps: 9120))
        #expect(facts[3].stop == FdtdRunStop(kind: .aborted, timesteps: 812))
        // the CPU loops after a missing GPU extension, a kernel that did not compile, a pipeline not created; an
        // ignored TILE value (segment 0) is no fallback
        #expect(facts[3].gpuFallback && facts[4].gpuFallback && facts[5].gpuFallback)
        #expect(!facts[0].gpuFallback && !facts[1].gpuFallback && !facts[6].gpuFallback)
        #expect(FdtdCalls.gpuFallbackCalls(try TestPaths.text(TestPaths.fixture("tool_log.txt"))) == [3, 4, 5])
        #expect(!FdtdParsers.isGpuFallback("Engine_Metal_Diamond: 195x73x17 cells (5 z-vectors, 812 operators)"))
        #expect(!FdtdParsers.isGpuFallback("note: Engine_Metal_Diamond: kernel compilation failed"))
        // the bare line is basic; the GPU engine's line names its backend
        #expect(facts[6].creates.map { $0.parenthesis } == [nil, "GPU, backend: Metal"])
        #expect(FdtdEngine.basic.accepts(facts[6].creates[0]))
        #expect(!FdtdEngine.multithreaded.accepts(facts[6].creates[0]))
        #expect(facts[6].stop == nil)
        // the launcher's note before the first marker is outside every segment; an unterminated segment runs to the end
        #expect(!segments.contains { $0.lines.contains { $0.hasPrefix("fdtdkit_run:") } })
        #expect(!segments[0...5].contains { $0.lines.contains { $0.hasPrefix("RESULT ") } })
        #expect(segments[6].lines.contains { $0.hasPrefix("RESULT ") })
        // a marker after text without a newline: the text still belongs to the open segment
        let glued = FdtdParsers.callSegments("FDTDKIT_CALL_BEGIN 7\nSpeed: 1 MCells/s FDTDKIT_CALL_END 7\n")
        #expect(glued == [FdtdCallSegment(index: 7, lines: ["Speed: 1 MCells/s "], ended: true)])
    }

    @Test func validationReports() throws {
        let real = try FdtdParsers.validation(try Data(contentsOf: URL(fileURLWithPath: TestPaths.repo
                                                                       + "/results/validation_cg18_mt4.json")))
        #expect(real.results.count == 15)
        #expect(real.results.allSatisfy { $0.passed })
        #expect(real.meta["tag"]?.string == "cg18_mt4")
        #expect(real.runs["slab"]?.first?.engine == "compressed SSE + multi-threading")

        let crashed = try FdtdParsers.validation(try Data(contentsOf: URL(fileURLWithPath:
                                                                          TestPaths.fixture("validation_nan.json"))))
        #expect(crashed.results.count == 3)
        let failed = try #require(crashed.results.first { !$0.passed })
        #expect(failed.caseName == "cavity")
        #expect(failed.error?.isNaN == true)
        #expect(failed.value == nil)
        // the envelope writes the NaN as "nan"
        let encoded = String(decoding: try FdtdJSON.encode(failed), as: UTF8.self)
        #expect(encoded.contains(#""error" : "nan""#))
        #expect(crashed.runs["cavity"]?.isEmpty == true)
    }

    @Test func numbersAndTaggedLines() {
        #expect(FdtdParsers.number("inf") == .infinity)
        #expect(FdtdParsers.number("-inf") == -.infinity)
        #expect(FdtdParsers.number("nan")?.isNaN == true)
        #expect(FdtdParsers.number("1.") == 1)
        #expect(FdtdParsers.number("1.e5") == 1e5)
        #expect(FdtdParsers.number("4.5e-07") == 4.5e-7)
        #expect(FdtdParsers.number("x1") == nil)
        let output = "noise\nFDTDKIT_LOAD {\"a\": 1}\nFDTDKIT_LOAD {\"a\": 2}\n"
        #expect(FdtdParsers.taggedJSON("FDTDKIT_LOAD", in: output, as: FdtdJSONValue.self)?["a"]?.double == 2)
        #expect(FdtdParsers.taggedJSON("FDTDKIT_PROBE", in: output, as: FdtdJSONValue.self) == nil)
    }
}
