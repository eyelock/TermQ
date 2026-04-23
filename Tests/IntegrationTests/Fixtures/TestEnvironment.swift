import Foundation
import TermQShared

/// Manages an isolated test environment with temporary directory and board file
///
/// Usage:
/// ```swift
/// let env = try TestEnvironment()
/// defer { env.cleanup() }
///
/// let board = TestBoardBuilder.minimal().build()
/// try env.writeBoard(board)
///
/// // Now test against env.dataDirectory
/// ```
public final class TestEnvironment {
    /// Unique identifier for this test environment
    public let id: UUID

    /// Temporary directory for this test (contains board.json)
    public let dataDirectory: URL

    /// Path to the board.json file
    public var boardURL: URL {
        dataDirectory.appendingPathComponent("board.json")
    }

    /// Initialize a new isolated test environment
    public init() throws {
        self.id = UUID()
        self.dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-IntegrationTests")
            .appendingPathComponent(id.uuidString)

        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Initialize with a specific directory (for debugging)
    public init(dataDirectory: URL) throws {
        self.id = UUID()
        self.dataDirectory = dataDirectory

        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // MARK: - Board Operations

    /// Write a board to the environment
    /// Note: Uses default date encoding (seconds since epoch) to match BoardLoader's decoder
    public func writeBoard(_ board: Board) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Important: Do NOT use .iso8601 - BoardLoader uses default decoder (seconds since epoch)
        let data = try encoder.encode(board)
        try data.write(to: boardURL)
    }

    /// Write a board from a builder
    public func writeBoard(from builder: TestBoardBuilder) throws {
        try writeBoard(builder.build())
    }

    /// Write raw JSON data as board
    public func writeBoardJSON(_ json: Data) throws {
        try json.write(to: boardURL)
    }

    /// Write raw JSON string as board
    public func writeBoardJSON(_ jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw TestEnvironmentError.invalidJSON("Could not encode string as UTF-8")
        }
        try data.write(to: boardURL)
    }

    /// Load the board using the shared BoardLoader
    public func loadBoard() throws -> Board {
        try BoardLoader.loadBoard(dataDirectory: dataDirectory)
    }

    /// Read board as raw JSON dictionary
    public func readBoardJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: boardURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestEnvironmentError.invalidJSON("Board is not a JSON object")
        }
        return json
    }

    /// Check if board file exists
    public var boardExists: Bool {
        FileManager.default.fileExists(atPath: boardURL.path)
    }

    // MARK: - Cleanup

    /// Remove the test environment directory
    public func cleanup() {
        try? FileManager.default.removeItem(at: dataDirectory)
    }

    /// Remove just the board file (keep directory)
    public func removeBoard() {
        try? FileManager.default.removeItem(at: boardURL)
    }

    deinit {
        cleanup()
    }
}

// MARK: - Errors

public enum TestEnvironmentError: Error, LocalizedError {
    case invalidJSON(String)
    case boardNotFound
    case fileOperationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let message):
            return "Invalid JSON: \(message)"
        case .boardNotFound:
            return "Board file not found"
        case .fileOperationFailed(let message):
            return "File operation failed: \(message)"
        }
    }
}

// MARK: - Test Helpers

extension TestEnvironment {
    /// Create environment with a pre-built board
    public static func withBoard(_ builder: TestBoardBuilder) throws -> TestEnvironment {
        let env = try TestEnvironment()
        try env.writeBoard(from: builder)
        return env
    }

    /// Create environment with minimal test data
    public static func minimal() throws -> TestEnvironment {
        try withBoard(TestBoardBuilder.minimal())
    }

    /// Create environment with comprehensive test data
    public static func comprehensive() throws -> TestEnvironment {
        try withBoard(TestBoardBuilder.comprehensive())
    }

    /// Create environment with worktree workflow data
    public static func worktreeWorkflow() throws -> TestEnvironment {
        try withBoard(TestBoardBuilder.worktreeWorkflow())
    }

    /// Create environment with empty board (columns only, no terminals)
    public static func empty() throws -> TestEnvironment {
        try withBoard(TestBoardBuilder())
    }

    /// Create environment with corrupted board file
    public static func corrupted() throws -> TestEnvironment {
        let env = try TestEnvironment()
        try env.writeBoardJSON("{ invalid json }")
        return env
    }

    /// Create environment with no board file
    public static func noBoard() throws -> TestEnvironment {
        try TestEnvironment()
    }
}

// MARK: - Assertions Helpers

extension TestEnvironment {
    /// Assert that a terminal exists in the board
    public func assertTerminalExists(
        name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Card {
        let board = try loadBoard()
        guard let card = board.findTerminal(identifier: name) else {
            throw TestAssertionError.terminalNotFound(name: name, file: file, line: line)
        }
        return card
    }

    /// Assert that a terminal does not exist
    public func assertTerminalDoesNotExist(
        name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let board = try loadBoard()
        if board.findTerminal(identifier: name) != nil {
            throw TestAssertionError.unexpectedTerminal(name: name, file: file, line: line)
        }
    }

    /// Get terminal count (excluding deleted)
    public func terminalCount() throws -> Int {
        let board = try loadBoard()
        return board.activeCards.count
    }
}

public enum TestAssertionError: Error, LocalizedError {
    case terminalNotFound(name: String, file: StaticString, line: UInt)
    case unexpectedTerminal(name: String, file: StaticString, line: UInt)

    public var errorDescription: String? {
        switch self {
        case .terminalNotFound(let name, let file, let line):
            return "Terminal '\(name)' not found (\(file):\(line))"
        case .unexpectedTerminal(let name, let file, let line):
            return "Terminal '\(name)' should not exist (\(file):\(line))"
        }
    }
}
