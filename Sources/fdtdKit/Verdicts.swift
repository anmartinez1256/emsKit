// SPDX-License-Identifier: GPL-3.0-or-later

// Verdicts (spec 2.4-2.10, 6.3): from what the tools printed and wrote to the issues that decide the exit. A verdict
// never sets the status itself: its errors go to session.error (exit 1 for a failed comparison, 4 for a tool that
// failed or output that cannot be read), its warnings to session.warn, and `partial` to session.partial.
import Foundation

/// What a verdict found.
struct FdtdVerdict: Sendable, Equatable {
    var passed: Bool
    /// Exit 0 counts as partial (check with --allow-partial, or a reference that is not stock v0.37.0).
    var partial = false
    var errors: [FdtdIssue] = []
    var warnings: [FdtdIssue] = []
}

/// The verdict rules per command.
enum FdtdVerdicts {
    /// bench (2.4): MISMATCH → fail (mismatch); IDENTICAL → ok; NOTHING COMPARED / NOTHING REQUIRED TO MATCH → ok with
    /// nothing_verified; --exact and a compared row not exact → fail (not_exact); no summary, a bench exit outside
    /// {0, 2}, or exit 2 without MISMATCH → tool_failed / tool_output_unparsed. Tolerant rows give tolerant_rows.
    static func bench(summary: FdtdBenchSummary?, rows: [FdtdBenchRow], exact: Bool, benchExit: Int32?) -> FdtdVerdict {
        var verdict = FdtdVerdict(passed: false)
        guard let status = benchExit else {
            verdict.errors.append(FdtdIssue(.toolFailed, "bench.py did not exit normally"))
            return verdict
        }
        guard status == 0 || status == 2 else {
            verdict.errors.append(FdtdIssue(.toolFailed, "bench.py exited with status \(status)"))
            return verdict
        }
        guard let summary else {
            // bench exits 2 on an argument error too (F4); then it never ran
            if status == 2 {
                verdict.errors.append(FdtdIssue(.toolFailed, "bench.py exited with status 2 without a summary line"))
            } else {
                verdict.errors.append(FdtdIssue(.toolOutputUnparsed, "bench.py printed no summary line"))
            }
            return verdict
        }
        var failedLabels: Set<String> = []
        switch summary.kind {
        case "MISMATCH":
            verdict.errors.append(FdtdIssue(.mismatch, "bench.py: " + summary.line))
            failedLabels = Set(summary.line.dropFirst("MISMATCH: ".count).components(separatedBy: ", "))
        case "IDENTICAL":
            break
        case "NOTHING COMPARED":
            verdict.warnings.append(FdtdIssue(.nothingVerified, "bench.py: " + summary.line))
        case "NOTHING REQUIRED TO MATCH":
            // with --exact the CLI requires the tolerant rows to match, so they are verified below
            if !exact { verdict.warnings.append(FdtdIssue(.nothingVerified, "bench.py: " + summary.line)) }
        default:
            verdict.errors.append(FdtdIssue(.toolOutputUnparsed, "bench.py printed an unknown summary: " + summary.line))
        }
        if status == 2 && summary.kind != "MISMATCH" {
            verdict.errors.append(FdtdIssue(.toolOutputUnparsed, "bench.py exited with status 2 without a MISMATCH line"))
        }
        let comparedRows = rows.filter { isCompared($0) }
        if exact {
            // --exact verifies the tolerant rows itself; without a compared row it verified nothing
            if summary.kind == "NOTHING REQUIRED TO MATCH" && comparedRows.isEmpty {
                verdict.warnings.append(FdtdIssue(.nothingVerified, "bench.py: " + summary.line))
            }
            // bench's own MISMATCH already names the rows it failed
            for row in comparedRows where !isExact(row) && !failedLabels.contains(row.label) {
                verdict.errors.append(FdtdIssue(.notExact, "\(row.label) is not bit-identical to the reference",
                                                field: "--exact"))
            }
        } else {
            let tolerant = comparedRows.filter { $0.tolerant }.map { $0.label }
            if !tolerant.isEmpty {
                let names = tolerant.joined(separator: ", ")
                verdict.warnings.append(FdtdIssue(.tolerantRows, "compared, not required to match: \(names)"))
            }
        }
        verdict.passed = verdict.errors.isEmpty
        return verdict
    }

    /// ab (2.5): ok when abtest exits 0, every config has a summary line, and every config that must match (the
    /// non-tolerant ones, all with --exact) has only `identical` diffs in its kept runs (`reference` for c0's);
    /// otherwise fail (mismatch / not_exact); an abtest exit other than 0 → tool_failed.
    static func ab(abtestExit: Int32?, configs: [FdtdABConfigResult], summaries: [FdtdParsedABSummary],
                   exact: Bool) -> FdtdVerdict {
        var verdict = FdtdVerdict(passed: false)
        guard let status = abtestExit, status == 0 else {
            let text = abtestExit.map { "abtest.py exited with status \($0)" } ?? "abtest.py did not exit normally"
            verdict.errors.append(FdtdIssue(.toolFailed, text))
            return verdict
        }
        let summarized = Set(summaries.map { $0.config })
        let unsummarized = configs.filter { !summarized.contains($0.index) }.map { "c\($0.index)" }
        if !unsummarized.isEmpty {
            let names = unsummarized.joined(separator: ", ")
            verdict.errors.append(FdtdIssue(.toolOutputUnparsed, "abtest.py printed no summary line for \(names)"))
        }
        var tolerantNames: [String] = []
        var verified = false
        for config in configs {
            let name = "c\(config.index) \(config.label)"
            let mustMatch = exact || !config.tolerant
            if mustMatch {
                if config.diffs.contains(where: { $0 != "reference" }) { verified = true }
                if !config.identical {
                    let code: FdtdCode = config.tolerant ? .notExact : .mismatch
                    let text = "\(name) is not identical in every kept run: " + diffsText(config)
                    verdict.errors.append(FdtdIssue(code, text, field: config.tolerant ? "--exact" : nil))
                }
            } else {
                tolerantNames.append(name)
                // bench fails a tolerant row with a PROBLEM too (bench.py:373-374)
                if config.diffs.contains(where: { $0.hasPrefix("PROBLEM") }) {
                    let text = "\(name) (tolerant) has a run with a PROBLEM: " + diffsText(config)
                    verdict.errors.append(FdtdIssue(.mismatch, text))
                }
            }
        }
        if !tolerantNames.isEmpty {
            let names = tolerantNames.joined(separator: ", ")
            verdict.warnings.append(FdtdIssue(.tolerantRows, "compared, not required to match: \(names)"))
        }
        if !configs.isEmpty && !verified {
            verdict.warnings.append(FdtdIssue(.nothingVerified, "no run of a config that must match was compared",
                                              hint: "--exact"))
        }
        verdict.passed = verdict.errors.isEmpty
        return verdict
    }

    /// The independent guard's exact rows per model: nSnap x (lite ? 3 : 5) + the non-tolerant extras + (lite ? 0 : 1);
    /// the full check compares the reference too (--repeat 2).
    static func expectedExactRows(snapshots: Int, lite: Bool, nonTolerantExtras: Int) -> Int {
        snapshots * (lite ? 3 : 5) + nonTolerantExtras + (lite ? 0 : 1)
    }

    /// check (2.6, 6.3): check.sh's final line and the independent guard (every block has a summary, every
    /// non-tolerant compared row is exact, the row count per model, the engines confirmed). ALL IDENTICAL with a failed
    /// guard → verdict_disagrees (4); FAIL → check_failed when every model it names printed a MISMATCH block and every
    /// model ran, otherwise tool_output_unparsed; `bench.py ... stopped` → tool_failed; a block without a summary →
    /// tool_output_unparsed. Then partial when `acceptance` is false (reference_not_stock) or when `allowPartial` let
    /// four models run without rfsim.
    static func check(finalLine: FdtdCheckFinal?, models: [FdtdCheckModel], expectedExactRows: Int, acceptance: Bool,
                      referenceSpec: String, allowPartial: Bool, rfsimFound: Bool) -> FdtdVerdict {
        var verdict = FdtdVerdict(passed: false)
        if !acceptance { verdict.warnings.append(referenceNotStock(referenceSpec)) }
        guard let finalLine else {
            verdict.errors.append(FdtdIssue(.toolOutputUnparsed, "check.sh printed no final line"))
            return verdict
        }
        if finalLine.kind == .benchStopped {
            verdict.errors.append(FdtdIssue(.toolFailed, finalLine.line))
            return verdict
        }
        var disagreements: [String] = []
        for model in models {
            if model.summary == nil {
                // bench stopped inside the block, after its header
                let text = "check model \(model.label): bench.py printed no summary line"
                verdict.errors.append(FdtdIssue(.toolOutputUnparsed, text))
            } else if model.summary?.kind == "MISMATCH" {
                disagreements.append("bench.py printed MISMATCH for \(model.label)")
            }
            let counted = model.rows.filter { !$0.tolerant && isCompared($0) }
            let notExact = counted.filter { !isExact($0) }.map { $0.label }
            if !notExact.isEmpty {
                let names = notExact.joined(separator: ", ")
                disagreements.append("\(model.label) has rows that are not exact (\(names))")
            }
            if counted.count != expectedExactRows {
                disagreements.append("\(model.label) has \(counted.count) counted rows, expected \(expectedExactRows)")
            }
            let unconfirmed = model.rows.filter { $0.engineConfirmed != true }.map { $0.label }
            if !unconfirmed.isEmpty {
                let names = unconfirmed.joined(separator: ", ")
                let text = "check model \(model.label): no Create line of the engine for \(names)"
                verdict.errors.append(FdtdIssue(.engineNotConfirmed, text))
            }
        }
        let expectedModels = rfsimFound ? 6 : 4
        if models.count != expectedModels {
            disagreements.append("\(models.count) models ran, expected \(expectedModels)")
        }
        switch finalLine.kind {
        case .fail:
            failed(finalLine, models: models, expectedModels: expectedModels, into: &verdict)
        case .allIdentical:
            if !rfsimFound { disagreements.append("rfsim was not found, so kgcpw and ksma did not run") }
            if let counted = finalLine.models, counted != expectedModels {
                disagreements.append("the final line counts \(counted) models, expected \(expectedModels)")
            }
        case .partial:
            if rfsimFound { disagreements.append("rfsim was found, so all six models should have run") }
        case .benchStopped:
            break
        }
        if finalLine.kind != .fail && !disagreements.isEmpty {
            let reasons = disagreements.joined(separator: "; ")
            let text = "check.sh printed \(finalLine.kind.rawValue), but \(reasons)"
            verdict.errors.append(FdtdIssue(.verdictDisagrees, text))
        }
        verdict.passed = verdict.errors.isEmpty
        if verdict.passed && !rfsimFound {
            let text = "four of six models ran: rfsim was not found, so kgcpw and ksma were skipped"
            verdict.warnings.append(FdtdIssue(.partial, text, hint: "--rfsim DIR"))
        }
        // Four models run only with allowPartial (the command refuses with 2 otherwise); they count as partial even
        // if a caller passed allowPartial false.
        verdict.partial = verdict.passed && (!acceptance || !rfsimFound)
        return verdict
    }

    /// check's reference_not_stock warning (spec 2.6), the one text for the plan and the verdict.
    static func referenceNotStock(_ referenceSpec: String) -> FdtdIssue {
        let text = "compared with \(referenceSpec), which is not stock v0.37.0: not the CPU acceptance"
        return FdtdIssue(.referenceNotStock, text, field: "--stock")
    }

    /// gpu_fallback for `subject` (a bench row, an ab config, a validation run, an FDTD.Run call): the metal-diamond
    /// engine prints its Create line before it sets up the GPU, so a run of the CPU loops still confirms the engine.
    static func gpuFallback(_ subject: String) -> FdtdIssue {
        FdtdIssue(.gpuFallback, "\(subject): the metal-diamond engine ran the CPU loops instead of the GPU")
    }

    /// validate (2.7): ok when the suite exits 0, every check passed, meta.libraries (~ read as `home`) all lie
    /// in `expectedDir` (by the given or the real path, FdtdDiscovery.lies), and each case has a run whose engine text
    /// is `engine`'s (cases whose runs are all cylindrical are skipped); a failed check → validation_failed; no JSON →
    /// tool_failed.
    static func validate(exit: Int32?, report: FdtdValidationReport?, expectedDir: String, engine: FdtdEngine,
                         home: String, system: any FdtdSystem) -> FdtdVerdict {
        var verdict = FdtdVerdict(passed: false)
        guard let report else {
            verdict.errors.append(FdtdIssue(.toolFailed, "the validation suite wrote no readable JSON" + statusSuffix(exit)))
            return verdict
        }
        if report.results.isEmpty {
            verdict.errors.append(FdtdIssue(.toolOutputUnparsed, "the validation JSON lists no checks"))
        }
        let failed = report.results.filter { !$0.passed }
        for check in failed {
            verdict.errors.append(FdtdIssue(.validationFailed, failedCheckText(check)))
        }
        if failed.isEmpty && exit != 0 {
            let text = exit.map { "the validation suite exited with status \($0) although every check passed" }
                ?? "the validation suite did not exit normally"
            verdict.errors.append(FdtdIssue(.toolFailed, text))
        }
        // The suite writes the home folder as `~` (common.py:41); the paths are dyld's image names.
        let libraries = report.meta["libraries"]?.array?.compactMap { $0.string } ?? []
        let expected = folded(expectedDir, home: home)
        // common.py replaces the home folder's text wherever it occurs (/Users/name2/x becomes ~2/x), so a name is
        // also tried with every `~` read as the home folder
        let foreign = libraries.filter { name in
            let everywhere = name.replacingOccurrences(of: "~", with: home)
            return ![folded(name, home: home), everywhere].contains {
                FdtdDiscovery.lies($0, in: expected, system: system)
            }
        }.map { folded($0, home: home) }
        if libraries.isEmpty {
            let text = "the validation JSON names no loaded openEMS library"
            verdict.errors.append(FdtdIssue(.libraryNotLoaded, text, field: "--lib"))
        } else if !foreign.isEmpty {
            let others = Set(foreign.map { FdtdPaths.dirname($0) }).sorted().joined(separator: ", ")
            let text = "the validation suite loaded libraries from \(others), not only from \(expected)"
            verdict.errors.append(FdtdIssue(.libraryNotLoaded, text, field: "--lib"))
        }
        for name in report.runs.keys.sorted() {
            let runs = report.runs[name] ?? []
            // cylindrical meshes run their own engines whatever was asked
            if runs.isEmpty || runs.allSatisfy({ $0.engine.contains("cylindrical") }) { continue }
            if runs.contains(where: { engine.acceptsValidationText($0.engine) }) { continue }
            let seen = Set(runs.map { $0.engine }).sorted().joined(separator: " | ")
            let text = "validation case \(name): no run shows the \(engine.rawValue) engine (runs: \(seen))"
            verdict.errors.append(FdtdIssue(.engineNotConfirmed, text, field: "--engine"))
        }
        verdict.passed = verdict.errors.isEmpty
        return verdict
    }

    /// debye-check (2.8): exit 0 and `PASS: every comparison is identical` → ok; `FAIL:` → script_check_failed;
    /// `no exported fields` → tool_failed.
    static func debye(exit: Int32?, parsed: FdtdParsedDebye) -> FdtdVerdict {
        var verdict = FdtdVerdict(passed: false)
        if parsed.noExportedFields {
            let text = "debye_check.sh: no exported fields (a run failed, or the library is not a build of this fork)"
            verdict.errors.append(FdtdIssue(.toolFailed, text))
            return verdict
        }
        guard let passed = parsed.passed, let line = parsed.verdictLine else {
            let text = "debye_check.sh printed no PASS or FAIL line" + statusSuffix(exit)
            verdict.errors.append(FdtdIssue(.toolFailed, text))
            return verdict
        }
        let different = parsed.comparisons.filter { !$0.identical }.map { $0.title }
        if !passed {
            var text = "debye_check.sh: " + line
            if !different.isEmpty { text += " (" + different.joined(separator: "; ") + " DIFFERENT)" }
            verdict.errors.append(FdtdIssue(.scriptCheckFailed, text))
        } else if exit != 0 {
            let ending = exit.map { " exited with status \($0)" } ?? " did not exit normally"
            verdict.errors.append(FdtdIssue(.toolFailed, "debye_check.sh printed PASS but" + ending))
        } else if !different.isEmpty {
            let text = "debye_check.sh printed PASS, but " + different.joined(separator: "; ") + " printed DIFFERENT"
            verdict.errors.append(FdtdIssue(.verdictDisagrees, text))
        } else if parsed.comparisons.isEmpty {
            verdict.errors.append(FdtdIssue(.verdictDisagrees, "debye_check.sh printed PASS without any comparison"))
        }
        verdict.passed = verdict.errors.isEmpty
        return verdict
    }

    /// diamond-check (2.8): as debye; `CPU run failed` / `Metal run failed` → tool_failed.
    static func diamond(exit: Int32?, parsed: FdtdParsedDiamond) -> FdtdVerdict {
        var verdict = FdtdVerdict(passed: false)
        if !parsed.runFailed.isEmpty {
            for side in parsed.runFailed {
                verdict.errors.append(FdtdIssue(.toolFailed, "diamond_check.sh: the \(side) run failed"))
            }
            return verdict
        }
        guard let passed = parsed.passed, let line = parsed.verdictLine else {
            let text = "diamond_check.sh printed no PASS or FAIL line" + statusSuffix(exit)
            verdict.errors.append(FdtdIssue(.toolFailed, text))
            return verdict
        }
        var findings = parsed.comparisons.filter { !$0.identical }.map { "\($0.box): \($0.label) DIFFERENT" }
        findings += parsed.gpuPathMissing.map { $0 + ": the GPU path did not run" }
        if parsed.tuningUnfinished { findings.append("tuned, batch 8: the tuning did not finish") }
        if !passed {
            var text = "diamond_check.sh: " + line
            if !findings.isEmpty { text += " (" + findings.joined(separator: "; ") + ")" }
            verdict.errors.append(FdtdIssue(.scriptCheckFailed, text))
        } else if exit != 0 {
            let ending = exit.map { " exited with status \($0)" } ?? " did not exit normally"
            verdict.errors.append(FdtdIssue(.toolFailed, "diamond_check.sh printed PASS but" + ending))
        } else if !findings.isEmpty {
            let text = "diamond_check.sh printed PASS, but " + findings.joined(separator: "; ")
            verdict.errors.append(FdtdIssue(.verdictDisagrees, text))
        } else if parsed.comparisons.isEmpty {
            verdict.errors.append(FdtdIssue(.verdictDisagrees, "diamond_check.sh printed PASS without any comparison"))
        }
        verdict.passed = verdict.errors.isEmpty
        return verdict
    }

    /// e2e (2.9): ok when the exit is 0, RESULT and OUT/result.json exist, and every call's Create line is the
    /// engine's (the multithreaded text for the default engine); RESULT missing → tool_failed; a Create mismatch →
    /// engine_not_confirmed; the loaded libraries lie in `targetDir` (library_not_loaded, as for run; `libraries` nil
    /// = the launcher left no report, which is its own finding); gpu_fallback as a warning. An interrupted run gives
    /// no error here (finish() adds it).
    /// `gpuFallbackCalls`: the indices of the calls whose segment has the Engine_Metal_Diamond fallback line
    /// (FdtdOpenEMSFacts.gpuFallback, which FdtdCall does not carry).
    static func e2e(exit: Int32?, result: FdtdJSONValue?, resultJsonExists: Bool, calls: [FdtdCall], engine: FdtdEngine?,
                    interrupted: Bool, libraries: [String]?, targetDir: String, system: any FdtdSystem,
                    gpuFallbackCalls: [Int] = []) -> FdtdVerdict {
        var verdict = FdtdVerdict(passed: false)
        if !interrupted {
            if exit != 0 {
                let text = exit.map { "run_one.py exited with status \($0)" } ?? "run_one.py did not exit normally"
                verdict.errors.append(FdtdIssue(.toolFailed, text))
            }
            if result == nil { verdict.errors.append(FdtdIssue(.toolFailed, "run_one.py printed no RESULT line")) }
            if !resultJsonExists { verdict.errors.append(FdtdIssue(.toolFailed, "run_one.py wrote no result.json")) }
            if calls.isEmpty {
                let text = "no FDTD.Run call was recorded, so the engine is not confirmed"
                verdict.errors.append(FdtdIssue(.engineNotConfirmed, text))
            }
            // dyld takes the installed copy of a snapshot file it cannot use, without a message
            if let libraries {
                confirmLibraries(libraries, ran: !calls.isEmpty, targetDir: targetDir, subject: "run_one.py",
                                 system: system, into: &verdict)
            }
        }
        // FDTD.Run gets no engine without --engine, so openEMS runs its default (fastest = the multithreaded texts)
        confirmEngines(calls, engine: engine ?? .multithreaded, field: engine == nil ? nil : "--engine",
                       into: &verdict)
        addFallbacks(gpuFallbackCalls, into: &verdict)
        verdict.passed = verdict.errors.isEmpty
        return verdict
    }

    /// run (2.10): exit 0 → ok; another exit or an exception → script_failed with its text; with `engine` every
    /// observable call shows its Create line (engine_not_confirmed; engine_not_observable for a redirected stdout);
    /// the loaded libraries lie in `targetDir`, by the given or the real path (library_not_loaded); no call →
    /// no_openems_call; options_lost and option_overridden as warnings. `gpuFallbackCalls` as for e2e.
    static func run(exit: Int32?, exception: String?, calls: [FdtdCall], engine: FdtdEngine?, libraries: [String],
                    targetDir: String, system: any FdtdSystem, gpuFallbackCalls: [Int] = []) -> FdtdVerdict {
        var verdict = FdtdVerdict(passed: false)
        if let exception {
            verdict.errors.append(FdtdIssue(.scriptFailed, "the script raised " + exception))
        } else if exit != 0 {
            let text = exit.map { "the script exited with status \($0)" } ?? "the script did not exit normally"
            verdict.errors.append(FdtdIssue(.scriptFailed, text))
        }
        if calls.isEmpty {
            verdict.warnings.append(FdtdIssue(.noOpenemsCall, "the script made no FDTD.Run call"))
        }
        if let engine { confirmEngines(calls, engine: engine, field: "--engine", into: &verdict) }
        confirmLibraries(libraries, ran: !calls.isEmpty, targetDir: targetDir, subject: "the script", system: system,
                         into: &verdict)
        for call in calls {
            if !call.optionsLost.isEmpty {
                let names = call.optionsLost.joined(separator: ", ")
                let text = "call \(call.index): the binding dropped \(names) after an option equal to 0 or False"
                verdict.warnings.append(FdtdIssue(.optionsLost, text))
            }
            for name in call.overridden.keys.sorted() {
                guard let values = call.overridden[name], values.script != values.cli else { continue }
                let text = "call \(call.index): the script's \(name)=\(values.script) was replaced by \(values.cli)"
                verdict.warnings.append(FdtdIssue(.optionOverridden, text, field: optionField(name)))
            }
        }
        addFallbacks(gpuFallbackCalls, into: &verdict)
        verdict.passed = verdict.errors.isEmpty
        return verdict
    }

    // MARK: helpers

    /// A row bench compared with the reference: it has `exact`, or `probes rel` (a later repeat of the reference).
    private static func isCompared(_ row: FdtdBenchRow) -> Bool { row.exact != nil || row.probesRel != nil }

    /// The row's `exact`, or bench's `same` from its parts when the row carries none.
    private static func isExact(_ row: FdtdBenchRow) -> Bool {
        if let exact = row.exact { return exact }
        return row.probesRel == 0 && row.problems.isEmpty && row.sparams.allSatisfy { $0.exact }
    }

    /// `ab` config diffs for a message.
    private static func diffsText(_ config: FdtdABConfigResult) -> String {
        config.diffs.isEmpty ? "no kept run" : config.diffs.joined(separator: ", ")
    }

    /// ` (exit status N)`, or nothing without a status.
    private static func statusSuffix(_ exit: Int32?) -> String {
        exit.map { " (exit status \($0))" } ?? ""
    }

    /// `CASE: QUANTITY failed (error E, tolerance T): NOTE`.
    private static func failedCheckText(_ check: FdtdValidationCheck) -> String {
        var text = "\(check.caseName): \(check.quantity) failed"
        var figures: [String] = []
        if let error = check.error { figures.append("error " + FdtdOptions.formatG(error)) }
        if let tolerance = check.tol { figures.append("tolerance " + FdtdOptions.formatG(tolerance)) }
        if !figures.isEmpty { text += " (" + figures.joined(separator: ", ") + ")" }
        if let note = check.note, !note.isEmpty { text += ": " + note }
        return text
    }

    /// An absolute path with `~` expanded and `.`, `..` and repeated slashes folded.
    private static func folded(_ path: String, home: String) -> String {
        FdtdPaths.absolute(path, cwd: "/", home: home)
    }

    /// Every call's Create line against `engine`; a call stopped by a stop request is left out.
    private static func confirmEngines(_ calls: [FdtdCall], engine: FdtdEngine, field: String?,
                                       into verdict: inout FdtdVerdict) {
        for call in calls where !call.stopRequested {
            if let text = call.createLine {
                if let create = FdtdParsers.createLine(text), engine.accepts(create) { continue }
                let message = "call \(call.index) printed \(text), not a Create line of the \(engine.rawValue) engine"
                verdict.errors.append(FdtdIssue(.engineNotConfirmed, message, field: field))
            } else if !call.engineObservable || call.stdoutRedirected {
                let message = "call \(call.index): the script redirected stdout around FDTD.Run, so its engine cannot be read"
                verdict.warnings.append(FdtdIssue(.engineNotObservable, message))
            } else {
                let message = "call \(call.index) printed no Create FDTD engine line"
                verdict.errors.append(FdtdIssue(.engineNotConfirmed, message, field: field))
            }
        }
    }

    /// library_not_loaded when a library the launcher recorded lies outside `targetDir` (FdtdDiscovery.lies), or when
    /// FDTD.Run ran (`ran`) and none was recorded.
    private static func confirmLibraries(_ libraries: [String], ran: Bool, targetDir: String, subject: String,
                                         system: any FdtdSystem, into verdict: inout FdtdVerdict) {
        let expected = folded(targetDir, home: "/")
        if !libraries.isEmpty {
            let foreign = libraries.filter { !FdtdDiscovery.lies(folded($0, home: "/"), in: expected, system: system) }
            if !foreign.isEmpty {
                let names = foreign.joined(separator: ", ")
                let text = "\(subject) loaded \(names), not from \(expected)"
                verdict.errors.append(FdtdIssue(.libraryNotLoaded, text, field: "--lib"))
            }
        } else if ran {
            let text = "\(subject) ran FDTD.Run, but no loaded openEMS library was recorded"
            verdict.errors.append(FdtdIssue(.libraryNotLoaded, text, field: "--lib"))
        }
    }

    private static func addFallbacks(_ indices: [Int], into verdict: inout FdtdVerdict) {
        for index in indices { verdict.warnings.append(gpuFallback("call \(index)")) }
    }

    /// check.sh's FAIL: check_failed only when every model it names printed a MISMATCH block and every model ran. An
    /// argument error makes bench.py exit 2 before it prints its header (F4), and check.sh counts that as FAIL too.
    private static func failed(_ finalLine: FdtdCheckFinal, models: [FdtdCheckModel], expectedModels: Int,
                               into verdict: inout FdtdVerdict) {
        let labels = finalLine.detail.split(separator: " ").map(String.init)
        let mismatched = Set(models.filter { $0.summary?.kind == "MISMATCH" }.map(\.label))
        let unexplained = labels.filter { !mismatched.contains($0) }
        if !labels.isEmpty && unexplained.isEmpty && models.count == expectedModels {
            verdict.errors.append(FdtdIssue(.checkFailed, finalLine.line))
            return
        }
        var reasons: [String] = []
        if labels.isEmpty { reasons.append("it names no model") }
        if !unexplained.isEmpty {
            reasons.append("bench.py printed no MISMATCH block for " + unexplained.joined(separator: ", "))
        }
        reasons.append("\(models.count) of \(expectedModels) models printed a block")
        let text = "check.sh printed FAIL (\(finalLine.detail)), but " + reasons.joined(separator: "; ")
        verdict.errors.append(FdtdIssue(.toolOutputUnparsed, text))
    }

    /// The CLI option behind an injected FDTD.Run option, in any of the script's spellings.
    private static func optionField(_ name: String) -> String? {
        let key = name.lowercased().filter { $0 != "_" && $0 != "-" }
        switch key {
        case "engine":
            return "--engine"
        case "numthreads":
            return "--threads"
        case "disabledumps":
            return "--nodumps"
        default:
            return nil
        }
    }
}
