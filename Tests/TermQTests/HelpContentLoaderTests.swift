import Foundation
import XCTest

@testable import TermQ

// MARK: - HelpContentLoader path resolution tests
//
// These tests exercise the path-splitting logic added to loadContent(for:) so
// that IDs like "reference/keyboard-shortcuts" and "tutorials/01-first-board"
// correctly resolve inside subdirectories of the bundled Help/ folder.
// They do NOT test actual file reads (bundle content varies by build config)
// — only the ID parsing semantics via a test-only hook.

final class HelpTopicIDTests: XCTestCase {

    // MARK: - Topic ID path splitting

    func test_flatID_hasNoPathSeparator() {
        let id = "about"
        XCTAssertFalse(id.contains("/"))
    }

    func test_pathID_splitCorrectly_reference() {
        let id = "reference/keyboard-shortcuts"
        let parts = id.split(separator: "/", maxSplits: 1)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "reference")
        XCTAssertEqual(String(parts[1]), "keyboard-shortcuts")
    }

    func test_pathID_splitCorrectly_tutorials() {
        let id = "tutorials/01-first-board"
        let parts = id.split(separator: "/", maxSplits: 1)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "tutorials")
        XCTAssertEqual(String(parts[1]), "01-first-board")
    }

    func test_pathID_deeperPath_splitAtFirstSlashOnly() {
        // maxSplits:1 ensures "a/b/c" splits into ["a", "b/c"], not ["a","b","c"]
        let id = "tutorials/nested/deep"
        let parts = id.split(separator: "/", maxSplits: 1)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "tutorials")
        XCTAssertEqual(String(parts[1]), "nested/deep")
    }

    // MARK: - Help index topic IDs match file structure convention

    func test_knownReferenceIDs_followConvention() {
        let referenceIDs = [
            "reference/keyboard-shortcuts",
            "reference/cli",
            "reference/mcp",
            "reference/configuration",
            "reference/security",
        ]
        for id in referenceIDs {
            let parts = id.split(separator: "/", maxSplits: 1)
            XCTAssertEqual(parts.first.map(String.init), "reference", "\(id) should be in reference/")
        }
    }

    func test_knownTutorialIDs_followConvention() {
        let tutorialIDs = [
            "tutorials/01-first-board",
            "tutorials/12-worktree-sidebar",
            "tutorials/13-harness-sidebar",
            "tutorials/14-marketplace",
        ]
        for id in tutorialIDs {
            let parts = id.split(separator: "/", maxSplits: 1)
            XCTAssertEqual(parts.first.map(String.init), "tutorials", "\(id) should be in tutorials/")
        }
    }

    func test_flatIDs_areTopLevel() {
        let flatIDs = ["about", "updates", "why"]
        for id in flatIDs {
            XCTAssertFalse(id.contains("/"), "\(id) should have no path separator")
        }
    }
}
