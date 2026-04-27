import Foundation
import TermQShared

/// Fluent builder for creating test boards programmatically
///
/// Usage:
/// ```swift
/// let board = try TestBoardBuilder()
///     .addColumn(name: "To Do")
///     .addColumn(name: "In Progress")
///     .addTerminal(name: "Test Terminal", column: "To Do")
///     .build()
/// ```
public final class TestBoardBuilder {
    private var columns: [Column] = []
    private var cards: [Card] = []

    public init() {
        // Add default columns
        addColumn(name: "To Do", description: "Tasks to start")
        addColumn(name: "In Progress", description: "Active work")
        addColumn(name: "Done", description: "Completed tasks")
    }

    // MARK: - Column Methods

    @discardableResult
    public func addColumn(
        name: String,
        description: String = "",
        color: String = "#808080"
    ) -> TestBoardBuilder {
        let column = Column(
            id: UUID(),
            name: name,
            description: description,
            orderIndex: columns.count,
            color: color
        )
        columns.append(column)
        return self
    }

    @discardableResult
    public func clearColumns() -> TestBoardBuilder {
        columns.removeAll()
        return self
    }

    // MARK: - Terminal/Card Methods

    @discardableResult
    public func addTerminal(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        column: String = "To Do",
        path: String = "/tmp/test",
        tags: [String: String] = [:],
        isFavourite: Bool = false,
        badge: String = "",
        llmPrompt: String = "",
        llmNextAction: String = "",
        allowAutorun: Bool = false
    ) -> TestBoardBuilder {
        guard let targetColumn = columns.first(where: { $0.name == column }) else {
            fatalError("Column '\(column)' not found. Add it first with addColumn().")
        }

        let cardsInColumn = cards.filter { $0.columnId == targetColumn.id }
        let orderIndex = cardsInColumn.count

        let card = Card(
            id: id,
            title: name,
            description: description,
            tags: tags.map { Tag(key: $0.key, value: $0.value) },
            columnId: targetColumn.id,
            orderIndex: orderIndex,
            workingDirectory: path,
            isFavourite: isFavourite,
            badge: badge,
            llmPrompt: llmPrompt,
            llmNextAction: llmNextAction,
            allowAutorun: allowAutorun,
            deletedAt: nil
        )
        cards.append(card)
        return self
    }

    @discardableResult
    public func addDeletedTerminal(
        name: String,
        column: String = "To Do"
    ) -> TestBoardBuilder {
        guard let targetColumn = columns.first(where: { $0.name == column }) else {
            fatalError("Column '\(column)' not found.")
        }

        let card = Card(
            id: UUID(),
            title: name,
            description: "Deleted terminal",
            tags: [],
            columnId: targetColumn.id,
            orderIndex: 0,
            workingDirectory: "/tmp/deleted",
            isFavourite: false,
            badge: "",
            llmPrompt: "",
            llmNextAction: "",
            allowAutorun: false,
            deletedAt: Date()
        )
        cards.append(card)
        return self
    }

    // MARK: - Build

    public func build() -> Board {
        Board(columns: columns, cards: cards)
    }

    public func buildJSON() throws -> Data {
        let board = build()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(board)
    }
}

// MARK: - Convenience Extensions

extension TestBoardBuilder {
    /// Create a minimal board with just one terminal
    public static func minimal(terminalName: String = "Test Terminal") -> TestBoardBuilder {
        TestBoardBuilder()
            .addTerminal(name: terminalName, column: "To Do")
    }

    /// Create a board with terminals in various states for comprehensive testing
    public static func comprehensive() -> TestBoardBuilder {
        TestBoardBuilder()
            .addTerminal(
                name: "Fresh Active Project",
                description: "Currently being worked on",
                column: "In Progress",
                path: "/Users/test/projects/active",
                tags: ["staleness": "fresh", "status": "active", "project": "test/repo"],
                llmPrompt: "Node.js backend with PostgreSQL",
                llmNextAction: "Continue implementing rate limiting"
            )
            .addTerminal(
                name: "Stale Project",
                description: "Hasn't been touched in a while",
                column: "In Progress",
                path: "/Users/test/projects/stale",
                tags: ["staleness": "stale", "status": "blocked", "blocked-by": "review"]
            )
            .addTerminal(
                name: "Favourite Terminal",
                description: "Marked as favourite",
                column: "To Do",
                isFavourite: true,
                badge: "important,urgent"
            )
            .addTerminal(
                name: "Completed Work",
                description: "All done",
                column: "Done",
                tags: ["staleness": "ageing", "status": "review"]
            )
            .addTerminal(
                name: "Autorun Enabled",
                description: "Has autorun permission",
                column: "To Do",
                llmNextAction: "Run tests",
                allowAutorun: true
            )
            .addDeletedTerminal(name: "Deleted Terminal")
    }

    /// Create a board simulating a worktree workflow
    public static func worktreeWorkflow() -> TestBoardBuilder {
        TestBoardBuilder()
            .addTerminal(
                name: "main",
                description: "Main development branch",
                column: "Done",
                path: "/Users/test/projects/repo",
                tags: ["worktree": "main", "project": "org/repo"]
            )
            .addTerminal(
                name: "feat/new-feature",
                description: "Feature branch worktree",
                column: "In Progress",
                path: "/Users/test/projects/repo-feat-new-feature",
                tags: ["worktree": "feat/new-feature", "project": "org/repo", "staleness": "fresh"],
                llmPrompt: "Implementing user authentication",
                llmNextAction: "Add OAuth2 integration"
            )
            .addTerminal(
                name: "fix/bug-123",
                description: "Bug fix worktree",
                column: "To Do",
                path: "/Users/test/projects/repo-fix-bug-123",
                tags: ["worktree": "fix/bug-123", "project": "org/repo", "type": "bugfix"]
            )
    }
}
