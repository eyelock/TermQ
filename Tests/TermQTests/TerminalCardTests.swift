import Foundation
import XCTest

@testable import TermQCore

final class TerminalCardTests: XCTestCase {
    func testInitializationWithDefaults() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        XCTAssertEqual(card.title, "New Terminal")
        XCTAssertEqual(card.description, "")
        XCTAssertTrue(card.tags.isEmpty)
        XCTAssertEqual(card.columnId, columnId)
        XCTAssertEqual(card.orderIndex, 0)
        XCTAssertEqual(card.shellPath, "/bin/zsh")
        XCTAssertEqual(card.workingDirectory, NSHomeDirectory())
    }

    func testInitializationWithCustomValues() {
        let columnId = UUID()
        let tags = [Tag(key: "env", value: "dev")]
        let card = TerminalCard(
            title: "My Terminal",
            description: "A test terminal",
            tags: tags,
            columnId: columnId,
            orderIndex: 5,
            shellPath: "/bin/bash",
            workingDirectory: "/tmp"
        )

        XCTAssertEqual(card.title, "My Terminal")
        XCTAssertEqual(card.description, "A test terminal")
        XCTAssertEqual(card.tags.count, 1)
        XCTAssertEqual(card.tags[0].key, "env")
        XCTAssertEqual(card.columnId, columnId)
        XCTAssertEqual(card.orderIndex, 5)
        XCTAssertEqual(card.shellPath, "/bin/bash")
        XCTAssertEqual(card.workingDirectory, "/tmp")
    }

    func testCodableRoundTrip() throws {
        let columnId = UUID()
        let tags = [
            Tag(key: "project", value: "termq"),
            Tag(key: "env", value: "test"),
        ]
        let original = TerminalCard(
            title: "Encoded Card",
            description: "Test description",
            tags: tags,
            columnId: columnId,
            orderIndex: 3,
            shellPath: "/bin/fish",
            workingDirectory: "/var/tmp"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.tags.count, original.tags.count)
        XCTAssertEqual(decoded.columnId, original.columnId)
        XCTAssertEqual(decoded.orderIndex, original.orderIndex)
        XCTAssertEqual(decoded.shellPath, original.shellPath)
        XCTAssertEqual(decoded.workingDirectory, original.workingDirectory)
    }

    func testEquatableConformance() {
        let id = UUID()
        let columnId = UUID()

        let card1 = TerminalCard(id: id, title: "A", columnId: columnId)
        let card2 = TerminalCard(id: id, title: "B", columnId: columnId)  // Same ID

        XCTAssertEqual(card1, card2)  // Equal by ID

        let card3 = TerminalCard(title: "A", columnId: columnId)
        XCTAssertNotEqual(card1, card3)  // Different IDs
    }

    func testObservableProperties() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        card.title = "Updated Title"
        card.description = "Updated description"
        card.tags = [Tag(key: "new", value: "tag")]
        card.shellPath = "/bin/sh"
        card.workingDirectory = "/usr/local"

        XCTAssertEqual(card.title, "Updated Title")
        XCTAssertEqual(card.description, "Updated description")
        XCTAssertEqual(card.tags.count, 1)
        XCTAssertEqual(card.shellPath, "/bin/sh")
        XCTAssertEqual(card.workingDirectory, "/usr/local")
    }

    // MARK: - Safe Paste Tests

    func testSafePasteEnabledDefaultsToTrue() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        XCTAssertTrue(card.safePasteEnabled)
    }

    func testSafePasteEnabledCustomValue() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId, safePasteEnabled: false)

        XCTAssertFalse(card.safePasteEnabled)
    }

    func testSafePasteEnabledCodableRoundTrip() throws {
        let columnId = UUID()
        let original = TerminalCard(columnId: columnId, safePasteEnabled: false)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertEqual(decoded.safePasteEnabled, original.safePasteEnabled)
        XCTAssertFalse(decoded.safePasteEnabled)
    }

    func testSafePasteEnabledDefaultsToTrueWhenMissingInJSON() throws {
        // Simulate loading old data without safePasteEnabled field
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test",
                "description": "",
                "tags": [],
                "columnId": "\(columnId.uuidString)",
                "orderIndex": 0,
                "shellPath": "/bin/zsh",
                "workingDirectory": "/tmp",
                "isFavourite": false,
                "initCommand": "",
                "llmPrompt": "",
                "badge": "",
                "fontName": "",
                "fontSize": 0
            }
            """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: json.data(using: .utf8)!)

        // Should default to true when missing
        XCTAssertTrue(decoded.safePasteEnabled)
    }

    // MARK: - Theme ID Tests

    func testThemeIdDefaultsToEmpty() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        XCTAssertEqual(card.themeId, "")
    }

    func testThemeIdCustomValue() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId, themeId: "dracula")

        XCTAssertEqual(card.themeId, "dracula")
    }

    func testThemeIdCodableRoundTrip() throws {
        let columnId = UUID()
        let original = TerminalCard(columnId: columnId, themeId: "monokai")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertEqual(decoded.themeId, original.themeId)
        XCTAssertEqual(decoded.themeId, "monokai")
    }

    func testThemeIdDefaultsToEmptyWhenMissingInJSON() throws {
        // Simulate loading old data without themeId field
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test",
                "description": "",
                "tags": [],
                "columnId": "\(columnId.uuidString)",
                "orderIndex": 0,
                "shellPath": "/bin/zsh",
                "workingDirectory": "/tmp",
                "isFavourite": false,
                "initCommand": "",
                "llmPrompt": "",
                "badge": "",
                "fontName": "",
                "fontSize": 0,
                "safePasteEnabled": true
            }
            """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: json.data(using: .utf8)!)

        // Should default to empty when missing
        XCTAssertEqual(decoded.themeId, "")
    }

    func testThemeIdObservable() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        XCTAssertEqual(card.themeId, "")

        card.themeId = "nord"
        XCTAssertEqual(card.themeId, "nord")

        card.themeId = ""
        XCTAssertEqual(card.themeId, "")
    }

    // MARK: - LLM Next Action Tests

    func testLlmNextActionDefaultsToEmpty() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        XCTAssertEqual(card.llmNextAction, "")
    }

    func testLlmNextActionCustomValue() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId, llmNextAction: "Fix the auth bug")

        XCTAssertEqual(card.llmNextAction, "Fix the auth bug")
    }

    func testLlmNextActionCodableRoundTrip() throws {
        let columnId = UUID()
        let original = TerminalCard(columnId: columnId, llmNextAction: "Continue from line 42")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertEqual(decoded.llmNextAction, original.llmNextAction)
        XCTAssertEqual(decoded.llmNextAction, "Continue from line 42")
    }

    func testLlmNextActionDefaultsToEmptyWhenMissingInJSON() throws {
        // Simulate loading old data without llmNextAction field
        let columnId = UUID()
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Test",
                "description": "",
                "tags": [],
                "columnId": "\(columnId.uuidString)",
                "orderIndex": 0,
                "shellPath": "/bin/zsh",
                "workingDirectory": "/tmp",
                "isFavourite": false,
                "initCommand": "",
                "llmPrompt": "",
                "badge": "",
                "fontName": "",
                "fontSize": 0,
                "safePasteEnabled": true,
                "themeId": ""
            }
            """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: json.data(using: .utf8)!)

        // Should default to empty when missing
        XCTAssertEqual(decoded.llmNextAction, "")
    }

    func testLlmNextActionObservable() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        XCTAssertEqual(card.llmNextAction, "")

        card.llmNextAction = "Implement feature X"
        XCTAssertEqual(card.llmNextAction, "Implement feature X")

        card.llmNextAction = ""
        XCTAssertEqual(card.llmNextAction, "")
    }

    func testBothLlmFieldsCoexist() {
        let columnId = UUID()
        let card = TerminalCard(
            columnId: columnId,
            llmPrompt: "Node.js backend",
            llmNextAction: "Fix the auth bug"
        )

        XCTAssertEqual(card.llmPrompt, "Node.js backend")
        XCTAssertEqual(card.llmNextAction, "Fix the auth bug")

        // Clear next action (simulating after use)
        card.llmNextAction = ""
        XCTAssertEqual(card.llmPrompt, "Node.js backend")  // Prompt unchanged
        XCTAssertEqual(card.llmNextAction, "")
    }

    // MARK: - Encode Tests for Optional Date Fields

    func testEncodeWithDeletedAt() throws {
        let columnId = UUID()
        let deletedDate = Date()
        let card = TerminalCard(columnId: columnId, deletedAt: deletedDate)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(card)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertNotNil(decoded.deletedAt)
        XCTAssertEqual(
            decoded.deletedAt?.timeIntervalSinceReferenceDate ?? 0,
            deletedDate.timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    func testEncodeWithLastLLMGet() throws {
        let columnId = UUID()
        let lastGetDate = Date()
        let card = TerminalCard(columnId: columnId, lastLLMGet: lastGetDate)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(card)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertNotNil(decoded.lastLLMGet)
        XCTAssertEqual(
            decoded.lastLLMGet?.timeIntervalSinceReferenceDate ?? 0,
            lastGetDate.timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    func testEncodeWithBothDatesNil() throws {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        let encoder = JSONEncoder()
        let data = try encoder.encode(card)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertNil(decoded.deletedAt)
        XCTAssertNil(decoded.lastLLMGet)
    }

    func testEncodeWithBothDatesSet() throws {
        let columnId = UUID()
        let card = TerminalCard(
            columnId: columnId,
            deletedAt: Date(timeIntervalSinceNow: -3600),
            lastLLMGet: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(card)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertNotNil(decoded.deletedAt)
        XCTAssertNotNil(decoded.lastLLMGet)
    }

    // MARK: - All Properties Round Trip

    func testFullCodableRoundTripAllProperties() throws {
        let columnId = UUID()
        let tag = Tag(key: "env", value: "prod")

        let original = TerminalCard(
            title: "Full Test",
            description: "Complete test card",
            tags: [tag],
            columnId: columnId,
            orderIndex: 5,
            shellPath: "/usr/bin/fish",
            workingDirectory: "/tmp/test",
            isFavourite: true,
            initCommand: "echo 'Hello'",
            llmPrompt: "Python project",
            llmNextAction: "Fix bug #123",
            badge: "dev,main",
            fontName: "Monaco",
            fontSize: 14,
            safePasteEnabled: false,
            themeId: "dracula",
            allowAutorun: true,
            deletedAt: Date(timeIntervalSinceNow: -86400),
            lastLLMGet: Date(),
            backend: .tmux
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, "Full Test")
        XCTAssertEqual(decoded.description, "Complete test card")
        XCTAssertEqual(decoded.tags.count, 1)
        XCTAssertEqual(decoded.columnId, columnId)
        XCTAssertEqual(decoded.orderIndex, 5)
        XCTAssertEqual(decoded.shellPath, "/usr/bin/fish")
        XCTAssertEqual(decoded.workingDirectory, "/tmp/test")
        XCTAssertTrue(decoded.isFavourite)
        XCTAssertEqual(decoded.initCommand, "echo 'Hello'")
        XCTAssertEqual(decoded.llmPrompt, "Python project")
        XCTAssertEqual(decoded.llmNextAction, "Fix bug #123")
        XCTAssertEqual(decoded.badge, "dev,main")
        XCTAssertEqual(decoded.fontName, "Monaco")
        XCTAssertEqual(decoded.fontSize, 14)
        XCTAssertFalse(decoded.safePasteEnabled)
        XCTAssertEqual(decoded.themeId, "dracula")
        XCTAssertTrue(decoded.allowAutorun)
        XCTAssertNotNil(decoded.deletedAt)
        XCTAssertNotNil(decoded.lastLLMGet)
        XCTAssertEqual(decoded.backend, .tmux)
    }
}
