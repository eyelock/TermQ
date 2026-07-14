import Foundation
import MCP
import XCTest

@testable import MCPServerLib

/// Validation and error-path tests for the four stack tools. Live-provider behavior is
/// exercised at the TermQShared layer (`GitSpiceStackProviderTests`); these tests cover
/// the MCP argument plumbing, which must fail cleanly without git-spice installed.
final class StackToolsTests: XCTestCase {
    var tempDirectory: URL!
    var server: TermQMCPServer!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-StackToolsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir
        server = TermQMCPServer(dataDirectory: tempDirectory)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        server = nil
    }

    private func text(_ result: CallTool.Result) -> String {
        if case .text(let text, _, _) = result.content.first {
            return text
        }
        return ""
    }

    // MARK: - Argument validation

    func test_stackStatus_missingRepoId_isError() async throws {
        let result = try await server.handleStackStatus([:])
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result).contains("repoId"))
    }

    func test_stackStatus_unknownRepoId_isError() async throws {
        let result = try await server.handleStackStatus(["repoId": .string(UUID().uuidString)])
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result).contains("Unknown repository"))
    }

    func test_stackCreateBranch_missingName_isError() async throws {
        let result = try await server.handleStackCreateBranch([
            "repoId": .string(UUID().uuidString),
            "worktreePath": .string("/tmp/wt"),
        ])
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result).contains("name"))
    }

    func test_stackSubmit_missingWorktreePath_isError() async throws {
        let result = try await server.handleStackSubmit([
            "repoId": .string(UUID().uuidString)
        ])
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result).contains("worktreePath"))
    }

    func test_stackRestack_unknownRepo_isError() async throws {
        let result = try await server.handleStackRestack([
            "repoId": .string(UUID().uuidString),
            "worktreePath": .string("/tmp/wt"),
        ])
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result).contains("Unknown repository"))
    }

    // MARK: - Tool registration

    func test_stackTools_areRegistered() {
        let names = Set(TermQMCPServer.availableTools.map { $0.name })
        XCTAssertTrue(names.contains("stack_status"))
        XCTAssertTrue(names.contains("stack_create_branch"))
        XCTAssertTrue(names.contains("stack_submit"))
        XCTAssertTrue(names.contains("stack_restack"))
    }

    func test_stackStatus_isReadOnly_othersAreNot() {
        let tools = TermQMCPServer.availableTools
        XCTAssertEqual(tools.first { $0.name == "stack_status" }?.annotations.readOnlyHint, true)
        XCTAssertEqual(tools.first { $0.name == "stack_submit" }?.annotations.readOnlyHint, false)
        XCTAssertEqual(tools.first { $0.name == "stack_restack" }?.annotations.readOnlyHint, false)
        XCTAssertEqual(tools.first { $0.name == "stack_create_branch" }?.annotations.readOnlyHint, false)
    }
}
