// SPDX-License-Identifier: GPL-3.0-or-later

// The knob registry (spec 4.3): the 38 OPENEMS_* names of BUILD.md section 7, their values, which ones the fork reads
// once per process, the commands that take them, and the library file their name is searched in. For bench and ab a
// knob travels only inside the CFGs; for validate, e2e and run it goes into the Python process's environment.
// check, debye-check and diamond-check take none.
import Foundation

/// How a knob's value is checked.
enum FdtdKnobRule: Sendable, Equatable {
    /// One of these words (FUSED 0/1, QOS 0/1/2, COEF packed/geom, ...); 0 stays a value for the number knobs.
    case oneOf([String])
    /// The eight `=1` switches: only "1". For off, leave the knob out (up to patch 0005 any value switched them on).
    case onlyOne
    /// An integer >= `min`, digits only.
    case integer(min: Int)
    /// A finite number within the bounds (PROBE_END_DB <= 0, PROBE_END_HOLD >= 0).
    case number(min: Double?, max: Double?)
    /// An existing folder (EXPORT_OPERATOR, EXPORT_FIELDS).
    case existingFolder
    /// `M:V` with M >= 1 and V >= 0; `M,V` too, but only in the environment (bench splits `#` lists on commas).
    case tile
}

/// Where a knob value travels.
enum FdtdKnobTransport: Sendable, Equatable {
    /// Inside a bench or ab CFG's `#` list: a value must not contain ',' or ';'.
    case cfgList
    /// In the Python process's environment (validate, e2e, run).
    case environment
}

/// One registry entry.
struct FdtdKnob: Sendable, Equatable {
    var name: String
    var rule: FdtdKnobRule
    /// The fork reads it once per process (a second run in the same process keeps the first value).
    var readOncePerProcess: Bool
    /// The commands that take it.
    var commands: Set<FdtdCommandName>
    /// The library file whose bytes must contain the name: libnf2ff for NF2FF_LEGACY, libopenEMS for the rest.
    var libraryFile = "libopenEMS.0.dylib"
    /// The values as info lists them, e.g. "0, 1" or "integer >= 1".
    var valuesText: String
}

/// A `NAME=VALUE` from a CFG's `#` list or a `--knob`.
struct FdtdKnobSetting: Sendable, Equatable, Hashable {
    var name: String
    var value: String

    var text: String { "\(name)=\(value)" }
}

/// info's knobs[] entry.
struct FdtdKnobInfo: Codable, Sendable, Equatable {
    var name: String
    var values: String
    var readOncePerProcess: Bool
    var commands: [String]
}

/// The registry and the knob rules.
enum FdtdKnobs {
    /// The 38 knobs of BUILD.md section 7, in its order (the knob tests compare the names with that table).
    static let registry: [FdtdKnob] = [
        entry("OPENEMS_FUSED", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_FUSED_BLOCK", .integer(min: 1), "integer >= 1"),
        entry("OPENEMS_FLAGS", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_FLAGS_SPIN_US", .integer(min: 0), "integer >= 0"),
        entry("OPENEMS_FUSED_STAT", .onlyOne, "1", once: true),
        entry("OPENEMS_BALANCE", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_NO_STAGGER", .onlyOne, "1", once: true),
        entry("OPENEMS_OP_INDEX_PER_CELL", .onlyOne, "1"),
        entry("OPENEMS_NO_PACKED_COEFF", .onlyOne, "1"),
        entry("OPENEMS_COEF", .oneOf(["packed", "geom"]), "packed, geom"),
        entry("OPENEMS_BARRIER_SPIN_US", .integer(min: 0), "integer >= 0", once: true),
        entry("OPENEMS_TUNE_WINDOW_MS", .integer(min: 1), "integer >= 1"),
        entry("OPENEMS_NO_PML_TABLE", .onlyOne, "1"),
        entry("OPENEMS_PML_YVEC", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_ADE_MERGED", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_QOS", .oneOf(["0", "1", "2"]), "0, 1, 2"),
        entry("OPENEMS_FTZ", .onlyOne, "1", once: true),
        entry("OPENEMS_NF2FF_LEGACY", .onlyOne, "1", once: true, file: FdtdLibraries.nf2ffFile),
        entry("OPENEMS_SETUP_TIMING", .onlyOne, "1", once: true),
        entry("OPENEMS_EXPORT_OPERATOR", .existingFolder, "an existing folder", runOnly: true),
        entry("OPENEMS_EXPORT_FIELDS", .existingFolder, "an existing folder", runOnly: true),
        entry("OPENEMS_PROBE_END_DB", .number(min: nil, max: 0), "a number <= 0 (0 = off)", runOnly: true),
        entry("OPENEMS_PROBE_END_HOLD", .number(min: 0, max: nil), "a number >= 0", runOnly: true),
        entry("OPENEMS_DIAMOND_K", .integer(min: 1), "integer >= 1"),
        entry("OPENEMS_DIAMOND_TILE", .tile, "M:V (M >= 1, V >= 0); M,V only in the environment"),
        entry("OPENEMS_DIAMOND_TUNE", .integer(min: 0), "integer >= 0"),
        entry("OPENEMS_DIAMOND_TG", .integer(min: 0), "integer >= 0"),
        entry("OPENEMS_DIAMOND_BATCH", .integer(min: 1), "integer >= 1"),
        entry("OPENEMS_DIAMOND_TIMING", .oneOf(["0", "1", "2"]), "0, 1, 2"),
        entry("OPENEMS_DIAMOND_COEF", .oneOf(["packed", "split"]), "packed, split"),
        entry("OPENEMS_DIAMOND_MERGE", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_DIAMOND_MURMERGE", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_DIAMOND_EVEN", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_DIAMOND_FASTIDX", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_DIAMOND_TGFLAG", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_DIAMOND_PML4", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_DIAMOND_PML3", .oneOf(["0", "1"]), "0, 1"),
        entry("OPENEMS_DIAMOND_CAND", .integer(min: 0), "integer >= 0"),
    ]

    /// The commands of every knob but EXPORT_* and PROBE_END_*, which only `run` takes (e2e's core.run owns the
    /// probe end).
    private static let tuningCommands: Set<FdtdCommandName> = [.bench, .ab, .validate, .e2e, .run]
    private static let digitBytes = Set("0123456789".utf8)

    private static func entry(_ name: String, _ rule: FdtdKnobRule, _ values: String, once: Bool = false,
                              runOnly: Bool = false, file: String = FdtdLibraries.openEMSFile) -> FdtdKnob {
        let commands: Set<FdtdCommandName> = runOnly ? [.run] : tuningCommands
        return FdtdKnob(name: name, rule: rule, readOncePerProcess: once, commands: commands, libraryFile: file,
                        valuesText: values)
    }

    static func knob(named name: String) -> FdtdKnob? { registry.first { $0.name == name } }

    /// Splits `NAME=VALUE` at the first '='; 64 usage without one (`field` names the option or the CFG).
    static func parse(_ text: String, field: String) throws -> FdtdKnobSetting {
        guard let eq = text.firstIndex(of: "="), eq > text.startIndex else {
            let shown = text.isEmpty ? "an empty knob" : text
            let hint = field == "--knob" ? "--knob OPENEMS_FUSED=0" : "#OPENEMS_FUSED=0"
            throw FdtdOptions.usage("\(field) \(shown) is not NAME=VALUE", field: field, hint: hint)
        }
        return FdtdKnobSetting(name: String(text[..<eq]), value: String(text[text.index(after: eq)...]))
    }

    /// The rules in order: an unknown name → 2 knob_unknown with the nearest name as hint; a name not allowed on
    /// `command` → 2 knob_not_allowed; a bad or empty value → 2 knob_value (the `=1` switches with the hint "leave the
    /// knob out for off"); an EXPORT_* folder that does not exist → 2 knob_value; ',' or ';' in a CFG value → 2
    /// knob_value.
    static func validate(_ setting: FdtdKnobSetting, command: FdtdCommandName, transport: FdtdKnobTransport,
                         system: any FdtdSystem) throws {
        // A CFG list can come from --config, --extra or --knob, so only the environment's origin is certain.
        let field: String? = transport == .environment ? "--knob" : nil
        guard let known = FdtdKnobs.knob(named: setting.name) else {
            throw FdtdError(.knobUnknown, "unknown knob \(setting.name)", field: field,
                            hint: suggestion(for: setting.name))
        }
        // check's --extra CFGs are validated as bench CFGs (spec 2.6): the knobs bench takes, inside the CFG.
        let effective: FdtdCommandName = command == .check && transport == .cfgList ? .bench : command
        guard known.commands.contains(effective) else {
            let takers = FdtdCommandName.allCases.filter { known.commands.contains($0) }.map(\.rawValue)
            let list = takers.joined(separator: ", ")
            let message = "\(known.name) is not taken by \(command.rawValue) (only by \(list))"
            throw FdtdError(.knobNotAllowed, message, field: field, hint: notAllowedHint(known, setting, command))
        }
        let value = setting.value
        guard !value.isEmpty else {
            let hint: String? = known.rule == .onlyOne ? "leave the knob out for off" : nil
            throw FdtdError(.knobValue, "\(known.name) has an empty value (values: \(known.valuesText))", field: field,
                            hint: hint)
        }
        if transport == .cfgList, value.contains(",") || value.contains(";") {
            // bench splits a `#` list on commas, and abtest turns ';' into ','.
            var hint: String? = nil
            if known.rule == .tile { hint = known.name + "=" + value.replacingOccurrences(of: ",", with: ":") }
            throw FdtdError(.knobValue, "\(setting.text): a value inside a config cannot hold ',' or ';'",
                            field: field, hint: hint)
        }
        try checkRule(known, value, transport: transport, field: field, system: system)
    }

    /// 3 knob_unsupported for a setting whose name the library's bytes do not contain (the knob would do nothing).
    static func requireSupported(_ settings: [FdtdKnobSetting], library: FdtdLibrary) throws {
        var seen = Set<String>()
        var issues: [FdtdIssue] = []
        for setting in settings {
            guard seen.insert(setting.name).inserted, !library.knobs.contains(setting.name) else { continue }
            let file = FdtdKnobs.knob(named: setting.name)?.libraryFile ?? FdtdLibraries.openEMSFile
            let message = "\(setting.name) does not occur in the \(file) of \(library.spec): the knob would do nothing"
            issues.append(FdtdIssue(.knobUnsupported, message, hint: "emskit fdtd info --lib \(library.spec)"))
        }
        if !issues.isEmpty { throw FdtdError(issues) }
    }

    /// knob_no_effect (DIAMOND_* with an engine other than metal-diamond), knob_ignored (TILE with M < 2K-1, K =
    /// DIAMOND_K or 4) and not_bit_identical_to_stock (FTZ), as warnings.
    static func warnings(_ settings: [FdtdKnobSetting], engine: FdtdEngine?) -> [FdtdIssue] {
        // engine nil = not known to the CLI (a script may pick its own), so knob_no_effect needs a known engine.
        var issues: [FdtdIssue] = []
        func add(_ issue: FdtdIssue) {
            if !issues.contains(issue) { issues.append(issue) }
        }
        let k = settings.last(where: { $0.name == "OPENEMS_DIAMOND_K" }).flatMap { plainInteger($0.value) } ?? 4
        let minimumM = k >= Int.max / 2 ? Int.max : 2 * k - 1
        for setting in settings {
            if setting.name.hasPrefix("OPENEMS_DIAMOND_"), let engine, engine != .metalDiamond {
                let message = "\(setting.name) has no effect with the engine \(engine.rawValue): "
                    + "only metal-diamond reads it"
                add(FdtdIssue(.knobNoEffect, message))
            }
            // The engine checks only M >= 2K-1 and ignores the tile with a message otherwise (F22).
            if setting.name == "OPENEMS_DIAMOND_TILE", let m = tileParts(setting.value, allowComma: true)?.m,
               m < minimumM {
                add(FdtdIssue(.knobIgnored,
                              "\(setting.text) is ignored at K=\(k): the engine needs M >= \(minimumM) (2K-1)"))
            }
            if setting.name == "OPENEMS_FTZ" {
                add(FdtdIssue(.notBitIdenticalToStock,
                              "\(setting.text) flushes subnormals to zero: the results are not bit-identical to stock"))
            }
        }
        return issues
    }

    /// Appends the --knob settings to every CFG's `#` list (so the labels show them); 64 usage when a CFG already
    /// sets the same name to another value.
    static func merge(_ knobs: [FdtdKnobSetting], into configs: [FdtdBenchConfig]) throws -> [FdtdBenchConfig] {
        var settings: [FdtdKnobSetting] = []
        for setting in knobs {
            if let earlier = settings.first(where: { $0.name == setting.name }) {
                guard earlier.value == setting.value else {
                    let message = "--knob \(setting.name) is given as \(earlier.value) and as \(setting.value)"
                    throw FdtdOptions.usage(message, field: "--knob")
                }
                continue
            }
            settings.append(setting)
        }
        var merged: [FdtdBenchConfig] = []
        for var config in configs {
            for setting in settings {
                if let own = config.knobs.first(where: { $0.name == setting.name }) {
                    guard own.value == setting.value else {
                        let message = "--knob \(setting.text) conflicts with \(own.text) in --config \(config.text)"
                        throw FdtdOptions.usage(message, field: "--knob")
                    }
                    continue
                }
                config.knobs.append(setting)
                config.text = appending(setting, to: config.text)
            }
            merged.append(config)
        }
        return merged
    }

    /// knob_ignored for each name that validate, e2e or run got with two values: the environment holds one value per
    /// name and the last one wins (environment), which the user should see.
    static func repeated(_ settings: [FdtdKnobSetting]) -> [FdtdIssue] {
        var issues: [FdtdIssue] = []
        var seen: [String] = []
        for setting in settings where !seen.contains(setting.name) {
            seen.append(setting.name)
            let values = settings.filter { $0.name == setting.name }.map(\.value)
            guard let last = values.last, values.contains(where: { $0 != last }) else { continue }
            let given = values.joined(separator: ", then ")
            issues.append(FdtdIssue(.knobIgnored, "--knob \(setting.name) is given as \(given): the last value, "
                                        + "\(last), is used and the earlier ones are ignored", field: "--knob"))
        }
        return issues
    }

    /// The settings as environment variables (validate, e2e, run); a later setting of the same name wins.
    static func environment(_ settings: [FdtdKnobSetting]) -> [String: String] {
        Dictionary(settings.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    /// The registry as info reports it.
    static func info() -> [FdtdKnobInfo] {
        registry.map { (knob: FdtdKnob) -> FdtdKnobInfo in
            let commands = FdtdCommandName.allCases.filter { knob.commands.contains($0) }.map(\.rawValue)
            return FdtdKnobInfo(name: knob.name, values: knob.valuesText, readOncePerProcess: knob.readOncePerProcess,
                                commands: commands)
        }
    }

    // MARK: - Private

    private static func checkRule(_ knob: FdtdKnob, _ value: String, transport: FdtdKnobTransport, field: String?,
                                  system: any FdtdSystem) throws {
        let text = knob.name + "=" + value
        switch knob.rule {
        case .oneOf(let words):
            guard words.contains(value) else {
                let near = FdtdOptions.nearest(value, among: words).map { knob.name + "=" + $0 }
                throw FdtdError(.knobValue, "\(text): the value must be one of \(words.joined(separator: ", "))",
                                field: field, hint: near)
            }
        case .onlyOne:
            // Up to patch 0005 any value, 0 included, switched these on, and the version strings cannot tell (F23).
            guard value == "1" else {
                throw FdtdError(.knobValue, "\(text): this switch takes only 1", field: field,
                                hint: "leave the knob out for off")
            }
        case .integer(let minimum):
            guard let number = plainInteger(value), number >= minimum else {
                throw FdtdError(.knobValue, "\(text): the value must be an integer >= \(minimum), digits only",
                                field: field)
            }
        case .number(let low, let high):
            guard let number = Double(value), number.isFinite else {
                throw FdtdError(.knobValue, "\(text): the value must be \(knob.valuesText)", field: field)
            }
            if let low, number < low {
                throw FdtdError(.knobValue, "\(text): the value must be \(knob.valuesText)", field: field)
            }
            if let high, number > high {
                throw FdtdError(.knobValue, "\(text): the value must be \(knob.valuesText)", field: field)
            }
        case .existingFolder:
            // FDTD.Run changes into its simulation folder, so a relative folder would land somewhere else.
            guard value.hasPrefix("/") else {
                throw FdtdError(.knobValue, "\(text): the folder must be an absolute path", field: field,
                                hint: knob.name + "=/absolute/folder")
            }
            guard system.isDirectory(value) else {
                throw FdtdError(.knobValue, "\(text): no such folder", field: field, hint: "mkdir -p " + value)
            }
        case .tile:
            guard tileParts(value, allowComma: transport == .environment) != nil else {
                let form = transport == .environment ? "M:V or M,V" : "M:V"
                throw FdtdError(.knobValue, "\(text): the value must be \(form) with M >= 1 and V >= 0", field: field)
            }
        }
    }

    /// A registry name for a mistyped one: the same name in capitals, with the OPENEMS_ prefix, or the nearest.
    private static func suggestion(for name: String) -> String? {
        let names = registry.map(\.name)
        let upper = name.uppercased()
        if names.contains(upper) { return upper }
        if names.contains("OPENEMS_" + upper) { return "OPENEMS_" + upper }
        return FdtdOptions.nearest(upper, among: names) ?? FdtdOptions.nearest("OPENEMS_" + upper, among: names)
    }

    private static func notAllowedHint(_ knob: FdtdKnob, _ setting: FdtdKnobSetting,
                                       _ command: FdtdCommandName) -> String? {
        if command == .e2e, knob.name.hasPrefix("OPENEMS_PROBE_END_") { return "--probe-end DB, --hold H" }
        if knob.commands == [.run] { return "emskit fdtd run SCRIPT --knob " + setting.text }
        return nil
    }

    /// Digits only (no sign, no spaces), as an Int; nil when empty or too large.
    private static func plainInteger(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ digitBytes.contains($0) }) else { return nil }
        return Int(text)
    }

    /// M and V of a DIAMOND_TILE value: `M:V`, or `M,V` when `allowComma`; nil for any other form or M < 1.
    private static func tileParts(_ value: String, allowComma: Bool) -> (m: Int, v: Int)? {
        let separators: Set<Character> = allowComma ? [":", ","] : [":"]
        guard let sep = value.firstIndex(where: { separators.contains($0) }) else { return nil }
        let head = String(value[..<sep])
        let rest = String(value[value.index(after: sep)...])
        guard let m = plainInteger(head), let v = plainInteger(rest), m >= 1 else { return nil }
        return (m: m, v: v)
    }

    /// The CFG text with one more `#` item, the way bench's parse_cfg reads it (empty items are skipped there).
    private static func appending(_ setting: FdtdKnobSetting, to text: String) -> String {
        guard text.contains("#") else { return text + "#" + setting.text }
        if text.hasSuffix("#") || text.hasSuffix(",") { return text + setting.text }
        return text + "," + setting.text
    }
}
