// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 KnobTests: the registry against BUILD.md section 7, the value rules, the warnings, and --knob merged
// into the CFGs.
import Foundation
import Testing
@testable import fdtdKit

@Suite struct KnobTests {
    /// Every backticked OPENEMS_ name in the first cell of the table rows between `## 7.` and `## 8.`, in order.
    static func buildMdNames() throws -> [String] {
        let text = try TestPaths.text(TestPaths.repo + "/BUILD.md")
        let start = try #require(text.range(of: "\n## 7."))
        let end = try #require(text.range(of: "\n## 8.", range: start.upperBound..<text.endIndex))
        var names: [String] = []
        for line in text[start.upperBound..<end.lowerBound].split(separator: "\n") where line.hasPrefix("| `OPENEMS_") {
            let cell = line.dropFirst().prefix { $0 != "|" }
            for match in String(cell).matches(of: #/`(OPENEMS_[A-Z0-9_]+)/#) {
                let name = String(match.output.1)
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    /// The first issue validate() raises, or nil.
    static func issue(_ text: String, _ command: FdtdCommandName = .bench,
                      _ transport: FdtdKnobTransport = .cfgList) -> FdtdIssue? {
        let system = FakeWorld().system
        system.addDirectory("/work/export")
        do {
            let setting = try FdtdKnobs.parse(text, field: "--knob")
            try FdtdKnobs.validate(setting, command: command, transport: transport, system: system)
            return nil
        } catch let error as FdtdError {
            return error.issues.first
        } catch {
            return FdtdIssue(.toolFailed, "\(error)")
        }
    }

    @Test func registryEqualsBuildMdSection7() throws {
        let names = try Self.buildMdNames()
        #expect(names.count == 38)
        #expect(FdtdKnobs.registry.map { $0.name } == names)
        #expect(Set(FdtdKnobs.registry.map { $0.name }).count == FdtdKnobs.registry.count)
    }

    @Test(arguments: ["OPENEMS_FTZ=1", "OPENEMS_FUSED=0", "OPENEMS_QOS=2", "OPENEMS_COEF=geom",
                      "OPENEMS_DIAMOND_TILE=12:8", "OPENEMS_DIAMOND_TILE=7:0", "OPENEMS_FUSED_BLOCK=4",
                      "OPENEMS_FLAGS_SPIN_US=0", "OPENEMS_DIAMOND_K=3"])
    func acceptedEverywhere(text: String) {
        for command in [FdtdCommandName.bench, .ab, .validate, .e2e, .run] {
            let transport: FdtdKnobTransport = command == .bench || command == .ab ? .cfgList : .environment
            #expect(Self.issue(text, command, transport) == nil, "\(text) on \(command)")
        }
    }

    @Test func switchesTakeOnlyOne() throws {
        let zero = try #require(Self.issue("OPENEMS_FTZ=0"))
        #expect(zero.code == .knobValue)
        #expect(zero.hint == "leave the knob out for off")
        #expect(Self.issue("OPENEMS_FTZ=2")?.code == .knobValue)
        let empty = try #require(Self.issue("OPENEMS_FTZ="))
        #expect(empty.code == .knobValue)
        #expect(empty.hint == "leave the knob out for off")
        #expect(Self.issue("OPENEMS_NO_STAGGER=yes", .run, .environment)?.code == .knobValue)
    }

    @Test func wordsNumbersAndTiles() {
        #expect(Self.issue("OPENEMS_COEF=fast")?.code == .knobValue)
        #expect(Self.issue("OPENEMS_FUSED_BLOCK=0")?.code == .knobValue)
        #expect(Self.issue("OPENEMS_FUSED_BLOCK=+2")?.code == .knobValue)
        #expect(Self.issue("OPENEMS_QOS=3")?.code == .knobValue)
        for command in [FdtdCommandName.validate, .e2e, .run] {
            #expect(Self.issue("OPENEMS_DIAMOND_TILE=7,0", command, .environment) == nil, "\(command)")
        }
        let inCfg = Self.issue("OPENEMS_DIAMOND_TILE=7,0", .bench, .cfgList)
        #expect(inCfg?.code == .knobValue)
        #expect(inCfg?.hint == "OPENEMS_DIAMOND_TILE=7:0")
        #expect(Self.issue("OPENEMS_DIAMOND_TILE=0:4")?.code == .knobValue)
    }

    @Test func runOnlyKnobsAndUnknownNames() {
        let export = Self.issue("OPENEMS_EXPORT_FIELDS=/work/export", .bench)
        #expect(export?.code == .knobNotAllowed)
        #expect(Self.issue("OPENEMS_EXPORT_FIELDS=/work/export", .run, .environment) == nil)
        #expect(Self.issue("OPENEMS_EXPORT_FIELDS=/work/none", .run, .environment)?.code == .knobValue)
        #expect(Self.issue("OPENEMS_PROBE_END_DB=-60", .e2e, .environment)?.code == .knobNotAllowed)
        #expect(Self.issue("OPENEMS_PROBE_END_DB=-60", .run, .environment) == nil)
        #expect(Self.issue("OPENEMS_PROBE_END_DB=5", .run, .environment)?.code == .knobValue)
        let unknown = Self.issue("OPENEMS_FUSD=0")
        #expect(unknown?.code == .knobUnknown)
        #expect(unknown?.hint?.contains("OPENEMS_FUSED") == true)
    }

    @Test func warnings() {
        let k = FdtdKnobSetting(name: "OPENEMS_DIAMOND_K", value: "2")
        #expect(FdtdKnobs.warnings([k], engine: .multithreaded).map(\.code) == [.knobNoEffect])
        #expect(FdtdKnobs.warnings([k], engine: .metalDiamond).isEmpty)
        // a script may pick its own engine: no knob_no_effect without a known one
        #expect(FdtdKnobs.warnings([k], engine: nil).isEmpty)
        let tile = FdtdKnobSetting(name: "OPENEMS_DIAMOND_TILE", value: "6:6")
        #expect(FdtdKnobs.warnings([tile], engine: .metalDiamond).map(\.code) == [.knobIgnored])
        // at K=3 the engine needs M >= 5, so 6:6 is used
        let k3 = FdtdKnobSetting(name: "OPENEMS_DIAMOND_K", value: "3")
        #expect(FdtdKnobs.warnings([k3, tile], engine: .metalDiamond).isEmpty)
        let ftz = FdtdKnobSetting(name: "OPENEMS_FTZ", value: "1")
        #expect(FdtdKnobs.warnings([ftz], engine: .multithreaded).map(\.code) == [.notBitIdenticalToStock])
    }

    @Test func knobOptionMergesIntoEveryConfig() throws {
        let world = FakeWorld()
        let configs = try ["cg29@multithreaded:4", "cg29@multithreaded:8#OPENEMS_QOS=1"].map {
            try FdtdBenchConfigs.parse($0, command: .bench, cwd: FakeWorld.repo, home: FakeWorld.home,
                                       system: world.system)
        }
        let fused = FdtdKnobSetting(name: "OPENEMS_FUSED", value: "0")
        let merged = try FdtdKnobs.merge([fused, fused], into: configs)
        #expect(merged.map { $0.text } == ["cg29@multithreaded:4#OPENEMS_FUSED=0",
                                           "cg29@multithreaded:8#OPENEMS_QOS=1,OPENEMS_FUSED=0"])
        #expect(merged.allSatisfy { $0.knobs.contains(fused) })
        // the same value inside a CFG is no conflict
        #expect(try FdtdKnobs.merge([FdtdKnobSetting(name: "OPENEMS_QOS", value: "1")], into: configs)[1].knobs.count == 1)
        #expect(throws: FdtdError.self) {
            _ = try FdtdKnobs.merge([FdtdKnobSetting(name: "OPENEMS_QOS", value: "2")], into: configs)
        }
        #expect(throws: FdtdError.self) {
            _ = try FdtdKnobs.merge([fused, FdtdKnobSetting(name: "OPENEMS_FUSED", value: "1")], into: configs)
        }
    }

    @Test func knobConflictThroughTheCLIExits64() {
        let run = FakeWorld().run(["bench", "patch", "--config", "cg29@multithreaded:4#OPENEMS_COEF=packed",
                                   "--config", "cg29@multithreaded:8", "--knob", "OPENEMS_COEF=geom", "--dry-run"])
        #expect(run.exit == 64)
        #expect(run.errorCodes == ["usage"])
        let merged = FakeWorld().run(["bench", "patch", "--config", "cg29@multithreaded:4", "--config",
                                      "cg29@multithreaded:8", "--knob", "OPENEMS_COEF=geom", "--dry-run"])
        #expect(merged.exit == 0)
        let configs = merged.envelope["jobs"]?.array?.first?["configs"]?.array?.compactMap { $0["cfg"]?.string } ?? []
        #expect(configs == ["cg29@multithreaded:4#OPENEMS_COEF=geom", "cg29@multithreaded:8#OPENEMS_COEF=geom"])
    }
}
