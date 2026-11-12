// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 LibraryScanTests (4.2: the byte scans, the LC_UUID reader, sameBytes/sameBuild/candidates; the real
// snapshots, read only) and StockTests (S8: check is the CPU acceptance only against stock).
import Foundation
import Testing
@testable import fdtdKit

@Suite struct LibraryScanTests {
    static let uuid = "0A1B2C3D-4E5F-4071-8293-A4B5C6D7E8F9"

    @Test func versionStrings() {
        func version(_ strings: [String]) -> String? {
            FdtdLibraries.versionString(in: MachO.thin(uuid: nil, strings: strings))
        }
        #expect(version(["v0.37.0-44-g074a687"]) == "v0.37.0-44-g074a687")
        #expect(version(["v0.37.0"]) == "v0.37.0")
        #expect(version(["v0.37.0-26-gcd80d8c-dirty"]) == "v0.37.0-26-gcd80d8c-dirty")
        #expect(version(["v0.37", "v1.0.0", "build v0.37.0 here"]) == nil)
        #expect(version(["xv0.37.0", "v0.38.1"]) == "v0.38.1")
    }

    @Test func enginesAndKnobs() {
        let help = [FdtdEngine.multithreaded, .metalDiamond].map { $0.helpString }
        let data = MachO.thin(uuid: nil, strings: help + ["  gpu: no tab here", "OPENEMS_FUSED_BLOCK",
                                                          "OPENEMS_NF2FF_LEGACY", "OPENEMS_NOT_A_KNOB"])
        #expect(FdtdLibraries.engines(in: data) == ["multithreaded", "metal-diamond"])
        // whole names only (FUSED_BLOCK is not FUSED); NF2FF_LEGACY counts only in libnf2ff
        #expect(FdtdLibraries.knobs(openEMS: data, nf2ff: nil) == ["OPENEMS_FUSED_BLOCK"])
        let nf2ff = MachO.thin(uuid: nil, strings: ["OPENEMS_NF2FF_LEGACY"])
        #expect(FdtdLibraries.knobs(openEMS: data, nf2ff: nf2ff) == ["OPENEMS_FUSED_BLOCK", "OPENEMS_NF2FF_LEGACY"])
    }

    @Test func machOUUIDs() {
        #expect(FdtdLibraries.machOUUID(MachO.thin(uuid: Self.uuid, strings: [])) == Self.uuid)
        #expect(FdtdLibraries.machOUUID(MachO.thin(uuid: Self.uuid.lowercased(), strings: [])) == Self.uuid)
        #expect(FdtdLibraries.machOUUID(MachO.thin(uuid: nil, strings: ["x"])) == nil)
        let other = "11111111-2222-4333-8444-555555555555"
        let fat = MachO.fat([(MachO.x86_64, 3, MachO.thin(uuid: other, strings: [], cpu: MachO.x86_64)),
                             (MachO.arm64, 0, MachO.thin(uuid: Self.uuid, strings: []))])
        #expect(FdtdLibraries.machOUUID(fat) == Self.uuid)
        let intelOnly = MachO.fat([(MachO.x86_64, 3, MachO.thin(uuid: other, strings: [], cpu: MachO.x86_64))])
        #expect(FdtdLibraries.machOUUID(intelOnly) == nil)
        #expect(FdtdLibraries.machOUUID(Data("not a Mach-O".utf8)) == nil)
        #expect(FdtdLibraries.machOUUID(Data()) == nil)
    }

    @Test func sha256IsStreamed() throws {
        let folder = try TempFolder("sha")
        defer { folder.remove() }
        // three chunks of 1 MiB and a tail
        let data = Data((0..<(3 << 20) + 17).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try folder.write("blob", data)
        let streamed = FdtdLibraries.sha256(path: folder.file("blob"), system: LiveSystem())
        #expect(streamed == FdtdLibraries.sha256(data))
        #expect(FdtdLibraries.sha256(Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(FdtdLibraries.sha256(path: folder.file("missing"), system: LiveSystem()) == nil)
    }

    @Test func sameBytesSameBuildAndCandidates() throws {
        let folder = try TempFolder("snaps")
        defer { folder.remove() }
        let snaps = folder.file("snap")
        func put(_ dir: String, _ library: FakeLibrary) throws {
            for (name, data) in library.files { try folder.write(dir + "/" + name, data) }
        }
        try put("snap/A", .cg29)
        try put("snap/B", .cg29)
        var rebuilt = FakeLibrary.cg29
        rebuilt.trailer = Array("installed copy".utf8)
        try put("snap/C", rebuilt)
        try put("snap/D", .cg27)
        var other = FakeLibrary.cg29
        other.openEMSUUID = "99999999-0000-4000-8000-000000000001"
        try put("elsewhere/X", other)
        var noUUID = FakeLibrary.cg29
        noUUID.openEMSUUID = nil
        try put("elsewhere/Y", noUUID)
        try FileManager.default.createDirectory(atPath: folder.file("snap/.hidden"), withIntermediateDirectories: true)

        let system = LiveSystem()
        let index = FdtdLibraries.index(snaps: snaps, system: system)
        #expect(index.entries.map { $0.name } == ["A", "B", "C", "D"])
        func identify(_ spec: String) throws -> FdtdLibrary {
            let location = try FdtdLibraries.locate(spec, snaps: snaps, installedDir: nil, cwd: folder.path,
                                                    home: FakeWorld.home, system: system)
            return FdtdLibraries.identify(location, index: index, system: system)
        }
        let a = try identify("A")
        #expect(a.versionString == "v0.37.0-44-g074a687")
        #expect(a.knobs == FdtdKnobs.registry.map { $0.name })
        #expect(a.engines == FdtdEngine.allCases.map { $0.rawValue })
        #expect(a.sameBytes == ["A", "B"])
        #expect(a.sameBuild == ["A", "B", "C"])
        #expect(a.candidates.isEmpty)
        #expect(a.note?.contains("same bytes as B") == true)
        #expect(a.note?.contains("same build as C (UUID)") == true)
        #expect(a.file("libopenEMS.0.dylib")?.uuid == FakeLibrary.cg29.openEMSUUID)
        #expect(a.file("libopenEMS.0.dylib")?.bytes == FakeLibrary.cg29.openEMS.count)

        // a snapshot's record built from its index entry is the one identify gives for its folder
        for entry in index.entries {
            let byName = try identify(entry.name)
            #expect(FdtdLibraries.identify(entry, index: index, system: system) == byName, "\(entry.name)")
        }

        let x = try identify(folder.file("elsewhere/X"))
        #expect(x.kind == .path)
        #expect(x.sameBuild.isEmpty)
        #expect(x.candidates == ["A", "B", "C"])
        #expect(x.note?.contains("no snapshot has this build") == true)
        // the other two files are the same bytes as cg29's
        #expect(x.file("libCSXCAD.0.dylib")?.sameBytes == ["A", "B", "C"])

        let y = try identify(folder.file("elsewhere/Y"))
        #expect(y.file("libopenEMS.0.dylib")?.uuid == nil)
        #expect(y.note?.contains("no LC_UUID in libopenEMS.0.dylib") == true)

        #expect(throws: FdtdError.self) { _ = try identify("nothing") }
    }

    /// info lists the snapshots from the index, which has read each file once: none is hashed and scanned a second
    /// time, and each record is the one identify gives for that folder.
    @Test func infoReadsEverySnapshotFileOnce() throws {
        let world = FakeWorld()
        let run = world.run(["info"])
        #expect(run.exit == 0, "\(run.stderr)")
        let files = world.system.allPaths.filter {
            $0.hasPrefix(FakeWorld.snaps + "/") && FdtdLibraries.fileNames.contains(FdtdPaths.basename($0))
        }
        // four complete snapshots and one without libnf2ff
        #expect(files.count == 14)
        for path in files { #expect(world.system.chunkReads(path) == 1, "\(path)") }
        let listed = try #require(run.result["snapshots"]?.array)
        let index = FdtdLibraries.index(snaps: FakeWorld.snaps, system: world.system)
        #expect(listed.count == index.entries.count)
        for (entry, record) in zip(index.entries, listed) {
            let location = FdtdLibraryLocation(spec: entry.name, kind: .snapshot, dir: entry.dir,
                                               complete: entry.complete)
            let expected = FdtdLibraries.identify(location, index: index, system: world.system)
            let decoded = try FdtdJSON.decode(FdtdLibrary.self, from: FdtdJSON.encode(record))
            #expect(decoded == expected, "\(entry.name)")
        }
    }

    /// check resolves its snapshots, its reference and SNAPS/stock (the stock scan and the match) from the index, which
    /// has streamed each file once: none is hashed a second time or read again whole.
    @Test func checkReadsEverySnapshotFileOnce() throws {
        let world = FakeWorld()
        let run = world.run(["check", "cg29", "--stock", "cg18", "--tag", "once", "--lite", "--rfsim", FakeWorld.rfsim,
                             "--dry-run"])
        #expect(run.exit == 0, "\(run.stderr)")
        let files = world.system.allPaths.filter {
            $0.hasPrefix(FakeWorld.snaps + "/") && FdtdLibraries.fileNames.contains(FdtdPaths.basename($0))
        }
        #expect(files.contains(FakeWorld.snaps + "/stock/" + FdtdLibraries.openEMSFile))
        for path in files {
            #expect(world.system.chunkReads(path) == 1, "\(path)")
            #expect(world.system.wholeReads(path) == 0, "\(path)")
        }
    }

    /// A snapshot name typed in another Unicode form than the folder's listed name (é composed, the listing
    /// decomposed): the record keeps the bytes typed, as without the index.
    @Test func aNameInAnotherUnicodeFormKeepsTheBytesTyped() throws {
        let world = FakeWorld()
        let listed = "caf\u{65}\u{301}"
        let typed = "caf\u{e9}"
        world.system.addLibraryFolder(FakeWorld.snaps + "/" + listed, FakeLibrary.cg29.files)
        let listing = FdtdLibraries.index(snaps: FakeWorld.snaps, system: world.system)
        #expect(listing.entries.contains { $0.name == typed })
        let run = world.run(["bench", "patch", "--config", typed + "@multithreaded:4", "--config",
                             typed + "@multithreaded:8", "--dry-run"])
        #expect(run.exit == 0, "\(run.stderr)")
        let library = try #require(run.envelope["libraries"]?.array?.first { $0["kind"]?.string == "snapshot" })
        #expect(library["spec"]?.string?.utf8.elementsEqual(typed.utf8) == true)
        #expect(library["dir"]?.string?.utf8.elementsEqual((FakeWorld.snaps + "/" + typed).utf8) == true)
    }

    // MARK: the real snapshots (read only)

    static let realSnaps = NSHomeDirectory() + "/opt/openEMS-dev/snap"
    static let realSnapsExist = FileManager.default.fileExists(atPath: realSnaps)

    @Test(.enabled(if: realSnapsExist)) func realSnapshotsHaveTheirProperties() throws {
        let system = LiveSystem()
        let index = FdtdLibraries.index(snaps: Self.realSnaps, system: system)
        #expect(!index.entries.isEmpty)
        let cpu = Set(FdtdEngine.cpuEngines.map { $0.rawValue })
        for entry in index.entries {
            let location = try FdtdLibraries.locate(entry.name, snaps: Self.realSnaps, installedDir: nil, cwd: "/",
                                                    home: NSHomeDirectory(), system: system)
            #expect(location.complete == entry.complete, "\(entry.name)")
            if entry.complete {
                #expect(entry.versionString != nil, "\(entry.name)")
                #expect(cpu.isSubset(of: Set(entry.engines)), "\(entry.name)")
            } else {
                #expect(throws: FdtdError.self, "\(entry.name)") { try FdtdLibraries.requireComplete(location) }
            }
        }
    }

    /// The rows of spec 4.2: (snapshot, sha256 prefix, version, knob names in libopenEMS, UUID prefix). The knob
    /// column counts libopenEMS; the record adds NF2FF_LEGACY from libnf2ff (cg18: 15 + 1, cg29: 29 + 1, cg31: 37 + 1,
    /// cg32d: 40 + 1; cg32d = patch 0040 built in the tree configured for cg31, so it reports cg31's version).
    static let rows: [(String, String, String, Int, String)] = [
        ("stock", "7eaaee52", "v0.37.0", 0, "B1A89DA1"),
        ("cg18", "0c32ad23", "v0.37.0-24-g087ce9e", 15, "24C8A7F2"),
        ("cg29", "3c859d81", "v0.37.0-44-g074a687", 29, "40BC8CFF"),
        ("cg31", "644198c2", "v0.37.0-57-gff2538a", 37, "499C07FD"),
        ("cg32d", "72e6d7ef", "v0.37.0-57-gff2538a", 40, "530052B0"),
    ]

    /// The installed rows: the installed libopenEMS by sha256 prefix, with its version, UUID prefix and build. It was
    /// cg18's build until 2026-11-06, cg29's until 2026-11-11 and is cg31's since, each in other bytes than the
    /// snapshot's file.
    static let installedRows: [(sha: String, version: String, uuid: String, build: String)] = [
        ("819179a2", "v0.37.0-24-g087ce9e", "24C8A7F2", "cg18"),
        ("0d81372e", "v0.37.0-44-g074a687", "40BC8CFF", "cg29"),
        ("23630ed6", "v0.37.0-57-gff2538a", "499C07FD", "cg31"),
    ]

    @Test(.enabled(if: realSnapsExist)) func spec42RowsWhileTheHashesHold() throws {
        let system = LiveSystem()
        let index = FdtdLibraries.index(snaps: Self.realSnaps, system: system)
        for (name, sha, version, knobs, uuid) in Self.rows {
            guard let entry = index.entries.first(where: { $0.name == name }),
                  entry.files["libopenEMS.0.dylib"]?.sha256?.hasPrefix(sha) == true
            else { continue }
            #expect(entry.versionString == version, "\(name)")
            #expect(entry.knobs.filter { $0 != "OPENEMS_NF2FF_LEGACY" }.count == knobs, "\(name)")
            #expect(entry.knobs.contains("OPENEMS_NF2FF_LEGACY") == (knobs > 0), "\(name)")
            #expect(entry.files["libopenEMS.0.dylib"]?.uuid?.hasPrefix(uuid) == true, "\(name)")
            switch name {
            case "stock": #expect(Set(entry.engines) == Set(FdtdEngine.cpuEngines.map { $0.rawValue }))
            case "cg18":
                #expect(entry.engines.contains("gpu") && entry.engines.contains("gpu-reference"))
                #expect(!entry.engines.contains("metal-diamond"))
            default: #expect(entry.knobs.contains("OPENEMS_NF2FF_LEGACY"))
            }
        }
        // the installed row that matches the installed libopenEMS: skipped for any other install
        let installed = NSHomeDirectory() + "/opt/openEMS/lib"
        let installedSha = FdtdLibraries.sha256(path: installed + "/libopenEMS.0.dylib", system: system)
        guard let row = Self.installedRows.first(where: { installedSha?.hasPrefix($0.sha) == true }) else { return }
        let location = try FdtdLibraries.locate("installed", snaps: Self.realSnaps, installedDir: installed, cwd: "/",
                                                home: NSHomeDirectory(), system: system)
        let library = FdtdLibraries.identify(location, index: index, system: system)
        #expect(library.versionString == row.version)
        #expect(library.file("libopenEMS.0.dylib")?.uuid?.hasPrefix(row.uuid) == true)
        #expect(library.sameBuild.contains(row.build))
        #expect(library.sameBytes.isEmpty)
        #expect(library.note?.contains("(installed copy)") == true)
        #expect(library.file("libCSXCAD.0.dylib")?.sameBytes.contains("cg29") == true)
    }
}

@Suite struct StockTests {
    static func reference(_ run: CLIRun) -> FdtdJSONValue? { run.result["reference"] }

    @Test func stockAndACopyOfItAreTheAcceptance() throws {
        let world = FakeWorld()
        let own = world.run(["check", "cg29", "--tag", "acc", "--lite", "--rfsim", FakeWorld.rfsim, "--dry-run"])
        #expect(own.exit == 0, "\(own.stderr)")
        #expect(own.status == "ok")
        #expect(Self.reference(own)?["acceptance"]?.bool == true)
        #expect(Self.reference(own)?["matchedBy"]?.string == "sha256")
        #expect(Self.reference(own)?["stockScan"]?["passed"]?.bool == true)
        #expect(!own.warningCodes.contains("reference_not_stock"))

        let copy = FakeWorld()
        copy.system.addLibraryFolder("/work/stock-copy", FakeLibrary.stock.files)
        let run = copy.run(["check", "cg29", "--stock", "/work/stock-copy", "--tag", "acc", "--lite", "--rfsim",
                            FakeWorld.rfsim, "--dry-run"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        #expect(Self.reference(run)?["acceptance"]?.bool == true)
        #expect(Self.reference(run)?["dir"]?.string == "/work/stock-copy")
    }

    @Test func anotherReferenceIsPlannedPartial() throws {
        let run = FakeWorld().run(["check", "cg29", "--stock", "cg18", "--tag", "smoke", "--lite", "--rfsim",
                                   FakeWorld.rfsim, "--dry-run"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "partial")
        #expect(Self.reference(run)?["acceptance"]?.bool == false)
        #expect(Self.reference(run)?["matchedBy"] == .null)
        #expect(run.warningCodes.contains("reference_not_stock"))
        // without rfsim only four models run: partial too, and only with --allow-partial
        let four = FakeWorld().run(["check", "cg29", "--tag", "smoke", "--lite", "--allow-partial", "--dry-run"])
        #expect(four.status == "partial")
        #expect(FakeWorld().run(["check", "cg29", "--tag", "smoke", "--lite", "--dry-run"]).exit == 2)
    }

    @Test func stockOpenEMSBesideAForkCSXCADIsNotTheAcceptance() throws {
        let world = FakeWorld()
        var files = FakeLibrary.stock.files
        files["libCSXCAD.0.dylib"] = FakeLibrary.cg29.csxcad
        world.system.addLibraryFolder("/work/mixed", files)
        let run = world.run(["check", "cg29", "--stock", "/work/mixed", "--tag", "mix", "--lite", "--rfsim",
                             FakeWorld.rfsim, "--dry-run"])
        #expect(run.status == "partial")
        #expect(Self.reference(run)?["acceptance"]?.bool == false)
        #expect(run.warningCodes.contains("reference_not_stock"))
    }

    @Test func aForkPlacedAsStockFailsTheScan() throws {
        let world = FakeWorld(snapshots: false)
        world.system.addLibraryFolder(FakeWorld.snaps + "/stock", FakeLibrary.cg18.files)
        world.system.addLibraryFolder(FakeWorld.snaps + "/cg29", FakeLibrary.cg29.files)
        let index = FdtdLibraries.index(snaps: FakeWorld.snaps, system: world.system)
        let scan = FdtdLibraries.stockScan(snaps: FakeWorld.snaps, index: index, system: world.system)
        #expect(scan.exists && !scan.passed)
        #expect(scan.reason?.contains("not v0.37.0") == true)
        #expect(scan.reason?.contains("holds the knobs") == true)
        // from the index entry as from reading the folder
        #expect(FdtdLibraries.stockScan(snaps: FakeWorld.snaps, index: FdtdSnapshotIndex(folder: FakeWorld.snaps),
                                        system: world.system) == scan)
        let run = world.run(["check", "cg29", "--tag", "fork", "--lite", "--rfsim", FakeWorld.rfsim, "--dry-run"])
        #expect(run.status == "partial")
        #expect(Self.reference(run)?["acceptance"]?.bool == false)
    }

    /// A registry name in the other library's file fails the stock scan, although the identity record (the index's
    /// knobs) does not count it; the scan from the index entry equals the one that reads the folder.
    @Test func aRegistryNameInEitherFileFailsTheStockScan() throws {
        let world = FakeWorld(snapshots: false)
        var files = FakeLibrary.stock.files
        files[FdtdLibraries.nf2ffFile] = MachO.thin(uuid: FakeLibrary.stock.nf2ffUUID,
                                                    strings: ["OPENEMS_FUSED", "libnf2ff stock"])
        world.system.addLibraryFolder(FakeWorld.snaps + "/stock", files)
        let index = FdtdLibraries.index(snaps: FakeWorld.snaps, system: world.system)
        #expect(index.entries.first { $0.name == "stock" }?.knobs.isEmpty == true)
        let scan = FdtdLibraries.stockScan(snaps: FakeWorld.snaps, index: index, system: world.system)
        #expect(!scan.passed)
        #expect(scan.knobs == ["OPENEMS_FUSED"])
        #expect(FdtdLibraries.stockScan(snaps: FakeWorld.snaps, index: FdtdSnapshotIndex(folder: FakeWorld.snaps),
                                        system: world.system) == scan)

        let clean = FakeWorld()
        let cleanIndex = FdtdLibraries.index(snaps: FakeWorld.snaps, system: clean.system)
        let passed = FdtdLibraries.stockScan(snaps: FakeWorld.snaps, index: cleanIndex, system: clean.system)
        #expect(passed.passed, "\(passed.reason ?? "")")
        #expect(FdtdLibraries.stockScan(snaps: FakeWorld.snaps, index: FdtdSnapshotIndex(folder: FakeWorld.snaps),
                                        system: clean.system) == passed)
    }

    /// SNAPS/stock that the folder's listing leaves out (another letter case, a folder that cannot be listed) is still
    /// the stock the reference is matched against.
    @Test func aStockFolderTheListingLeavesOutIsStillTheReference() throws {
        let world = FakeWorld()
        world.system.update { $0.unlisted = [FakeWorld.snaps + "/stock"] }
        let unlisted = FdtdLibraries.index(snaps: FakeWorld.snaps, system: world.system)
        #expect(!unlisted.entries.contains { $0.name == "stock" })
        world.system.addLibraryFolder("/work/stock-copy", FakeLibrary.stock.files)
        let run = world.run(["check", "cg29", "--stock", "/work/stock-copy", "--tag", "acc", "--lite", "--rfsim",
                             FakeWorld.rfsim, "--dry-run"])
        #expect(run.exit == 0, "\(run.stderr)")
        #expect(run.status == "ok")
        #expect(Self.reference(run)?["acceptance"]?.bool == true)
        #expect(Self.reference(run)?["matchedBy"]?.string == "sha256")
        #expect(Self.reference(run)?["stockScan"]?["passed"]?.bool == true)
    }

    @Test(.enabled(if: LibraryScanTests.realSnapsExist)) func realStockPassesTheScan() {
        let system = LiveSystem()
        let snaps = LibraryScanTests.realSnaps
        let stock = snaps + "/stock/libopenEMS.0.dylib"
        guard FdtdLibraries.sha256(path: stock, system: system)?.hasPrefix("7eaaee52") == true else { return }
        let scan = FdtdLibraries.stockScan(snaps: snaps, index: FdtdSnapshotIndex(folder: snaps), system: system)
        #expect(scan.passed, "\(scan.reason ?? "")")
        #expect(scan.knobs.isEmpty)
    }
}
