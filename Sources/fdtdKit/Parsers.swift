// SPDX-License-Identifier: GPL-3.0-or-later

// Reading the tools' output (spec 6): bench rows and summaries, abtest records, check.sh's blocks and final line,
// the validation JSON (JSON5: Python writes NaN, F21), debye/diamond lines, e2e's RESULT, openEMS lines per call
// segment, usage.fmt's `during` text, the launcher report and the probes' tagged lines. NUM accepts inf and nan:
// bench prints inf for a difference without a finite figure. Every parser is total: what it cannot read it leaves
// out or reports as nil, and the command decides (tool_output_unparsed).
import Foundation

// MARK: - Sampler and probe lines

/// usage.Sampler's stop() result (usage.py:84-105), keys as Python writes them.
struct FdtdSamplerResult: Codable, Sendable, Equatable {
    var cpuSelf: Double
    var cpuOther: Double
    var gpuSelf: Double
    var gpuOther: Double
    var wall: Double
    @FdtdNullable var gpuDev: Double? = nil
    var busy: [String] = []

    enum CodingKeys: String, CodingKey {
        case cpuSelf = "cpu_self", cpuOther = "cpu_other", gpuSelf = "gpu_self", gpuOther = "gpu_other", wall
        case gpuDev = "gpu_dev", busy
    }
}

/// What a sampler saw: the validity test of a sampler result (processesSeen > 0 and utilSamples > 0).
struct FdtdLoadCounts: Codable, Sendable, Equatable {
    var processesSeen: Int
    var gpuClientsSeen: Int
    var utilSamples: Int
}

/// The FDTDKIT_PROBE line (spec 5.2).
struct FdtdProbeResult: Codable, Sendable, Equatable {
    var executable: String
    var realPath: String
    var version: String
    /// The DYLD_LIBRARY_PATH the interpreter saw (dyldKept = equal to the value sent).
    @FdtdNullable var dyld: String? = nil
    @FdtdNullable var numpy: String? = nil
    @FdtdNullable var openemsModule: String? = nil
    /// libinfo.loaded_libs(): the loaded libopenEMS/libCSXCAD/libnf2ff images, in load order.
    @FdtdNullable var libraries: [String]? = nil
    @FdtdNullable var openemsVersion: String? = nil
    /// The binding turns a False/0 option into "" (F19); true when no openEMS.pyx lies beside the module.
    @FdtdNullable var legacyEmptyOption: Bool? = nil
    @FdtdNullable var importError: String? = nil
}

/// The FDTDKIT_RFSIM line.
struct FdtdRfsimProbe: Codable, Sendable, Equatable {
    var core: String
    @FdtdNullable var probeEndDb: Double? = nil
    @FdtdNullable var probeEndHold: Double? = nil
    @FdtdNullable var zMult: Double? = nil
    @FdtdNullable var minCell: Double? = nil
    @FdtdNullable var minCellEffective: Double? = nil
    @FdtdNullable var env: [String: String]? = nil
}

/// The FDTDKIT_QUIET line: bench.wait_quiet's (cpu, busy, late).
struct FdtdQuietLine: Codable, Sendable, Equatable {
    @FdtdNullable var cpu: Double? = nil
    @FdtdNullable var busy: [String]? = nil
    var late: Bool
}

/// The FDTDKIT_LOAD line.
struct FdtdLoadLine: Codable, Sendable, Equatable {
    /// nil when the sampler could not run (stop() returned None).
    @FdtdNullable var load: FdtdSamplerResult? = nil
    var processesSeen: Int
    var gpuClientsSeen: Int
    var utilSamples: Int

    var counts: FdtdLoadCounts {
        FdtdLoadCounts(processesSeen: processesSeen, gpuClientsSeen: gpuClientsSeen, utilSamples: utilSamples)
    }
}

// MARK: - bench (6.1)

/// usage.fmt's text: `during W s: self cpu C% gpu>=G s, others cpu C% gpu G%[, gpu dev D%][ [busy,...]]`.
struct FdtdUsageFmt: Sendable, Equatable {
    var wallSeconds: Double
    var selfCpuPercent: Double
    var selfGpuSecondsAtLeast: Double
    var othersCpuPercent: Double
    var othersGpuPercent: Double
    var gpuDevicePercent: Double? = nil
    var busy: [String] = []
}

/// One `SNN:` field of a bench row.
struct FdtdParsedSParam: Sendable, Equatable {
    var name: String
    /// `below -40 dB, compared exactly: ...`
    var belowFloor = false
    /// `equal` (below the floor).
    var equal = false
    var maxAbsDiff: Double? = nil
    var maxDb: Double? = nil
    /// `(differs below -40 dB)`.
    var differsBelowFloor = false

    /// bench's `same` for this field (bench.py:362-369): below the floor only `equal` counts (bench keeps its own
    /// exact flag there); otherwise max|dS| exactly 0 without `(differs below -40 dB)`.
    var exact: Bool { belowFloor ? equal : (maxAbsDiff == 0 && !differsBelowFloor) }
}

/// `(Z of N files all zero in the reference, compared exactly)`.
struct FdtdZeroFiles: Codable, Sendable, Equatable {
    var zero: Int
    var total: Int
}

/// One bench row as printed (bench.py:338-382).
struct FdtdParsedBenchRow: Sendable, Equatable {
    var line: String
    var label: String
    var mcs: Double
    var seconds: Double
    var timesteps: Int
    /// The `x MC` figure: million cells.
    var megaCells: Double
    /// top's CPU-only reading from the second before the run (bench.py:19-20); never a load.
    var othersCpuBefore: Int
    /// `runs a/b`: the repeat count (those speeds have no load of their own).
    var repeats: Int? = nil
    var busyBefore: [String] = []
    /// The load of the row's fastest repeat; nil without a `during` part.
    var during: FdtdUsageFmt? = nil
    var quietWaitTimedOut = false
    var autoPickedThreads: Int? = nil
    var reference = false
    var probesRel: Double? = nil
    var zeroFiles: FdtdZeroFiles? = nil
    var problems: [String] = []
    var sparams: [FdtdParsedSParam] = []
    /// `S-params not computed (--no-sparams)` or `S-params skipped: N probe samples, raise --nrts`.
    var sparamNote: String? = nil
    var tolerant = false
    var openemsVersion: String? = nil

    /// bench's `same` (bench.py:369): probes rel exactly 0, no PROBLEM, every S field exact.
    var exact: Bool { probesRel == 0 && problems.isEmpty && sparams.allSatisfy(\.exact) }
}

/// The summary line: `MISMATCH`, `NOTHING COMPARED`, `NOTHING REQUIRED TO MATCH` or `IDENTICAL`, and its text.
struct FdtdBenchSummary: Codable, Sendable, Equatable {
    var kind: String
    var line: String
}

/// One bench output (stdout or a --tag table).
struct FdtdParsedBench: Sendable, Equatable {
    /// NAME of `# NAME  load avg X` (stdout) or `# NAME  YYYY-MM-DD HH:MM` (a tag file).
    var name: String? = nil
    var rows: [FdtdParsedBenchRow] = []
    var summary: FdtdBenchSummary? = nil
    /// `wrote PATH`.
    var wrote: String? = nil
    /// The free `#` comment lines that were skipped.
    var skipped: [String] = []
}

// MARK: - check (6.3)

/// check.sh's last line.
struct FdtdCheckFinal: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable {
        case allIdentical = "ALL IDENTICAL", partial = "PARTIAL", fail = "FAIL"
        /// `bench.py NAME stopped with exit status N` → tool_failed.
        case benchStopped = "bench stopped"
    }

    var tag: String
    var kind: Kind
    var detail = ""
    /// `(N models)` of ALL IDENTICAL.
    var models: Int? = nil
    var benchExit: Int32? = nil
    var line: String
}

/// check.sh's output: bench blocks separated by their headers, then the final line.
struct FdtdParsedCheck: Sendable, Equatable {
    var blocks: [FdtdParsedBench] = []
    var finalLine: FdtdCheckFinal? = nil
}

// MARK: - abtest (6.2)

/// `# NAME  YYYY-MM-DD HH:MM  load avg X  N rounds, interleaved[, each round after others <= P % CPU]`.
struct FdtdParsedABHeader: Sendable, Equatable {
    var name: String
    var date: String
    var rounds: Int
    var quietPercent: Int? = nil
}

/// `[# redo ]rR cI  X MC/s  others cpu C% gpu G%  DIFF`; -1 means the load is missing.
struct FdtdParsedABRun: Sendable, Equatable {
    var round: Int
    var config: Int
    var mcs: Double
    var othersCpu: Int
    var othersGpu: Int
    /// `reference`, `identical`, `probes rel NUM` or `PROBLEM ...`.
    var diff: String
    /// A discarded run (`# redo `).
    var redo = false
    var line: String
}

/// `# rR[ cI]: TEXT`.
struct FdtdParsedABNote: Sendable, Equatable {
    var round: Int
    var config: Int? = nil
    var text: String
}

/// `cI LABEL  MEDIAN [MIN-MAX]  xRATIO [MIN-MAX]  others C%/G%  DIFFS` (abtest's own medians, which include -1 values;
/// they stay in tool.log and the record).
struct FdtdParsedABSummary: Sendable, Equatable {
    var config: Int
    var label: String
    var medianMcs: Double
    var minMcs: Double
    var maxMcs: Double
    var ratio: Double
    var minRatio: Double
    var maxRatio: Double
    var othersCpu: Int
    var othersGpu: Int
    var diffs: String
    var line: String
}

/// An abtest record part (or its stdout).
struct FdtdParsedAB: Sendable, Equatable {
    var header: FdtdParsedABHeader? = nil
    var runs: [FdtdParsedABRun] = []
    var notes: [FdtdParsedABNote] = []
    /// The text of `# summary NAME: TEXT`.
    var summaryHeader: String? = nil
    var summaries: [FdtdParsedABSummary] = []
}

// MARK: - validation (6.4)

/// One entry of the suite's `runs{case: [...]}`.
struct FdtdValidationRun: Codable, Sendable, Equatable {
    var run: String
    /// The Create parenthesis texts joined by "; ", or "basic".
    var engine: String
    @FdtdNullable var threads: FdtdJSONValue? = nil
}

/// One entry of the suite's `results[]`; a crashed case has error NaN and passed false.
struct FdtdValidationCheck: Codable, Sendable, Equatable {
    var caseName: String
    var quantity: String
    @FdtdNullable var value: Double? = nil
    @FdtdNullable var reference: Double? = nil
    @FdtdNullable var error: Double? = nil
    @FdtdNullable var tol: Double? = nil
    @FdtdNullable var kind: String? = nil
    var passed: Bool
    @FdtdNullable var note: String? = nil

    enum CodingKeys: String, CodingKey { case caseName = "case", quantity, value, reference, error, tol, kind, passed, note }
}

/// OUT/validation_TAG.json.
struct FdtdValidationReport: Codable, Sendable, Equatable {
    /// tag, engine, threads, libraries, lib_path (with ~), quick, and whatever else the suite writes.
    var meta: [String: FdtdJSONValue]
    /// Case times in seconds: run times, shown only with a valid whole-run load.
    var timings: [String: FdtdJSONValue]
    var runs: [String: [FdtdValidationRun]]
    var results: [FdtdValidationCheck]
}

// MARK: - debye, diamond (6.4)

/// One comparison of a script check.
struct FdtdScriptComparison: Codable, Sendable, Equatable {
    var title: String
    var identical: Bool
}

/// debye_check.sh's output: `== ` run headers, `X vs Y:` titles each followed by `  IDENTICAL|DIFFERENT`, the
/// `no exported fields` line, and `PASS: ` or `FAIL: `.
struct FdtdParsedDebye: Sendable, Equatable {
    var runs: [String] = []
    var comparisons: [FdtdScriptComparison] = []
    var noExportedFields = false
    var verdictLine: String? = nil
    /// PASS → true, FAIL → false, nil without a verdict line.
    var passed: Bool? = nil
}

/// One `  LABEL: IDENTICAL|DIFFERENT` line of a diamond box.
struct FdtdDiamondComparison: Codable, Sendable, Equatable {
    var box: String
    var label: String
    var identical: Bool
}

/// diamond_check.sh's output: `== ` boxes, their comparisons, `  K=N: the GPU path did not run`, `  tuned, batch 8:
/// the tuning did not finish`, `  CPU|Metal run failed`, and `PASS: ` or `FAIL: `.
struct FdtdParsedDiamond: Sendable, Equatable {
    var boxes: [String] = []
    var comparisons: [FdtdDiamondComparison] = []
    /// "BOX: K=N" for each GPU path that did not run.
    var gpuPathMissing: [String] = []
    var tuningUnfinished = false
    /// "CPU" or "Metal", per failed run.
    var runFailed: [String] = []
    var verdictLine: String? = nil
    var passed: Bool? = nil
}

// MARK: - openEMS lines and call segments (6.4)

/// `Create FDTD engine[ (TEXT)]`.
struct FdtdCreateLine: Sendable, Equatable {
    var line: String
    /// nil for the bare line (basic).
    var parenthesis: String? = nil
}

/// The lines between `FDTDKIT_CALL_BEGIN k` and `FDTDKIT_CALL_END k`.
struct FdtdCallSegment: Sendable, Equatable {
    var index: Int
    var lines: [String] = []
    /// The END marker was seen.
    var ended = false
}

/// How a run stopped.
enum FdtdStopKind: String, Codable, Sendable {
    case probeEnd, energy, maxTimesteps, aborted
}

/// A call's `stop{kind, timesteps}`.
struct FdtdRunStop: Codable, Sendable, Equatable {
    var kind: FdtdStopKind
    @FdtdNullable var timesteps: Int? = nil
}

/// What one segment's openEMS lines say.
struct FdtdOpenEMSFacts: Sendable, Equatable {
    var creates: [FdtdCreateLine] = []
    var threadsFixed: Int? = nil
    var threadsPicked: Int? = nil
    /// `Time for N iterations with C cells : T sec`.
    var timesteps: Int? = nil
    var cells: Double? = nil
    var seconds: Double? = nil
    var stop: FdtdRunStop? = nil
    /// An Engine_Metal_Diamond fallback line (FdtdParsers.isGpuFallback).
    var gpuFallback = false

    /// N*C/T/1e6 (bench's formula).
    var mcs: Double? {
        guard let n = timesteps, let c = cells, let t = seconds, t > 0 else { return nil }
        return Double(n) * c / t / 1e6
    }
}

// MARK: - launcher report (13)

/// The report's python{executable, version}.
struct FdtdLauncherPython: Codable, Sendable, Equatable {
    var executable: String
    var version: String
}

/// The report's binding{version, legacyEmptyOption}.
struct FdtdLauncherBinding: Codable, Sendable, Equatable {
    @FdtdNullable var version: String? = nil
    @FdtdNullable var legacyEmptyOption: Bool? = nil
}

/// An injected option the script also gave: both values as repr().
struct FdtdOverride: Codable, Sendable, Equatable {
    var script: String
    var cli: String
}

/// One FDTD.Run call as the shim recorded it.
struct FdtdLauncherCall: Codable, Sendable, Equatable {
    var index: Int
    var simPath: String
    var setupOnly: Bool
    var options: [String: String]
    var applied: [String: String]
    var overridden: [String: FdtdOverride]
    var optionsLost: [String]
    var stdoutRedirected: Bool
    var wallSeconds: Double
    @FdtdNullable var load: FdtdSamplerResult? = nil
    @FdtdNullable var loadCounts: FdtdLoadCounts? = nil
    var stopRequested: Bool
    /// OPENEMS_PROBE_END_DB and _HOLD as the call saw them.
    var probeEnd: [String: String?]
}

/// RUN/launcher-ROLE.json.
struct FdtdLauncherReport: Codable, Sendable, Equatable {
    /// "script" or "exec".
    var mode: String
    var target: String
    var argv: [String]
    @FdtdNullable var exit: Int32? = nil
    var interrupted: Bool
    @FdtdNullable var exception: String? = nil
    var wallSeconds: Double
    @FdtdNullable var load: FdtdSamplerResult? = nil
    @FdtdNullable var loadCounts: FdtdLoadCounts? = nil
    /// Script mode: loaded_libs() at the end; [] in exec mode.
    var libraries: [String]
    @FdtdNullable var dyld: String? = nil
    var python: FdtdLauncherPython
    @FdtdNullable var binding: FdtdLauncherBinding? = nil
    var calls: [FdtdLauncherCall]
}

// MARK: - Parsers

/// The parsers of spec 6.
enum FdtdParsers {
    /// NUM: `[-+]?(?:\d+(?:\.\d*)?(?:[eE][-+]?\d+)?|inf|nan)`.
    static let numberPattern = #"[-+]?(?:\d+(?:\.\d*)?(?:[eE][-+]?\d+)?|inf|nan)"#

    /// A NUM as Double (inf and nan included).
    static func number(_ text: String) -> Double? {
        let pattern = #/[+\-]?(?:\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?|inf|nan)/#
        guard text.wholeMatch(of: pattern) != nil else { return nil }
        var body = Substring(text)
        var negative = false
        if let sign = body.first, sign == "+" || sign == "-" {
            negative = sign == "-"
            body = body.dropFirst()
        }
        if body == "inf" { return negative ? -Double.infinity : Double.infinity }
        if body == "nan" { return Double.nan }
        // NUM allows `1.` and `1.e5`; give the parser a digit after the dot.
        var digits = String(body)
        if let dot = digits.firstIndex(of: ".") {
            let next = digits.index(after: dot)
            if next == digits.endIndex || digits[next] == "e" || digits[next] == "E" { digits.insert("0", at: next) }
        }
        guard let value = Double(digits) else { return nil }
        return negative ? -value : value
    }

    /// A whole bench output: header, rows, summary, `wrote`, skipped `#` lines (a `# ` + summary is a summary).
    static func benchOutput(_ text: String) -> FdtdParsedBench {
        let patterns = FdtdBenchPatterns()
        var bench = FdtdParsedBench()
        for line in lines(text) { absorb(line, into: &bench, patterns) }
        return bench
    }

    /// One row line, or nil when the line is not a row.
    static func benchRow(_ line: String) -> FdtdParsedBenchRow? {
        row(line, FdtdBenchPatterns())
    }

    /// `^(?:# )?(MISMATCH|NOTHING COMPARED|NOTHING REQUIRED TO MATCH|IDENTICAL): (.*)$`.
    static func benchSummary(_ line: String) -> FdtdBenchSummary? {
        summary(line, FdtdBenchPatterns())
    }

    /// usage.fmt's `during ...` text, wherever it sits in `text`.
    static func usageFmt(_ text: String) -> FdtdUsageFmt? {
        usage(text, FdtdBenchPatterns())
    }

    /// An abtest record part or stdout; any `#` line that is not a header, redo run, note or summary header is skipped.
    static func abtestOutput(_ text: String) -> FdtdParsedAB {
        let header = #/^# (\S+)  (\d{4}-\d\d-\d\d \d\d:\d\d)  load avg [\d.]+  (\d+) rounds, interleaved(?:, each round after others <= (\d+) % CPU)?$/#
        let run = #/^(# redo )?r(\d+) c(\d+) +(\S+) MC/s  others cpu +(-?\d+)% gpu +(-?\d+)%  (.+)$/#
        let summaryHeader = #/^# summary (\S+): (.*)$/#
        let note = #/^# r(\d+)(?: c(\d+))?: (.*)$/#
        let summary = #/^c(\d+) (\S+)\s+([\d.]+) \[(\d+)-(\d+)\]  x([\d.]+) \[([\d.]+)-([\d.]+)\]  others (-?\d+)%/(-?\d+)%  (.*)$/#
        var ab = FdtdParsedAB()
        for line in lines(text) {
            if let m = line.wholeMatch(of: header), let rounds = Int(m.output.3) {
                ab.header = FdtdParsedABHeader(name: String(m.output.1), date: String(m.output.2), rounds: rounds,
                                               quietPercent: m.output.4.flatMap { Int($0) })
                continue
            }
            if let m = line.wholeMatch(of: run), let round = Int(m.output.2), let config = Int(m.output.3),
               let mcs = number(String(m.output.4)), let cpu = Int(m.output.5), let gpu = Int(m.output.6),
               isABDiff(m.output.7) {
                ab.runs.append(FdtdParsedABRun(round: round, config: config, mcs: mcs, othersCpu: cpu, othersGpu: gpu,
                                               diff: String(m.output.7), redo: m.output.1 != nil, line: line))
                continue
            }
            if let m = line.wholeMatch(of: summaryHeader) {
                ab.summaryHeader = String(m.output.2)
                continue
            }
            if let m = line.wholeMatch(of: note), let round = Int(m.output.1) {
                ab.notes.append(FdtdParsedABNote(round: round, config: m.output.2.flatMap { Int($0) },
                                                 text: String(m.output.3)))
                continue
            }
            if let m = line.wholeMatch(of: summary) {
                let o = m.output
                if let config = Int(o.1), let median = number(String(o.3)), let low = number(String(o.4)),
                   let high = number(String(o.5)), let ratio = number(String(o.6)), let ratioLow = number(String(o.7)),
                   let ratioHigh = number(String(o.8)), let cpu = Int(o.9), let gpu = Int(o.10) {
                    ab.summaries.append(FdtdParsedABSummary(config: config, label: String(o.2), medianMcs: median,
                                                            minMcs: low, maxMcs: high, ratio: ratio, minRatio: ratioLow,
                                                            maxRatio: ratioHigh, othersCpu: cpu, othersGpu: gpu,
                                                            diffs: String(o.11), line: line))
                }
            }
        }
        return ab
    }

    /// check.sh's output: the bench blocks and the final line.
    static func checkOutput(_ text: String) -> FdtdParsedCheck {
        let patterns = FdtdBenchPatterns()
        var check = FdtdParsedCheck()
        var block = FdtdParsedBench()
        var inBlock = false
        for line in lines(text) {
            if let name = header(line, patterns) {
                if inBlock { check.blocks.append(block) }
                block = FdtdParsedBench(name: name)
                inBlock = true
                continue
            }
            if line.hasPrefix("check.sh "), let last = checkFinal(line) {
                check.finalLine = last
                continue
            }
            if inBlock { absorb(line, into: &block, patterns) }
        }
        if inBlock { check.blocks.append(block) }
        return check
    }

    /// One of check.sh's four final-line forms, or nil.
    static func checkFinal(_ line: String) -> FdtdCheckFinal? {
        let identical = #/^check\.sh (\S+): ALL IDENTICAL \((\d+) models\)$/#
        let partial = #/^check\.sh (\S+): PARTIAL: (.*)$/#
        let fail = #/^check\.sh (\S+): FAIL: (.*)$/#
        let stopped = #/^check\.sh (\S+): bench\.py (\S+) stopped with exit status (\d+)$/#
        if let m = line.wholeMatch(of: identical) {
            return FdtdCheckFinal(tag: String(m.output.1), kind: .allIdentical, models: Int(m.output.2), line: line)
        }
        if let m = line.wholeMatch(of: partial) {
            return FdtdCheckFinal(tag: String(m.output.1), kind: .partial, detail: String(m.output.2), line: line)
        }
        if let m = line.wholeMatch(of: fail) {
            return FdtdCheckFinal(tag: String(m.output.1), kind: .fail, detail: String(m.output.2), line: line)
        }
        if let m = line.wholeMatch(of: stopped) {
            return FdtdCheckFinal(tag: String(m.output.1), kind: .benchStopped, detail: String(m.output.2),
                                  benchExit: Int32(m.output.3), line: line)
        }
        return nil
    }

    /// The validation JSON, read as JSON5 (NaN and Infinity allowed).
    static func validation(_ data: Data) throws -> FdtdValidationReport { try FdtdJSON.decode(FdtdValidationReport.self, from: data) }

    static func debyeOutput(_ text: String) -> FdtdParsedDebye {
        let header = #/^== (.*)$/#
        let title = #/^(\S.* vs .*):$/#
        let result = #/^  (IDENTICAL|DIFFERENT)$/#
        var debye = FdtdParsedDebye()
        var pending: String? = nil
        for line in lines(text) {
            if let m = line.wholeMatch(of: header) {
                debye.runs.append(m.output.1.trimmingCharacters(in: .whitespaces))
                continue
            }
            if let m = line.wholeMatch(of: result) {
                // the verdict belongs to the `X vs Y:` title printed before it
                debye.comparisons.append(FdtdScriptComparison(title: pending ?? "", identical: m.output.1 == "IDENTICAL"))
                pending = nil
                continue
            }
            if let m = line.wholeMatch(of: title) {
                pending = String(m.output.1)
                continue
            }
            if line.hasPrefix("debye_check.sh: no exported fields") {
                debye.noExportedFields = true
                continue
            }
            if line.hasPrefix("PASS: ") || line.hasPrefix("FAIL: ") {
                debye.verdictLine = line
                debye.passed = line.hasPrefix("PASS: ")
            }
        }
        return debye
    }

    static func diamondOutput(_ text: String) -> FdtdParsedDiamond {
        let header = #/^== (.*)$/#
        let missing = #/^  K=(\d+): the GPU path did not run$/#
        let failed = #/^  (CPU|Metal) run failed/#
        let comparison = #/^  (.+): (IDENTICAL|DIFFERENT)$/#
        var diamond = FdtdParsedDiamond()
        var box = ""
        for line in lines(text) {
            if let m = line.wholeMatch(of: header) {
                // `== bc, n lines, ts timesteps ARGS` keeps a trailing space when there are no ARGS
                box = m.output.1.trimmingCharacters(in: .whitespaces)
                diamond.boxes.append(box)
                continue
            }
            if let m = line.wholeMatch(of: missing) {
                diamond.gpuPathMissing.append("\(box): K=\(m.output.1)")
                continue
            }
            if line == "  tuned, batch 8: the tuning did not finish" {
                diamond.tuningUnfinished = true
                continue
            }
            if let m = line.firstMatch(of: failed) {
                diamond.runFailed.append(String(m.output.1))
                continue
            }
            if let m = line.wholeMatch(of: comparison) {
                diamond.comparisons.append(FdtdDiamondComparison(box: box, label: String(m.output.1),
                                                                 identical: m.output.2 == "IDENTICAL"))
                continue
            }
            if line.hasPrefix("PASS: ") || line.hasPrefix("FAIL: ") {
                diamond.verdictLine = line
                diamond.passed = line.hasPrefix("PASS: ")
            }
        }
        return diamond
    }

    /// The JSON of `^RESULT (\{.*\})$` (JSON5), the last such line.
    static func e2eResult(_ text: String) -> FdtdJSONValue? {
        let result = #/^RESULT (\{.*\})$/#
        var json: String? = nil
        for line in lines(text) {
            if let m = line.wholeMatch(of: result) { json = String(m.output.1) }
        }
        guard let json else { return nil }
        return try? FdtdJSON.decode(FdtdJSONValue.self, from: Data(json.utf8))
    }

    /// The call segments of a tool.log, by the launcher's markers; an unterminated segment has ended false.
    static func callSegments(_ text: String) -> [FdtdCallSegment] {
        let marker = #/FDTDKIT_CALL_(BEGIN|END) (\d+)\s*/#
        var segments: [FdtdCallSegment] = []
        var current: FdtdCallSegment? = nil
        for line in lines(text) {
            // A marker normally starts its line; if openEMS left a line without its newline, the text before the
            // marker still belongs to the segment that is open.
            guard let at = line.range(of: "FDTDKIT_CALL_"),
                  let m = String(line[at.lowerBound...]).wholeMatch(of: marker),
                  let index = Int(m.output.2) else {
                current?.lines.append(line)
                continue
            }
            let before = String(line[..<at.lowerBound])
            if !before.isEmpty { current?.lines.append(before) }
            if m.output.1 == "BEGIN" {
                if let unterminated = current { segments.append(unterminated) }
                current = FdtdCallSegment(index: index)
            } else if var segment = current, segment.index == index {
                segment.ended = true
                segments.append(segment)
                current = nil
            }
        }
        if let unterminated = current { segments.append(unterminated) }
        return segments
    }

    /// The openEMS lines of one segment (or of one openEMS.log).
    static func openEMSFacts(_ lines: [String]) -> FdtdOpenEMSFacts {
        let fixed = #/openEMS - fixed number of threads: (\d+)/#
        let picked = #/Best performance found using (\d+) threads/#
        let timing = #/Time for (\d+) iterations with ([\d.eE+\-]+) cells : ([\d.eE+\-]+) sec/#
        let aborted = #/RunFDTD: simulation aborted after (\d+)/#
        let probeEnd = #/RunFDTD: probe end criterion reached after (\d+) timesteps/#
        let energy = #/RunFDTD: end-criteria of (-?[\d.]+)dB reached after (\d+)/#
        var facts = FdtdOpenEMSFacts()
        for line in lines {
            if line.hasPrefix("Create FDTD engine"), let create = createLine(line) {
                facts.creates.append(create)
                continue
            }
            if let m = line.firstMatch(of: fixed) {
                facts.threadsFixed = Int(m.output.1)
                continue
            }
            if let m = line.firstMatch(of: picked) {
                facts.threadsPicked = Int(m.output.1)
                continue
            }
            if let m = line.firstMatch(of: timing) {
                facts.timesteps = Int(m.output.1)
                facts.cells = Double(m.output.2)
                facts.seconds = Double(m.output.3)
                continue
            }
            if let m = line.firstMatch(of: aborted) {
                facts.stop = FdtdRunStop(kind: .aborted, timesteps: Int(m.output.1))
                continue
            }
            if let m = line.firstMatch(of: probeEnd) {
                facts.stop = FdtdRunStop(kind: .probeEnd, timesteps: Int(m.output.1))
                continue
            }
            if let m = line.firstMatch(of: energy) {
                facts.stop = FdtdRunStop(kind: .energy, timesteps: Int(m.output.2))
                continue
            }
            if line.contains("RunFDTD: Warning: Max. number of timesteps was reached") {
                facts.stop = FdtdRunStop(kind: .maxTimesteps)
                continue
            }
            if isGpuFallback(line) { facts.gpuFallback = true }
        }
        // The max-timesteps warning carries no count; the Time-for line after it does.
        if let stop = facts.stop, stop.kind == .maxTimesteps, stop.timesteps == nil {
            facts.stop = FdtdRunStop(kind: .maxTimesteps, timesteps: facts.timesteps)
        }
        return facts
    }

    /// An Engine_Metal_Diamond line after which the engine runs the CPU loops (spec 4.4): `... running the CPU loops`,
    /// or the two SetupGPU failures that do not say so (engine_metal_diamond.mm, cg29 :976 and :983).
    static func isGpuFallback(_ line: String) -> Bool {
        let prefix = "Engine_Metal_Diamond: "
        guard line.hasPrefix(prefix) else { return false }
        return line.contains("running the CPU loops") || line.hasPrefix(prefix + "kernel compilation failed")
            || line.hasPrefix(prefix + "pipeline creation failed")
    }

    /// The fallback lines of a log (isGpuFallback).
    static func gpuFallbackLines(_ text: String) -> [String] { lines(text).filter { isGpuFallback($0) } }

    /// `^Create FDTD engine(?: \((.*)\))?\s*$`.
    static func createLine(_ line: String) -> FdtdCreateLine? {
        // callers pass every log line; only Create lines pay for the regex
        guard line.hasPrefix("Create FDTD engine") else { return nil }
        let create = #/^Create FDTD engine(?: \((.*)\))?\s*$/#
        guard let m = line.wholeMatch(of: create) else { return nil }
        var text = line
        while let last = text.last, last.isWhitespace { text.removeLast() }
        return FdtdCreateLine(line: text, parenthesis: m.output.1.map { String($0) })
    }

    /// A launcher report (JSON5).
    static func launcherReport(_ data: Data) throws -> FdtdLauncherReport {
        try FdtdJSON.decode(FdtdLauncherReport.self, from: data)
    }

    /// The JSON after `TAG ` on the last line that starts with it, decoded as JSON5; nil when there is none.
    static func taggedJSON<T: Decodable>(_ tag: String, in output: String, as type: T.Type) -> T? {
        let prefix = tag + " "
        guard let line = lines(output).last(where: { $0.hasPrefix(prefix) }) else { return nil }
        return try? FdtdJSON.decode(type, from: Data(line.dropFirst(prefix.count).utf8))
    }

    // MARK: helpers

    /// Lines without their terminators ("\r\n" is one Character, so it is one separator).
    private static func lines(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map { String($0) }
    }

    /// One line of a bench output into `bench`: the header names it, a summary (also `# ` + summary) ends it.
    private static func absorb(_ line: String, into bench: inout FdtdParsedBench, _ p: FdtdBenchPatterns) {
        if let name = header(line, p) {
            if bench.name == nil { bench.name = name }
            return
        }
        if let found = summary(line, p) {
            bench.summary = found
            return
        }
        if line.hasPrefix("#") {
            bench.skipped.append(line)
            return
        }
        if let m = line.wholeMatch(of: p.wrote) {
            bench.wrote = String(m.output.1)
            return
        }
        // Anything else that is not a row (Python warnings, the runner's messages) is left out.
        if let parsed = row(line, p) { bench.rows.append(parsed) }
    }

    /// NAME of a stdout or tag-file header.
    private static func header(_ line: String, _ p: FdtdBenchPatterns) -> String? {
        if let m = line.wholeMatch(of: p.stdoutHeader) { return String(m.output.1) }
        if let m = line.wholeMatch(of: p.tagHeader) { return String(m.output.1) }
        return nil
    }

    private static func summary(_ line: String, _ p: FdtdBenchPatterns) -> FdtdBenchSummary? {
        guard let m = line.wholeMatch(of: p.summary) else { return nil }
        let text = line.hasPrefix("# ") ? String(line.dropFirst(2)) : line
        return FdtdBenchSummary(kind: String(m.output.1), line: text)
    }

    /// bench's s_note for --no-sparams (bench.py:322).
    private static let noSparamsNote = "S-params not computed (--no-sparams)"

    private static func row(_ line: String, _ p: FdtdBenchPatterns) -> FdtdParsedBenchRow? {
        guard let m = line.wholeMatch(of: p.row) else { return nil }
        // mcs, t and the cell figure are read as NUM: `{:8.1f}` prints inf and nan as words
        guard let mcs = number(String(m.output.mcs)), let seconds = number(String(m.output.t)),
              let timesteps = Int(m.output.nts), let megaCells = number(String(m.output.mc)),
              let othersBefore = Int(m.output.other) else { return nil }
        var parsed = FdtdParsedBenchRow(line: line, label: String(m.output.label), mcs: mcs, seconds: seconds,
                                        timesteps: timesteps, megaCells: megaCells, othersCpuBefore: othersBefore)
        let rest = String(m.output.rest)
        if let r = rest.firstMatch(of: p.runs) { parsed.repeats = r.output.1.split(separator: "/").count }
        if let b = rest.firstMatch(of: p.busy) { parsed.busyBefore = b.output.1.split(separator: ",").map { String($0) } }
        parsed.during = usage(rest, p)
        parsed.quietWaitTimedOut = rest.contains("  quiet-wait timed out")
        if let a = rest.firstMatch(of: p.autoPicked) { parsed.autoPickedThreads = Int(a.output.1) }
        parsed.reference = rest.contains("  [ref]")
        if let r = rest.firstMatch(of: p.probes) { parsed.probesRel = number(String(r.output.1)) }
        if let z = rest.firstMatch(of: p.zeroFiles), let zero = Int(z.output.1), let total = Int(z.output.2) {
            parsed.zeroFiles = FdtdZeroFiles(zero: zero, total: total)
        }
        if let pr = rest.firstMatch(of: p.problems) {
            parsed.problems = pr.output.1.components(separatedBy: "; ").filter { !$0.isEmpty }
        }
        parsed.sparams = sparams(rest, p)
        if rest.contains(noSparamsNote) {
            parsed.sparamNote = noSparamsNote
        } else if let n = rest.firstMatch(of: p.skippedNote) {
            parsed.sparamNote = String(n.output)
        }
        parsed.tolerant = rest.contains("  (tolerant)")
        if let v = rest.firstMatch(of: p.version) { parsed.openemsVersion = String(v.output.1) }
        return parsed
    }

    /// The `SNN:` fields in the order bench printed them; each is one two-space separated part of the row.
    private static func sparams(_ rest: String, _ p: FdtdBenchPatterns) -> [FdtdParsedSParam] {
        var fields: [FdtdParsedSParam] = []
        for part in rest.components(separatedBy: "  ") {
            let text = part.trimmingCharacters(in: .whitespaces)
            if let m = text.wholeMatch(of: p.sBelowFloor) {
                var field = FdtdParsedSParam(name: String(m.output.1))
                field.belowFloor = true
                if m.output.2 == "equal" {
                    field.equal = true
                } else if let diff = m.output.3 {
                    field.maxAbsDiff = number(String(diff))
                }
                fields.append(field)
            } else if let m = text.wholeMatch(of: p.sField) {
                var field = FdtdParsedSParam(name: String(m.output.1))
                field.maxAbsDiff = number(String(m.output.2))
                field.maxDb = number(String(m.output.3))
                field.differsBelowFloor = m.output.4 != nil
                fields.append(field)
            }
        }
        return fields
    }

    private static func usage(_ text: String, _ p: FdtdBenchPatterns) -> FdtdUsageFmt? {
        guard let m = text.firstMatch(of: p.during) else { return nil }
        guard let wall = number(String(m.output.w)), let selfCpu = number(String(m.output.cs)),
              let selfGpu = number(String(m.output.gs)), let othersCpu = number(String(m.output.co)),
              let othersGpu = number(String(m.output.go)) else { return nil }
        var use = FdtdUsageFmt(wallSeconds: wall, selfCpuPercent: selfCpu, selfGpuSecondsAtLeast: selfGpu,
                               othersCpuPercent: othersCpu, othersGpuPercent: othersGpu)
        if let dev = m.output.gd { use.gpuDevicePercent = number(String(dev)) }
        if let busy = m.output.busy { use.busy = busy.split(separator: ",").map { String($0) } }
        return use
    }

    /// abtest's diff field: `reference`, `identical`, `probes rel NUM` or `PROBLEM ...`.
    private static func isABDiff(_ diff: Substring) -> Bool {
        let word = String(diff)
        if word == "reference" { return true }
        if word == "identical" { return true }
        if word.hasPrefix("PROBLEM ") { return true }
        guard diff.hasPrefix("probes rel ") else { return false }
        return number(String(diff.dropFirst("probes rel ".count))) != nil
    }
}

/// The bench patterns (spec 6.1), made once per parse: Regex is not Sendable, so they cannot be static constants.
private struct FdtdBenchPatterns {
    let row = #/^(?<label>\S+)\s+(?<mcs>\S+) MC/s\s+(?<t>\S+) s\s+(?<nts>\d+) TS x (?<mc>\S+) MC\s+others\s+(?<other>\d+)%(?<rest>.*)$/#
    let runs = #/  runs (\S+)/#
    /// Up to the next two-space separator: top names cut to 16 characters may hold single spaces.
    let busy = #/  busy (.*?)(?=  |$)/#
    let during = #/during (?<w>[\d.]+) s: self cpu (?<cs>\d+)% gpu>=(?<gs>[\d.]+) s, others cpu (?<co>\d+)% gpu (?<go>\d+)%(?:, gpu dev (?<gd>\d+)%)?(?: \[(?<busy>[^\]]*)\])?/#
    let autoPicked = #/\(auto-picked (\d+) threads\)/#
    let probes = #/probes rel=(\S+)/#
    let zeroFiles = #/\((\d+) of (\d+) files all zero in the reference, compared exactly\)/#
    let problems = #/PROBLEM: (.*?)(?=  S\d\d: |  S-params |  \(tolerant\)|  openEMS |$)/#
    let sBelowFloor = #/(S\d\d): below -40 dB, compared exactly: (equal|max\|dS\|=(\S+))/#
    let sField = #/(S\d\d): max\|dS\|=(\S+) max dB=(\S+)( \(differs below -40 dB\))?/#
    let skippedNote = #/S-params skipped: \d+ probe samples?, raise --nrts/#
    let version = #/  openEMS (\S+)$/#
    let summary = #/^(?:# )?(MISMATCH|NOTHING COMPARED|NOTHING REQUIRED TO MATCH|IDENTICAL): (.*)$/#
    let stdoutHeader = #/^# (\S+)  load avg [\d.]+$/#
    let tagHeader = #/^# (\S+)  \d{4}-\d\d-\d\d \d\d:\d\d$/#
    let wrote = #/^wrote (.+)$/#
}
