import XCTest

@testable import TermQ

final class GitURLHelperTests: XCTestCase {

    // MARK: - shortURL

    func test_shortURL_stripsHost_noScheme() {
        XCTAssertEqual(GitURLHelper.shortURL("github.com/eyelock/assistants"), "eyelock/assistants")
    }

    func test_shortURL_stripsHostAndScheme_https() {
        XCTAssertEqual(GitURLHelper.shortURL("https://github.com/eyelock/assistants"), "eyelock/assistants")
    }

    func test_shortURL_stripsHostAndScheme_http() {
        XCTAssertEqual(GitURLHelper.shortURL("http://github.com/org/repo"), "org/repo")
    }

    func test_shortURL_passesThrough_absolutePath() {
        XCTAssertEqual(GitURLHelper.shortURL("/local/path"), "/local/path")
    }

    func test_shortURL_passesThrough_relativePath() {
        XCTAssertEqual(GitURLHelper.shortURL("./relative/path"), "./relative/path")
    }

    func test_shortURL_anthropicsURL() {
        XCTAssertEqual(
            GitURLHelper.shortURL("https://github.com/anthropics/claude-plugins-official"),
            "anthropics/claude-plugins-official"
        )
    }

    // MARK: - repoOwner

    func test_repoOwner_https_returnsOrg() {
        XCTAssertEqual(GitURLHelper.repoOwner("https://github.com/eyelock/assistants"), "eyelock")
    }

    func test_repoOwner_noScheme_returnsOrg() {
        XCTAssertEqual(GitURLHelper.repoOwner("github.com/eyelock/assistants"), "eyelock")
    }

    func test_repoOwner_anthropics() {
        XCTAssertEqual(
            GitURLHelper.repoOwner("https://github.com/anthropics/claude-plugins-official"),
            "anthropics"
        )
    }

    func test_repoOwner_noPath_returnsNil() {
        XCTAssertNil(GitURLHelper.repoOwner("github.com"))
    }

    func test_repoOwner_emptyString_returnsNil() {
        XCTAssertNil(GitURLHelper.repoOwner(""))
    }

    func test_repoOwner_orgOnly_noRepo_returnsNil() {
        // "github.com/eyelock" has a host and one path component but no slash after the org
        XCTAssertNil(GitURLHelper.repoOwner("github.com/eyelock"))
    }

    // MARK: - browserURL

    func test_browserURL_noScheme_returnsHttpsURL() {
        let url = GitURLHelper.browserURL(for: "github.com/eyelock/assistants")
        XCTAssertEqual(url?.absoluteString, "https://github.com/eyelock/assistants")
    }

    func test_browserURL_withPath_includesTreeRef() {
        let url = GitURLHelper.browserURL(for: "github.com/eyelock/assistants", path: "skills/foo")
        XCTAssertEqual(url?.absoluteString, "https://github.com/eyelock/assistants/tree/HEAD/skills/foo")
    }

    func test_browserURL_absolutePath_returnsNil() {
        XCTAssertNil(GitURLHelper.browserURL(for: "/local/path"))
    }

    func test_browserURL_relativePath_returnsNil() {
        XCTAssertNil(GitURLHelper.browserURL(for: "./relative"))
    }
}
