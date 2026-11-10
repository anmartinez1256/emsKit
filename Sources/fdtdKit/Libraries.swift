// SPDX-License-Identifier: GPL-3.0-or-later

// Libraries (spec 4.1, 4.2): LIB resolution and completeness, the identity record (streamed sha256, the Mach-O
// LC_UUID read in Swift because otool is an xcrun stub here, F1), byte scans for the version string, the engines' help
// strings and the knob names, sameBytes/sameBuild/candidates against the snapshots, the stock identity test of check,
// and build folders (CMakeCache.txt). Version strings are informational only (F7): identity is sha256 or LC_UUID.
import Foundation
import CryptoKit

/// Where a LIB form points (spec 4.1), before its files are read.
struct FdtdLibraryLocation: Sendable, Equatable {
    var spec: String
    var kind: FdtdLibraryKind
    var dir: String
    var complete: Bool
    /// The `.0.dylib` names missing from `dir`.
    var missing: [String] = []
}

/// One subfolder of SNAPS and the identity of its files.
struct FdtdSnapshotEntry: Sendable, Equatable {
    var name: String
    var dir: String
    var complete: Bool
    /// By file name.
    var files: [String: FdtdFileIdentity] = [:]
    /// By file name: the bytes read, or the size when the file could not be read.
    var bytes: [String: Int] = [:]
    var versionString: String? = nil
    var engines: [String] = []
    var knobs: [String] = []
    /// Every registry name in libopenEMS or libnf2ff, whichever file it belongs to (the stock scan's stricter test).
    var registryNames: Set<String> = []
}

/// SNAPS, read once per command (FdtdSession.snapshotIndex).
struct FdtdSnapshotIndex: Sendable, Equatable {
    var folder: String
    var entries: [FdtdSnapshotEntry] = []

    /// The entry of the folder `dir`, when the index holds it: the one rule by which a record is taken from the
    /// index instead of the files (FdtdLibraries.record, stockScan). Only the same bytes count: String == compares
    /// canonically, so a name typed in another Unicode form would find an entry whose path differs from the one asked.
    func entry(at dir: String) -> FdtdSnapshotEntry? { entries.first { $0.dir.utf8.elementsEqual(dir.utf8) } }
}

/// The stock scan of SNAPS/stock (spec 2.6): versionString exactly v0.37.0, exactly the five CPU engines, no registry
/// knob in libopenEMS or libnf2ff.
struct FdtdStockScan: Codable, Sendable, Equatable {
    var dir: String
    var exists: Bool
    @FdtdNullable var versionString: String? = nil
    var engines: [String] = []
    var knobs: [String] = []
    var passed: Bool
    @FdtdNullable var reason: String? = nil
}

/// How a check reference compares with SNAPS/stock: every one of the three files must have the stock file's LC_UUID
/// (same build) or sha256 (same bytes).
struct FdtdStockMatch: Sendable, Equatable {
    /// "uuid", "sha256" or nil (the result's matchedBy).
    var matchedBy: String?
    /// The scan passed and every file matched.
    var acceptance: Bool
    /// The reference's three files by identity.
    var files: [FdtdFileIdentity]
}

/// An `info --build DIR` entry (spec 2.2): DIR/libopenEMS.0.dylib and DIR/nf2ff/libnf2ff.0.dylib, and three
/// CMakeCache.txt values.
struct FdtdBuildInfo: Codable, Sendable, Equatable {
    var dir: String
    @FdtdNullable var installPrefix: String? = nil
    @FdtdNullable var enableMetal: String? = nil
    @FdtdNullable var buildType: String? = nil
    @FdtdNullable var library: FdtdLibrary? = nil
}

/// LIB resolution, identity and scans.
enum FdtdLibraries {
    /// A library folder holds these three files.
    static let fileNames = ["libopenEMS.0.dylib", "libCSXCAD.0.dylib", "libnf2ff.0.dylib"]
    static let openEMSFile = "libopenEMS.0.dylib"
    static let nf2ffFile = "libnf2ff.0.dylib"
    /// The streamed hash's chunk size.
    static let chunkSize = 1 << 20

    /// LC_UUID, and CPU_TYPE_ARM | CPU_ARCH_ABI64.
    private static let loadCommandUUID: UInt32 = 0x1b
    private static let cpuTypeARM64: UInt32 = 0x0100_000c
    /// The arm64e cpusubtype (without the capability bits), taken only when a fat file has no plain arm64 slice.
    private static let cpuSubtypeARM64E: UInt32 = 2
    private static let digits = Set("0123456789".utf8)
    private static let lowerHex = Set("0123456789abcdef".utf8)
    private static let identifierBytes = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_".utf8)
    /// The byte offsets before which the 8-4-4-4-12 form has a dash.
    private static let uuidDashes: Set<Int> = [4, 6, 8, 10]

    /// A file read once: its sha256, its size and, when asked, its bytes.
    private struct Streamed {
        var sha256: String
        var bytes: Int
        var data: Data?
    }

    /// Whether locate reads `spec` as a snapshot name (a folder in SNAPS): no '/', not `installed`, not empty, `.`
    /// or `..`, and no leading '-'. `~` alone is a name too: only a path is expanded.
    static func isSnapshotName(_ spec: String) -> Bool {
        !spec.contains("/") && !spec.hasPrefix("-") && !["installed", "", ".", ".."].contains(spec)
    }

    /// A LIB form: `installed` (installedDir, from the probe), a snapshot name under SNAPS (the name `installed` is
    /// reserved), or a path containing '/'. A LIB that starts with '-' (hint: the same folder by its path) or a
    /// missing folder → 2 library_not_found; an incomplete one comes back with complete false (requireComplete
    /// refuses it).
    static func locate(_ spec: String, snaps: String, installedDir: String?, cwd: String, home: String,
                       system: any FdtdSystem) throws -> FdtdLibraryLocation {
        // check.sh hands snapshot names to bench.py, whose argparse reads such a value as an option and exits before
        // it prints anything; the rule holds for every LIB form and command, so that all of them read alike
        guard !spec.hasPrefix("-") else {
            // a name is a folder in SNAPS, a relative path one below the cwd
            let byPath = spec.contains("/") ? "./" + spec : FdtdPaths.join(snaps, spec)
            throw FdtdError(.libraryNotFound,
                            "LIB \(spec) starts with '-': bench.py's argparse would read such a name as an option "
                                + "(check.sh hands snapshot names to it), so no LIB may start with '-'",
                            hint: "the folder by its path, \(byPath)")
        }
        let kind: FdtdLibraryKind
        let dir: String
        if spec == "installed" {
            guard let installedDir else {
                throw FdtdError(.libraryNotFound,
                                "installed names no folder: the python probe loaded no libopenEMS without a snapshot",
                                hint: "emskit fdtd info")
            }
            kind = .installed
            dir = installedDir
        } else if spec.contains("/") {
            kind = .path
            dir = FdtdPaths.absolute(spec, cwd: cwd, home: home)
        } else {
            guard !spec.isEmpty, spec != ".", spec != ".." else {
                throw FdtdError(.libraryNotFound, "\"\(spec)\" is not a snapshot name", hint: "emskit fdtd info")
            }
            kind = .snapshot
            dir = FdtdPaths.join(snaps, spec)
        }
        guard system.isDirectory(dir) else {
            let what = kind == .snapshot ? "no snapshot \(spec) in \(snaps)" : "\(spec): \(dir) is not a folder"
            throw FdtdError(.libraryNotFound, what, hint: kind == .snapshot ? "emskit fdtd info" : nil)
        }
        let missing = fileNames.filter { !system.isRegularFile(FdtdPaths.join(dir, $0)) }
        return FdtdLibraryLocation(spec: spec, kind: kind, dir: dir, complete: missing.isEmpty, missing: missing)
    }

    /// 2 library_incomplete listing the missing files (F8).
    static func requireComplete(_ location: FdtdLibraryLocation) throws {
        guard !location.complete else { return }
        // dyld would take the installed copy of a missing file without a message (F8).
        let list = location.missing.joined(separator: ", ")
        var message = "\(location.spec) is incomplete: \(location.dir) lacks \(list)"
        // the installed folder is the real folder of the loaded libopenEMS (FdtdDiscovery.installedDir)
        if location.kind == .installed { message += " (the three files must lie in the one real folder of libopenEMS)" }
        throw FdtdError(.libraryIncomplete, message, hint: "emskit fdtd info")
    }

    /// bench.py's rule for a LIB@ folder (check_loaded), for bench, ab and check: after each run it takes the real
    /// path of every loaded library and wants it inside the real folder, so a folder whose names are links to
    /// files in another folder would fail after the first simulation. 2 library_incomplete before anything runs.
    /// validate, e2e and run accept such a folder (FdtdDiscovery.lies). The installed library is not held to it.
    static func requireOwnFiles(_ library: FdtdLibrary, field: String?, system: any FdtdSystem) throws {
        guard library.kind != .installed else { return }
        let folder = (system.realPath(library.dir) ?? library.dir) + "/"
        for name in fileNames {
            let path = FdtdPaths.join(library.dir, name)
            guard let real = system.realPath(path), !real.hasPrefix(folder) else { continue }
            let message = "\(library.spec): \(path) leads to \(real), outside the folder; bench.py takes a library "
                + "only when its three files lie in the folder itself"
            throw FdtdError(.libraryIncomplete, message, field: field,
                            hint: "a folder that holds the three files (copies, or links inside the folder)")
        }
    }

    /// Every subfolder of SNAPS with its files' sha256 and LC_UUID, version string, engines and knobs.
    static func index(snaps: String, system: any FdtdSystem) -> FdtdSnapshotIndex {
        var index = FdtdSnapshotIndex(folder: snaps)
        guard let names = system.listDirectory(snaps) else { return index }
        for name in names {
            let dir = FdtdPaths.join(snaps, name)
            guard !name.hasPrefix("."), system.isDirectory(dir) else { continue }
            index.entries.append(snapshotEntry(name: name, dir: dir, system: system))
        }
        return index
    }

    /// The identity record of a location (spec 4.2): files with real path, sha256, bytes, uuid, sameBytes and
    /// sameBuild; versionString, engines, knobs; sameBytes, sameBuild and (only when sameBuild is empty) candidates of
    /// its libopenEMS; a note such as "same build as cg18 (UUID), other bytes (installed copy)".
    static func identify(_ location: FdtdLibraryLocation, index: FdtdSnapshotIndex, system: any FdtdSystem) -> FdtdLibrary {
        var library = FdtdLibrary(spec: location.spec, kind: location.kind, dir: location.dir,
                                  complete: location.complete)
        var openEMSData: Data? = nil
        var nf2ffData: Data? = nil
        for name in fileNames {
            let path = FdtdPaths.join(location.dir, name)
            guard system.isRegularFile(path) else { continue }
            let read = stream(path, keep: true, system: system)
            library.files.append(fileRecord(name: name, path: path, read: read, index: index, system: system))
            if name == openEMSFile { openEMSData = read?.data }
            if name == nf2ffFile { nf2ffData = read?.data }
        }
        fill(&library, openEMS: openEMSData, nf2ff: nf2ffData, index: index, system: system)
        return library
    }

    /// The identity record of a location, from the index when it holds the location's folder (a snapshot by its
    /// name or by its path), else from the files: every command takes its records here, so a folder that the index
    /// has read is never read and hashed a second time.
    static func record(_ location: FdtdLibraryLocation, index: FdtdSnapshotIndex,
                       system: any FdtdSystem) -> FdtdLibrary {
        guard let entry = index.entry(at: location.dir) else {
            return identify(location, index: index, system: system)
        }
        return identify(entry, as: location, index: index, system: system)
    }

    /// The identity record of a snapshot folder from its index entry: the record identify gives for that folder
    /// (its name as the spec, or the spec and kind of `location`, which names the same folder), without reading and
    /// scanning its files a second time.
    static func identify(_ entry: FdtdSnapshotEntry, as location: FdtdLibraryLocation? = nil,
                         index: FdtdSnapshotIndex, system: any FdtdSystem) -> FdtdLibrary {
        var library = FdtdLibrary(spec: location?.spec ?? entry.name, kind: location?.kind ?? .snapshot,
                                  dir: entry.dir, complete: entry.complete)
        for name in fileNames {
            guard let identity = entry.files[name] else { continue }
            library.files.append(fileRecord(identity, path: FdtdPaths.join(entry.dir, name), bytes: entry.bytes[name],
                                            index: index, system: system))
        }
        library.versionString = entry.versionString
        library.engines = entry.engines
        library.knobs = entry.knobs
        compare(&library, index: index, system: system)
        return library
    }

    /// An `info --build DIR`: the two files' identities, CMAKE_INSTALL_PREFIX, ENABLE_METAL and CMAKE_BUILD_TYPE, and
    /// the warning build_installs_over_prefix when that prefix holds the installed library.
    static func readBuild(_ dir: String, installedDir: String?, index: FdtdSnapshotIndex, system: any FdtdSystem,
                          warnings: inout [FdtdIssue]) -> FdtdBuildInfo {
        var info = FdtdBuildInfo(dir: dir)
        guard system.isDirectory(dir) else {
            warnings.append(FdtdIssue(.folderMissing, "--build \(dir) is not a folder", field: "--build"))
            return info
        }
        if let data = system.readFile(FdtdPaths.join(dir, "CMakeCache.txt")) {
            let values = cmakeValues(String(decoding: data, as: UTF8.self))
            info.installPrefix = values["CMAKE_INSTALL_PREFIX"]
            info.enableMetal = values["ENABLE_METAL"]
            info.buildType = values["CMAKE_BUILD_TYPE"]
        } else {
            warnings.append(FdtdIssue(.folderMissing, "--build \(dir) has no CMakeCache.txt", field: "--build"))
        }
        // A build folder keeps libnf2ff in its nf2ff/ subfolder; libCSXCAD is built elsewhere.
        let paths = [(openEMSFile, FdtdPaths.join(dir, openEMSFile)),
                     (nf2ffFile, FdtdPaths.join(FdtdPaths.join(dir, "nf2ff"), nf2ffFile))]
        var library = FdtdLibrary(spec: dir, kind: .build, dir: dir, complete: true)
        var openEMSData: Data? = nil
        var nf2ffData: Data? = nil
        for (name, path) in paths {
            guard system.isRegularFile(path) else {
                library.complete = false
                warnings.append(FdtdIssue(.libraryNotFound, "--build \(dir) has no \(path)", field: "--build"))
                continue
            }
            let read = stream(path, keep: true, system: system)
            library.files.append(fileRecord(name: name, path: path, read: read, index: index, system: system))
            if name == openEMSFile { openEMSData = read?.data }
            if name == nf2ffFile { nf2ffData = read?.data }
        }
        if !library.files.isEmpty {
            fill(&library, openEMS: openEMSData, nf2ff: nf2ffData, index: index, system: system)
            info.library = library
        }
        if let prefix = info.installPrefix, !prefix.isEmpty, let installedDir {
            let prefixReal = system.realPath(prefix) ?? prefix
            let installedReal = system.realPath(installedDir) ?? installedDir
            let base = prefixReal.hasSuffix("/") ? prefixReal : prefixReal + "/"
            if installedReal == prefixReal || installedReal.hasPrefix(base) {
                let message = "cmake --install of \(dir) writes into \(prefix), "
                    + "which holds the installed library \(installedDir)"
                warnings.append(FdtdIssue(.buildInstallsOverPrefix, message, field: "--build",
                                          hint: "cp -a \(prefix) \(prefix).backup"))
            }
        }
        return info
    }

    /// sha256 as lowercase hex, streamed in chunkSize pieces through system.readChunks; nil when unreadable.
    static func sha256(path: String, system: any FdtdSystem) -> String? {
        stream(path, keep: false, system: system)?.sha256
    }

    /// sha256 of bytes in memory (the launcher copy, small outputs), lowercase hex.
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// LC_UUID (load command 0x1b) of a thin arm64 Mach-O, or of the arm64 slice of a fat one, as uppercase
    /// 8-4-4-4-12 hex; nil without one.
    static func machOUUID(_ data: Data) -> String? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String? in
            guard let magic = FdtdLibraries.bigEndian32(raw, 0) else { return nil }
            // Fat headers are big-endian: FAT_MAGIC and FAT_MAGIC_64.
            if magic == 0xcafe_babe || magic == 0xcafe_babf {
                guard let slice = FdtdLibraries.arm64Slice(raw, wide: magic == 0xcafe_babf) else { return nil }
                return FdtdLibraries.thinUUID(raw, start: slice.lowerBound, end: slice.upperBound)
            }
            return FdtdLibraries.thinUUID(raw, start: 0, end: raw.count)
        }
    }

    /// `\0(v0\.\d+\.\d+(?:-\d+-g[0-9a-f]+)?(?:-dirty)?)\0` in the libopenEMS bytes.
    static func versionString(in data: Data) -> String? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String? in
            let needle = Array("v0.".utf8)
            // Searching for "v0." and testing the byte before is much faster than a needle that starts with NUL.
            var from = 1
            while let hit = FdtdLibraries.firstOffset(of: needle, in: raw, from: from) {
                from = hit + 1
                guard raw[hit - 1] == 0, let end = FdtdLibraries.versionEnd(raw, start: hit) else { continue }
                return String(decoding: raw[hit..<end], as: UTF8.self)
            }
            return nil
        }
    }

    /// The engines whose help string `"  NAME: \t"` occurs, in FdtdEngine order.
    static func engines(in data: Data) -> [String] {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [String] in
            FdtdEngine.allCases.filter { (engine: FdtdEngine) -> Bool in
                FdtdLibraries.firstOffset(of: Array(engine.helpString.utf8), in: raw, from: 0) != nil
            }.map(\.rawValue)
        }
    }

    /// The registry names that occur as bytes: NF2FF_LEGACY in libnf2ff, the others in libopenEMS.
    static func knobs(openEMS: Data, nf2ff: Data?) -> [String] {
        let inOpenEMS = registryNames(in: openEMS)
        let inNf2ff: Set<String> = nf2ff.map { FdtdLibraries.registryNames(in: $0) } ?? []
        return FdtdKnobs.registry.filter { (knob: FdtdKnob) -> Bool in
            knob.libraryFile == FdtdLibraries.nf2ffFile ? inNf2ff.contains(knob.name) : inOpenEMS.contains(knob.name)
        }.map(\.name)
    }

    /// Whether `data` contains the UTF-8 bytes of `needle`.
    static func contains(_ data: Data, _ needle: String) -> Bool { data.range(of: Data(needle.utf8)) != nil }

    /// The stock scan of SNAPS/stock, from its index entry (the files are read again only when `index` does not hold
    /// that folder).
    static func stockScan(snaps: String, index: FdtdSnapshotIndex, system: any FdtdSystem) -> FdtdStockScan {
        let dir = FdtdPaths.join(snaps, "stock")
        guard system.isDirectory(dir) else {
            return FdtdStockScan(dir: dir, exists: false, passed: false, reason: "\(dir) is not a folder")
        }
        let entry = index.entry(at: dir) ?? snapshotEntry(name: "stock", dir: dir, system: system)
        var scan = FdtdStockScan(dir: dir, exists: true, passed: false)
        var reasons: [String] = []
        let missing = fileNames.filter { entry.files[$0] == nil }
        if !missing.isEmpty { reasons.append("it lacks " + missing.joined(separator: ", ")) }
        // a file that could not be read has an identity without sha256
        if entry.files[openEMSFile]?.sha256 != nil {
            scan.versionString = entry.versionString
            scan.engines = entry.engines
            // Unlike the identity record, stock must hold no registry name in either file.
            scan.knobs = FdtdKnobs.registry.map(\.name).filter { entry.registryNames.contains($0) }
            if scan.versionString != "v0.37.0" {
                reasons.append("its version string is \(scan.versionString ?? "absent"), not v0.37.0")
            }
            if Set(scan.engines) != Set(FdtdEngine.cpuEngines.map(\.rawValue)) {
                reasons.append("its engines are \(scan.engines.joined(separator: ", ")), not the five CPU engines")
            }
            if !scan.knobs.isEmpty { reasons.append("it holds the knobs " + scan.knobs.joined(separator: ", ")) }
        } else if missing.isEmpty {
            reasons.append("\(openEMSFile) cannot be read")
        }
        scan.passed = reasons.isEmpty
        scan.reason = reasons.isEmpty ? nil : reasons.joined(separator: "; ")
        return scan
    }

    /// A check reference against SNAPS/stock: per file uuid or sha256, and the acceptance (scan passed, all matched).
    static func stockMatch(reference: FdtdLibrary, stock: FdtdLibrary?, scan: FdtdStockScan) -> FdtdStockMatch {
        var files: [FdtdFileIdentity] = []
        for name in fileNames {
            var identity = FdtdFileIdentity(name: name)
            identity.sha256 = reference.file(name)?.sha256
            identity.uuid = reference.file(name)?.uuid
            files.append(identity)
        }
        guard let stock else { return FdtdStockMatch(matchedBy: nil, acceptance: false, files: files) }
        var allSameBytes = true
        var allMatched = true
        for identity in files {
            let theirs = stock.file(identity.name)
            let sameBytes = identity.sha256 != nil && identity.sha256 == theirs?.sha256
            let sameBuild = identity.uuid != nil && identity.uuid == theirs?.uuid
            if !sameBytes { allSameBytes = false }
            if !sameBytes && !sameBuild { allMatched = false }
        }
        // sha256 when all three are the same bytes, uuid when at least one is only the same build.
        let matchedBy: String? = allMatched ? (allSameBytes ? "sha256" : "uuid") : nil
        return FdtdStockMatch(matchedBy: matchedBy, acceptance: allMatched && scan.passed, files: files)
    }

    /// 3 engine_unsupported when the library's help strings do not list `engine` (before the run; F6).
    static func requireEngine(_ engine: FdtdEngine, in library: FdtdLibrary) throws {
        guard !library.engines.contains(engine.rawValue) else { return }
        let listed = library.engines.isEmpty ? "none" : library.engines.joined(separator: ", ")
        var message = "\(library.spec) does not list the engine \(engine.rawValue) (its engines: \(listed)), "
            + "and openEMS would run its default engine without a message"
        if engine == .metalDiamond { message += "; metal-diamond needs cg19 or later" }
        throw FdtdError(.engineUnsupported, message, hint: "emskit fdtd info --lib \(library.spec)")
    }

    /// 3 library_lacks_feature when the library lacks one of `knobs` (registry names found in its bytes) or `engines`
    /// (the debye and diamond gates of spec 2.8), with `hint`.
    static func requireFeatures(_ library: FdtdLibrary, knobs: [String], engines: [FdtdEngine], hint: String) throws {
        let missingKnobs = knobs.filter { !library.knobs.contains($0) }
        let missingEngines = engines.filter { !library.engines.contains($0.rawValue) }
        let missing = missingKnobs + missingEngines.map { "the engine " + $0.rawValue }
        guard !missing.isEmpty else { return }
        throw FdtdError(.libraryLacksFeature, "\(library.spec) lacks \(missing.joined(separator: ", "))", hint: hint)
    }

    // MARK: - Private: records

    private static func snapshotEntry(name: String, dir: String, system: any FdtdSystem) -> FdtdSnapshotEntry {
        var entry = FdtdSnapshotEntry(name: name, dir: dir, complete: true)
        var openEMSData: Data? = nil
        var nf2ffData: Data? = nil
        for file in fileNames {
            let path = FdtdPaths.join(dir, file)
            guard system.isRegularFile(path) else {
                entry.complete = false
                continue
            }
            let read = stream(path, keep: true, system: system)
            var identity = FdtdFileIdentity(name: file)
            identity.sha256 = read?.sha256
            identity.uuid = read?.data.flatMap { FdtdLibraries.machOUUID($0) }
            entry.files[file] = identity
            entry.bytes[file] = read?.bytes ?? system.fileSize(path)
            if file == openEMSFile { openEMSData = read?.data }
            if file == nf2ffFile { nf2ffData = read?.data }
        }
        if let openEMSData {
            entry.versionString = versionString(in: openEMSData)
            entry.engines = engines(in: openEMSData)
            entry.knobs = knobs(openEMS: openEMSData, nf2ff: nf2ffData)
            entry.registryNames = registryNames(in: openEMSData)
            if let nf2ffData { entry.registryNames.formUnion(registryNames(in: nf2ffData)) }
        }
        return entry
    }

    private static func fileRecord(name: String, path: String, read: Streamed?, index: FdtdSnapshotIndex,
                                   system: any FdtdSystem) -> FdtdLibraryFile {
        var identity = FdtdFileIdentity(name: name)
        identity.sha256 = read?.sha256
        identity.uuid = read?.data.flatMap { FdtdLibraries.machOUUID($0) }
        return fileRecord(identity, path: path, bytes: read?.bytes ?? system.fileSize(path), index: index,
                          system: system)
    }

    private static func fileRecord(_ identity: FdtdFileIdentity, path: String, bytes: Int?, index: FdtdSnapshotIndex,
                                   system: any FdtdSystem) -> FdtdLibraryFile {
        let name = identity.name
        var file = FdtdLibraryFile(name: name, path: system.realPath(path) ?? path)
        file.sha256 = identity.sha256
        file.bytes = bytes
        file.uuid = identity.uuid
        if let sha = file.sha256 {
            file.sameBytes = index.entries.filter { $0.files[name]?.sha256 == sha }.map(\.name)
        }
        if let uuid = file.uuid {
            file.sameBuild = index.entries.filter { $0.files[name]?.uuid == uuid }.map(\.name)
        }
        return file
    }

    /// Version, engines and knobs from the bytes, then compare.
    private static func fill(_ library: inout FdtdLibrary, openEMS: Data?, nf2ff: Data?, index: FdtdSnapshotIndex,
                             system: any FdtdSystem) {
        if let openEMS {
            library.versionString = versionString(in: openEMS)
            library.engines = engines(in: openEMS)
            library.knobs = knobs(openEMS: openEMS, nf2ff: nf2ff)
        }
        compare(&library, index: index, system: system)
    }

    /// The library's sameBytes/sameBuild are its libopenEMS's; then the candidates and the note.
    private static func compare(_ library: inout FdtdLibrary, index: FdtdSnapshotIndex, system: any FdtdSystem) {
        if let main = library.file(openEMSFile) {
            library.sameBytes = main.sameBytes
            library.sameBuild = main.sameBuild
        }
        // The folder itself, when it is a snapshot, is not news in the note and no candidate.
        let ownDir = system.realPath(library.dir) ?? library.dir
        let own = Set(index.entries.filter { (system.realPath($0.dir) ?? $0.dir) == ownDir }.map(\.name))
        if library.sameBuild.isEmpty, let version = library.versionString {
            let knobSet = Set(library.knobs)
            let engineSet = Set(library.engines)
            library.candidates = index.entries.filter { (entry: FdtdSnapshotEntry) -> Bool in
                guard !own.contains(entry.name), entry.versionString == version else { return false }
                return Set(entry.knobs) == knobSet && Set(entry.engines) == engineSet
            }.map(\.name)
        }
        library.note = note(library, own: own)
    }

    private static func note(_ library: FdtdLibrary, own: Set<String>) -> String? {
        guard let main = library.file(openEMSFile) else { return "no \(openEMSFile) in \(library.dir)" }
        let bytes = library.sameBytes.filter { !own.contains($0) }
        let build = library.sameBuild.filter { !own.contains($0) && !bytes.contains($0) }
        var parts: [String] = []
        if !bytes.isEmpty { parts.append("same bytes as " + bytes.joined(separator: ", ")) }
        if !build.isEmpty {
            var text = "same build as " + build.joined(separator: ", ") + " (UUID)"
            if bytes.isEmpty {
                // cmake --install rewrites the file, so an installed library is the same build in other bytes (F20).
                text += ", other bytes"
                if library.kind == .installed { text += " (installed copy)" }
            }
            parts.append(text)
        }
        if parts.isEmpty, library.sameBuild.isEmpty {
            parts.append(main.uuid == nil ? "no LC_UUID in \(openEMSFile)" : "no snapshot has this build")
            if !library.candidates.isEmpty {
                parts.append("same version string, knobs and engines as " + library.candidates.joined(separator: ", "))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// `KEY:TYPE=VALUE` lines of a CMakeCache.txt for the three keys info reports; the first one of each wins.
    private static func cmakeValues(_ text: String) -> [String: String] {
        let wanted: Set<String> = ["CMAKE_INSTALL_PREFIX", "ENABLE_METAL", "CMAKE_BUILD_TYPE"]
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard !line.hasPrefix("//"), !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let head = line[..<eq]
            let key = String(head.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? head)
            guard wanted.contains(key), values[key] == nil else { continue }
            values[key] = String(line[line.index(after: eq)...])
        }
        return values
    }

    // MARK: - Private: bytes

    private static func stream(_ path: String, keep: Bool, system: any FdtdSystem) -> Streamed? {
        var hasher = SHA256()
        var count = 0
        var kept = Data()
        if keep, let size = system.fileSize(path), size > 0 { kept.reserveCapacity(size) }
        let complete = system.readChunks(path, chunkSize: chunkSize) { (chunk: Data) in
            hasher.update(data: chunk)
            count += chunk.count
            if keep { kept.append(chunk) }
        }
        guard complete else { return nil }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return Streamed(sha256: hex, bytes: count, data: keep ? kept : nil)
    }

    /// The offset of the first `needle` at or after `start`, by memmem.
    private static func firstOffset(of needle: [UInt8], in raw: UnsafeRawBufferPointer, from start: Int) -> Int? {
        guard !needle.isEmpty, start >= 0, raw.count - start >= needle.count, let base = raw.baseAddress else {
            return nil
        }
        return needle.withUnsafeBytes { (little: UnsafeRawBufferPointer) -> Int? in
            guard let pattern = little.baseAddress,
                  let hit = memmem(base + start, raw.count - start, pattern, little.count) else { return nil }
            return base.distance(to: UnsafeRawPointer(hit))
        }
    }

    /// Every registry name that occurs as a whole token: `OPENEMS_` plus the longest run of identifier bytes.
    private static func registryNames(in data: Data) -> Set<String> {
        let names = Set(FdtdKnobs.registry.map(\.name))
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Set<String> in
            let prefix = Array("OPENEMS_".utf8)
            var found = Set<String>()
            var from = 0
            while let hit = FdtdLibraries.firstOffset(of: prefix, in: raw, from: from) {
                let end = FdtdLibraries.runEnd(raw, from: hit + prefix.count, FdtdLibraries.identifierBytes)
                let token = String(decoding: raw[hit..<end], as: UTF8.self)
                if names.contains(token) { found.insert(token) }
                from = hit + prefix.count
            }
            return found
        }
    }

    /// The first offset at or after `start` whose byte is not in `allowed`.
    private static func runEnd(_ raw: UnsafeRawBufferPointer, from start: Int, _ allowed: Set<UInt8>) -> Int {
        var i = start
        while i < raw.count, allowed.contains(raw[i]) { i += 1 }
        return i
    }

    /// Where the closing NUL of `v0.N.N[-N-gHEX][-dirty]` lies when the version starts at `start` ("v0." known).
    private static func versionEnd(_ raw: UnsafeRawBufferPointer, start: Int) -> Int? {
        let minorStart = start + 3
        let minorEnd = runEnd(raw, from: minorStart, digits)
        guard minorEnd > minorStart, minorEnd < raw.count, raw[minorEnd] == UInt8(ascii: ".") else { return nil }
        let patchStart = minorEnd + 1
        var i = runEnd(raw, from: patchStart, digits)
        guard i > patchStart else { return nil }
        if let describeEnd = gitDescribeEnd(raw, from: i) { i = describeEnd }
        let dirty = Array("-dirty".utf8)
        if i + dirty.count < raw.count, (0..<dirty.count).allSatisfy({ raw[i + $0] == dirty[$0] }) {
            i += dirty.count
        }
        guard i < raw.count, raw[i] == 0 else { return nil }
        return i
    }

    /// The end of `-N-gHEX` (git describe's count and lowercase hash) at `start`, or nil.
    private static func gitDescribeEnd(_ raw: UnsafeRawBufferPointer, from start: Int) -> Int? {
        guard start < raw.count, raw[start] == UInt8(ascii: "-") else { return nil }
        let countEnd = runEnd(raw, from: start + 1, digits)
        guard countEnd > start + 1, countEnd + 1 < raw.count, raw[countEnd] == UInt8(ascii: "-"),
              raw[countEnd + 1] == UInt8(ascii: "g") else { return nil }
        let hashEnd = runEnd(raw, from: countEnd + 2, lowerHex)
        return hashEnd > countEnd + 2 ? hashEnd : nil
    }

    // MARK: - Private: Mach-O

    private static func bigEndian32(_ raw: UnsafeRawBufferPointer, _ at: Int) -> UInt32? {
        guard at >= 0, raw.count - at >= 4 else { return nil }
        var value: UInt32 = 0
        for k in 0..<4 { value = (value << 8) | UInt32(raw[at + k]) }
        return value
    }

    private static func bigEndian64(_ raw: UnsafeRawBufferPointer, _ at: Int) -> UInt64? {
        guard at >= 0, raw.count - at >= 8 else { return nil }
        var value: UInt64 = 0
        for k in 0..<8 { value = (value << 8) | UInt64(raw[at + k]) }
        return value
    }

    private static func littleEndian32(_ raw: UnsafeRawBufferPointer, _ at: Int) -> UInt32? {
        guard at >= 0, raw.count - at >= 4 else { return nil }
        var value: UInt32 = 0
        for k in (0..<4).reversed() { value = (value << 8) | UInt32(raw[at + k]) }
        return value
    }

    /// The byte range of the arm64 slice of a fat file (fat_arch: 20 bytes, fat_arch_64: 32); a plain arm64 slice
    /// before an arm64e one.
    private static func arm64Slice(_ raw: UnsafeRawBufferPointer, wide: Bool) -> Range<Int>? {
        // A Java class file shares FAT_MAGIC; its version field makes a huge or implausible count.
        guard let count = bigEndian32(raw, 4), count >= 1, count <= 64 else { return nil }
        let entrySize = wide ? 32 : 20
        var arm64e: Range<Int>? = nil
        for k in 0..<Int(count) {
            let at = 8 + k * entrySize
            guard let cpu = bigEndian32(raw, at), let subtype = bigEndian32(raw, at + 4) else { break }
            guard cpu == cpuTypeARM64 else { continue }
            let offsetField = wide ? bigEndian64(raw, at + 8) : bigEndian32(raw, at + 8).map { UInt64($0) }
            let sizeField = wide ? bigEndian64(raw, at + 16) : bigEndian32(raw, at + 12).map { UInt64($0) }
            guard let offsetValue = offsetField, let sizeValue = sizeField,
                  let offset = Int(exactly: offsetValue), let size = Int(exactly: sizeValue),
                  offset <= raw.count, size <= raw.count - offset else { continue }
            let range = offset..<(offset + size)
            if subtype & 0x00ff_ffff != cpuSubtypeARM64E { return range }
            if arm64e == nil { arm64e = range }
        }
        return arm64e
    }

    /// LC_UUID of the thin arm64 Mach-O in raw[start..<end] (mach_header_64: 32 bytes, mach_header: 28).
    private static func thinUUID(_ raw: UnsafeRawBufferPointer, start: Int, end: Int) -> String? {
        guard let magic = littleEndian32(raw, start) else { return nil }
        let headerSize: Int
        switch magic {
        case 0xfeed_facf: headerSize = 32
        case 0xfeed_face: headerSize = 28
        default: return nil
        }
        guard end - start >= headerSize, let cpu = littleEndian32(raw, start + 4), cpu == cpuTypeARM64,
              let commandCount = littleEndian32(raw, start + 16),
              let commandBytes = littleEndian32(raw, start + 20) else { return nil }
        let commandsEnd = min(end, start + headerSize + Int(commandBytes))
        var at = start + headerSize
        var seen: UInt32 = 0
        while seen < commandCount, commandsEnd - at >= 8 {
            guard let command = littleEndian32(raw, at), let sizeField = littleEndian32(raw, at + 4) else { return nil }
            let size = Int(sizeField)
            guard size >= 8, size <= commandsEnd - at else { return nil }
            if command == loadCommandUUID {
                // uuid_command: cmd, cmdsize, then the 16 bytes.
                guard size >= 24 else { return nil }
                return uuidText(raw, at + 8)
            }
            at += size
            seen += 1
        }
        return nil
    }

    private static func uuidText(_ raw: UnsafeRawBufferPointer, _ at: Int) -> String? {
        guard at >= 0, raw.count - at >= 16 else { return nil }
        var text = ""
        for k in 0..<16 {
            if uuidDashes.contains(k) { text += "-" }
            text += String(format: "%02X", raw[at + k])
        }
        return text
    }
}
