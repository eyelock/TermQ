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
        XCTAssertFalse(card.isRunning)
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

    func testIsRunningNotPersisted() throws {
        let columnId = UUID()
        let original = TerminalCard(columnId: columnId)
        original.isRunning = true

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        // isRunning should be false after decoding (not persisted)
        XCTAssertFalse(decoded.isRunning)
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
}
