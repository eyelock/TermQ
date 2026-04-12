import Foundation
import XCTest

@testable import TermQShared

final class RepoConfigTests: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-RepoConfigTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - GitRepository Codable Round-Trip

    func testGitRepositoryCodableRoundTrip() throws {
        let original = GitRepository(
            id: UUID(),
            name: "TermQ",
            path: "/Users/user/project",
            worktreeBasePath: "/Users/user/project-wt",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GitRepository.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.worktreeBasePath, original.worktreeBasePath)
        // Date round-trip via ISO8601 is accurate to the second
        XCTAssertEqual(decoded.addedAt.timeIntervalSince1970, original.addedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testGitRepositoryNilWorktreeBasePath() throws {
        let original = GitRepository(name: "MyRepo", path: "/path/to/repo")
        XCTAssertNil(original.worktreeBasePath)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GitRepository.self, from: data)

        XCTAssertNil(decoded.worktreeBasePath)
    }

    // MARK: - GitWorktree Codable Round-Trip

    func testGitWorktreeCodableRoundTrip() throws {
        let original = GitWorktree(
            path: "/Users/user/project-wt/feat-sidebar",
            branch: "feat-sidebar",
            commitHash: "abc12345",
            isMainWorktree: false,
            isLocked: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitWorktree.self, from: data)

        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.branch, original.branch)
        XCTAssertEqual(decoded.commitHash, original.commitHash)
        XCTAssertEqual(decoded.isMainWorktree, original.isMainWorktree)
        XCTAssertEqual(decoded.isLocked, original.isLocked)
        XCTAssertEqual(decoded.id, original.id)
    }

    func testGitWorktreeNilBranchCodable() throws {
        let original = GitWorktree(
            path: "/some/detached",
            branch: nil,
            commitHash: "deadbeef",
            isMainWorktree: false,
            isLocked: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitWorktree.self, from: data)

        XCTAssertNil(decoded.branch)
    }

    // MARK: - RepoConfig Codable Round-Trip

    func testRepoConfigEmptyCodable() throws {
        let original = RepoConfig()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RepoConfig.self, from: data)
        XCTAssertEqual(decoded.repositories.count, 0)
    }

    func testRepoConfigWithRepositoriesCodable() throws {
        let repos = [
            GitRepository(name: "Repo1", path: "/path/1"),
            GitRepository(name: "Repo2", path: "/path/2", worktreeBasePath: "/wt"),
        ]
        let original = RepoConfig(repositories: repos)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RepoConfig.self, from: data)

        XCTAssertEqual(decoded.repositories.count, 2)
        XCTAssertEqual(decoded.repositories[0].name, "Repo1")
        XCTAssertEqual(decoded.repositories[1].worktreeBasePath, "/wt")
    }

    // MARK: - RepoConfigLoader.getConfigURL

    func testGetConfigURLContainsReposJson() {
        let url = RepoConfigLoader.getConfigURL(dataDirectory: tempDirectory)
        XCTAssertEqual(url.lastPathComponent, "repos.json")
        XCTAssertTrue(url.path.contains(tempDirectory.lastPathComponent))
    }

    // MARK: - RepoConfigLoader.load

    func testLoadReturnsEmptyConfigWhenFileAbsent() throws {
        let config = try RepoConfigLoader.load(dataDirectory: tempDirectory)
        XCTAssertEqual(config.repositories.count, 0)
    }

    func testLoadDecodesExistingFile() throws {
        let repos = [GitRepository(name: "TermQ", path: "/Users/user/termq")]
        let config = RepoConfig(repositories: repos)
        try RepoConfigLoader.save(config, dataDirectory: tempDirectory)

        let loaded = try RepoConfigLoader.load(dataDirectory: tempDirectory)
        XCTAssertEqual(loaded.repositories.count, 1)
        XCTAssertEqual(loaded.repositories[0].name, "TermQ")
        XCTAssertEqual(loaded.repositories[0].path, "/Users/user/termq")
    }

    func testLoadThrowsOnMalformedJSON() throws {
        let configURL = RepoConfigLoader.getConfigURL(dataDirectory: tempDirectory)
        try "{ not valid json }".data(using: .utf8)!.write(to: configURL)

        XCTAssertThrowsError(try RepoConfigLoader.load(dataDirectory: tempDirectory)) { error in
            guard let loadError = error as? RepoConfigLoader.LoadError else {
                XCTFail("Expected LoadError, got \(error)")
                return
            }
            if case .decodingFailed(let message) = loadError {
                XCTAssertFalse(message.isEmpty)
            } else {
                XCTFail("Expected decodingFailed")
            }
        }
    }

    // MARK: - RepoConfigLoader.save

    func testSaveCreatesFile() throws {
        let config = RepoConfig(repositories: [GitRepository(name: "Test", path: "/test")])
        try RepoConfigLoader.save(config, dataDirectory: tempDirectory)

        let configURL = RepoConfigLoader.getConfigURL(dataDirectory: tempDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testSaveAndLoadRoundTrip() throws {
        let original = RepoConfig(repositories: [
            GitRepository(name: "Repo A", path: "/path/a"),
            GitRepository(name: "Repo B", path: "/path/b", worktreeBasePath: "/wt/b"),
        ])
        try RepoConfigLoader.save(original, dataDirectory: tempDirectory)

        let loaded = try RepoConfigLoader.load(dataDirectory: tempDirectory)
        XCTAssertEqual(loaded.repositories.count, 2)
        XCTAssertEqual(loaded.repositories[0].name, "Repo A")
        XCTAssertEqual(loaded.repositories[1].worktreeBasePath, "/wt/b")
    }

    func testSaveCreatesDirectoryIfNeeded() throws {
        let nestedDir = tempDirectory.appendingPathComponent("nested/subdir")
        // Directory does not exist yet
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedDir.path))

        let config = RepoConfig(repositories: [GitRepository(name: "Test", path: "/test")])
        try RepoConfigLoader.save(config, dataDirectory: nestedDir)

        let configURL = RepoConfigLoader.getConfigURL(dataDirectory: nestedDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testSaveOverwritesExistingFile() throws {
        let first = RepoConfig(repositories: [GitRepository(name: "First", path: "/first")])
        try RepoConfigLoader.save(first, dataDirectory: tempDirectory)

        let second = RepoConfig(repositories: [
            GitRepository(name: "Second A", path: "/second/a"),
            GitRepository(name: "Second B", path: "/second/b"),
        ])
        try RepoConfigLoader.save(second, dataDirectory: tempDirectory)

        let loaded = try RepoConfigLoader.load(dataDirectory: tempDirectory)
        XCTAssertEqual(loaded.repositories.count, 2)
        XCTAssertEqual(loaded.repositories[0].name, "Second A")
    }

    // MARK: - LoadError descriptions

    func testLoadErrorDecodingFailedDescription() {
        let error = RepoConfigLoader.LoadError.decodingFailed("bad format")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("bad format"))
    }

    func testLoadErrorCoordinationFailedDescription() {
        let error = RepoConfigLoader.LoadError.coordinationFailed("lock failed")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("lock failed"))
    }

    // MARK: - SaveError descriptions

    func testSaveErrorEncodingFailedDescription() {
        let error = RepoConfigLoader.SaveError.encodingFailed("invalid data")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("invalid data"))
    }

    func testSaveErrorWriteFailedDescription() {
        let error = RepoConfigLoader.SaveError.writeFailed("permission denied")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("permission denied"))
    }

    func testSaveErrorCoordinationFailedDescription() {
        let error = RepoConfigLoader.SaveError.coordinationFailed("timeout")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("timeout"))
    }
}
