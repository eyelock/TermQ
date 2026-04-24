import Foundation
import TermQShared
import XCTest

/// Integration tests for the termqcli command line tool
///
/// These tests verify CLI commands work correctly against test data.
/// Uses --data-dir option to isolate test data from production.
final class CLIToolTests: XCTestCase {

    // MARK: - Test Infrastructure

    var testEnv: TestEnvironment!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testEnv = try TestEnvironment.comprehensive()
    }

    override func tearDownWithError() throws {
        testEnv?.cleanup()
        testEnv = nil
        try super.tearDownWithError()
    }

    /// Run CLI command and return output
    private func runCLI(_ arguments: [String]) throws -> (output: String, exitCode: Int32) {
        let cliPath = findCLIExecutable()
        guard FileManager.default.fileExists(atPath: cliPath) else {
            throw CLITestError.executableNotFound(cliPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        return (output, process.terminationStatus)
    }

    /// Run CLI command expecting JSON output
    private func runCLIJSON(_ arguments: [String]) throws -> Any {
        let (output, exitCode) = try runCLI(arguments)

        guard exitCode == 0 else {
            throw CLITestError.commandFailed(exitCode: exitCode, output: output)
        }

        guard let data = output.data(using: .utf8) else {
            throw CLITestError.invalidOutput("Not UTF-8")
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    /// Find the CLI executable in the build directory
    private func findCLIExecutable() -> String {
        // Try standard build locations
        let possiblePaths = [
            // Swift Package Manager debug build
            ".build/debug/termqcli",
            // From test execution directory
            "../../../.build/debug/termqcli",
            // Xcode derived data
            "DerivedData/TermQ/Build/Products/Debug/termqcli",
        ]

        // Also check relative to the package root
        let packageRoot = findPackageRoot()

        for path in possiblePaths {
            let fullPath = packageRoot.appendingPathComponent(path).path
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }

        // Default to the most common location
        return packageRoot.appendingPathComponent(".build/debug/termqcli").path
    }

    /// Find the package root directory
    private func findPackageRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            let packageSwift = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwift.path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        // Fallback to current directory
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    // MARK: - List Command Tests

    func testListAllTerminals() throws {
        let args = ["list", "--data-dir", testEnv.dataDirectory.path]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        // comprehensive() creates 5 active terminals (one deleted one doesn't count)
        XCTAssertEqual(terminals.count, 5, "Should list all 5 active terminals")

        // Check first terminal has expected fields
        if let first = terminals.first {
            XCTAssertNotNil(first["id"], "Should have id")
            XCTAssertNotNil(first["name"], "Should have name")
            XCTAssertNotNil(first["column"], "Should have column")
        }
    }

    func testListWithColumnFilter() throws {
        let args = ["list", "--data-dir", testEnv.dataDirectory.path, "--column", "In Progress"]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        // All results should be in "In Progress" column
        for terminal in terminals {
            let column = terminal["column"] as? String
            XCTAssertEqual(column, "In Progress", "Should filter to In Progress column")
        }
    }

    func testListColumnsOnly() throws {
        let args = ["list", "--data-dir", testEnv.dataDirectory.path, "--columns"]
        let result = try runCLIJSON(args)

        guard let columns = result as? [[String: Any]] else {
            XCTFail("Expected array of columns")
            return
        }

        // Should have standard columns
        XCTAssertGreaterThanOrEqual(columns.count, 3, "Should have at least 3 columns")

        let columnNames = columns.compactMap { $0["name"] as? String }
        XCTAssertTrue(columnNames.contains("To Do"), "Should have To Do column")
        XCTAssertTrue(columnNames.contains("In Progress"), "Should have In Progress column")
        XCTAssertTrue(columnNames.contains("Done"), "Should have Done column")
    }

    func testListEmptyBoard() throws {
        let emptyEnv = try TestEnvironment.empty()
        defer { emptyEnv.cleanup() }

        let args = ["list", "--data-dir", emptyEnv.dataDirectory.path]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        XCTAssertEqual(terminals.count, 0, "Empty board should have no terminals")
    }

    // MARK: - Find Command Tests

    func testFindByName() throws {
        // "Fresh Active Project" is one of the terminals in comprehensive()
        let args = ["find", "--data-dir", testEnv.dataDirectory.path, "--name", "Fresh"]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        XCTAssertGreaterThanOrEqual(terminals.count, 1, "Should find at least one match")

        // First result should contain the search term
        if let first = terminals.first, let name = first["name"] as? String {
            XCTAssertTrue(name.contains("Fresh"), "Name should contain search term")
        }
    }

    func testFindByColumn() throws {
        let args = ["find", "--data-dir", testEnv.dataDirectory.path, "--column", "Done"]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        // All results should be in Done column
        for terminal in terminals {
            let column = terminal["column"] as? String
            XCTAssertEqual(column, "Done", "Should filter to Done column")
        }
    }

    func testFindByTag() throws {
        // comprehensive() board has terminals with staleness=fresh, staleness=stale, staleness=ageing
        let args = ["find", "--data-dir", testEnv.dataDirectory.path, "--tag", "staleness=fresh"]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        // Should find at least one terminal with staleness=fresh
        XCTAssertGreaterThanOrEqual(terminals.count, 1, "Should find at least one match")

        // All results should have the staleness=fresh tag
        for terminal in terminals {
            guard let tags = terminal["tags"] as? [String: String] else {
                XCTFail("Tags should be dictionary")
                continue
            }
            XCTAssertEqual(tags["staleness"], "fresh", "Should have staleness=fresh tag")
        }
    }

    func testFindByTagKeyOnly() throws {
        let args = ["find", "--data-dir", testEnv.dataDirectory.path, "--tag", "project"]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        // All results should have a project tag (any value)
        for terminal in terminals {
            guard let tags = terminal["tags"] as? [String: String] else {
                XCTFail("Tags should be dictionary")
                continue
            }
            XCTAssertNotNil(tags["project"], "Should have project tag")
        }
    }

    func testFindNoResults() throws {
        let args = ["find", "--data-dir", testEnv.dataDirectory.path, "--name", "xyznonexistent12345"]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        XCTAssertEqual(terminals.count, 0, "Should find no matches")
    }

    func testFindByID() throws {
        // First get a terminal to find its ID
        let listArgs = ["list", "--data-dir", testEnv.dataDirectory.path]
        let listResult = try runCLIJSON(listArgs)

        guard let terminals = listResult as? [[String: Any]],
            let firstTerminal = terminals.first,
            let terminalId = firstTerminal["id"] as? String
        else {
            XCTFail("Could not get terminal ID for test")
            return
        }

        // Now find by ID
        let args = ["find", "--data-dir", testEnv.dataDirectory.path, "--id", terminalId]
        let result = try runCLIJSON(args)

        guard let found = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        XCTAssertEqual(found.count, 1, "Should find exactly one terminal by ID")
        XCTAssertEqual(found.first?["id"] as? String, terminalId)
    }

    func testFindFavourites() throws {
        let args = ["find", "--data-dir", testEnv.dataDirectory.path, "--favourites"]
        let result = try runCLIJSON(args)

        guard let terminals = result as? [[String: Any]] else {
            XCTFail("Expected array of terminals")
            return
        }

        // All results should be favourites
        for terminal in terminals {
            let isFavourite = terminal["isFavourite"] as? Bool ?? false
            XCTAssertTrue(isFavourite, "Should only return favourites")
        }
    }

    // MARK: - Open Command Tests

    func testOpenReturnsTerminalDetails() throws {
        // Use an actual terminal name from comprehensive()
        let args = ["open", "--data-dir", testEnv.dataDirectory.path, "Fresh Active Project"]
        let (output, exitCode) = try runCLI(args)

        // Note: open command may fail with "Failed to communicate with TermQ"
        // since TermQ app isn't running during tests, but it should at least
        // find the terminal and attempt to construct the URL

        // Check if it found the terminal (either success output or specific error)
        if exitCode == 0 {
            // Successfully opened (TermQ must be running)
            guard let data = output.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                XCTFail("Expected JSON output on success")
                return
            }
            XCTAssertNotNil(json["id"])
            XCTAssertNotNil(json["name"])
        } else {
            // Expected: TermQ not running, but terminal should be found
            // The error should mention communication failure, not "not found"
            XCTAssertFalse(
                output.contains("Terminal not found"),
                "Terminal should be found even if TermQ isn't running"
            )
        }
    }

    func testOpenNonexistentTerminal() throws {
        let args = ["open", "--data-dir", testEnv.dataDirectory.path, "NonexistentTerminal12345"]
        let (output, exitCode) = try runCLI(args)

        XCTAssertNotEqual(exitCode, 0, "Should fail for nonexistent terminal")
        XCTAssertTrue(output.contains("not found") || output.contains("error"), "Should indicate not found")
    }

    // MARK: - Pending Command Tests

    func testPendingShowsTerminalsWithLLMNextAction() throws {
        // Create environment with terminals that have llmNextAction set
        let builder = TestBoardBuilder()
            .addColumn(name: "To Do")
            .addTerminal(
                name: "Pending Task",
                column: "To Do",
                llmNextAction: "Continue implementing feature X"
            )
            .addTerminal(
                name: "No Pending",
                column: "To Do"
            )

        let pendingEnv = try TestEnvironment.withBoard(builder)
        defer { pendingEnv.cleanup() }

        let args = ["pending", "--data-dir", pendingEnv.dataDirectory.path]
        let result = try runCLIJSON(args)

        guard let output = result as? [String: Any],
            let terminals = output["terminals"] as? [[String: Any]]
        else {
            XCTFail("Expected pending output format")
            return
        }

        // Find the terminal with pending action
        let withAction = terminals.first { ($0["llmNextAction"] as? String)?.isEmpty == false }
        XCTAssertNotNil(withAction, "Should include terminal with llmNextAction")
        let actionValue = withAction?["llmNextAction"] as? String
        XCTAssertEqual(actionValue, "Continue implementing feature X")
    }

    func testPendingActionsOnlyFlag() throws {
        // Create environment with mixed terminals
        let builder = TestBoardBuilder()
            .addColumn(name: "To Do")
            .addTerminal(
                name: "With Action",
                column: "To Do",
                llmNextAction: "Do something"
            )
            .addTerminal(
                name: "Without Action",
                column: "To Do"
            )

        let pendingEnv = try TestEnvironment.withBoard(builder)
        defer { pendingEnv.cleanup() }

        let args = ["pending", "--data-dir", pendingEnv.dataDirectory.path, "--actions-only"]
        let result = try runCLIJSON(args)

        guard let output = result as? [String: Any],
            let terminals = output["terminals"] as? [[String: Any]]
        else {
            XCTFail("Expected pending output format")
            return
        }

        // Should only include terminals with llmNextAction
        for terminal in terminals {
            let action = terminal["llmNextAction"] as? String ?? ""
            XCTAssertFalse(action.isEmpty, "All terminals should have llmNextAction with --actions-only")
        }
    }

    func testPendingSummary() throws {
        let args = ["pending", "--data-dir", testEnv.dataDirectory.path]
        let result = try runCLIJSON(args)

        guard let output = result as? [String: Any],
            let summary = output["summary"] as? [String: Any]
        else {
            XCTFail("Expected summary in pending output")
            return
        }

        XCTAssertNotNil(summary["total"], "Summary should have total")
        XCTAssertNotNil(summary["withNextAction"], "Summary should have withNextAction count")
    }

    // MARK: - Error Handling Tests

    func testMissingBoardFile() throws {
        let emptyEnv = try TestEnvironment.noBoard()
        defer { emptyEnv.cleanup() }

        let args = ["list", "--data-dir", emptyEnv.dataDirectory.path]
        let (output, exitCode) = try runCLI(args)

        XCTAssertNotEqual(exitCode, 0, "Should fail with missing board")
        XCTAssertTrue(
            output.lowercased().contains("error") || output.lowercased().contains("not found"),
            "Should indicate error"
        )
    }

    // MARK: - Write Command Tests (URL Construction Only)
    // Note: Write operations use URL schemes to communicate with TermQ app.
    // We can only test that they correctly find terminals and construct URLs,
    // not that the actual writes succeed (since TermQ app isn't running).

    func testSetFindsTerminal() throws {
        // Use an actual terminal name from comprehensive()
        let args = ["set", "Fresh Active Project", "--data-dir", testEnv.dataDirectory.path, "--badge", "test"]
        let (output, exitCode) = try runCLI(args)

        // Should find the terminal (may fail because TermQ isn't running)
        XCTAssertFalse(
            output.contains("Terminal not found"),
            "Should find the terminal"
        )

        // If TermQ isn't running, we expect the URL scheme to fail, not a "not found" error
        if exitCode != 0 {
            XCTAssertTrue(
                output.contains("TermQ") || output.contains("communicate") || output.contains("URL"),
                "Error should be about TermQ communication, not finding terminal"
            )
        }
    }

    func testSetNonexistentTerminal() throws {
        let args = [
            "set", "NonexistentTerminal12345", "--data-dir", testEnv.dataDirectory.path, "--badge", "test",
        ]
        let (output, exitCode) = try runCLI(args)

        XCTAssertNotEqual(exitCode, 0, "Should fail for nonexistent terminal")
        XCTAssertTrue(output.contains("not found"), "Should indicate terminal not found")
    }

    func testMoveFindsTerminal() throws {
        // Use an actual terminal name from comprehensive()
        let args = ["move", "Fresh Active Project", "Done", "--data-dir", testEnv.dataDirectory.path]
        let (output, exitCode) = try runCLI(args)

        // Should find the terminal
        XCTAssertFalse(
            output.contains("Terminal not found"),
            "Should find the terminal"
        )

        // If TermQ isn't running, we expect the URL scheme to fail
        if exitCode != 0 {
            XCTAssertTrue(
                output.contains("TermQ") || output.contains("communicate"),
                "Error should be about TermQ communication"
            )
        }
    }

    func testMoveNonexistentTerminal() throws {
        let args = ["move", "NonexistentTerminal12345", "Done", "--data-dir", testEnv.dataDirectory.path]
        let (output, exitCode) = try runCLI(args)

        XCTAssertNotEqual(exitCode, 0, "Should fail for nonexistent terminal")
        XCTAssertTrue(output.contains("not found"), "Should indicate terminal not found")
    }
}

// MARK: - Helper Types

enum CLITestError: Error, LocalizedError {
    case executableNotFound(String)
    case commandFailed(exitCode: Int32, output: String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "CLI executable not found at: \(path). Run 'swift build' first."
        case .commandFailed(let exitCode, let output):
            return "Command failed with exit code \(exitCode): \(output)"
        case .invalidOutput(let reason):
            return "Invalid output: \(reason)"
        }
    }
}
