import Foundation
import XCTest

@testable import TermQCore

/// Tests for tmux metadata structures and encoding/decoding
/// Note: These tests cover the metadata structures. Integration tests with actual tmux
/// require tmux to be installed and are better suited for manual/integration testing.
final class TmuxMetadataTests: XCTestCase {

    // MARK: - TerminalCard Backend Tests

    func testBackendDefaultsToDirect() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        XCTAssertEqual(card.backend, .direct)
    }

    func testBackendCanBeSetToDirect() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId, backend: .direct)

        XCTAssertEqual(card.backend, .direct)
    }

    func testBackendCodableRoundTrip() throws {
        let columnId = UUID()
        let original = TerminalCard(columnId: columnId, backend: .tmuxAttach)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertEqual(decoded.backend, original.backend)
        XCTAssertEqual(decoded.backend, .tmuxAttach)
    }

    func testDirectBackendCodableRoundTrip() throws {
        let columnId = UUID()
        let original = TerminalCard(columnId: columnId, backend: .direct)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: data)

        XCTAssertEqual(decoded.backend, .direct)
    }

    func testBackendDefaultsToDirectWhenMissingInJSON() throws {
        // Simulate loading old data without backend field (pre-tmux feature cards)
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
                "llmNextAction": "",
                "badge": "",
                "fontName": "",
                "fontSize": 0,
                "safePasteEnabled": true,
                "themeId": "",
                "allowAutorun": false
            }
            """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalCard.self, from: json.data(using: .utf8)!)

        // Should default to direct when missing (pre-tmux cards were direct mode)
        XCTAssertEqual(decoded.backend, .direct)
    }

    // MARK: - tmux Session Name Tests

    func testTmuxSessionName() {
        let id = UUID()
        let card = TerminalCard(id: id, columnId: UUID())

        let expectedPrefix = "termq-\(id.uuidString.prefix(8).lowercased())"
        XCTAssertEqual(card.tmuxSessionName, expectedPrefix)
    }

    func testTmuxSessionNameIsConsistent() {
        let id = UUID()
        let card = TerminalCard(id: id, columnId: UUID())

        // Session name should be consistent across calls
        XCTAssertEqual(card.tmuxSessionName, card.tmuxSessionName)
    }

    func testTmuxSessionNameFormat() {
        let card = TerminalCard(columnId: UUID())

        // Should start with "termq-"
        XCTAssertTrue(card.tmuxSessionName.hasPrefix("termq-"))

        // Should be lowercase
        XCTAssertEqual(card.tmuxSessionName, card.tmuxSessionName.lowercased())

        // Should have predictable length (termq- + 8 chars = 14)
        XCTAssertEqual(card.tmuxSessionName.count, 14)
    }

    // MARK: - Backend Display Names

    func testBackendDisplayNames() {
        // In test environment, NSLocalizedString returns keys, not translated values
        // We verify the keys are correct localization strings
        XCTAssertTrue(TerminalBackend.direct.displayName.contains("backend.direct"))
        XCTAssertTrue(TerminalBackend.tmuxAttach.displayName.contains("backend.tmux.attach"))
        XCTAssertTrue(TerminalBackend.tmuxControl.displayName.contains("backend.tmux.control"))
    }

    func testBackendDescriptions() {
        // In test environment, NSLocalizedString returns keys, not translated values
        XCTAssertTrue(TerminalBackend.direct.description.contains("backend.direct.description"))
        XCTAssertTrue(TerminalBackend.tmuxAttach.description.contains("backend.tmux.attach.description"))
        XCTAssertTrue(TerminalBackend.tmuxControl.description.contains("backend.tmux.control.description"))
    }

    // MARK: - Backend Observable

    func testBackendObservable() {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId)

        XCTAssertEqual(card.backend, .direct)

        card.backend = .tmuxAttach
        XCTAssertEqual(card.backend, .tmuxAttach)

        card.backend = .tmuxControl
        XCTAssertEqual(card.backend, .tmuxControl)

        card.backend = .direct
        XCTAssertEqual(card.backend, .direct)
    }

    // MARK: - isWired Tests (LLM awareness tracking)

    func testIsWiredFalseWhenNeverCalled() {
        let card = TerminalCard(columnId: UUID())
        XCTAssertNil(card.lastLLMGet)
        XCTAssertFalse(card.isWired)
    }

    func testIsWiredTrueWhenRecentlyAccessed() {
        let card = TerminalCard(columnId: UUID())
        card.lastLLMGet = Date()
        XCTAssertTrue(card.isWired)
    }

    func testIsWiredFalseWhenAccessedLongAgo() {
        let card = TerminalCard(columnId: UUID())
        // Set to 11 minutes ago (threshold is 10 minutes)
        card.lastLLMGet = Date().addingTimeInterval(-660)
        XCTAssertFalse(card.isWired)
    }

    func testIsWiredAtThresholdBoundary() {
        let card = TerminalCard(columnId: UUID())

        // Just under threshold (9 minutes ago)
        card.lastLLMGet = Date().addingTimeInterval(-540)
        XCTAssertTrue(card.isWired)

        // Just over threshold (11 minutes ago)
        card.lastLLMGet = Date().addingTimeInterval(-660)
        XCTAssertFalse(card.isWired)
    }

    // MARK: - Metadata Fields for Sync

    func testAllMetadataFieldsPresent() {
        let columnId = UUID()
        let tags = [Tag(key: "env", value: "prod")]
        let card = TerminalCard(
            title: "Test Terminal",
            description: "A test description",
            tags: tags,
            columnId: columnId,
            isFavourite: true,
            llmPrompt: "This is a Node.js project",
            llmNextAction: "Fix the auth bug",
            badge: "prod,main"
        )

        // Verify all fields that would be synced to tmux
        XCTAssertEqual(card.title, "Test Terminal")
        XCTAssertEqual(card.description, "A test description")
        XCTAssertEqual(card.tags.count, 1)
        XCTAssertEqual(card.tags.first?.key, "env")
        XCTAssertEqual(card.tags.first?.value, "prod")
        XCTAssertEqual(card.columnId, columnId)
        XCTAssertTrue(card.isFavourite)
        XCTAssertEqual(card.llmPrompt, "This is a Node.js project")
        XCTAssertEqual(card.llmNextAction, "Fix the auth bug")
        XCTAssertEqual(card.badge, "prod,main")
    }

    func testBadgesParsingMultiple() {
        let card = TerminalCard(columnId: UUID(), badge: "prod, main, v2.0")

        let badges = card.badges
        XCTAssertEqual(badges.count, 3)
        XCTAssertEqual(badges[0], "prod")
        XCTAssertEqual(badges[1], "main")
        XCTAssertEqual(badges[2], "v2.0")
    }

    func testBadgesParsingEmpty() {
        let card = TerminalCard(columnId: UUID(), badge: "")
        XCTAssertTrue(card.badges.isEmpty)
    }

    func testBadgesParsingSingle() {
        let card = TerminalCard(columnId: UUID(), badge: "dev")
        XCTAssertEqual(card.badges, ["dev"])
    }

    // MARK: - Tag Encoding for Sync

    func testTagsCanBeEncodedAsString() {
        // This mimics what TmuxManager does for tag encoding
        let tags = [
            Tag(key: "env", value: "production"),
            Tag(key: "project", value: "termq"),
        ]

        let encoded = tags.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        XCTAssertEqual(encoded, "env:production,project:termq")

        // Verify we can decode it back
        let decoded = encoded.split(separator: ",").compactMap { pair -> Tag? in
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Tag(key: String(parts[0]), value: String(parts[1]))
        }

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].key, "env")
        XCTAssertEqual(decoded[0].value, "production")
        XCTAssertEqual(decoded[1].key, "project")
        XCTAssertEqual(decoded[1].value, "termq")
    }

    func testTagEncodingWithColonInValue() {
        // Tags with colons in the value should work with maxSplits: 1
        let tag = Tag(key: "url", value: "https://example.com")

        let encoded = "\(tag.key):\(tag.value)"
        XCTAssertEqual(encoded, "url:https://example.com")

        // Decode with maxSplits: 1
        let parts = encoded.split(separator: ":", maxSplits: 1)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "url")
        XCTAssertEqual(String(parts[1]), "https://example.com")
    }

    func testEmptyTagsEncoding() {
        let tags: [Tag] = []
        let encoded = tags.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        XCTAssertEqual(encoded, "")
    }

    // MARK: - TerminalCard Full Property Tests

    func testTerminalCardAllPropertiesInitialization() {
        let id = UUID()
        let columnId = UUID()
        let tags = [Tag(key: "type", value: "dev"), Tag(key: "team", value: "backend")]

        let card = TerminalCard(
            id: id,
            title: "Dev Server",
            description: "Development backend server",
            tags: tags,
            columnId: columnId,
            orderIndex: 3,
            shellPath: "/bin/bash",
            workingDirectory: "/home/dev/project",
            isFavourite: true,
            initCommand: "npm run dev",
            llmPrompt: "This is a Node.js backend service",
            llmNextAction: "Check test coverage",
            badge: "dev,v2,urgent",
            fontName: "Menlo",
            fontSize: 14,
            safePasteEnabled: false,
            themeId: "dracula",
            allowAutorun: true,
            backend: .tmuxAttach
        )

        XCTAssertEqual(card.id, id)
        XCTAssertEqual(card.title, "Dev Server")
        XCTAssertEqual(card.description, "Development backend server")
        XCTAssertEqual(card.tags.count, 2)
        XCTAssertEqual(card.columnId, columnId)
        XCTAssertEqual(card.orderIndex, 3)
        XCTAssertEqual(card.shellPath, "/bin/bash")
        XCTAssertEqual(card.workingDirectory, "/home/dev/project")
        XCTAssertTrue(card.isFavourite)
        XCTAssertEqual(card.initCommand, "npm run dev")
        XCTAssertEqual(card.llmPrompt, "This is a Node.js backend service")
        XCTAssertEqual(card.llmNextAction, "Check test coverage")
        XCTAssertEqual(card.badge, "dev,v2,urgent")
        XCTAssertEqual(card.fontName, "Menlo")
        XCTAssertEqual(card.fontSize, 14)
        XCTAssertFalse(card.safePasteEnabled)
        XCTAssertEqual(card.themeId, "dracula")
        XCTAssertEqual(card.backend, .tmuxAttach)
        XCTAssertTrue(card.allowAutorun)
    }

    // MARK: - TerminalBackend Enum Tests

    func testBackendAllCases() {
        let allCases = TerminalBackend.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.direct))
        XCTAssertTrue(allCases.contains(.tmuxAttach))
        XCTAssertTrue(allCases.contains(.tmuxControl))
    }

    func testBackendRawValues() {
        XCTAssertEqual(TerminalBackend.direct.rawValue, "direct")
        XCTAssertEqual(TerminalBackend.tmuxAttach.rawValue, "tmuxAttach")
        XCTAssertEqual(TerminalBackend.tmuxControl.rawValue, "tmuxControl")
    }

    func testBackendFromRawValue() {
        XCTAssertEqual(TerminalBackend(rawValue: "direct"), .direct)
        XCTAssertEqual(TerminalBackend(rawValue: "tmuxAttach"), .tmuxAttach)
        XCTAssertEqual(TerminalBackend(rawValue: "tmuxControl"), .tmuxControl)
        XCTAssertNil(TerminalBackend(rawValue: "invalid"))
    }

    func testBackendUsesTmuxHelper() {
        XCTAssertFalse(TerminalBackend.direct.usesTmux)
        XCTAssertTrue(TerminalBackend.tmuxAttach.usesTmux)
        XCTAssertTrue(TerminalBackend.tmuxControl.usesTmux)
    }

    // MARK: - Tag Tests

    func testTagInitialization() {
        let tag = Tag(key: "environment", value: "production")

        XCTAssertEqual(tag.key, "environment")
        XCTAssertEqual(tag.value, "production")
    }

    func testTagWithCustomId() {
        let customId = UUID()
        let tag = Tag(id: customId, key: "test", value: "value")

        XCTAssertEqual(tag.id, customId)
    }

    func testTagHashable() {
        let tag1 = Tag(key: "env", value: "dev")
        let tag2 = Tag(key: "env", value: "dev")
        let tag3 = Tag(key: "env", value: "prod")

        // Same key/value but different UUIDs, so not equal
        XCTAssertNotEqual(tag1, tag2)

        // Different values, definitely not equal
        XCTAssertNotEqual(tag1, tag3)

        // Set operations should work
        var tagSet = Set<Tag>()
        tagSet.insert(tag1)
        tagSet.insert(tag2)
        XCTAssertEqual(tagSet.count, 2)  // Both are unique due to different UUIDs
    }

    func testTagCodable() throws {
        let original = Tag(key: "deployment", value: "kubernetes")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tag.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.key, original.key)
        XCTAssertEqual(decoded.value, original.value)
    }

    // MARK: - isTransient Tests

    func testCardIsTransientWhenMarked() {
        let card = TerminalCard(columnId: UUID())
        card.isTransient = true
        XCTAssertTrue(card.isTransient)
    }

    func testCardIsNotTransientWhenHasColumnId() {
        let card = TerminalCard(columnId: UUID())
        XCTAssertFalse(card.isTransient)
    }

    // MARK: - tmux Session Name Edge Cases

    func testTmuxSessionNameDifferentCards() {
        let card1 = TerminalCard(columnId: UUID())
        let card2 = TerminalCard(columnId: UUID())

        // Different cards should have different session names
        XCTAssertNotEqual(card1.tmuxSessionName, card2.tmuxSessionName)
    }

    func testTmuxSessionNameUsesLowercasedUUID() {
        let id = UUID()
        let card = TerminalCard(id: id, columnId: UUID())

        // Verify the session name uses lowercase
        let expected = "termq-\(id.uuidString.prefix(8).lowercased())"
        XCTAssertEqual(card.tmuxSessionName, expected)

        // Also verify it's all lowercase
        XCTAssertEqual(card.tmuxSessionName, card.tmuxSessionName.lowercased())
    }

    // MARK: - Badge Parsing Edge Cases

    func testBadgesWithWhitespaceOnly() {
        let card = TerminalCard(columnId: UUID(), badge: "   ")
        // Should filter out empty strings after trimming
        XCTAssertTrue(card.badges.isEmpty || card.badges.allSatisfy { !$0.isEmpty })
    }

    func testBadgesWithExtraCommas() {
        let card = TerminalCard(columnId: UUID(), badge: "dev,,prod,")
        // Should handle extra commas gracefully
        let nonEmptyBadges = card.badges.filter { !$0.isEmpty }
        XCTAssertTrue(nonEmptyBadges.contains("dev"))
        XCTAssertTrue(nonEmptyBadges.contains("prod"))
    }

    // MARK: - isWired Edge Cases

    func testIsWiredExactlyAtThreshold() {
        let card = TerminalCard(columnId: UUID())
        // Exactly at 10 minute threshold
        card.lastLLMGet = Date().addingTimeInterval(-600)

        // At exactly 10 minutes, should be considered not wired (>= 10 minutes)
        // The implementation uses < 600 seconds
        XCTAssertFalse(card.isWired)
    }

    func testIsWiredJustBeforeThreshold() {
        let card = TerminalCard(columnId: UUID())
        // One second before threshold
        card.lastLLMGet = Date().addingTimeInterval(-599)
        XCTAssertTrue(card.isWired)
    }

    func testIsWiredFutureDateHandling() {
        let card = TerminalCard(columnId: UUID())
        // Future date (which shouldn't happen but should be handled)
        card.lastLLMGet = Date().addingTimeInterval(60)
        // A future date is still within the 10 minute window
        XCTAssertTrue(card.isWired)
    }

    // MARK: - Metadata Sync Encoding Edge Cases

    func testTagEncodingWithEmptyKey() {
        let tag = Tag(key: "", value: "value")
        let encoded = "\(tag.key):\(tag.value)"
        XCTAssertEqual(encoded, ":value")
    }

    func testTagEncodingWithEmptyValue() {
        let tag = Tag(key: "key", value: "")
        let encoded = "\(tag.key):\(tag.value)"
        XCTAssertEqual(encoded, "key:")
    }

    func testTagEncodingWithSpecialCharacters() {
        let tag = Tag(key: "path", value: "/usr/local/bin")
        let encoded = "\(tag.key):\(tag.value)"

        // Verify encoding preserves special characters
        XCTAssertTrue(encoded.contains("/"))
        XCTAssertEqual(encoded, "path:/usr/local/bin")
    }

    func testLongDescriptionHandling() {
        let longDesc = String(repeating: "This is a test. ", count: 100)
        let card = TerminalCard(description: longDesc, columnId: UUID())

        XCTAssertEqual(card.description, longDesc)
        XCTAssertGreaterThan(card.description.count, 1000)
    }

    func testUnicodeInMetadata() {
        let card = TerminalCard(
            title: "测试终端 🚀",
            description: "Unicode description: こんにちは",
            columnId: UUID(),
            llmPrompt: "Prompt with emoji: 👋"
        )

        XCTAssertTrue(card.title.contains("🚀"))
        XCTAssertTrue(card.description.contains("こんにちは"))
        XCTAssertTrue(card.llmPrompt.contains("👋"))
    }
}
