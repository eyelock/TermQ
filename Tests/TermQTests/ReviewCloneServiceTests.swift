import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class ReviewCloneServiceTests: XCTestCase {
    private var root: URL!
    private var service: ReviewCloneService!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("review-clones-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        service = ReviewCloneService(
            cloneBase: root.appendingPathComponent("focus-repos"),
            reviewBase: root.appendingPathComponent("focus-worktrees"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testClonePathEndsInOwnerAndNameSoThePRSlugIsRight() {
        let path = service.clonePath(for: "eyelock/mcp-toolkit")
        XCTAssertTrue(path.hasSuffix("/github.com/eyelock/mcp-toolkit"))
        XCTAssertEqual(RunWithFocusSheet.repoSlug(from: path), "eyelock/mcp-toolkit")
    }

    func testRefreshFindsReviewCheckoutsInHiddenClones() async throws {
        let review = try makeReviewCheckout(repository: "o/r", number: 5)

        await service.refresh(openRequests: [], ghPath: nil, cardDirectories: { [] })

        XCTAssertEqual(
            service.checkouts["o/r#5"].map { ReviewCheckouts.canonical($0.path) },
            ReviewCheckouts.canonical(review.path))
        XCTAssertNotNil(service.checkout(for: request("o/r", 5)))
        XCTAssertNil(service.checkout(for: request("o/r", 6)))
    }

    func testRequestsMatchCheckoutsWhateverTheCase() async throws {
        _ = try makeReviewCheckout(repository: "eyelock/termq", number: 5)

        await service.refresh(openRequests: [], ghPath: nil, cardDirectories: { [] })

        XCTAssertNotNil(service.checkout(for: request("EyeLock/TermQ", 5)))
        XCTAssertEqual(ReviewCloneService.key(repository: "EyeLock/TermQ", number: 5), "eyelock/termq#5")
    }

    func testRemoveDeletesTheCheckoutAndForgetsIt() async throws {
        let review = try makeReviewCheckout(repository: "o/r", number: 5)
        await service.refresh(openRequests: [], ghPath: nil, cardDirectories: { [] })
        let worktree = try XCTUnwrap(service.checkouts["o/r#5"])

        try await service.remove(worktree, repository: "o/r")

        XCTAssertFalse(FileManager.default.fileExists(atPath: review.path))
        XCTAssertNil(service.checkouts["o/r#5"])
        let listed = try await GitServiceShared.listWorktrees(repoPath: service.clonePath(for: "o/r"))
        XCTAssertEqual(listed.count, 1)
    }

    func testRemoveRefusesFoldersOutsideTheReviewFolder() async throws {
        let outside = root.appendingPathComponent("termq-focus--x--1")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let worktree = GitWorktree(
            path: outside.path, branch: nil, commitHash: "a", isMainWorktree: false, isLocked: false)

        do {
            try await service.remove(worktree, repository: "o/r")
            XCTFail("expected a refusal")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: - Helpers

    private func request(_ repository: String, _ number: Int) -> ReviewRequest {
        ReviewRequest(
            number: number, title: "t", url: "https://github.com/\(repository)/pull/\(number)",
            repository: repository, author: nil, isDraft: false, createdAt: Date())
    }

    /// A hidden clone of `repository` with one detached review checkout for `number`.
    private func makeReviewCheckout(repository: String, number: Int) throws -> URL {
        let clone = URL(fileURLWithPath: service.clonePath(for: repository))
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
        try git(clone, "init", "-q")
        try git(clone, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base")
        let key = (["github.com"] + repository.split(separator: "/").map(String.init)).joined(separator: "--")
        let review = service.reviewBase.appendingPathComponent(
            ReviewCheckouts.directoryName(repoKey: key, headRefName: "feat", prNumber: number))
        try FileManager.default.createDirectory(at: service.reviewBase, withIntermediateDirectories: true)
        try git(clone, "worktree", "add", "-q", "--detach", review.path)
        return review
    }

    private func git(_ dir: URL, _ args: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path] + args
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " "))")
    }
}
