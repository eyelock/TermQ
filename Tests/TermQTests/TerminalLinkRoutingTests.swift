import XCTest

@testable import TermQ

/// Static guardrail: every `requestOpenLink` definition in TermQ must route
/// through `TermQTerminalLink.open(link:cwd:)`.
///
/// SwiftTerm has *two* ways for a URL click to land outside our central
/// handler:
///   1. A `TerminalViewDelegate` conformer that doesn't override the method
///      (tmux control mode hit this).
///   2. A `LocalProcessTerminalView` subclass — `LocalProcessTerminalView.init`
///      assigns `terminalDelegate = self`, so the view itself fields
///      `requestOpenLink`, not the configured `processDelegate`. Forgetting
///      to override on the subclass silently regresses to SwiftTerm's broken
///      default (`URL(string:)` + `NSWorkspace.open` → macOS "-50" dialog).
///
/// This test scans the project for every `requestOpenLink` declaration site
/// and asserts each one calls `TermQTerminalLink.open`.
final class TerminalLinkRoutingTests: XCTestCase {

    func testEveryRequestOpenLinkDefinition_routesThroughTermQTerminalLink() throws {
        let sourcesURL = try sourcesDirectory()
        let swiftFiles = try collectSwiftFiles(under: sourcesURL)

        var offenders: [String] = []

        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for definition in requestOpenLinkBodies(in: contents) {
                if !definition.body.contains("TermQTerminalLink.open") {
                    offenders.append(
                        "\(file.lastPathComponent):\(definition.line) — does not call TermQTerminalLink.open"
                    )
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            Some `requestOpenLink` definitions don't route through TermQTerminalLink.open. \
            They will fall back to SwiftTerm's broken default and produce the macOS "-50" \
            Finder dialog for absolute paths.

            \(offenders.joined(separator: "\n"))

            Fix: call `TermQTerminalLink.open(link: link, cwd: <cwd or nil>)` from the body.
            """
        )
    }

    func testTermQTerminalView_installsLinkDelegate() throws {
        // Regression guard: TermQTerminalView must install TermQLinkDelegate in its
        // init. SwiftTerm's requestOpenLink witness table entry is baked into the
        // SwiftTerm binary — a subclass override in our module is never consulted.
        // Per SwiftTerm's docs, the correct approach is to set a custom terminalDelegate
        // and proxy all values. TermQLinkDelegate does this; installLinkDelegate wires it.
        let url = try sourcesDirectory().appendingPathComponent("Views/TerminalHostView.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(
            contents.contains("installLinkDelegate"),
            """
            TermQTerminalView must call installLinkDelegate() in its init overrides. \
            SwiftTerm's requestOpenLink witness is baked into the SwiftTerm binary — \
            the only reliable fix is to replace terminalDelegate with a proxy (TermQLinkDelegate) \
            per SwiftTerm's own documentation.
            """
        )
        XCTAssertTrue(
            contents.contains("TermQLinkDelegate"),
            "TermQLinkDelegate proxy must be defined in TerminalHostView.swift."
        )
    }

    // MARK: - Source scanning

    private struct DefinitionMatch {
        let line: Int
        let body: String
    }

    private func sourcesDirectory() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TermQTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        url.appendPathComponent("Sources/TermQ")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue
        else {
            throw NSError(
                domain: "TerminalLinkRoutingTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Sources/TermQ not found at \(url.path)"]
            )
        }
        return url
    }

    private func collectSwiftFiles(under root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator
        where url.pathExtension == "swift" {
            result.append(url)
        }
        return result
    }

    /// Finds every `func requestOpenLink(...)` declaration in `source` and
    /// returns its line number plus the brace-balanced body.
    private func requestOpenLinkBodies(in source: String) -> [DefinitionMatch] {
        let pattern = #"func\s+requestOpenLink\s*\([^{]*\)\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match -> DefinitionMatch? in
            let openBrace = match.range.location + match.range.length - 1
            var depth = 1
            var i = openBrace + 1
            while i < ns.length && depth > 0 {
                let ch = ns.character(at: i)
                if ch == 0x7B { depth += 1 }
                if ch == 0x7D { depth -= 1 }
                i += 1
            }
            guard depth == 0 else { return nil }
            let body = ns.substring(with: NSRange(location: openBrace + 1, length: i - openBrace - 2))
            let prefix = ns.substring(with: NSRange(location: 0, length: match.range.location))
            let line = prefix.reduce(into: 1) { count, ch in if ch == "\n" { count += 1 } }
            return DefinitionMatch(line: line, body: body)
        }
    }
}
