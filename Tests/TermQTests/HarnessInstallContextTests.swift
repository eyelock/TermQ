import TermQShared
import XCTest

@testable import TermQ

@MainActor
final class HarnessInstallContextTests: XCTestCase {

    private func makeContext() -> HarnessInstallContext {
        HarnessInstallContext(
            installedNames: [],
            installedHarnesses: [],
            onInstall: { _ in }
        )
    }

    /// `SearchResult` has no public memberwise init, so build fixtures the same
    /// way production does — by decoding `ynh search --format json` output.
    private func makeResult(json: String) throws -> SearchResult {
        try JSONDecoder().decode(SearchResult.self, from: Data(json.utf8))
    }

    // MARK: - Local sources

    func testApplyLibrary_localSource_usesRepoPathVerbatim() throws {
        // A local source's `repo` is the harness's own filesystem path and
        // `path` is absent. Appending the name yields a directory that has
        // never existed, so the install argument must be `repo` untouched.
        let result = try makeResult(
            json: """
                {
                  "name": "ynh-guide",
                  "repo": "/Users/david/Storage/Workspace/eyelock/ynh",
                  "from": { "type": "source", "name": "ynh" }
                }
                """
        )

        let config = makeContext().applyLibrary(result: result)

        XCTAssertEqual(config.installArgs, ["/Users/david/Storage/Workspace/eyelock/ynh"])
        XCTAssertEqual(config.displayName, "ynh-guide")
    }

    func testApplyLibrary_localSource_inSubdirectory_usesRepoPathVerbatim() throws {
        // `ynh-dev` lives at `<repo>/.claude`; `repo` already points there.
        let result = try makeResult(
            json: """
                {
                  "name": "ynh-dev",
                  "repo": "/Users/david/Storage/Workspace/eyelock/ynh/.claude",
                  "from": { "type": "source", "name": "ynh" }
                }
                """
        )

        let config = makeContext().applyLibrary(result: result)

        XCTAssertEqual(config.installArgs, ["/Users/david/Storage/Workspace/eyelock/ynh/.claude"])
    }

    // MARK: - Registry results (existing behaviour — must not regress)

    func testApplyLibrary_registryWithoutPath_appendsName() throws {
        // A registry monorepo holds harnesses in subdirectories named after
        // them, so the name is the right fallback here.
        let result = try makeResult(
            json: """
                {
                  "name": "david",
                  "repo": "github.com/eyelock/assistants",
                  "from": { "type": "registry", "name": "eyelock-assistants" }
                }
                """
        )

        let config = makeContext().applyLibrary(result: result)

        XCTAssertEqual(config.installArgs, ["github.com/eyelock/assistants/david"])
    }

    func testApplyLibrary_registryWithPath_appendsPath() throws {
        let result = try makeResult(
            json: """
                {
                  "name": "david",
                  "repo": "github.com/eyelock/assistants",
                  "path": "ynh/david",
                  "from": { "type": "registry", "name": "eyelock-assistants" }
                }
                """
        )

        let config = makeContext().applyLibrary(result: result)

        XCTAssertEqual(config.installArgs, ["github.com/eyelock/assistants/ynh/david"])
    }

    // MARK: - Missing repo

    func testApplyLibrary_withoutRepo_fallsBackToName() throws {
        let result = try makeResult(
            json: """
                {
                  "name": "solo",
                  "from": { "type": "registry", "name": "eyelock-assistants" }
                }
                """
        )

        let config = makeContext().applyLibrary(result: result)

        XCTAssertEqual(config.installArgs, ["solo"])
    }
}
