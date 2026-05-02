import Foundation
import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class HarnessIncludeEditorTests: XCTestCase {

    private func makeTarget(
        url: String = "https://github.com/o/r",
        path: String? = "plugins/foo",
        ref: String? = "main",
        picks: [String] = []
    ) -> IncludeEditTarget {
        IncludeEditTarget(sourceURL: url, path: path, ref: ref, picks: picks)
    }

    private func makeRepo() -> HarnessRepository {
        HarnessRepository(ynhDetector: MockYNHDetector(status: .missing))
    }

    // MARK: - requestEdit / requestRemove

    func test_requestEdit_setsEditingTarget() {
        let editor = HarnessIncludeEditor(
            detector: MockYNHDetector(status: .missing),
            repository: makeRepo()
        )
        let target = makeTarget()
        editor.requestEdit(target)
        XCTAssertEqual(editor.editingTarget?.id, target.id)
        XCTAssertNil(editor.removalTarget)
    }

    func test_requestRemove_setsRemovalTarget() {
        let editor = HarnessIncludeEditor(
            detector: MockYNHDetector(status: .missing),
            repository: makeRepo()
        )
        let target = makeTarget()
        editor.requestRemove(target)
        XCTAssertEqual(editor.removalTarget?.id, target.id)
        XCTAssertNil(editor.editingTarget)
    }

    func test_requestEdit_clearsPriorErrorMessage() {
        let editor = HarnessIncludeEditor(
            detector: MockYNHDetector(status: .missing),
            repository: makeRepo()
        )
        editor.errorMessage = "stale error"
        editor.requestEdit(makeTarget())
        XCTAssertNil(editor.errorMessage)
    }

    // MARK: - confirmRemove with no ready toolchain

    func test_confirmRemove_withMissingToolchain_isNoOp() async {
        let editor = HarnessIncludeEditor(
            detector: MockYNHDetector(status: .missing),
            repository: makeRepo()
        )
        let target = makeTarget()
        editor.requestRemove(target)
        await editor.confirmRemove(target: target, harnessName: "my-harness")
        // No toolchain → guard fires before mutator runs; nothing changes.
        XCTAssertNotNil(editor.removalTarget)
    }

    func test_confirmEdit_withMissingToolchain_setsErrorMessage() async {
        let editor = HarnessIncludeEditor(
            detector: MockYNHDetector(status: .missing),
            repository: makeRepo()
        )
        editor.requestEdit(makeTarget())
        await editor.confirmEdit(
            harnessName: "my-harness",
            newPath: "new-path",
            newRef: "feature-branch",
            newPicks: nil
        )
        XCTAssertNotNil(editor.errorMessage)
        XCTAssertNotNil(editor.editingTarget)
    }

    // MARK: - IncludeEditTarget identity

    func test_target_identity_includesPath() {
        let a = makeTarget(url: "https://x", path: "p1")
        let b = makeTarget(url: "https://x", path: "p2")
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_target_identity_nilPath() {
        let a = makeTarget(url: "https://x", path: nil)
        let b = makeTarget(url: "https://x", path: nil)
        XCTAssertEqual(a.id, b.id)
    }

}

// MARK: - IncludeKey / IncludePluginLookup tests

@MainActor
final class IncludeKeyTests: XCTestCase {

    func test_matches_exactURLAndPath() {
        let key = IncludeKey(url: "https://github.com/o/r", path: "plugins/foo")
        XCTAssertTrue(key.matches(url: "https://github.com/o/r", path: "plugins/foo"))
    }

    func test_matches_normalizesTrailingDotGit() {
        let key = IncludeKey(url: "https://github.com/o/r.git", path: nil)
        XCTAssertTrue(key.matches(url: "https://github.com/o/r", path: nil))
    }

    func test_matches_normalizesScheme() {
        let key = IncludeKey(url: "HTTPS://GITHUB.com/o/r", path: nil)
        XCTAssertTrue(key.matches(url: "https://github.com/o/r", path: nil))
    }

    func test_matches_treatsEmptyPathAsNil() {
        let key = IncludeKey(url: "u", path: "")
        XCTAssertTrue(key.matches(url: "u", path: nil))
    }

    func test_matches_failsOnDifferentPath() {
        let key = IncludeKey(url: "u", path: "p1")
        XCTAssertFalse(key.matches(url: "u", path: "p2"))
    }
}
