// SPDX-License-Identifier: GPL-3.0-or-later

// Spec 16.1 TextRuleTests (S7): the public text names no first name, calls nothing "wrong", and never opens files.
import Foundation
import Testing
@testable import fdtdKit

enum TextRules {
    static let heading = "## Command line: `emskit fdtd` (fdtdKit)"

    /// The README section from its heading up to the next `## ` heading.
    static func section(of readme: String) -> String? {
        guard let start = readme.range(of: heading + "\n") else { return nil }
        let rest = readme[start.lowerBound...]
        let body = rest.dropFirst(heading.count + 1)
        guard let next = body.range(of: "\n## ") else { return String(rest) }
        return String(rest[..<next.lowerBound])
    }

    /// SHA-256 of each first name (lowercased) the public text must not contain, so the rule names none itself.
    static let nameHashes: Set<String> = ["519ba91a5a5b4afb9dc66f8805ce8c442b6576316c19c6896af2fa9bda6aff71"]

    /// Every finding of the rules in `text`.
    static func findings(_ text: String, name: String, names: Set<String> = nameHashes) -> [String] {
        var found: [String] = []
        let words = Set(text.split { !$0.isLetter }.map { $0.lowercased() })
        if words.contains(where: { names.contains(FdtdLibraries.sha256(Data($0.utf8))) }) {
            found.append("\(name): first name")
        }
        if text.range(of: "wrong", options: .caseInsensitive) != nil { found.append("\(name): wrong") }
        if text.contains("/usr/bin/open") { found.append("\(name): /usr/bin/open") }
        if text.contains("NSWorkspace") { found.append("\(name): NSWorkspace") }
        return found
    }
}

@Suite struct TextRuleTests {
    @Test func sourcesPlanAndReadmeSectionFollowTheRules() throws {
        let root = TestPaths.repo
        var texts: [(String, String)] = []
        let sources = root + "/Sources"
        let walker = try #require(FileManager.default.enumerator(atPath: sources))
        for case let relative as String in walker {
            let path = sources + "/" + relative
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }
            texts.append(("Sources/" + relative, try TestPaths.text(path)))
        }
        #expect(texts.count >= 20)
        texts.append(("Docs/fdtdKit/PLAN.md", try TestPaths.text(root + "/Docs/fdtdKit/PLAN.md")))
        let readme = try TestPaths.text(root + "/README.md")
        texts.append(("README section", try #require(TextRules.section(of: readme))))
        let findings = texts.flatMap { TextRules.findings($0.1, name: $0.0) }
        #expect(findings.isEmpty, "\(findings)")
    }

    @Test func theRulesCatchWhatTheyLookFor() {
        #expect(TextRules.findings("The WRONG engine", name: "x") == ["x: wrong"])
        let tester: Set = [FdtdLibraries.sha256(Data("tester".utf8))]
        #expect(TextRules.findings("ask Tester, please", name: "x", names: tester) == ["x: first name"])
        #expect(TextRules.findings("the testers decide", name: "x", names: tester).isEmpty)
        #expect(TextRules.nameHashes.allSatisfy { $0.count == 64 })
        #expect(TextRules.findings("/usr/bin/open report.pdf; NSWorkspace", name: "x").count == 2)
        #expect(TextRules.findings("the author decides", name: "x").isEmpty)
    }

    @Test func readmeSectionEndsAtTheNextHeading() throws {
        let text = "intro\n\(TextRules.heading)\nbody line\n## Next\nother\n"
        #expect(TextRules.section(of: text) == "\(TextRules.heading)\nbody line")
    }
}
