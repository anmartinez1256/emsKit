// SPDX-License-Identifier: GPL-3.0-or-later

// The envelope: one JSON document per call (spec section 7), its issue objects, and the family's JSON settings.
// Keys are camelCase, issue codes snake_case. Optionals marked @FdtdNullable are written as null (a withheld figure
// must show as null, not vanish); plain optionals are left out when nil.
import Foundation

/// Every issue code of spec section 9. The raw value is the code written in the envelope and on stderr.
enum FdtdCode: String, Codable, Sendable, CaseIterable {
    // exit 64
    case usage
    // exit 2: bad input
    case repoNotFound = "repo_not_found"
    case toolMissing = "tool_missing"
    case libraryNotFound = "library_not_found"
    case libraryIncomplete = "library_incomplete"
    case configInvalid = "config_invalid"
    case knobUnknown = "knob_unknown"
    case knobValue = "knob_value"
    case knobNotAllowed = "knob_not_allowed"
    case rfsimNotFound = "rfsim_not_found"
    case scriptNotFound = "script_not_found"
    case folderMissing = "folder_missing"
    case hostsFileMissing = "hosts_file_missing"
    case tagInvalid = "tag_invalid"
    case protectedPath = "protected_path"
    // exit 3: not supported by that library or Python
    case engineUnsupported = "engine_unsupported"
    case knobUnsupported = "knob_unsupported"
    case libraryLacksFeature = "library_lacks_feature"
    case pythonNotFound = "python_not_found"
    case pythonStripsDyld = "python_strips_dyld"
    case pythonNoOpenems = "python_no_openems"
    case pythonNameMismatch = "python_name_mismatch"
    // exit 4: runtime
    case toolFailed = "tool_failed"
    case toolOutputUnparsed = "tool_output_unparsed"
    case engineNotConfirmed = "engine_not_confirmed"
    case libraryNotLoaded = "library_not_loaded"
    case verdictDisagrees = "verdict_disagrees"
    case spawnFailed = "spawn_failed"
    case launcherFailed = "launcher_failed"
    case loadUnavailable = "load_unavailable"
    // exit 1: the tool ran and its verdict did not pass
    case mismatch
    case notExact = "not_exact"
    case checkFailed = "check_failed"
    case validationFailed = "validation_failed"
    case scriptCheckFailed = "script_check_failed"
    case scriptFailed = "script_failed"
    // exit 5 as errors; simulation_running and concurrency_unknown are warnings on the commands that only warn
    case simulationRunning = "simulation_running"
    case concurrencyUnknown = "concurrency_unknown"
    case wouldOverwrite = "would_overwrite"
    // exit 130
    case interrupted
    // warnings only
    case envRemoved = "env_removed"
    case pythonEnvKept = "python_env_kept"
    case rfsimEnv = "rfsim_env"
    case toolsModified = "tools_modified"
    case toolsTreeSkipped = "tools_tree_skipped"
    case pythonSkipped = "python_skipped"
    case knobNoEffect = "knob_no_effect"
    case knobIgnored = "knob_ignored"
    case notBitIdenticalToStock = "not_bit_identical_to_stock"
    case nothingVerified = "nothing_verified"
    case tolerantRows = "tolerant_rows"
    case extraNotCounted = "extra_not_counted"
    case referenceNotStock = "reference_not_stock"
    case gpuFallback = "gpu_fallback"
    case loadedMac = "loaded_mac"
    case loadMissing = "load_missing"
    case quietWaitTimedOut = "quiet_wait_timed_out"
    case distributeLocal = "distribute_local"
    case frequenciesNotApplicable = "frequencies_not_applicable"
    case optionOverridden = "option_overridden"
    case optionsLost = "options_lost"
    case engineNotObservable = "engine_not_observable"
    case noOpenemsCall = "no_openems_call"
    case partial
    case outputBackedUp = "output_backed_up"
    case buildInstallsOverPrefix = "build_installs_over_prefix"
    case caffeinateFailed = "caffeinate_failed"
    case reportRebuilt = "report_rebuilt"
    case killed
}

/// One warning or error: sbrKit's fields {code, message, field, hint} in momKit's object form.
struct FdtdIssue: Codable, Sendable, Equatable, CustomStringConvertible {
    var code: FdtdCode
    var message: String
    var field: String?
    var hint: String?

    init(_ code: FdtdCode, _ message: String, field: String? = nil, hint: String? = nil) {
        self.code = code; self.message = message; self.field = field; self.hint = hint
    }

    /// `CODE: MESSAGE (hint: HINT)`, sbr's format (spec 8).
    var description: String { "\(code.rawValue): \(message)" + (hint.map { " (hint: \($0))" } ?? "") }
    /// The stderr line, the same for warnings and errors.
    var stderrLine: String { "emskit fdtd: " + description }
}

/// The envelope's `status`; the exit code decides it (FdtdExit in FdtdKit.swift).
enum FdtdStatus: String, Codable, Sendable { case ok, partial, fail, error, refused, interrupted }

/// An optional written as JSON null instead of being left out.
@propertyWrapper
struct FdtdNullable<Value: Codable & Sendable>: Codable, Sendable {
    var wrappedValue: Value?
    init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { wrappedValue = nil } else { wrappedValue = try c.decode(Value.self) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}
extension FdtdNullable: Equatable where Value: Equatable {}
extension KeyedDecodingContainer {
    /// A missing key reads as nil, as it does for a plain optional.
    func decode<V>(_ type: FdtdNullable<V>.Type, forKey key: Key) throws -> FdtdNullable<V> {
        try decodeIfPresent(type, forKey: key) ?? FdtdNullable(wrappedValue: nil)
    }
}

/// Any JSON value, for tool output the CLI passes on (RESULT, result.json, the suite's timings).
enum FdtdJSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([FdtdJSONValue])
    case object([String: FdtdJSONValue])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([FdtdJSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: FdtdJSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var double: Double? {
        if case .number(let d) = self { return d }
        return nil
    }
    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    var object: [String: FdtdJSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    var array: [FdtdJSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    subscript(key: String) -> FdtdJSONValue? { object?[key] }
}

/// The family's JSON settings: pretty-printed, sorted keys, inf/-inf/nan as strings; tool JSON is read as JSON5
/// because Python's json writes NaN and Infinity (F21).
enum FdtdJSON {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data { try encoder().encode(value) }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.allowsJSON5 = true
        return d
    }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T { try decoder().decode(type, from: data) }
}

/// A command's `result`, type-erased so that each command keeps its own result struct (Commands/*.swift).
struct FdtdAnyResult: Encodable, Sendable {
    let value: any Encodable & Sendable
    init(_ value: any Encodable & Sendable) { self.value = value }
    func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}

/// `repo`: the tools tree (spec 3.1).
struct FdtdRepo: Codable, Sendable, Equatable {
    var root: String
    @FdtdNullable var head: String? = nil
    @FdtdNullable var dirty: Bool? = nil
    var toolsModified: [String] = []
}

/// `python`: the interpreter for every Python child and what its probe found (spec 3.2).
struct FdtdPython: Codable, Sendable, Equatable {
    var path: String
    @FdtdNullable var realPath: String? = nil
    @FdtdNullable var version: String? = nil
    @FdtdNullable var dyldKept: Bool? = nil
    @FdtdNullable var openemsModule: String? = nil
    @FdtdNullable var openemsVersion: String? = nil
    @FdtdNullable var legacyEmptyOption: Bool? = nil
    @FdtdNullable var numpy: String? = nil
}

/// How a library was named (spec 4.1); `build` is an `info --build DIR`.
enum FdtdLibraryKind: String, Codable, Sendable { case installed, snapshot, path, build }

/// One of a library folder's three files (spec 4.2).
struct FdtdLibraryFile: Codable, Sendable, Equatable {
    var name: String
    /// The real path (symlinks resolved).
    var path: String
    @FdtdNullable var sha256: String? = nil
    @FdtdNullable var bytes: Int? = nil
    /// LC_UUID of the arm64 image, uppercase with dashes.
    @FdtdNullable var uuid: String? = nil
    /// Snapshots whose file of this name has the same sha256 / the same LC_UUID.
    var sameBytes: [String] = []
    var sameBuild: [String] = []
}

/// The identity record of a library folder (spec 4.2, `FdtdLibrary`).
struct FdtdLibrary: Codable, Sendable, Equatable {
    var spec: String
    var kind: FdtdLibraryKind
    var dir: String
    var complete: Bool
    var files: [FdtdLibraryFile] = []
    /// Informational only: version strings can be stale (F7).
    @FdtdNullable var versionString: String? = nil
    var engines: [String] = []
    var knobs: [String] = []
    /// Snapshots whose libopenEMS has the same sha256 / the same LC_UUID.
    var sameBytes: [String] = []
    var sameBuild: [String] = []
    /// Only when sameBuild is empty: snapshots with the same version string, knob set and engine set.
    var candidates: [String] = []
    @FdtdNullable var note: String? = nil

    func file(_ name: String) -> FdtdLibraryFile? { files.first { $0.name == name } }
}

/// A file named by identity: jobs and check's reference carry these instead of host paths.
struct FdtdFileIdentity: Codable, Sendable, Equatable {
    var name: String
    @FdtdNullable var sha256: String? = nil
    @FdtdNullable var uuid: String? = nil
}

/// `rfsim`: the toolkit folder and the defaults its probe read (spec 3.4).
struct FdtdRfsim: Codable, Sendable, Equatable {
    var path: String
    @FdtdNullable var head: String? = nil
    @FdtdNullable var rfsimCommit: String? = nil
    @FdtdNullable var dirty: Bool? = nil
    @FdtdNullable var probeEndDb: Double? = nil
    @FdtdNullable var probeEndHold: Double? = nil
    @FdtdNullable var zMult: Double? = nil
    @FdtdNullable var minCell: Double? = nil
    @FdtdNullable var minCellEffective: Double? = nil
    var env: [String: String] = [:]
}

/// `distribution`: fem's mode/nodes/reason plus requested/hosts (spec 12). v1 always runs locally.
struct FdtdDistribution: Codable, Sendable, Equatable {
    var requested: String
    var mode: String = "off"
    var nodes: Int = 1
    @FdtdNullable var hosts: String? = nil
    var reason: String
}

/// What the concurrency scans decided (spec 11). `noneFound` is written as "none" (a case named `none` would be
/// confused with Optional.none).
enum FdtdConcurrencyResult: String, Codable, Sendable { case noneFound = "none", found, unknown }

/// Another process holding an openEMS library.
struct FdtdConcurrentProcess: Codable, Sendable, Equatable {
    var pid: Int32
    @FdtdNullable var command: String? = nil
    var libraries: [String] = []
}

/// One lsof scan as it ran.
struct FdtdConcurrencyScan: Codable, Sendable, Equatable {
    var argv: [String]
    @FdtdNullable var exit: Int32? = nil
    var records: Int = 0
}

/// `concurrent`: what the scans found at the start.
struct FdtdConcurrent: Codable, Sendable, Equatable {
    var result: FdtdConcurrencyResult
    var processes: [FdtdConcurrentProcess] = []
    var scans: [FdtdConcurrencyScan] = []
}

/// A removed environment variable.
struct FdtdEnvEntry: Codable, Sendable, Equatable {
    var name: String
    var value: String
}

/// The role of a child process (spec 5.2); the launcher report of role R is RUN/launcher-R.json.
enum FdtdRole: String, Codable, Sendable, CaseIterable {
    case pythonProbe = "python-probe", zshProbe = "zsh-probe", rfsimProbe = "rfsim-probe", git, lsof, ps
    case samplerCheck = "sampler-check", quiet, load, caffeinate
    case bench, ab, check, validate, debye, diamond, e2e, run
}

/// One child as resolved and as it ran: the backend's resolved invocation and the envelope's record in one type.
/// `environment` (the full child environment) and `controlPipe` are not written; the record shows envSet/envRemoved.
struct FdtdInvocation: Codable, Sendable, Equatable {
    var role: FdtdRole
    @FdtdNullable var jobId: String? = nil
    var argv: [String]
    var cwd: String
    /// Only the variables the CLI set or changed.
    var envSet: [String: String] = [:]
    var envRemoved: [FdtdEnvEntry] = []
    @FdtdNullable var exit: Int32? = nil
    /// Bookkeeping, not a performance figure: never printed on stderr.
    @FdtdNullable var seconds: Double? = nil
    var ran = false
    var interrupted = false
    var host = "local"
    var environment: [String: String] = [:]
    /// The child gets the control pipe's read end on fd 3 (launcher children).
    var controlPipe = false

    enum CodingKeys: String, CodingKey { case role, jobId, argv, cwd, envSet, envRemoved, exit, seconds, ran, interrupted }
}

/// Where a load reading came from (spec 7).
enum FdtdLoadSource: String, Codable, Sendable {
    case sampler = "usage.Sampler", benchRow = "bench row", abtestLine = "abtest line"
}

/// The other processes' (and the run's own) CPU and GPU use during a run (spec 7, FdtdLoad). Percent: 100 = one core.
struct FdtdLoad: Codable, Sendable, Equatable {
    @FdtdNullable var wallSeconds: Double? = nil
    @FdtdNullable var selfCpuPercent: Double? = nil
    @FdtdNullable var selfGpuPercent: Double? = nil
    @FdtdNullable var selfGpuSecondsAtLeast: Double? = nil
    @FdtdNullable var othersCpuPercent: Double? = nil
    @FdtdNullable var othersGpuPercent: Double? = nil
    @FdtdNullable var gpuDevicePercent: Double? = nil
    var busy: [String] = []
    /// From the launcher or the LOAD helper; null for parsed rows.
    @FdtdNullable var processesSeen: Int? = nil
    @FdtdNullable var gpuClientsSeen: Int? = nil
    @FdtdNullable var utilSamples: Int? = nil
    var source: FdtdLoadSource
    var valid: Bool
    @FdtdNullable var invalidReason: String? = nil
    /// Others above --warn-cpu / --warn-gpu: marks the figure, never blocks.
    var loaded = false
}

/// A named output and its protection (spec 10).
struct FdtdOutput: Codable, Sendable, Equatable {
    var path: String
    @FdtdNullable var sha256: String? = nil
    var existedBefore: Bool
    var backup: String? = nil
}

/// `timing`: bookkeeping durations, not performance figures.
struct FdtdTiming: Codable, Sendable, Equatable {
    /// ISO 8601 with the local offset.
    var startedAt = ""
    var wallSeconds = 0.0
    var probeSeconds = 0.0
    var toolSeconds = 0.0
}

/// The one JSON document a command prints (spec 7). Every key is written; nil ones as null.
struct FdtdEnvelope: Encodable, Sendable {
    var schema: String
    var tool = "emskit"
    var kit = "fdtd"
    var version = FdtdKitInfo.version
    var command: String
    /// The arguments after `fdtd`, as given (the command included).
    var arguments: [String]
    var status: FdtdStatus = .ok
    var dryRun = false
    var warnings: [FdtdIssue] = []
    var errors: [FdtdIssue] = []
    var repo: FdtdRepo? = nil
    var python: FdtdPython? = nil
    var libraries: [FdtdLibrary] = []
    var rfsim: FdtdRfsim? = nil
    var distribution: FdtdDistribution? = nil
    var concurrent: FdtdConcurrent? = nil
    var jobs: [FdtdJob] = []
    var invocations: [FdtdInvocation] = []
    var result: FdtdAnyResult? = nil
    var load: FdtdLoad? = nil
    var runFolder: String? = nil
    var keptRuns = false
    var outputs: [FdtdOutput] = []
    var timing = FdtdTiming()

    init(command: FdtdCommandName, arguments: [String]) {
        schema = FdtdEnvelope.schema(command)
        self.command = command.rawValue
        self.arguments = arguments
    }

    /// `emskit.fdtd.<command>/1`.
    static func schema(_ command: FdtdCommandName) -> String { "emskit.fdtd.\(command.rawValue)/1" }

    enum CodingKeys: String, CodingKey {
        case schema, tool, kit, version, command, arguments, status, dryRun, warnings, errors, repo, python, libraries
        case rfsim, distribution, concurrent, jobs, invocations, result, load, runFolder, keptRuns, outputs, timing
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(tool, forKey: .tool)
        try c.encode(kit, forKey: .kit)
        try c.encode(version, forKey: .version)
        try c.encode(command, forKey: .command)
        try c.encode(arguments, forKey: .arguments)
        try c.encode(status, forKey: .status)
        try c.encode(dryRun, forKey: .dryRun)
        try c.encode(warnings, forKey: .warnings)
        try c.encode(errors, forKey: .errors)
        try c.encode(repo, forKey: .repo)               // an Optional encodes nil as null here
        try c.encode(python, forKey: .python)
        try c.encode(libraries, forKey: .libraries)
        try c.encode(rfsim, forKey: .rfsim)
        try c.encode(distribution, forKey: .distribution)
        try c.encode(concurrent, forKey: .concurrent)
        try c.encode(jobs, forKey: .jobs)
        try c.encode(invocations, forKey: .invocations)
        try c.encode(result, forKey: .result)
        try c.encode(load, forKey: .load)
        try c.encode(runFolder, forKey: .runFolder)
        try c.encode(keptRuns, forKey: .keptRuns)
        try c.encode(outputs, forKey: .outputs)
        try c.encode(timing, forKey: .timing)
    }
}
