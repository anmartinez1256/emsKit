// SPDX-License-Identifier: GPL-3.0-or-later

// Loads (spec 7): what the rest of the Mac used while a figure was measured. A failed ps or ioreg reads as zero use
// (F12), so each source has its own validity test. A speed or run time is shown, on stderr and in the envelope, only
// with a valid load; otherwise it is withheld (null) with the warning load_missing. ab's statistics use only runs
// with valid loads.
import Foundation

/// The --warn-cpu / --warn-gpu marks: others above them make a load `loaded` (it marks the figure, never blocks).
struct FdtdThresholds: Sendable, Equatable {
    var warnCpu: Double
    var warnGpu: Double
}

/// ab's run record (spec 7, "ab run"). mcs is null without a valid load.
struct FdtdABRunResult: Codable, Sendable, Equatable {
    var round: Int
    var config: Int
    @FdtdNullable var mcs: Double? = nil
    /// abtest's -1 (usage returned None) becomes null.
    @FdtdNullable var othersCpu: Int? = nil
    @FdtdNullable var othersGpu: Int? = nil
    var loadValid: Bool
    var diff: String
    /// false for a `# redo ` run; null for runs read from stdout after an interrupt.
    @FdtdNullable var kept: Bool? = nil
}

/// ab's per-config statistics, computed by the CLI from the kept runs with valid loads (spec 2.5, "ab config").
struct FdtdABConfigResult: Codable, Sendable, Equatable {
    var index: Int
    var config: String
    var label: String
    var tolerant: Bool
    @FdtdNullable var medianMcs: Double? = nil
    @FdtdNullable var minMcs: Double? = nil
    @FdtdNullable var maxMcs: Double? = nil
    /// The median paired ratio to c0 (both runs of the round valid) and its range.
    @FdtdNullable var medianRatio: Double? = nil
    @FdtdNullable var minRatio: Double? = nil
    @FdtdNullable var maxRatio: Double? = nil
    @FdtdNullable var othersCpuMedian: Double? = nil
    @FdtdNullable var othersGpuMedian: Double? = nil
    var runsWithLoad = 0
    var runsWithoutLoad = 0
    var diffs: [String] = []
    /// Only `identical` diffs in its kept runs (`reference` for c0's).
    var identical: Bool
}

/// Load validity, the figure lines and the ab statistics.
enum FdtdLoads {
    /// A sampler result (the launcher's, the LOAD helper's): valid when counts.processesSeen > 0 and
    /// counts.utilSamples > 0; a nil result (no sampler on this system) is invalid.
    static func fromSampler(_ result: FdtdSamplerResult?, counts: FdtdLoadCounts?, thresholds: FdtdThresholds) -> FdtdLoad {
        var load = FdtdLoad(source: .sampler, valid: false)
        load.processesSeen = counts?.processesSeen
        load.gpuClientsSeen = counts?.gpuClientsSeen
        load.utilSamples = counts?.utilSamples
        guard let result else {
            load.invalidReason = "no sampler result (usage.Sampler runs only on macOS)"
            return load
        }
        load.wallSeconds = result.wall
        load.selfCpuPercent = result.cpuSelf
        load.selfGpuPercent = result.gpuSelf
        load.selfGpuSecondsAtLeast = result.gpuSelf * result.wall / 100
        load.othersCpuPercent = result.cpuOther
        load.othersGpuPercent = result.gpuOther
        load.gpuDevicePercent = result.gpuDev
        load.busy = result.busy
        // A failed ps or ioreg reads as an idle Mac (F12): only the counts tell the two apart.
        if let counts {
            if counts.processesSeen <= 0 {
                load.invalidReason = "the sampler saw no processes (ps gave no sample)"
            } else if counts.utilSamples <= 0 {
                load.invalidReason = "the sampler took no GPU utilisation sample (ioreg gave none)"
            } else {
                load.valid = true
            }
        } else {
            load.invalidReason = "the sampler's process and sample counts are missing"
        }
        load.loaded = load.valid && isLoaded(load, thresholds: thresholds)
        return load
    }

    /// A bench row's `during` part: nil without one (a missing load); valid when it has `gpu dev` and is not
    /// `self cpu 0%` over more than 1 s.
    static func fromBenchRow(_ row: FdtdParsedBenchRow, thresholds: FdtdThresholds) -> FdtdLoad? {
        guard let use = row.during else { return nil }
        var load = FdtdLoad(source: .benchRow, valid: false)
        load.wallSeconds = use.wallSeconds
        load.selfCpuPercent = use.selfCpuPercent
        load.selfGpuSecondsAtLeast = use.selfGpuSecondsAtLeast
        load.othersCpuPercent = use.othersCpuPercent
        load.othersGpuPercent = use.othersGpuPercent
        load.gpuDevicePercent = use.gpuDevicePercent
        load.busy = use.busy
        // A working sampler always takes a utilisation sample at stop, and a run longer than a second always uses
        // some CPU of its own (usage.py:89).
        if use.gpuDevicePercent == nil {
            load.invalidReason = "the during part has no gpu dev figure (ioreg gave no utilisation sample)"
        } else if use.selfCpuPercent == 0 && use.wallSeconds > 1 {
            let wall = FdtdOptions.formatG(use.wallSeconds)
            load.invalidReason = "the during part shows self cpu 0% over \(wall) s (ps gave no sample)"
        } else {
            load.valid = true
        }
        load.loaded = load.valid && isLoaded(load, thresholds: thresholds)
        return load
    }

    /// An abtest run line: valid when others' cpu and gpu are >= 0 and both sampler checks around the run were valid.
    static func fromAbtestRun(_ run: FdtdParsedABRun, samplerChecksValid: Bool, thresholds: FdtdThresholds) -> FdtdLoad {
        var load = FdtdLoad(source: .abtestLine, valid: false)
        if run.othersCpu >= 0 { load.othersCpuPercent = Double(run.othersCpu) }
        if run.othersGpu >= 0 { load.othersGpuPercent = Double(run.othersGpu) }
        if run.othersCpu < 0 || run.othersGpu < 0 {
            load.invalidReason = "abtest printed -1: usage returned no sample for the run"
        } else if !samplerChecksValid {
            load.invalidReason = "a sampler check around the abtest run was not valid"
        } else {
            load.valid = true
        }
        load.loaded = load.valid && isLoaded(load, thresholds: thresholds)
        return load
    }

    /// Others above either threshold.
    static func isLoaded(_ load: FdtdLoad, thresholds: FdtdThresholds) -> Bool {
        (load.othersCpuPercent ?? 0) > thresholds.warnCpu || (load.othersGpuPercent ?? 0) > thresholds.warnGpu
    }

    /// Whether a figure measured under `load` may be shown.
    static func shows(_ load: FdtdLoad?) -> Bool { load?.valid == true }

    /// `LABEL X MC/s (others cpu C% gpu G%)`, or `LABEL: speed withheld (no valid load during the run)`.
    static func figure(_ label: String, mcs: Double?, load: FdtdLoad?) -> String {
        guard let load, shows(load) else { return "\(label): speed withheld (no valid load during the run)" }
        guard let mcs else { return "\(label): no speed figure" }
        let speed = String(format: "%.1f", mcs)
        return "\(label) \(speed) MC/s (\(othersCore(load)))"
    }

    /// `others cpu C% gpu G%`, with `, gpu dev D%` when known.
    static func othersText(_ load: FdtdLoad) -> String {
        var text = othersCore(load)
        if let device = load.gpuDevicePercent { text += ", gpu dev " + percent(device) }
        return text
    }

    /// The per-config statistics from `runs` (kept runs with a valid load only); `configs`, `labels` and `tolerant`
    /// are per config index.
    static func abStatistics(runs: [FdtdABRunResult], configs: [String], labels: [String],
                             tolerant: [Bool]) -> [FdtdABConfigResult] {
        let kept = runs.filter { $0.kept != false }
        let counted = kept.filter { $0.loadValid && $0.mcs != nil }
        // c0's speed per round, for the paired ratios (the last kept run of a round wins)
        var reference: [Int: Double] = [:]
        for run in counted where run.config == 0 {
            if let mcs = run.mcs { reference[run.round] = mcs }
        }
        var results: [FdtdABConfigResult] = []
        for (index, config) in configs.enumerated() {
            let label = index < labels.count ? labels[index] : config
            let isTolerant = index < tolerant.count ? tolerant[index] : false
            let mine = kept.filter { $0.config == index }
            let valid = counted.filter { $0.config == index }
            let speeds = valid.compactMap { $0.mcs }
            var byRound: [Int: Double] = [:]
            for run in valid {
                if let mcs = run.mcs { byRound[run.round] = mcs }
            }
            var ratios: [Double] = []
            for (round, mcs) in byRound {
                if let base = reference[round], base > 0 { ratios.append(mcs / base) }
            }
            let identical = !mine.isEmpty && mine.allSatisfy { isIdenticalDiff($0.diff, config: index) }
            var result = FdtdABConfigResult(index: index, config: config, label: label, tolerant: isTolerant,
                                            identical: identical)
            result.medianMcs = median(speeds)
            result.minMcs = speeds.min()
            result.maxMcs = speeds.max()
            result.medianRatio = median(ratios)
            result.minRatio = ratios.min()
            result.maxRatio = ratios.max()
            result.othersCpuMedian = median(valid.compactMap { run in run.othersCpu.map { Double($0) } })
            result.othersGpuMedian = median(valid.compactMap { run in run.othersGpu.map { Double($0) } })
            result.runsWithLoad = valid.count
            result.runsWithoutLoad = mine.count - valid.count
            result.diffs = Array(Set(mine.map { $0.diff })).sorted()
            results.append(result)
        }
        return results
    }

    /// The median (the mean of the middle two for an even count); nil for no values.
    static func median(_ values: [Double]) -> Double? {
        // NaN has no place in an order
        let sorted = values.filter { !$0.isNaN }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    // MARK: helpers

    /// `others cpu C% gpu G%`.
    private static func othersCore(_ load: FdtdLoad) -> String {
        "others cpu \(percent(load.othersCpuPercent)) gpu \(percent(load.othersGpuPercent))"
    }

    /// `45%`, or `unknown` for a figure the source did not give.
    private static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "unknown" }
        return String(format: "%.0f%%", value == 0 ? 0.0 : value)
    }

    /// abtest's diff for a run that matches: `identical`, or `reference` for c0's (its first run and any redo of it).
    private static func isIdenticalDiff(_ diff: String, config: Int) -> Bool {
        diff == "identical" || (config == 0 && diff == "reference")
    }
}
