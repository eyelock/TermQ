import XCTest

@testable import TermQ

final class TerminalSelectionPathResolverTests: XCTestCase {

    func testResolve_absoluteDirectory_existing_returnsSelfAsDirectory() {
        let resolved = TerminalSelectionPathResolver.resolve(
            selection: "/Users/me/Workspace/project",
            cwd: nil,
            fileExists: { $0 == "/Users/me/Workspace/project" },
            isDirectory: { $0 == "/Users/me/Workspace/project" }
        )
        XCTAssertEqual(
            resolved,
            ResolvedSelectionPath(
                exactPath: "/Users/me/Workspace/project",
                directory: "/Users/me/Workspace/project"
            )
        )
    }

    func testResolve_absoluteFile_existing_directoryIsParent() {
        let resolved = TerminalSelectionPathResolver.resolve(
            selection: "/Users/me/Workspace/project/README.md",
            cwd: nil,
            fileExists: { $0 == "/Users/me/Workspace/project/README.md" },
            isDirectory: { _ in false }
        )
        XCTAssertEqual(
            resolved,
            ResolvedSelectionPath(
                exactPath: "/Users/me/Workspace/project/README.md",
                directory: "/Users/me/Workspace/project"
            )
        )
    }

    func testResolve_relativePath_withCwd_resolvesAgainstIt() {
        let resolved = TerminalSelectionPathResolver.resolve(
            selection: "sub/file.md",
            cwd: "/tmp",
            fileExists: { $0 == "/tmp/sub/file.md" },
            isDirectory: { _ in false }
        )
        XCTAssertEqual(
            resolved,
            ResolvedSelectionPath(exactPath: "/tmp/sub/file.md", directory: "/tmp/sub")
        )
    }

    func testResolve_relativePath_withoutCwd_returnsNil() {
        let resolved = TerminalSelectionPathResolver.resolve(
            selection: "file.md",
            cwd: nil,
            fileExists: { _ in true },
            isDirectory: { _ in false }
        )
        XCTAssertNil(resolved)
    }

    func testResolve_nonExistentPath_returnsNil() {
        let resolved = TerminalSelectionPathResolver.resolve(
            selection: "/nope/missing",
            cwd: nil,
            fileExists: { _ in false },
            isDirectory: { _ in false }
        )
        XCTAssertNil(resolved)
    }

    func testResolve_pathWithTrailingPunctuation_sanitizedBeforeLookup() {
        let resolved = TerminalSelectionPathResolver.resolve(
            selection: "/Users/me/Plans/foo.md,",
            cwd: nil,
            fileExists: { $0 == "/Users/me/Plans/foo.md" },
            isDirectory: { _ in false }
        )
        XCTAssertEqual(
            resolved,
            ResolvedSelectionPath(exactPath: "/Users/me/Plans/foo.md", directory: "/Users/me/Plans")
        )
    }

    func testResolve_httpURL_returnsNil() {
        let resolved = TerminalSelectionPathResolver.resolve(
            selection: "https://example.com/x",
            cwd: nil,
            fileExists: { _ in true },
            isDirectory: { _ in false }
        )
        XCTAssertNil(resolved)
    }

    func testResolve_emptyOrWhitespaceSelection_returnsNil() {
        XCTAssertNil(
            TerminalSelectionPathResolver.resolve(
                selection: "", cwd: "/tmp", fileExists: { _ in true }, isDirectory: { _ in true }))
        XCTAssertNil(
            TerminalSelectionPathResolver.resolve(
                selection: "   \n  ", cwd: "/tmp", fileExists: { _ in true }, isDirectory: { _ in true }))
    }

    func testResolve_plainProseSelection_returnsNil() {
        let resolved = TerminalSelectionPathResolver.resolve(
            selection: "just some regular output text",
            cwd: "/tmp",
            fileExists: { _ in false },
            isDirectory: { _ in false }
        )
        XCTAssertNil(resolved)
    }
}
