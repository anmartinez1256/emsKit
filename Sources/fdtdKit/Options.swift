// SPDX-License-Identifier: GPL-3.0-or-later

// The grammar of `emskit fdtd` (spec 2): command specs, a strict tokenizer, typed options per command with the
// cross-option rules, nearest-option hints, the %g scale rule and the usage texts.
// Strict on purpose (femKit's validate rule): a typo can never silently run another configuration. Values that need
// the file system or a library (CFGs, knobs, LIBs, engines, folders) stay raw here; the commands check them.
import Foundation

/// The ten commands; the raw value is the command word and the schema name.
enum FdtdCommandName: String, CaseIterable, Codable, Sendable {
    case info, load, bench, ab, check, validate
    case debyeCheck = "debye-check", diamondCheck = "diamond-check"
    case e2e, run

    /// bench, ab, check, validate, debye-check, diamond-check, e2e and run (spec 2.1).
    var isRunCommand: Bool { self != .info && self != .load }
}

/// How an option takes its value.
enum FdtdOptionKind: Sendable, Equatable {
    /// `--name`
    case flag
    /// `--name VALUE`, at most once
    case value
    /// `--name VALUE`, any number of times
    case repeated
}

/// An option of another command that this command refuses with its own message and hint.
struct FdtdRefusedOption: Sendable, Equatable {
    var message: String
    var hint: String?
}

/// The grammar of one command.
struct FdtdCommandSpec: Sendable {
    var name: FdtdCommandName
    var positionals: ClosedRange<Int>
    var positionalName: String
    var options: [String: FdtdOptionKind]
    var refused: [String: FdtdRefusedOption] = [:]
    /// Only run: everything after `--` goes to the script.
    var takesPassthrough = false
}

/// The tokens of one command line after the command word, sorted into positionals, values and switches.
struct FdtdArguments: Sendable, Equatable {
    var command: FdtdCommandName
    var positionals: [String] = []
    var values: [String: [String]] = [:]
    var switches: Set<String> = []
    var passthrough: [String] = []

    func has(_ name: String) -> Bool { switches.contains(name) || values[name] != nil }
    func flag(_ name: String) -> Bool { switches.contains(name) }
    func value(_ name: String) -> String? { values[name]?.last }
    func all(_ name: String) -> [String] { values[name] ?? [] }

    /// A decimal integer (digits only) within min...max; nil when the option is absent.
    func integer(_ name: String, min: Int, max: Int = Int.max) throws -> Int? {
        guard let s = value(name) else { return nil }
        let digits = !s.isEmpty && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
        guard digits, let v = Int(s), v >= min, v <= max else {
            let range = max == Int.max ? "an integer >= \(min)" : "an integer in \(min)...\(max)"
            throw FdtdOptions.usage("--\(name) \(s): expected \(range)", field: "--" + name)
        }
        return v
    }

    /// A finite number (Swift's Double(...)) that `valid` accepts, described by `what`; nil when absent.
    func number(_ name: String, _ what: String, where valid: (Double) -> Bool) throws -> Double? {
        guard let s = value(name) else { return nil }
        guard let v = Double(s), v.isFinite, valid(v) else {
            throw FdtdOptions.usage("--\(name) \(s): expected \(what)", field: "--" + name)
        }
        return v
    }
}

enum FdtdOptions {
    /// Options of every command.
    static let allCommands: [String: FdtdOptionKind] = [
        "repo": .value, "python": .value, "snaps": .value, "rfsim": .value, "output": .value, "overwrite": .flag,
    ]
    /// Options of the run commands (bench, ab, check, validate, debye-check, diamond-check, e2e, run).
    static let runCommands: [String: FdtdOptionKind] = [
        "runs": .value, "keep-runs": .flag, "dry-run": .flag, "no-caffeinate": .flag, "allow-concurrent": .flag,
        "nodes": .value, "hosts": .value, "distribute": .value,
    ]
    /// Options of the commands whose figures carry a load (every command but info).
    static let speeds: [String: FdtdOptionKind] = ["warn-cpu": .value, "warn-gpu": .value]
    /// The quiet-wait options of bench, e2e and run.
    static let quietWait: [String: FdtdOptionKind] = ["quiet": .value, "quiet-gpu": .value, "quiet-max": .value]

    /// The grammar of `command`.
    static func spec(for command: FdtdCommandName) -> FdtdCommandSpec {
        func merged(_ parts: [String: FdtdOptionKind]...) -> [String: FdtdOptionKind] {
            parts.reduce(into: [:]) { $0.merge($1) { a, _ in a } }
        }
        let base = merged(allCommands, runCommands, speeds)
        let noKnob = ["knob": FdtdRefusedOption(message: "\(command.rawValue) takes no --knob",
                                                hint: "check, debye-check and diamond-check run with the scripts' own settings")]
        switch command {
        case .info:
            return FdtdCommandSpec(name: .info, positionals: 0...0, positionalName: "",
                                   options: merged(allCommands, ["lib": .repeated, "build": .repeated]))
        case .load:
            return FdtdCommandSpec(name: .load, positionals: 0...0, positionalName: "",
                                   options: merged(allCommands, speeds, ["seconds": .value]))
        case .bench:
            return FdtdCommandSpec(name: .bench, positionals: 1...1, positionalName: "MODEL", options: merged(base, quietWait, [
                "config": .repeated, "scale": .value, "nrts": .value, "knob": .repeated, "repeat": .value,
                "no-sparams": .flag, "tag": .value, "results": .value, "exact": .flag,
            ]))
        case .ab:
            return FdtdCommandSpec(name: .ab, positionals: 1...1, positionalName: "MODEL", options: merged(base, [
                "config": .repeated, "scale": .value, "nrts": .value, "knob": .repeated, "rounds": .value,
                "quiet": .value, "quiet-max": .value, "redo": .value, "run-redo": .value, "record": .value,
                "append": .flag, "exact": .flag,
            ]), refused: ["quiet-gpu": FdtdRefusedOption(message: "ab takes no --quiet-gpu",
                                                          hint: "abtest waits for GPU <= 10 % itself and has no flag for it")])
        case .check:
            let fixed = FdtdRefusedOption(message: "check takes no such option: check.sh sets it itself", hint: "check.sh fixes these")
            return FdtdCommandSpec(name: .check, positionals: 1...Int.max, positionalName: "SNAP", options: merged(base, [
                "tag": .value, "lite": .flag, "stock": .value, "extra": .repeated, "quiet-max": .value, "allow-partial": .flag,
            ]), refused: ["quiet": fixed, "repeat": fixed, "results": fixed, "knob": fixed, "config": fixed])
        case .validate:
            return FdtdCommandSpec(name: .validate, positionals: 0...0, positionalName: "", options: merged(base, [
                "lib": .value, "engine": .value, "threads": .value, "quick": .flag, "case": .repeated,
                "knob": .repeated, "tag": .value, "results": .value,
            ]))
        case .debyeCheck:
            return FdtdCommandSpec(name: .debyeCheck, positionals: 1...1, positionalName: "LIB",
                                   options: merged(base, ["ref": .value, "threads": .value]), refused: noKnob)
        case .diamondCheck:
            return FdtdCommandSpec(name: .diamondCheck, positionals: 1...1, positionalName: "LIB", options: base, refused: noKnob)
        case .e2e:
            return FdtdCommandSpec(name: .e2e, positionals: 1...1, positionalName: "MODEL", options: merged(base, quietWait, [
                "lib": .value, "engine": .value, "floor": .value, "probe-end": .value, "hold": .value,
                "out-dir": .value, "knob": .repeated,
            ]))
        case .run:
            return FdtdCommandSpec(name: .run, positionals: 1...1, positionalName: "SCRIPT", options: merged(base, quietWait, [
                "lib": .value, "engine": .value, "threads": .value, "nodumps": .flag, "knob": .repeated,
            ]), takesPassthrough: true)
        }
    }

    /// The placeholder shown after an option in hints and usage texts.
    static func metavar(_ name: String) -> String {
        switch name {
        case "config", "extra": "CFG"
        case "knob": "K=V"
        case "tag": "T"
        case "scale", "quiet-max", "seconds": "S"
        case "nrts", "threads", "nodes", "redo", "run-redo": "N"
        case "repeat", "rounds": "R"
        case "quiet", "quiet-gpu", "warn-cpu", "warn-gpu": "PCT"
        case "results", "build", "repo", "snaps", "rfsim", "runs", "out-dir": "DIR"
        case "record", "output", "hosts": "FILE"
        case "python": "PATH"
        case "lib", "stock", "ref": "LIB"
        case "engine": "E"
        case "case": "slab|cavity|lines"
        case "floor": "toolkit|MM"
        case "probe-end": "toolkit|off|DB"
        case "hold": "toolkit|H"
        case "distribute": "auto|off|frequencies|domain"
        default: "VALUE"
        }
    }

    /// The options whose value is a path (metavar DIR, FILE or PATH): an empty value is a usage error for each.
    static let pathValued: Set<String> = ["repo", "python", "snaps", "rfsim", "runs", "output", "hosts", "results",
                                          "record", "out-dir", "build"]

    /// `emskit fdtd COMMAND --help`: a `--help` before any `--`.
    static func wantsHelp(_ args: [String]) -> Bool { args.prefix { $0 != "--" }.contains("--help") }

    /// A usage error (exit 64).
    static func usage(_ message: String, field: String? = nil, hint: String? = nil) -> FdtdError {
        FdtdError(.usage, message, field: field, hint: hint)
    }

    /// Sorts the tokens after the command word. Refuses `--name=value`, unknown options (with the nearest valid one
    /// as the hint), missing values, an empty value of a path option, repeated non-repeatable options, a positional
    /// that starts with '-' and stray positionals (a value given to a switch shows up as one).
    static func tokenize(_ spec: FdtdCommandSpec, _ args: [String]) throws -> FdtdArguments {
        var out = FdtdArguments(command: spec.name)
        var afterSwitch: [Int: String] = [:]     // positional index -> the switch right before it
        var lastSwitch: String?
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--" {
                guard spec.takesPassthrough else {
                    throw usage("'--' is only for run (the arguments after it go to the script)", field: "--")
                }
                out.passthrough = Array(args[(i + 1)...])
                break
            }
            if a.hasPrefix("--") {
                let body = String(a.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    let name = String(body[..<eq]), value = String(body[body.index(after: eq)...])
                    throw usage("\(a): the form --name=value is not accepted", field: "--" + name, hint: "--\(name) \(value)")
                }
                if let refused = spec.refused[body] { throw usage(refused.message, field: a, hint: refused.hint) }
                guard let kind = spec.options[body] else {
                    throw usage("\(a) is not an option of \(spec.name.rawValue)", field: a,
                                hint: nearest(body, among: Array(spec.options.keys) + ["help"]).map { "--" + $0 })
                }
                switch kind {
                case .flag:
                    if out.switches.contains(body) { throw usage("\(a) is given twice", field: a) }
                    out.switches.insert(body)
                    lastSwitch = body
                    i += 1
                case .value, .repeated:
                    guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else {
                        throw usage("\(a) needs a value", field: a, hint: "\(a) \(metavar(body))")
                    }
                    if kind == .value, out.values[body] != nil { throw usage("\(a) is given twice", field: a, hint: "give \(a) once") }
                    // an unset shell variable: the empty path would stand for the cwd
                    if args[i + 1].isEmpty, pathValued.contains(body) {
                        throw usage("\(a) needs a \(metavar(body)); the value is empty", field: a,
                                    hint: "\(a) \(metavar(body))")
                    }
                    out.values[body, default: []].append(args[i + 1])
                    lastSwitch = nil
                    i += 2
                }
                continue
            }
            if a.hasPrefix("-") {
                // -snaps DIR, -python=PATH: an option written with one dash must not be read as a SNAP, LIB, MODEL
                // or SCRIPT name (no LIB may start with '-' anyway, Libraries.swift); the line does not parse
                let word = String(a.drop(while: { $0 == "-" }).prefix(while: { $0 != "=" }))
                // -h and -help ask for the help text: say how it is spelt instead of pointing at a file ./-h
                let option = word == "h" || word == "help" ? "--help"
                    : nearest(word, among: Array(spec.options.keys) + ["help"]).map { "--" + $0 }
                throw usage("'\(a)' starts with '-': options are written --name, and no \(positionalWord(spec)) "
                                + "may start with '-'", field: a,
                            hint: option ?? "a folder or a script of that name by its path, ./\(a)")
            }
            if let s = lastSwitch { afterSwitch[out.positionals.count] = s }
            out.positionals.append(a)
            lastSwitch = nil
            i += 1
        }
        if out.positionals.count > spec.positionals.upperBound {
            let k = spec.positionals.upperBound
            throw usage("unexpected argument '\(out.positionals[k])'", field: out.positionals[k],
                        hint: afterSwitch[k].map { "--\($0) takes no value" })
        }
        if out.positionals.count < spec.positionals.lowerBound {
            throw usage("\(spec.name.rawValue) needs \(spec.positionalName)", field: spec.positionalName,
                        hint: "emskit fdtd \(spec.name.rawValue) --help")
        }
        return out
    }

    /// What a command's positional is called in a message; "argument" for the commands that take none.
    static func positionalWord(_ spec: FdtdCommandSpec) -> String {
        spec.positionalName.isEmpty ? "argument" : spec.positionalName
    }

    /// The candidate nearest to `word` within edit distance 2 (ties: alphabetical), or nil.
    static func nearest(_ word: String, among candidates: [String]) -> String? {
        let scored = candidates.map { ($0, editDistance(word, $0)) }.filter { $0.1 <= 2 }
        return scored.min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }?.0
    }

    /// Levenshtein distance over characters.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }

    /// A scale as bench and abtest print it: `%g`.
    static func formatG(_ value: Double) -> String { String(format: "%g", value) }

    /// bench names its run folders and `--tag` tables MODEL_s%g_nN, so a scale must survive `%g` unchanged.
    static func scaleIsExact(_ value: Double) -> Bool { Double(formatG(value)) == value }

    /// `[A-Za-z0-9_.][A-Za-z0-9_.-]*`: bench.py and run_validation.py (argparse) read a value that starts with '-' as
    /// an option and exit 2 before they print anything.
    static func isTag(_ text: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-".utf8)
        guard let first = text.utf8.first, first != UInt8(ascii: "-") else { return false }
        return text.utf8.allSatisfy { allowed.contains($0) }
    }

    /// check.sh's timestep counts, the `--nrts` defaults of bench and ab (spec 2.4).
    static func defaultNrts(_ model: FdtdBenchModel, scale: Double) -> Int? {
        switch (model, scale) {
        case (.patch, 1): 10500
        case (.patch, 5): 1200
        case (.notch, 1): 16000
        case (.notch, 3): 2000
        case (.kgcpw, 1): 15000
        case (.ksma, 1): 6000
        default: nil
        }
    }
}

// MARK: - Typed options

/// `--distribute`: the family's four values (Docs/fdtdKit/PLAN.md, section 11); v1 runs everything on this Mac.
enum FdtdDistributeMode: String, Codable, Sendable, CaseIterable { case auto, off, frequencies, domain }

/// The options of spec 2.1's common table, with their defaults applied.
struct FdtdCommonOptions: Sendable, Equatable {
    var repo: String? = nil
    var python: String? = nil
    var snaps: String? = nil
    var rfsim: String? = nil
    var runs: String? = nil
    var output: String? = nil
    var overwrite = false
    var keepRuns = false
    var dryRun = false
    var noCaffeinate = false
    var allowConcurrent = false
    var warnCpu = 150.0
    var warnGpu = 10.0
    var nodes: Int? = nil
    var hosts: String? = nil
    var distribute: FdtdDistributeMode = .auto
    /// The options that decide where discovery looks; each of them can name a protected folder.
    static let discoveryOptions = ["repo", "python", "snaps", "rfsim"]

    /// The discovery options that the line names something with: with any of them the protected folders of the
    /// plain line count beside those the options name. Sources only asks whether there is one; the names are
    /// read by the tests only.
    var discoveryGiven: [String] {
        let given = [repo, python, snaps, rfsim]
        return zip(Self.discoveryOptions, given).filter { $0.1 != nil }.map(\.0)
    }
}

/// `--quiet PCT [--quiet-gpu PCT] [--quiet-max S]` with bench's defaults (GPU 10 %, 900 s).
struct FdtdQuiet: Sendable, Equatable {
    var percent: Double
    var gpuPercent = 10.0
    var maxSeconds = 900.0
}

/// bench's MODELS.
enum FdtdBenchModel: String, CaseIterable, Codable, Sendable {
    case patch, notch, kgcpw, ksma
    /// The two boards are built by the rfsim toolkit.
    var needsRfsim: Bool { self == .kgcpw || self == .ksma }
}

/// MODEL, `--scale` and `--nrts` of bench and ab.
struct FdtdModelRun: Sendable, Equatable {
    var model: FdtdBenchModel
    var scale: Double
    var nrts: Int
    var nrtsGiven: Bool
    /// The scale as the tools print it (%g).
    var scaleText: String { FdtdOptions.formatG(scale) }
    /// bench's run-folder and table name, MODEL_s%g_nN.
    var name: String { "\(model.rawValue)_s\(scaleText)_n\(nrts)" }
}

struct FdtdInfoOptions: Sendable, Equatable {
    var libs: [String] = []
    var builds: [String] = []
}

struct FdtdLoadOptions: Sendable, Equatable {
    var seconds = 5.0
}

/// CFGs and knobs stay raw: BenchConfig and Knobs parse them (exit 2) and merge (a conflict is exit 64).
struct FdtdBenchOptions: Sendable, Equatable {
    var run: FdtdModelRun
    var configs: [String]
    var knobs: [String] = []
    var repeatCount = 1
    var quiet: FdtdQuiet? = nil
    var noSparams = false
    var tag: String? = nil
    var results: String? = nil
    var exact = false
}

struct FdtdABOptions: Sendable, Equatable {
    var run: FdtdModelRun
    var configs: [String]
    var knobs: [String] = []
    var rounds = 5
    /// gpuPercent is unused: abtest waits for GPU <= 10 % itself.
    var quiet: FdtdQuiet? = nil
    var redo: Int? = nil
    var runRedo: Int? = nil
    var record: String? = nil
    var append = false
    var exact = false
}

struct FdtdCheckOptions: Sendable, Equatable {
    var snapshots: [String]
    var tag: String
    var lite = false
    var stock: String? = nil
    var extras: [String] = []
    var quietMax: Double? = nil
    var allowPartial = false
}

/// The validation suite's cases.
enum FdtdValidationCase: String, CaseIterable, Codable, Sendable { case slab, cavity, lines }

struct FdtdValidateOptions: Sendable, Equatable {
    var lib = "installed"
    var engine: String? = nil
    var threads: Int? = nil
    var quick = false
    var cases: [FdtdValidationCase] = []
    var knobs: [String] = []
    var tag: String? = nil
    var results: String? = nil
}

struct FdtdDebyeCheckOptions: Sendable, Equatable {
    var lib: String
    var ref: String? = nil
    var threads: Int? = nil
}

struct FdtdDiamondCheckOptions: Sendable, Equatable {
    var lib: String
}

/// run_one.py's two models (any other name would silently run the SMA, F11).
enum FdtdE2EModel: String, CaseIterable, Codable, Sendable { case gcpw, sma }

/// `toolkit` (read from the rfsim probe) or a number given by the user.
enum FdtdToolkitOr: Sendable, Equatable {
    case toolkit
    case value(Double)
}

/// `--probe-end toolkit|off|DB`.
enum FdtdProbeEndChoice: Sendable, Equatable {
    case toolkit
    case off
    case db(Double)
}

struct FdtdE2EOptions: Sendable, Equatable {
    var model: FdtdE2EModel
    var lib = "installed"
    var engine: String? = nil
    var floor: FdtdToolkitOr = .toolkit
    var probeEnd: FdtdProbeEndChoice = .toolkit
    var hold: FdtdToolkitOr = .toolkit
    var outDir: String? = nil
    var knobs: [String] = []
    var quiet: FdtdQuiet? = nil
}

struct FdtdRunOptions: Sendable, Equatable {
    var script: String
    var scriptArguments: [String] = []
    var lib = "installed"
    var engine: String? = nil
    var threads: Int? = nil
    var nodumps = false
    var knobs: [String] = []
    var quiet: FdtdQuiet? = nil
}

/// One command's typed options; the dispatcher switches on it.
enum FdtdCommandOptions: Sendable, Equatable {
    case info(FdtdInfoOptions)
    case load(FdtdLoadOptions)
    case bench(FdtdBenchOptions)
    case ab(FdtdABOptions)
    case check(FdtdCheckOptions)
    case validate(FdtdValidateOptions)
    case debyeCheck(FdtdDebyeCheckOptions)
    case diamondCheck(FdtdDiamondCheckOptions)
    case e2e(FdtdE2EOptions)
    case run(FdtdRunOptions)
}

extension FdtdCommandOptions {
    /// Every LIB that the line names, as given: check's SNAPs, --stock, --lib, --ref and the LIB of each CFG (--config,
    /// --extra, ab's). Read before anything resolves them, so one that names no library is listed too: the folders
    /// among them are protected for this command (FdtdSession.protectedFolders).
    var librarySpecs: [String] {
        // the text before '#' up to its last '@', as BenchConfig splits a CFG; the grammar is not checked here
        func lib(ofConfig text: String) -> String? {
            let spec = text[..<(text.firstIndex(of: "#") ?? text.endIndex)]
            return spec.lastIndex(of: "@").map { String(spec[..<$0]) }
        }
        switch self {
        case .info(let o): return o.libs
        case .load: return []
        case .bench(let o): return o.configs.compactMap(lib(ofConfig:))
        case .ab(let o): return o.configs.compactMap(lib(ofConfig:))
        case .check(let o): return o.snapshots + [o.stock].compactMap { $0 } + o.extras.compactMap(lib(ofConfig:))
        case .validate(let o): return [o.lib]
        case .debyeCheck(let o): return [o.lib] + [o.ref].compactMap { $0 }
        case .diamondCheck(let o): return [o.lib]
        case .e2e(let o): return [o.lib]
        case .run(let o): return [o.lib]
        }
    }
}

/// A parsed command line.
struct FdtdParsedCommand: Sendable, Equatable {
    var command: FdtdCommandName
    var common: FdtdCommonOptions
    var options: FdtdCommandOptions
}

// MARK: - Cross-option rules

extension FdtdOptions {
    /// Parses the tokens after the command word. Usage errors are exit 64; a bad `--tag` is exit 2 (tag_invalid).
    static func parse(_ command: FdtdCommandName, _ args: [String]) throws -> FdtdParsedCommand {
        let a = try tokenize(spec(for: command), args)
        let common = try commonOptions(a)
        let options: FdtdCommandOptions
        switch command {
        case .info:
            options = .info(FdtdInfoOptions(libs: a.all("lib"), builds: a.all("build")))
        case .load:
            let s = try a.number("seconds", "a number of seconds in 1...600", where: { $0 >= 1 && $0 <= 600 }) ?? 5
            options = .load(FdtdLoadOptions(seconds: s))
        case .bench: options = .bench(try bench(a, common))
        case .ab: options = .ab(try ab(a, common))
        case .check: options = .check(try check(a))
        case .validate: options = .validate(try validate(a))
        case .debyeCheck:
            options = .debyeCheck(FdtdDebyeCheckOptions(lib: a.positionals[0], ref: a.value("ref"),
                                                        threads: try a.integer("threads", min: 0)))
        case .diamondCheck: options = .diamondCheck(FdtdDiamondCheckOptions(lib: a.positionals[0]))
        case .e2e: options = .e2e(try e2e(a))
        case .run: options = .run(try run(a))
        }
        return FdtdParsedCommand(command: command, common: common, options: options)
    }

    /// Whether a line that did not parse holds `--output` (also as `--output=FILE`): only to say on stderr that
    /// the file is not written. Nothing else of such a line is read. After run's `--` the tokens are the script's.
    static func namesOutput(_ command: FdtdCommandName, _ args: [String]) -> Bool {
        let own = spec(for: command).takesPassthrough ? Array(args.prefix { $0 != "--" }) : args
        return own.contains { $0 == "--output" || $0.hasPrefix("--output=") }
    }

    static func commonOptions(_ a: FdtdArguments) throws -> FdtdCommonOptions {
        var c = FdtdCommonOptions()
        c.repo = a.value("repo")
        c.python = a.value("python")
        c.snaps = a.value("snaps")
        c.rfsim = a.value("rfsim")
        c.runs = a.value("runs")
        c.output = a.value("output")
        c.overwrite = a.flag("overwrite")
        c.keepRuns = a.flag("keep-runs")
        c.dryRun = a.flag("dry-run")
        c.noCaffeinate = a.flag("no-caffeinate")
        c.allowConcurrent = a.flag("allow-concurrent")
        c.warnCpu = try a.number("warn-cpu", "a CPU percentage >= 0", where: { $0 >= 0 }) ?? 150
        c.warnGpu = try a.number("warn-gpu", "a GPU percentage >= 0", where: { $0 >= 0 }) ?? 10
        c.nodes = try a.integer("nodes", min: 1)
        c.hosts = a.value("hosts")
        if c.nodes != nil, c.hosts != nil {
            throw usage("--nodes and --hosts: give one of them", field: "--hosts", hint: "--nodes N or --hosts FILE")
        }
        if let d = a.value("distribute") {
            guard let mode = FdtdDistributeMode(rawValue: d) else {
                throw usage("--distribute \(d): expected auto, off, frequencies or domain", field: "--distribute",
                            hint: nearest(d, among: FdtdDistributeMode.allCases.map(\.rawValue)))
            }
            c.distribute = mode
        }
        return c
    }

    /// bench and ab speeds describe one Mac.
    static func requireSingleMac(_ c: FdtdCommonOptions, _ command: String) throws {
        if let n = c.nodes, n > 1 {
            throw usage("--nodes \(n): \(command) speeds describe one Mac", field: "--nodes", hint: "leave --nodes out")
        }
        if c.hosts != nil { throw usage("--hosts: \(command) speeds describe one Mac", field: "--hosts", hint: "leave --hosts out") }
    }

    static func benchModel(_ text: String) throws -> FdtdBenchModel {
        guard let m = FdtdBenchModel(rawValue: text) else {
            throw usage("unknown model '\(text)': one of patch, notch, kgcpw, ksma", field: "MODEL",
                        hint: nearest(text, among: FdtdBenchModel.allCases.map(\.rawValue)))
        }
        return m
    }

    /// `--scale` (finite, > 0, unchanged by %g) and `--nrts` (given, or check.sh's default for the pair).
    static func modelRun(_ a: FdtdArguments, _ model: FdtdBenchModel) throws -> FdtdModelRun {
        let scale = try a.number("scale", "a number > 0", where: { $0 > 0 }) ?? 1
        guard scaleIsExact(scale) else {
            throw usage("--scale \(a.value("scale") ?? formatG(scale)): bench names its run folders and tables with %g, so two scales that print the same would share them",
                        field: "--scale", hint: "at most six significant digits")
        }
        if let n = try a.integer("nrts", min: 1) { return FdtdModelRun(model: model, scale: scale, nrts: n, nrtsGiven: true) }
        guard let n = defaultNrts(model, scale: scale) else {
            throw usage("\(model.rawValue) at scale \(formatG(scale)) has no default timestep count (check.sh's: patch at 1 and 5, notch at 1 and 3, kgcpw and ksma at 1)",
                        field: "--nrts", hint: "--nrts N")
        }
        return FdtdModelRun(model: model, scale: scale, nrts: n, nrtsGiven: false)
    }

    /// `--quiet PCT` (0 < PCT <= 1000) with its two dependents; they need `--quiet`.
    static func quietOptions(_ a: FdtdArguments, gpu: Bool) throws -> FdtdQuiet? {
        let pct = try a.number("quiet", "a CPU percentage in (0, 1000]", where: { $0 > 0 && $0 <= 1000 })
        var g: Double? = nil
        if gpu { g = try a.number("quiet-gpu", "a GPU percentage >= 0", where: { $0 >= 0 }) }
        let m = try a.number("quiet-max", "a number of seconds > 0", where: { $0 > 0 })
        guard let pct else {
            if g != nil { throw usage("--quiet-gpu needs --quiet PCT", field: "--quiet-gpu", hint: "--quiet 60") }
            if m != nil { throw usage("--quiet-max needs --quiet PCT", field: "--quiet-max", hint: "--quiet 60") }
            return nil
        }
        return FdtdQuiet(percent: pct, gpuPercent: g ?? 10, maxSeconds: m ?? 900)
    }

    /// `--tag T`: `[A-Za-z0-9_.][A-Za-z0-9_.-]*` (exit 2 tag_invalid otherwise). Each command calls it after its
    /// usage rules (bench after its --knob rules, in BenchCommand), so that a usage error (64) on the same line is
    /// the one reported.
    static func requireTag(_ tag: String?) throws {
        guard let t = tag, !isTag(t) else { return }
        let message = "--tag \(t): only letters, digits, '_', '.' and '-', and not '-' first"
        throw FdtdError(.tagInvalid, message, field: "--tag", hint: "e.g. --tag cg29")
    }

    static func bench(_ a: FdtdArguments, _ c: FdtdCommonOptions) throws -> FdtdBenchOptions {
        try requireSingleMac(c, "bench")
        let run = try modelRun(a, try benchModel(a.positionals[0]))
        let configs = a.all("config")
        guard !configs.isEmpty else {
            throw usage("bench needs --config CFG", field: "--config", hint: "--config multithreaded:4")
        }
        var o = FdtdBenchOptions(run: run, configs: configs)
        o.knobs = a.all("knob")
        o.repeatCount = try a.integer("repeat", min: 1) ?? 1
        o.quiet = try quietOptions(a, gpu: true)
        o.noSparams = a.flag("no-sparams")
        o.tag = a.value("tag")
        o.results = a.value("results")
        if o.results != nil, o.tag == nil { throw usage("--results needs --tag T", field: "--results", hint: "--tag T") }
        o.exact = a.flag("exact")
        if o.exact, configs.count < 2, o.repeatCount < 2 {
            throw usage("--exact needs two or more configs or --repeat 2 or more", field: "--exact", hint: "add a --config, or --repeat 2")
        }
        // the tag is checked by the command, after the usage rules of --knob against the configs
        return o
    }

    static func ab(_ a: FdtdArguments, _ c: FdtdCommonOptions) throws -> FdtdABOptions {
        try requireSingleMac(c, "ab")
        let run = try modelRun(a, try benchModel(a.positionals[0]))
        let configs = a.all("config")
        guard configs.count >= 2 else {
            throw usage("ab needs at least two --config CFG", field: "--config", hint: "--config A --config B")
        }
        var o = FdtdABOptions(run: run, configs: configs)
        o.knobs = a.all("knob")
        o.rounds = try a.integer("rounds", min: 1) ?? 5
        o.quiet = try quietOptions(a, gpu: false)
        o.redo = try a.integer("redo", min: 1)
        o.runRedo = try a.integer("run-redo", min: 1)
        if o.redo != nil, o.runRedo != nil {
            throw usage("--redo and --run-redo: give one of them", field: "--run-redo", hint: "--run-redo replaces --redo")
        }
        if o.runRedo != nil, o.quiet == nil {
            throw usage("--run-redo needs --quiet PCT > 0", field: "--run-redo", hint: "abtest.py redoes every run when --quiet is 0")
        }
        if o.redo != nil, o.quiet == nil {
            throw usage("--redo needs --quiet PCT > 0", field: "--redo", hint: "abtest.py never redoes a round when --quiet is 0")
        }
        o.record = a.value("record")
        o.append = a.flag("append")
        if o.append, o.record == nil { throw usage("--append needs --record FILE", field: "--append", hint: "--record FILE --append") }
        if o.record != nil, c.overwrite {
            throw usage("--overwrite does not apply to --record: abtest.py appends to the file", field: "--overwrite",
                        hint: "--append, or a new --record FILE")
        }
        o.exact = a.flag("exact")
        return o
    }

    static func check(_ a: FdtdArguments) throws -> FdtdCheckOptions {
        guard let t = a.value("tag") else {
            throw usage("check needs --tag T: check.sh writes results/MODEL_sS_nN_T.txt", field: "--tag", hint: "--tag T")
        }
        var o = FdtdCheckOptions(snapshots: a.positionals, tag: t)
        o.lite = a.flag("lite")
        o.stock = a.value("stock")
        o.extras = a.all("extra")
        o.quietMax = try a.number("quiet-max", "a number of seconds > 0", where: { $0 > 0 })
        if o.lite, o.quietMax != nil {
            throw usage("--quiet-max applies to the full check only: --lite runs without a quiet wait", field: "--quiet-max",
                        hint: "leave out --lite or --quiet-max")
        }
        o.allowPartial = a.flag("allow-partial")
        try requireTag(t)
        return o
    }

    static func validate(_ a: FdtdArguments) throws -> FdtdValidateOptions {
        var o = FdtdValidateOptions()
        o.lib = a.value("lib") ?? "installed"
        o.engine = a.value("engine")
        o.threads = try a.integer("threads", min: 0)
        o.quick = a.flag("quick")
        o.cases = try a.all("case").map { text in
            guard let c = FdtdValidationCase(rawValue: text) else {
                throw usage("--case \(text): expected slab, cavity or lines", field: "--case",
                            hint: nearest(text, among: FdtdValidationCase.allCases.map(\.rawValue)))
            }
            return c
        }
        o.knobs = a.all("knob")
        o.tag = a.value("tag")
        o.results = a.value("results")
        if o.results != nil, o.tag == nil { throw usage("--results needs --tag T", field: "--results", hint: "--tag T") }
        // a --knob that is not NAME=VALUE is a usage error, so it is found before the tag
        for text in o.knobs { _ = try FdtdKnobs.parse(text, field: "--knob") }
        try requireTag(o.tag)
        return o
    }

    static func e2e(_ a: FdtdArguments) throws -> FdtdE2EOptions {
        let text = a.positionals[0]
        guard let model = FdtdE2EModel(rawValue: text) else {
            throw usage("e2e runs gcpw or sma, not '\(text)' (run_one.py would run the SMA for any other name)", field: "MODEL",
                        hint: "gcpw or sma")
        }
        var o = FdtdE2EOptions(model: model)
        o.lib = a.value("lib") ?? "installed"
        o.engine = a.value("engine")
        if let f = a.value("floor") {
            guard model == .sma else {
                throw usage("--floor is the SMA mesh floor: sma only", field: "--floor", hint: "leave --floor out for gcpw")
            }
            if f == "toolkit" { o.floor = .toolkit }
            else if let v = Double(f), v.isFinite, v > 0 { o.floor = .value(v) }
            else { throw usage("--floor \(f): expected toolkit or a cell size in mm > 0", field: "--floor") }
        }
        if let p = a.value("probe-end") {
            switch p {
            case "toolkit": o.probeEnd = .toolkit
            case "off": o.probeEnd = .off
            default:
                guard let v = Double(p), v.isFinite else {
                    throw usage("--probe-end \(p): expected toolkit, off or a level in dB below 0", field: "--probe-end")
                }
                guard v < 0 else {
                    throw usage("--probe-end \(p): the level must be below 0 dB (core.run refuses positive values)",
                                field: "--probe-end", hint: v == 0 ? "--probe-end off" : "--probe-end -60")
                }
                o.probeEnd = .db(v)
            }
        }
        if let h = a.value("hold") {
            if h == "toolkit" { o.hold = .toolkit }
            else if let v = Double(h), v.isFinite, v > 0 { o.hold = .value(v) }
            else { throw usage("--hold \(h): expected toolkit or a number of excitation lengths > 0", field: "--hold") }
        }
        o.outDir = a.value("out-dir")
        o.knobs = a.all("knob")
        o.quiet = try quietOptions(a, gpu: true)
        return o
    }

    static func run(_ a: FdtdArguments) throws -> FdtdRunOptions {
        var o = FdtdRunOptions(script: a.positionals[0])
        o.scriptArguments = a.passthrough
        o.lib = a.value("lib") ?? "installed"
        o.engine = a.value("engine")
        o.threads = try a.integer("threads", min: 0)
        o.nodumps = a.flag("nodumps")
        o.knobs = a.all("knob")
        o.quiet = try quietOptions(a, gpu: true)
        return o
    }
}

// MARK: - Usage texts

enum FdtdUsage {
    static let overview = """
    usage: emskit fdtd COMMAND [options]        one JSON document on stdout; tool output and a summary on stderr
           emskit fdtd --version | --help | COMMAND --help

    commands:
      info           probes only: Python, the installed library and the snapshots (sha256, build UUID, engines,
                     knobs), build folders, rfsim, running simulations, the knob registry
      load           the other processes' CPU and GPU use over a few seconds (bench/usage.py)
      bench          bench/bench.py: time configs on one model and compare them bit for bit
      ab             bench/abtest.py: interleaved rounds, paired ratios to the first config
      check          bench/check.sh: snapshots against stock v0.37.0 on the benchmark models
      validate       the validation suite (bench/validation/run_validation.py)
      debye-check    scripts/checks/debye_check.sh
      diamond-check  scripts/checks/diamond_check.sh (cg28 or later)
      e2e            scripts/e2e/run_one.py: one full toolkit run, gcpw or sma
      run            any openEMS Python script, with engine, threads and nodumps set on every FDTD.Run

    exit: 0 ok or partial, 1 a check did not pass, 2 bad input, 3 not supported by that library or Python,
          4 a tool failed, 5 refused, 64 usage, 130 interrupted
    """

    static let common = """
    common options:
      --repo DIR  --python PATH  --snaps DIR  --rfsim DIR  --output FILE  --overwrite
    """

    static let runOptions = """
    run options:
      --runs DIR  --keep-runs  --dry-run  --no-caffeinate  --allow-concurrent
      --warn-cpu PCT (150)  --warn-gpu PCT (10): rows whose others' load exceeds these are marked loaded
      --nodes N | --hosts FILE  --distribute auto|off|frequencies|domain   (designed; v1 runs on this Mac)
    """

    /// The grammar line(s) of one command (spec 2).
    static func synopsis(_ command: FdtdCommandName) -> String {
        switch command {
        case .info:
            "emskit fdtd info [--lib LIB]... [--build DIR]... [common]"
        case .load:
            "emskit fdtd load [--seconds S] [--warn-cpu PCT] [--warn-gpu PCT] [common]"
        case .bench:
            """
            emskit fdtd bench MODEL --config CFG [--config CFG]... [--scale S] [--nrts N] [--knob K=V]... [--repeat R]
                              [--quiet PCT [--quiet-gpu PCT] [--quiet-max S]] [--no-sparams] [--tag T [--results DIR]]
                              [--exact] [common] [run options]
            """
        case .ab:
            """
            emskit fdtd ab MODEL --config CFG --config CFG [--config CFG]... [--scale S] [--nrts N] [--knob K=V]...
                           [--rounds R] [--quiet PCT [--quiet-max S] [--redo N | --run-redo N]] [--record FILE [--append]]
                           [--exact] [common] [run options]
            """
        case .check:
            """
            emskit fdtd check SNAP [SNAP]... --tag T [--lite] [--stock LIB] [--extra CFG]... [--quiet-max S]
                              [--allow-partial] [common] [run options]
            """
        case .validate:
            """
            emskit fdtd validate [--lib LIB] [--engine E] [--threads N] [--quick] [--case slab|cavity|lines]...
                                 [--knob K=V]... [--tag T [--results DIR]] [common] [run options]
            """
        case .debyeCheck:
            "emskit fdtd debye-check LIB [--ref LIB] [--threads N] [common] [run options]"
        case .diamondCheck:
            "emskit fdtd diamond-check LIB [common] [run options]"
        case .e2e:
            """
            emskit fdtd e2e gcpw|sma [--lib LIB] [--engine E] [--floor toolkit|MM] [--probe-end toolkit|off|DB]
                            [--hold toolkit|H] [--out-dir DIR] [--knob K=V]... [--quiet PCT [--quiet-gpu PCT]
                            [--quiet-max S]] [common] [run options]
            """
        case .run:
            """
            emskit fdtd run SCRIPT [--lib LIB] [--engine E] [--threads N] [--nodumps] [--knob K=V]...
                            [--quiet PCT [--quiet-gpu PCT] [--quiet-max S]] [common] [run options] [-- ARGS...]
            """
        }
    }

    /// What one command does, in a few lines.
    static func notes(_ command: FdtdCommandName) -> String {
        switch command {
        case .info:
            """
            The repo, Python (probed without a snapshot), the machine, the installed library and every snapshot (or
            only the --lib ones) with sha256, LC_UUID, engines and knobs, each --build DIR (CMakeCache.txt), rfsim,
            running simulations and the knob registry. No run folder.
            """
        case .load:
            "The other processes' CPU and GPU use over S seconds (1 to 600, default 5); exit 4 when the sampler saw nothing."
        case .bench:
            """
            MODEL: patch, notch, kgcpw, ksma (the two boards need rfsim). CFG: [LIB@]ENGINE[:THREADS][+nodumps][#K=V,...];
            the first CFG is the reference. --nrts defaults (check.sh): patch 10500 (scale 5: 1200), notch 16000
            (scale 3: 2000), kgcpw 15000, ksma 6000. --knob K=V goes into every CFG. --exact: every compared run
            bit-identical, tolerant ones included. --tag T writes RESULTS/MODEL_s%g_nN_T.txt (refused if it exists).
            """
        case .ab:
            """
            At least two CFGs, interleaved for --rounds R (default 5). --redo and --run-redo need --quiet > 0.
            --record FILE (default: in the run folder) must be new unless --append.
            """
        case .check:
            """
            SNAP: a complete snapshot, a folder or installed. The CPU acceptance only when the reference (--stock,
            default stock) is the stock v0.37.0 build in all three libraries; otherwise status partial.
            check.sh writes REPO/results/*_T.txt: refused when one exists, unless --overwrite (backups next to them).
            """
        case .validate:
            "--lib defaults to installed; --engine sets VALIDATION_ENGINE (default fastest), --threads VALIDATION_THREADS."
        case .debyeCheck:
            "Both folders must be fork builds (OPENEMS_EXPORT_FIELDS); --threads sets THREADS (default 4)."
        case .diamondCheck:
            "LIB must have metal-diamond and the tiling tuner (cg28 or later)."
        case .e2e:
            """
            The toolkit's own defaults unless given: --floor (sma only) 0 = toolkit, --probe-end and --hold from rfsim's
            core. Needs rfsim (--rfsim DIR or RFSIM_PATH). --out-dir DIR defaults to the run folder's e2e/.
            """
        case .run:
            """
            Runs SCRIPT as `python3 SCRIPT ARGS` would, with --engine, --threads and --nodumps injected into every
            FDTD.Run call (the script's own spellings of them are dropped and recorded).
            """
        }
    }

    /// `emskit fdtd COMMAND --help`.
    static func text(for command: FdtdCommandName) -> String {
        var parts = ["usage: " + synopsis(command), notes(command), common]
        if command.isRunCommand { parts.append(runOptions) }
        return parts.joined(separator: "\n\n") + "\n"
    }
}
