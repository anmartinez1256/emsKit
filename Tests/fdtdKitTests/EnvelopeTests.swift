// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 EnvelopeTests (sections 7-9, S4): the encoding, the schema names, the status/exit table and precedence,
// the stderr format, figures withheld without a valid load, and ab statistics over valid runs only.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct EnvelopeTests {
    struct Sample: Encodable {
        var zeta = 1
        var alpha = Double.infinity
        var minus = -Double.infinity
        var nan = Double.nan
        var path = "/a/b"
    }

    @Test func encoding() throws {
        let text = String(decoding: try FdtdJSON.encode(Sample()), as: UTF8.self)
        #expect(text.contains(#""alpha" : "inf""#))
        #expect(text.contains(#""minus" : "-inf""#))
        #expect(text.contains(#""nan" : "nan""#))
        let keys = text.split(separator: "\n").compactMap { line -> String? in
            guard let open = line.firstIndex(of: "\""), let close = line[line.index(after: open)...].firstIndex(of: "\"")
            else { return nil }
            return String(line[line.index(after: open)..<close])
        }
        #expect(keys == ["alpha", "minus", "nan", "path", "zeta"])
        // the decoder reads the strings back as JSON values and accepts JSON5's NaN
        let value = try FdtdJSON.decode(FdtdJSONValue.self, from: Data(#"{"x": NaN, "y": Infinity}"#.utf8))
        #expect(value["x"]?.double?.isNaN == true)
        #expect(value["y"]?.double == .infinity)
    }

    @Test func everyCommandHasItsSchema() {
        for command in FdtdCommandName.allCases {
            let run = FakeWorld().run([command.rawValue, "--frob"])
            #expect(run.exit == 64, "\(command)")
            #expect(run.envelope["schema"]?.string == "emskit.fdtd.\(command.rawValue)/1", "\(command)")
            #expect(run.envelope["tool"]?.string == "emskit" && run.envelope["kit"]?.string == "fdtd")
            #expect(run.envelope["version"]?.string == "0.1.0")
            #expect(run.envelope["command"]?.string == command.rawValue)
            #expect(run.envelope["arguments"]?.array?.compactMap { $0.string } == [command.rawValue, "--frob"])
        }
    }

    /// Spec 9: the exit of every error code.
    static let exits: [Int32: [FdtdCode]] = [
        64: [.usage],
        2: [.repoNotFound, .toolMissing, .libraryNotFound, .libraryIncomplete, .configInvalid, .knobUnknown, .knobValue,
            .knobNotAllowed, .rfsimNotFound, .scriptNotFound, .folderMissing, .hostsFileMissing, .tagInvalid,
            .protectedPath],
        3: [.engineUnsupported, .knobUnsupported, .libraryLacksFeature, .pythonNotFound, .pythonStripsDyld,
            .pythonNoOpenems, .pythonNameMismatch],
        4: [.toolFailed, .toolOutputUnparsed, .engineNotConfirmed, .libraryNotLoaded, .verdictDisagrees, .spawnFailed,
            .launcherFailed, .loadUnavailable],
        1: [.mismatch, .notExact, .checkFailed, .validationFailed, .scriptCheckFailed, .scriptFailed],
        5: [.simulationRunning, .concurrencyUnknown, .wouldOverwrite],
        130: [.interrupted],
    ]

    @Test func exitTableAndPrecedence() {
        var listed = Set<FdtdCode>()
        for (exit, codes) in Self.exits {
            for code in codes {
                #expect(code.exitCode == exit, "\(code)")
                listed.insert(code)
            }
        }
        // every other code is a warning only
        for code in FdtdCode.allCases where !listed.contains(code) { #expect(code.exitCode == nil, "\(code)") }
        #expect(FdtdExit.combine([.mismatch, .usage, .knobValue], interrupted: false) == 64)
        #expect(FdtdExit.combine([.engineUnsupported, .libraryNotFound], interrupted: false) == 2)
        #expect(FdtdExit.combine([.simulationRunning, .engineUnsupported], interrupted: false) == 3)
        #expect(FdtdExit.combine([.toolFailed, .wouldOverwrite], interrupted: false) == 5)
        #expect(FdtdExit.combine([.mismatch, .toolFailed], interrupted: false) == 4)
        #expect(FdtdExit.combine([.mismatch], interrupted: false) == 1)
        #expect(FdtdExit.combine([], interrupted: false) == 0)
        // a signal replaces 4 and 1 (and 0), never 64, 2, 3 or 5
        #expect(FdtdExit.combine([.toolFailed, .mismatch], interrupted: true) == 130)
        #expect(FdtdExit.combine([], interrupted: true) == 130)
        #expect(FdtdExit.combine([.wouldOverwrite], interrupted: true) == 5)
        #expect(FdtdExit.combine([.libraryNotFound], interrupted: true) == 2)
        let statuses: [(Int32, Bool, FdtdStatus)] = [(0, false, .ok), (0, true, .partial), (1, false, .fail),
                                                      (2, false, .error), (3, false, .error), (4, false, .error),
                                                      (5, false, .refused), (64, false, .error),
                                                      (130, false, .interrupted)]
        for (exit, partial, status) in statuses { #expect(FdtdExit.status(for: exit, partial: partial) == status) }
    }

    @Test func stderrIssueFormat() {
        let issue = FdtdIssue(.knobValue, "OPENEMS_FTZ=0 is not a value", field: "--knob",
                              hint: "leave the knob out for off")
        #expect(issue.stderrLine == "emskit fdtd: knob_value: OPENEMS_FTZ=0 is not a value (hint: leave the knob out for off)")
        #expect(FdtdIssue(.partial, "four of six").stderrLine == "emskit fdtd: partial: four of six")
        let run = FakeWorld().run(["bench", "patch", "--config", "nosuch@multithreaded:4", "--config",
                                   "cg29@multithreaded:4", "--dry-run"])
        #expect(run.exit == 2)
        #expect(run.stderr.split(separator: "\n").contains { $0.hasPrefix("emskit fdtd: library_not_found: ") })
    }

    /// A bench run on the fake Mac whose second row has no gpu dev figure (so no valid load).
    @Test func benchRowWithoutValidLoadIsWithheld() throws {
        let world = FakeWorld()
        let variants = try TestPaths.lines(TestPaths.fixture("bench_variants.txt"))
        let lines = ["# patch_s1_n2000  load avg 3.42", variants[1], variants[2],
                     "IDENTICAL: every run of 1 config equals the reference"]
        let log = "Create FDTD engine (compressed SSE + multi-threading)\n"
        var tool = FakeToolRun(lines: lines, files: [
            "runs/patch_s1_n2000/stock_multithreaded_t4/rep0/openEMS.log": log,
            "runs/patch_s1_n2000/cg29_multithreaded_t4/rep0/openEMS.log": log,
        ])
        tool.report = FakeToolRun.report(mode: "exec", argv: ["/opt/py/bin/python3"], exit: 0)
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["bench", "patch", "--nrts", "2000", "--config", "stock@multithreaded:4", "--config",
                             "cg29@multithreaded:4"])
        #expect(run.exit == 0, "\(run.stderr)")
        let rows = try #require(run.result["rows"]?.array)
        #expect(rows.count == 2)
        #expect(rows[0]["mcs"]?.double == 320.4)
        #expect(rows[0]["seconds"]?.double == 13.39)
        #expect(rows[0]["load"]?["valid"]?.bool == true)
        #expect(rows[1]["mcs"] == .null)
        #expect(rows[1]["seconds"] == .null)
        #expect(rows[1]["speedWithheld"]?.bool == true)
        #expect(rows[1]["load"]?["valid"]?.bool == false)
        #expect(rows[1]["engineConfirmed"]?.bool == true)
        #expect(run.warningCodes.contains("load_missing"))
        #expect(run.stderr.contains("320.4"))
        #expect(!run.stderr.contains("1877"))
        #expect(!run.stderr.contains("2.29"))
    }

    /// A script run whose first FDTD.Run call has no load: its MC/s and seconds are null and never printed.
    @Test func callWithoutValidLoadIsWithheld() throws {
        let world = FakeWorld()
        world.system.addFile("/work/board.py", "import openEMS\n")
        let segments = try TestPaths.lines(TestPaths.fixture("tool_log.txt"))
        let first = try #require(segments.firstIndex(of: "FDTDKIT_CALL_BEGIN 1"))
        let last = try #require(segments.firstIndex(of: "FDTDKIT_CALL_END 2"))
        let lines = Array(segments[first...last]).map {
            $0.replacingOccurrences(of: "CALL_BEGIN 1", with: "CALL_BEGIN 0")
                .replacingOccurrences(of: "CALL_END 1", with: "CALL_END 0")
                .replacingOccurrences(of: "CALL_BEGIN 2", with: "CALL_BEGIN 1")
                .replacingOccurrences(of: "CALL_END 2", with: "CALL_END 1")
        }
        let valid = FakeSystem.load(cpuOther: 40, gpuOther: 2, cpuSelf: 390, wall: 2.5)
        var tool = FakeToolRun(lines: lines)
        tool.report = FakeToolRun.report(mode: "script", argv: ["/work/board.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: .null),
                                                 FakeToolRun.call(index: 1, load: valid)],
                                         load: valid,
                                         libraries: FdtdLibraries.fileNames.map { FakeWorld.snaps + "/cg29/" + $0 })
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["run", "/work/board.py", "--lib", "cg29", "--threads", "4"])
        let calls = try #require(run.result["calls"]?.array, "\(run.stderr)")
        #expect(calls.count == 2)
        #expect(calls[0]["mcs"] == .null)
        #expect(calls[0]["seconds"] == .null)
        #expect(calls[0]["timesteps"]?.double == 15000)
        #expect(calls[1]["mcs"]?.double.map { abs($0 - 615.6) < 0.1 } == true)
        #expect(run.warningCodes.contains("load_missing"))
        #expect(!run.stderr.contains("1805"))
        #expect(run.stderr.contains("615.6"))
    }

    /// e2e's build and post stages take milliseconds: the summary gives them in ms instead of `0.0 s`, and the
    /// envelope keeps RESULT's numbers as they are.
    @Test func shortRunTimesPrintInMilliseconds() throws {
        #expect(FdtdFigures.seconds(4.1) == "4.1 s")
        #expect(FdtdFigures.seconds(0.1) == "0.1 s")
        #expect(FdtdFigures.seconds(0.0175) == "17.5 ms")
        let world = FakeWorld()
        let result = #"RESULT {"model": "gcpw", "floor": 0.0, "db": "-60", "hold": 0.5, "cells": 241995, "#
            + #""t_build": 0.0045123, "t_run": 4.5, "t_post": 0.0175, "t_total": 4.5220123}"#
        let lines = ["FDTDKIT_CALL_BEGIN 0", "Create FDTD engine (compressed SSE + multi-threading)",
                     "Time for 34300 iterations with 241995.00 cells : 4.40 sec", "FDTDKIT_CALL_END 0", result]
        let valid = FakeSystem.load(cpuOther: 40, gpuOther: 2, cpuSelf: 390, wall: 4.6)
        var tool = FakeToolRun(lines: lines, absoluteFiles: [FakeWorld.runFolder("e2e") + "/e2e/result.json": "{}"])
        tool.report = FakeToolRun.report(mode: "script", argv: ["run_one.py"], exit: 0,
                                         calls: [FakeToolRun.call(index: 0, load: valid)], load: valid,
                                         libraries: FdtdLibraries.fileNames.map { FakeWorld.snaps + "/cg29/" + $0 })
        world.system.update { $0.spawn = tool.handler(world.system) }
        let run = world.run(["e2e", "gcpw", "--lib", "cg29", "--rfsim", FakeWorld.rfsim])
        #expect(run.exit == 0, "\(run.stderr)")
        let summary = "e2e gcpw: ok: build 4.5 ms, run 4.5 s, post 17.5 ms (others cpu 40% gpu 2% over the whole run)"
        #expect(run.stderr.contains(summary), "\(run.stderr)")
        #expect(run.result["result"]?["t_build"]?.double == 0.0045123)
        #expect(run.result["result"]?["t_post"]?.double == 0.0175)
    }

    @Test func abStatisticsUseValidRunsOnly() throws {
        func run(_ round: Int, _ config: Int, _ mcs: Double?, valid: Bool, kept: Bool? = true,
                 diff: String = "identical") -> FdtdABRunResult {
            FdtdABRunResult(round: round, config: config, mcs: mcs, othersCpu: valid ? 50 : nil,
                            othersGpu: valid ? 2 : nil, loadValid: valid, diff: diff, kept: kept)
        }
        let runs = [run(0, 0, 100, valid: true, diff: "reference"), run(0, 1, 200, valid: true),
                    run(1, 0, 110, valid: true), run(1, 1, nil, valid: false),
                    run(2, 0, 100, valid: true), run(2, 1, 400, valid: true, kept: false),
                    run(3, 0, 100, valid: true), run(3, 1, 300, valid: true)]
        let stats = FdtdLoads.abStatistics(runs: runs, configs: ["a@multithreaded:4", "b@multithreaded:4"],
                                           labels: ["a@multithreaded:4", "b@multithreaded:4"], tolerant: [false, false])
        #expect(stats.count == 2)
        let b = stats[1]
        #expect(b.runsWithLoad == 2)
        #expect(b.runsWithoutLoad == 1)
        #expect(b.medianMcs == 250)
        #expect(b.minMcs == 200 && b.maxMcs == 300)
        #expect(b.medianRatio == 2.5)
        #expect(b.minRatio == 2 && b.maxRatio == 3)
        #expect(b.identical)
        #expect(stats[0].medianMcs == 100)
        #expect(stats[0].identical)
        #expect(FdtdLoads.median([3, 1, 2]) == 2)
        #expect(FdtdLoads.median([]) == nil)
        #expect(FdtdLoads.median([.nan, 4]) == 4)
    }
}
