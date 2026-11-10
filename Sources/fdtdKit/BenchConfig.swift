// SPDX-License-Identifier: GPL-3.0-or-later

// bench configs (spec 2.4, 4.4, 6.1): the CFG grammar `[LIB@]ENGINE[:THREADS][+nodumps][#NAME=VAL,...]` as bench.py's
// parse_cfg reads it (`ENGINE+nodumps:THREADS` too), labels and run subfolders by bench's own algorithm
// (bench.py:302-311), tolerance from the CFG's own knobs only, and the engine to Create-line table.
import Foundation

/// The engines bench, the validation suite, e2e and run know (bench ENGINES, in its order).
enum FdtdEngine: String, CaseIterable, Codable, Sendable {
    case fastest, basic, sse
    case sseCompressed = "sse-compressed"
    case multithreaded, gpu
    case gpuReference = "gpu-reference"
    case metalDiamond = "metal-diamond"

    /// The five CPU engines every library has (the stock scan wants exactly these).
    static let cpuEngines: [FdtdEngine] = [.fastest, .basic, .sse, .sseCompressed, .multithreaded]

    /// The Create parentheses of the multithreaded engine: Cartesian, cylindrical and cylindrical multigrid meshes.
    private static let multithreadingTexts: Set<String> = [
        "compressed SSE + multi-threading",
        "cylindrical mesh using sse compression + multithreading",
        "cylindrical multi grid mesh using sse compression + multithreading",
    ]

    /// The GPU engine prints its backend; a cylindrical multigrid run prints one line per level.
    private static let gpuPrefixes = ["GPU, backend: ", "GPU, cylindrical multi-grid level "]

    /// How the library's --help lists it: two spaces, the name, a colon, a space and a tab.
    var helpString: String { "  \(rawValue): \t" }

    /// gpu, gpu-reference and metal-diamond: compared, not required to match (Apple's GPU flushes subnormals).
    var isTolerant: Bool { self == .gpu || self == .gpuReference || self == .metalDiamond }

    /// Whether a Create line is one this engine prints (spec 4.4): basic the bare line; sse ` (SSE)`; sse-compressed
    /// ` (compressed SSE)`; multithreaded and fastest the three multi-threading texts; gpu and gpu-reference
    /// ` (GPU, backend: ...)` and ` (GPU, cylindrical multi-grid level ...)`; metal-diamond ` (Metal, diamond-blocked)`.
    func accepts(_ create: FdtdCreateLine) -> Bool {
        guard let text = create.parenthesis else { return self == .basic }
        switch self {
        case .basic:
            return false
        case .sse:
            return text == "SSE"
        case .sseCompressed:
            return text == "compressed SSE"
        case .fastest, .multithreaded:
            return Self.multithreadingTexts.contains(text)
        case .gpu, .gpuReference:
            return Self.gpuPrefixes.contains(where: { text.hasPrefix($0) })
        case .metalDiamond:
            return text == "Metal, diamond-blocked"
        }
    }

    /// Whether a validation run's `engine` text (the Create parenthesis texts joined by "; ", or "basic") is this
    /// engine's: every part must be one of its Create texts ("?", no Create line at all, never is).
    func acceptsValidationText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.components(separatedBy: "; ").allSatisfy { part in
            if part == "basic" { return self == .basic }
            return accepts(FdtdCreateLine(line: "Create FDTD engine (" + part + ")", parenthesis: part))
        }
    }
}

/// One bench CFG, parsed and validated.
struct FdtdBenchConfig: Sendable, Equatable {
    /// The CFG text bench gets (installed@ stripped; a relative LIB path made absolute).
    var text: String
    /// The LIB as given; nil = the installed library.
    var lib: String? = nil
    var engine: FdtdEngine
    var threads: Int? = nil
    var nodumps = false
    /// In the CFG's own order.
    var knobs: [FdtdKnobSetting] = []
}

/// CFG parsing, formatting, labels, run subfolders and tolerance.
enum FdtdBenchConfigs {
    private static let grammar = "[LIB@]ENGINE[:THREADS][+nodumps][#NAME=VAL,...]"
    static let libHint =
        "a snapshot name, or a folder path, not starting with '-' and without '@', '#', ',', ';' or spaces"
    /// bench splits the CFG at '#' and the last '@', its `#` list at ','; abtest turns ';' into ','.
    private static let libForbidden: Set<Character> = ["@", "#", ",", ";"]
    private static let digits = Set("0123456789".utf8)
    /// bench.py:305, `re.sub(r'[^A-Za-z0-9_.-]', '_', ...)`.
    private static let subfolderBytes = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-".utf8)

    /// Whether a CFG can carry `lib` (a snapshot name or a folder) as its LIB: bench splits the CFG at '#', '@' and
    /// ',', and its rows and check.sh's lists on whitespace.
    static func carries(lib: String) -> Bool {
        !lib.isEmpty && !lib.hasPrefix("-") && !lib.contains(where: { libForbidden.contains($0) || $0.isWhitespace })
    }

    /// Parses one CFG: LIB not starting with '-' and without '@', '#', ',', ';' or whitespace, THREADS digits only, the
    /// `+nodumps` flag in either place (once), and each `#` knob as NAME=VALUE, once per name, validated for `command`
    /// with transport .cfgList (check's extras as bench knobs: check.sh hands them to bench). A grammar error,
    /// whitespace anywhere (bench rows and check.sh's EXTRA are split on it) or an empty item → 2 config_invalid; an
    /// ENGINE outside bench ENGINES → 3 engine_unsupported (spec 2.4); knob errors as FdtdKnobs.validate. Whether the
    /// library has the engine is checked later (FdtdLibraries.requireEngine).
    static func parse(_ text: String, command: FdtdCommandName, cwd: String, home: String,
                      system: any FdtdSystem) throws -> FdtdBenchConfig {
        let field = command == .check ? "--extra" : "--config"
        guard !text.isEmpty else { throw invalid("the CFG is empty", field: field) }
        guard !text.contains(where: { $0.isWhitespace }) else {
            throw invalid("CFG '\(text)' contains whitespace", field: field)
        }

        let specEnd = text.firstIndex(of: "#") ?? text.endIndex
        let spec = text[..<specEnd]

        // LIB: everything before the last '@' (bench's rpartition).
        var lib: String? = nil
        var libText: String? = nil
        var rest = spec
        if let at = spec.lastIndex(of: "@") {
            let given = String(spec[..<at])
            rest = spec[spec.index(after: at)...]
            guard !given.isEmpty else { throw invalid("\(text): no LIB before '@'", field: field) }
            // bench.py's argparse would read the CFG as an option (FdtdLibraries.locate has the same rule)
            guard !given.hasPrefix("-") else {
                throw FdtdError(.configInvalid, "\(text): LIB \(given) starts with '-'", field: field, hint: libHint)
            }
            guard !given.contains(where: { libForbidden.contains($0) }) else {
                throw FdtdError(.configInvalid, "\(text): LIB \(given) contains '@', ',' or ';'", field: field,
                                hint: libHint)
            }
            if given != "installed" {
                let resolved = given.contains("/") ? FdtdPaths.absolute(given, cwd: cwd, home: home) : given
                guard !resolved.contains(where: { libForbidden.contains($0) || $0.isWhitespace }) else {
                    let message = "\(text): LIB path \(resolved) contains '@', '#', ',', ';' or spaces"
                    throw FdtdError(.configInvalid, message, field: field, hint: libHint)
                }
                lib = given
                libText = resolved
            }
        }

        // ENGINE[+nodumps][:THREADS[+nodumps]], partitioned as bench does.
        let colon = partition(rest, ":")
        let enginePart = partition(colon.head, "+")
        let threadsPart = colon.tail.map { partition($0, "+") }
        let engineName = String(enginePart.head)
        guard !engineName.isEmpty else { throw invalid("\(text): no ENGINE", field: field) }
        guard let engine = FdtdEngine(rawValue: engineName) else {
            let names = FdtdEngine.allCases.map(\.rawValue)
            let message = "\(text): engine \(engineName) is not one of " + names.joined(separator: ", ")
            throw FdtdError(.engineUnsupported, message, field: field,
                            hint: FdtdOptions.nearest(engineName, among: names))
        }
        let flags = [enginePart.tail, threadsPart?.tail].compactMap { $0 }
        for flag in flags where flag != "nodumps" {
            throw invalid("\(text): flag +\(flag) is not +nodumps", field: field)
        }
        guard flags.count < 2 else { throw invalid("\(text): +nodumps given twice", field: field) }
        var threads: Int? = nil
        if let given = threadsPart?.head {
            guard !given.isEmpty else { throw invalid("\(text): no THREADS after ':'", field: field) }
            guard given.utf8.allSatisfy({ digits.contains($0) }), let n = Int(given) else {
                throw invalid("\(text): THREADS \(given) is not a whole number", field: field)
            }
            threads = n
        }

        // The `#` list, after the grammar: validate may look at the file system (EXPORT_* folders).
        var knobs: [FdtdKnobSetting] = []
        if specEnd < text.endIndex {
            let list = text[text.index(after: specEnd)...]
            guard !list.isEmpty else { throw invalid("\(text): no knobs after '#'", field: field) }
            let knobCommand: FdtdCommandName = command == .check ? .bench : command
            for item in list.split(separator: ",", omittingEmptySubsequences: false) {
                guard let eq = item.firstIndex(of: "="), eq != item.startIndex else {
                    throw invalid("\(text): knob item '\(item)' is not NAME=VALUE", field: field)
                }
                let setting = FdtdKnobSetting(name: String(item[..<eq]), value: String(item[item.index(after: eq)...]))
                guard !knobs.contains(where: { $0.name == setting.name }) else {
                    throw invalid("\(text): knob \(setting.name) given twice", field: field)
                }
                try FdtdKnobs.validate(setting, command: knobCommand, transport: .cfgList, system: system)
                knobs.append(setting)
            }
        }

        var config = FdtdBenchConfig(text: "", lib: lib, engine: engine, threads: threads, nodumps: !flags.isEmpty,
                                     knobs: knobs)
        config.text = compose(libText, config)
        return config
    }

    /// The CFG text for bench: `[LIB@]ENGINE[:THREADS][+nodumps][#K=V,...]`, knobs in their order. A LIB path keeps
    /// the absolute form parse put into `text` (Knobs.merge formats parsed configs again).
    static func format(_ config: FdtdBenchConfig) -> String {
        compose(libPrefix(config), config)
    }

    /// bench's row label: the CFG with `LIB@` replaced by `basename(LIB)@` when LIB contains '/'.
    static func label(_ cfg: String) -> String {
        let specEnd = cfg.firstIndex(of: "#") ?? cfg.endIndex
        guard let at = cfg[..<specEnd].lastIndex(of: "@") else { return cfg }
        let lib = cfg[..<at]
        guard lib.contains("/") else { return cfg }
        // os.path.basename(lib.rstrip('/')): the part after the last '/', trailing slashes first removed.
        var trimmed = lib
        while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        let base = trimmed.lastIndex(of: "/").map { trimmed[trimmed.index(after: $0)...] } ?? trimmed
        return String(base) + String(cfg[at...])
    }

    /// bench's run subfolders for the labels in config order: ':' → '_t', every character outside [A-Za-z0-9_.-]
    /// → '_', then `_2`, `_3`, ... for a name already used.
    static func runSubfolders(_ labels: [String]) -> [String] {
        var used = Set<String>()
        var names: [String] = []
        for label in labels {
            let first = subfolderName(label)
            var name = first
            var i = 1
            while used.contains(name) {
                i += 1
                name = first + "_" + String(i)
            }
            used.insert(name)
            names.append(name)
        }
        return names
    }

    /// The CFG is tolerant by itself: a tolerant engine, or OPENEMS_FTZ set (not 0) among its own knobs. bench's
    /// is_tolerant also reads OPENEMS_FTZ from its environment, which the CLI removes, so only the CFG counts.
    static func isTolerant(_ config: FdtdBenchConfig) -> Bool {
        if config.engine.isTolerant { return true }
        let ftz = config.knobs.last(where: { $0.name == "OPENEMS_FTZ" })?.value ?? ""
        return ftz != "" && ftz != "0"
    }

    /// ab mirrors bench (bench.py:327): every config is tolerant when c0 is; otherwise each by itself.
    static func abTolerance(_ configs: [FdtdBenchConfig]) -> [Bool] {
        let reference = configs.first.map { isTolerant($0) } ?? false
        return configs.map { reference || isTolerant($0) }
    }

    /// Whether an openEMS.log holds a Create line of `engine` (engine confirmation, F6): at least one, and every one
    /// in it is this engine's (a GPU multigrid run prints one per level).
    static func createLineMatches(_ engine: FdtdEngine, log: String) -> Bool {
        var seen = false
        for line in log.split(whereSeparator: \.isNewline) {
            guard let create = FdtdParsers.createLine(String(line)) else { continue }
            guard engine.accepts(create) else { return false }
            seen = true
        }
        return seen
    }

    private static func invalid(_ message: String, field: String) -> FdtdError {
        FdtdError(.configInvalid, message, field: field, hint: grammar)
    }

    /// Python's str.partition: the part before the first `separator` and, when there is one, the part after it.
    private static func partition(_ text: Substring, _ separator: Character) -> (head: Substring, tail: Substring?) {
        guard let i = text.firstIndex(of: separator) else { return (text, nil) }
        return (text[..<i], text[text.index(after: i)...])
    }

    private static func compose(_ lib: String?, _ config: FdtdBenchConfig) -> String {
        var text = lib.map { $0 + "@" } ?? ""
        text += config.engine.rawValue
        if let threads = config.threads { text += ":" + String(threads) }
        if config.nodumps { text += "+nodumps" }
        if !config.knobs.isEmpty { text += "#" + config.knobs.map(\.text).joined(separator: ",") }
        return text
    }

    /// The LIB part of a config's text: nil for the installed library, the name for a snapshot, and for a path the
    /// absolute form already in `text` (or the path as given when `text` has none).
    private static func libPrefix(_ config: FdtdBenchConfig) -> String? {
        guard let lib = config.lib, lib != "installed" else { return nil }
        guard lib.contains("/") else { return lib }
        let specEnd = config.text.firstIndex(of: "#") ?? config.text.endIndex
        if let at = config.text[..<specEnd].lastIndex(of: "@"), config.text.hasPrefix("/") {
            return String(config.text[..<at])
        }
        return lib
    }

    /// One label's subfolder before the `_N` suffix, per code point as Python's re.sub sees the text.
    private static func subfolderName(_ label: String) -> String {
        var name = String.UnicodeScalarView()
        for scalar in label.unicodeScalars {
            if scalar == ":" {
                name.append(contentsOf: "_t".unicodeScalars)
            } else if scalar.isASCII, subfolderBytes.contains(UInt8(scalar.value)) {
                name.append(scalar)
            } else {
                name.append("_")
            }
        }
        return String(name)
    }
}
