// SPDX-License-Identifier: GPL-3.0-or-later

// Child environments (spec 5.1): start from the CLI's own environment, remove what would change a run without saying
// so (DYLD_*, OPENEMS_*, the tools' input variables, most PYTHON*, Malloc*), keep PYTHONPATH, PYTHONUSERBASE and the
// owner's RFSIM_* with a warning, then set only what the command needs. DYLD never goes to /bin/zsh (F1).
import Foundation

/// A child's environment: the whole of it, plus what the CLI set and removed relative to its own (the invocation
/// record's envSet and envRemoved).
struct FdtdChildEnvironment: Sendable, Equatable {
    /// The child's whole environment.
    var environment: [String: String]
    /// Only the variables the CLI set or changed.
    var envSet: [String: String] = [:]
    /// The inherited variables taken out, with their values.
    var envRemoved: [FdtdEnvEntry] = []

    /// This environment plus `values`, which are recorded in envSet.
    func adding(_ values: [String: String]) -> FdtdChildEnvironment {
        var e = self
        for (name, value) in values {
            e.environment[name] = value
            e.envSet[name] = value
        }
        return e
    }

    /// The same without any DYLD_* variable, for /bin/zsh.
    var forZsh: FdtdChildEnvironment {
        var e = self
        e.environment = e.environment.filter { !$0.key.hasPrefix("DYLD_") }
        e.envSet = e.envSet.filter { !$0.key.hasPrefix("DYLD_") }
        return e
    }
}

/// The remove, keep and set rules.
enum FdtdChildEnv {
    /// Removed by name besides the prefixes DYLD_, OPENEMS_, PYTHON (but PYTHONPATH, PYTHONUSERBASE) and Malloc:
    /// the validation and e2e inputs, the script inputs, and RFSIM_PATH (set again from discovery only).
    static let removedNames: Set<String> = ["VALIDATION_ENGINE", "VALIDATION_THREADS", "VALIDATION_WORK", "E2E_ENGINE",
                                            "THREADS", "STOCK", "LITE", "EXTRA", "QUIET_MAX", "DEBYE", "DRUDE", "ENG",
                                            "RFSIM_PATH"]

    /// Every variable with one of these prefixes goes, except keptPython. Malloc*: libmalloc settings move the large
    /// blocks, which is what the allocation-placement valley depends on.
    private static let removedPrefixes = ["DYLD_", "OPENEMS_", "PYTHON", "Malloc"]

    /// They choose which openEMS binding loads; the probe records it.
    private static let keptPython: Set<String> = ["PYTHONPATH", "PYTHONUSERBASE"]

    /// The base environment of every child: `inherited` (the CLI's) with the removals (one env_removed warning that
    /// lists name=value), the kept PYTHONPATH/PYTHONUSERBASE (python_env_kept) and RFSIM_* (rfsim_env), then PATH =
    /// dirname(python) + ":" + the old PATH without duplicating that entry, PYTHONDONTWRITEBYTECODE=1, and
    /// RFSIM_PATH = `rfsimPath` when rfsim was found. An inherited PYTHONDONTWRITEBYTECODE, or an RFSIM_PATH equal to
    /// `rfsimPath`, is set again unchanged in effect and is not listed as removed.
    static func base(inherited: [String: String], python: String, rfsimPath: String?,
                     warnings: inout [FdtdIssue]) -> FdtdChildEnvironment {
        var environment: [String: String] = [:]
        var removed: [FdtdEnvEntry] = []
        var pythonKept: [String] = []
        var rfsimKept: [String] = []
        for name in inherited.keys.sorted() {
            let value = inherited[name] ?? ""
            if isRemoved(name) {
                let setAgain = name == "PYTHONDONTWRITEBYTECODE" || (name == "RFSIM_PATH" && value == rfsimPath)
                if !setAgain { removed.append(FdtdEnvEntry(name: name, value: value)) }
                continue
            }
            environment[name] = value
            if keptPython.contains(name) {
                pythonKept.append(name + "=" + value)
            } else if name.hasPrefix("RFSIM_") {
                rfsimKept.append(name + "=" + value)
            }
        }

        if !removed.isEmpty {
            let list = removed.map { $0.name + "=" + $0.value }.joined(separator: ", ")
            // A removed OPENEMS_ knob still reaches a run when it is given the way the CLI records it.
            let knob = removed.first(where: { $0.name.hasPrefix("OPENEMS_") && !$0.name.hasPrefix("OPENEMS_BENCH_") })
            warnings.append(FdtdIssue(.envRemoved, "removed from the child environment: " + list,
                                      hint: knob.map { "--knob " + $0.name + "=" + $0.value }))
        }
        if !pythonKept.isEmpty {
            let list = pythonKept.joined(separator: ", ")
            let message = "kept in the child environment (it can choose the binding): " + list
            warnings.append(FdtdIssue(.pythonEnvKept, message))
        }
        if !rfsimKept.isEmpty {
            let list = rfsimKept.joined(separator: ", ")
            warnings.append(FdtdIssue(.rfsimEnv, "kept in the child environment for rfsim: " + list))
        }

        var set = ["PATH": prefixPath(FdtdPaths.dirname(python), inherited["PATH"]), "PYTHONDONTWRITEBYTECODE": "1"]
        if let rfsimPath { set["RFSIM_PATH"] = rfsimPath }
        return FdtdChildEnvironment(environment: environment, envRemoved: removed).adding(set)
    }

    /// Whether the remove step takes `name` out.
    static func isRemoved(_ name: String) -> Bool {
        if keptPython.contains(name) { return false }
        if removedNames.contains(name) { return true }
        return removedPrefixes.contains(where: { name.hasPrefix($0) })
    }

    /// PATH with `folder` first, once (an entry equal to it, with or without a trailing '/', is dropped further on);
    /// just `folder` when there is no PATH.
    static func prefixPath(_ folder: String, _ path: String?) -> String {
        guard !folder.isEmpty else { return path ?? "" }
        guard let path, !path.isEmpty else { return folder }
        let rest = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            .filter { $0 != folder && $0 != folder + "/" }
        return ([folder] + rest).joined(separator: ":")
    }
}
