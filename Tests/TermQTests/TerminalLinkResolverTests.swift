import XCTest

@testable import TermQ

final class TerminalLinkResolverTests: XCTestCase {

    // MARK: - sanitize

    func testSanitize_trimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(TerminalLinkResolver.sanitize("  /tmp/file.md  "), "/tmp/file.md")
    }

    func testSanitize_stripsTrailingPunctuationFromPath() {
        XCTAssertEqual(TerminalLinkResolver.sanitize("/tmp/file.md."), "/tmp/file.md")
        XCTAssertEqual(TerminalLinkResolver.sanitize("/tmp/file.md,"), "/tmp/file.md")
        XCTAssertEqual(TerminalLinkResolver.sanitize("/tmp/file.md)"), "/tmp/file.md")
        XCTAssertEqual(TerminalLinkResolver.sanitize("/tmp/file.md]"), "/tmp/file.md")
        XCTAssertEqual(TerminalLinkResolver.sanitize("/tmp/file.md:"), "/tmp/file.md")
        XCTAssertEqual(TerminalLinkResolver.sanitize("/tmp/file.md\""), "/tmp/file.md")
    }

    func testSanitize_stripsCombinedTrailingPunctuationAndWhitespace() {
        XCTAssertEqual(TerminalLinkResolver.sanitize("/tmp/file.md).\n"), "/tmp/file.md")
    }

    func testSanitize_doesNotTouchInteriorPunctuation() {
        XCTAssertEqual(TerminalLinkResolver.sanitize("/a.b/c.d.md"), "/a.b/c.d.md")
    }

    func testSanitize_emptyAndWhitespaceOnly() {
        XCTAssertEqual(TerminalLinkResolver.sanitize(""), "")
        XCTAssertEqual(TerminalLinkResolver.sanitize("   \n  "), "")
    }

    // MARK: - resolve: http/https

    func testResolve_httpURL_returnsOpenURL() {
        let action = TerminalLinkResolver.resolve(
            link: "https://example.com/x",
            cwd: nil,
            fileExists: { _ in false }
        )
        XCTAssertEqual(action, .openURL(URL(string: "https://example.com/x")!))
    }

    func testResolve_httpURL_withTrailingPunctuation_isStripped() {
        let action = TerminalLinkResolver.resolve(
            link: "https://example.com/x).",
            cwd: nil,
            fileExists: { _ in false }
        )
        XCTAssertEqual(action, .openURL(URL(string: "https://example.com/x")!))
    }

    // MARK: - resolve: absolute paths

    func testResolve_absolutePath_existing_returnsOpenFile() {
        let action = TerminalLinkResolver.resolve(
            link: "/tmp/foo.md",
            cwd: nil,
            fileExists: { $0 == "/tmp/foo.md" }
        )
        XCTAssertEqual(action, .openFile(URL(fileURLWithPath: "/tmp/foo.md").standardized))
    }

    func testResolve_absolutePath_missing_revealsNearestExistingParent() {
        let action = TerminalLinkResolver.resolve(
            link: "/tmp/missing/dir/file.md",
            cwd: nil,
            fileExists: { $0 == "/tmp" }
        )
        guard case .revealInFinder(let file, let root) = action else {
            XCTFail("expected revealInFinder, got \(action)")
            return
        }
        XCTAssertEqual(file.path, "/tmp/missing/dir/file.md")
        XCTAssertEqual(root.path, "/tmp")
    }

    func testResolve_absolutePath_missingAllParents_revealsRoot() {
        let action = TerminalLinkResolver.resolve(
            link: "/nope/file.md",
            cwd: nil,
            fileExists: { _ in false }
        )
        if case .revealInFinder(_, let root) = action {
            XCTAssertEqual(root.path, "/")
        } else {
            XCTFail("expected revealInFinder, got \(action)")
        }
    }

    func testResolve_absolutePath_withTrailingPunctuation_existsAfterTrim() {
        let action = TerminalLinkResolver.resolve(
            link: "/tmp/foo.md.",
            cwd: nil,
            fileExists: { $0 == "/tmp/foo.md" }
        )
        XCTAssertEqual(action, .openFile(URL(fileURLWithPath: "/tmp/foo.md").standardized))
    }

    // MARK: - resolve: relative paths

    func testResolve_relativePath_withCwd_resolvesAndOpens() {
        let action = TerminalLinkResolver.resolve(
            link: "sub/file.md",
            cwd: "/tmp",
            fileExists: { $0 == "/tmp/sub/file.md" }
        )
        XCTAssertEqual(action, .openFile(URL(fileURLWithPath: "/tmp/sub/file.md").standardized))
    }

    func testResolve_relativePath_withCwd_missing_revealsParent() {
        let action = TerminalLinkResolver.resolve(
            link: "sub/file.md",
            cwd: "/tmp",
            fileExists: { $0 == "/tmp" }
        )
        if case .revealInFinder(_, let root) = action {
            XCTAssertEqual(root.path, "/tmp")
        } else {
            XCTFail("expected revealInFinder, got \(action)")
        }
    }

    func testResolve_relativePath_withoutCwd_returnsFallbackString() {
        let action = TerminalLinkResolver.resolve(
            link: "file.md",
            cwd: nil,
            fileExists: { _ in false }
        )
        XCTAssertEqual(action, .fallbackString("file.md"))
    }

    // MARK: - resolve: edge cases

    func testResolve_emptyLink_isNoop() {
        let action = TerminalLinkResolver.resolve(
            link: "",
            cwd: "/tmp",
            fileExists: { _ in true }
        )
        XCTAssertEqual(action, .noop)
    }

    func testResolve_whitespaceOnlyLink_isNoop() {
        let action = TerminalLinkResolver.resolve(
            link: "   \n  ",
            cwd: "/tmp",
            fileExists: { _ in true }
        )
        XCTAssertEqual(action, .noop)
    }

    func testResolve_directoryPath_existing_returnsOpenFile() {
        // Directories take the same .openFile branch — the executor delegates
        // to NSWorkspace which opens the folder in Finder.
        let action = TerminalLinkResolver.resolve(
            link: "/Users/me/Workspace/project",
            cwd: nil,
            fileExists: { $0 == "/Users/me/Workspace/project" }
        )
        XCTAssertEqual(
            action,
            .openFile(URL(fileURLWithPath: "/Users/me/Workspace/project").standardized)
        )
    }

    func testResolve_pathWithSpacesAndTrailingComma_handledCorrectly() {
        // Mimics the real-world case: "Plan committed to /Users/.../foo.md, and ..."
        // Once SwiftTerm's regex captures the path with a trailing comma, sanitize
        // must strip it so fileExists matches.
        let action = TerminalLinkResolver.resolve(
            link: "/Users/me/Plans/foo.md,",
            cwd: nil,
            fileExists: { $0 == "/Users/me/Plans/foo.md" }
        )
        XCTAssertEqual(
            action,
            .openFile(URL(fileURLWithPath: "/Users/me/Plans/foo.md").standardized)
        )
    }
}
