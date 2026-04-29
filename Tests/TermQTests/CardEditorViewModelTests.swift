import XCTest

@testable import TermQ
@testable import TermQCore

@MainActor
final class CardEditorViewModelTests: XCTestCase {

    // MARK: - isValid

    func testIsValid_emptyTitle_false() {
        let vm = CardEditorViewModel()
        vm.title = ""
        XCTAssertFalse(vm.isValid)
    }

    func testIsValid_whitespaceOnlyTitle_false() {
        let vm = CardEditorViewModel()
        vm.title = "   "
        XCTAssertFalse(vm.isValid)
    }

    func testIsValid_populatedTitle_true() {
        let vm = CardEditorViewModel()
        vm.title = "My Terminal"
        XCTAssertTrue(vm.isValid)
    }

    func testIsValid_titleWithLeadingTrailingSpaces_true() {
        let vm = CardEditorViewModel()
        vm.title = "  My Terminal  "
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - load(from:)

    func testLoad_populatesAllFields() {
        let columnId = UUID()
        let card = TerminalCard(columnId: UUID())
        card.title = "My Terminal"
        card.description = "A test terminal"
        card.workingDirectory = "/Users/test"
        card.shellPath = "/bin/zsh"
        card.columnId = columnId
        card.isFavourite = true
        card.initCommand = "echo hello"
        card.llmPrompt = "Node.js project"
        card.llmNextAction = "Fix bug"
        card.badge = "urgent"
        card.fontName = "Menlo"
        card.fontSize = 14
        card.safePasteEnabled = false
        card.themeId = "dark"
        card.allowAutorun = true
        card.allowOscClipboard = false
        card.confirmExternalModifications = false
        card.backend = TerminalBackend.tmuxAttach

        let vm = CardEditorViewModel()
        vm.load(from: card)

        XCTAssertEqual(vm.title, "My Terminal")
        XCTAssertEqual(vm.description, "A test terminal")
        XCTAssertEqual(vm.workingDirectory, "/Users/test")
        XCTAssertEqual(vm.shellPath, "/bin/zsh")
        XCTAssertEqual(vm.selectedColumnId, columnId)
        XCTAssertTrue(vm.isFavourite)
        XCTAssertEqual(vm.initCommand, "echo hello")
        XCTAssertEqual(vm.llmPrompt, "Node.js project")
        XCTAssertEqual(vm.llmNextAction, "Fix bug")
        XCTAssertEqual(vm.badge, "urgent")
        XCTAssertEqual(vm.fontName, "Menlo")
        XCTAssertEqual(vm.fontSize, 14)
        XCTAssertEqual(vm.safePasteEnabled, false)
        XCTAssertEqual(vm.themeId, "dark")
        XCTAssertTrue(vm.allowAutorun)
        XCTAssertFalse(vm.allowOscClipboard)
        XCTAssertFalse(vm.confirmExternalModifications)
        XCTAssertEqual(vm.backend, .tmuxAttach)
    }

    func testLoad_fontSizeNil_loadsAsInherit() {
        // Pre-Optional behavior: fontSize=0 sentinel was treated as
        // "default 13pt" at load time. The Optional contract surfaces
        // "inherit" explicitly so the editor's override toggle has
        // something honest to bind to.
        let card = TerminalCard(columnId: UUID())
        card.fontSize = nil

        let vm = CardEditorViewModel()
        vm.load(from: card)

        XCTAssertNil(vm.fontSize)
    }

    func testLoad_sortsTags() {
        let card = TerminalCard(columnId: UUID())
        card.tags = [
            Tag(key: "zzz", value: "last"),
            Tag(key: "aaa", value: "first"),
            Tag(key: "mmm", value: "middle"),
        ]

        let vm = CardEditorViewModel()
        vm.load(from: card)

        XCTAssertEqual(vm.tags.map { $0.key }, ["aaa", "mmm", "zzz"])
    }

    // MARK: - save(to:)

    func testSave_writesAllFieldsToCard() {
        let vm = CardEditorViewModel()
        let columnId = UUID()
        vm.title = "Saved Terminal"
        vm.description = "Saved description"
        vm.workingDirectory = "/tmp"
        vm.shellPath = "/bin/bash"
        vm.selectedColumnId = columnId
        vm.isFavourite = true
        vm.initCommand = "npm start"
        vm.llmPrompt = "React project"
        vm.llmNextAction = "Add tests"
        vm.badge = "prod"
        vm.fontName = "Monaco"
        vm.fontSize = 16
        vm.safePasteEnabled = false
        vm.themeId = "light"
        vm.allowAutorun = true
        vm.allowOscClipboard = false
        vm.confirmExternalModifications = false
        vm.backend = TerminalBackend.tmuxControl

        let card = TerminalCard(columnId: UUID())
        vm.save(to: card)

        XCTAssertEqual(card.title, "Saved Terminal")
        XCTAssertEqual(card.description, "Saved description")
        XCTAssertEqual(card.workingDirectory, "/tmp")
        XCTAssertEqual(card.shellPath, "/bin/bash")
        XCTAssertEqual(card.columnId, columnId)
        XCTAssertTrue(card.isFavourite)
        XCTAssertEqual(card.initCommand, "npm start")
        XCTAssertEqual(card.llmPrompt, "React project")
        XCTAssertEqual(card.llmNextAction, "Add tests")
        XCTAssertEqual(card.badge, "prod")
        XCTAssertEqual(card.fontName, "Monaco")
        XCTAssertEqual(card.fontSize, 16)
        XCTAssertEqual(card.safePasteEnabled, false)
        XCTAssertEqual(card.themeId, "light")
        XCTAssertTrue(card.allowAutorun)
        XCTAssertFalse(card.allowOscClipboard)
        XCTAssertFalse(card.confirmExternalModifications)
        XCTAssertEqual(card.backend, TerminalBackend.tmuxControl)
    }

    func testSave_roundTrip() {
        let original = TerminalCard(columnId: UUID())
        original.title = "Round Trip"
        original.description = "Test"
        original.badge = "urgent"

        let vm = CardEditorViewModel()
        vm.load(from: original)

        let copy = TerminalCard(columnId: UUID())
        vm.save(to: copy)

        XCTAssertEqual(copy.title, original.title)
        XCTAssertEqual(copy.description, original.description)
        XCTAssertEqual(copy.badge, original.badge)
    }

    // MARK: - addTag / deleteTag

    func testAddTag_appendsTag() {
        let vm = CardEditorViewModel()
        vm.addTag(key: "env", value: "prod")

        XCTAssertEqual(vm.tags.count, 1)
        XCTAssertEqual(vm.tags.first?.key, "env")
        XCTAssertEqual(vm.tags.first?.value, "prod")
    }

    func testDeleteTag_removesMatchingTag() {
        let vm = CardEditorViewModel()
        vm.addTag(key: "env", value: "prod")
        let id = vm.tags.first!.id

        vm.deleteTag(id: id)

        XCTAssertTrue(vm.tags.isEmpty)
    }

    func testDeleteTag_nonExistentId_noChange() {
        let vm = CardEditorViewModel()
        vm.addTag(key: "env", value: "prod")

        vm.deleteTag(id: UUID())

        XCTAssertEqual(vm.tags.count, 1)
    }

    // MARK: - syncTagItems

    func testSyncTagItems_populatesFromTags() {
        let vm = CardEditorViewModel()
        vm.addTag(key: "env", value: "prod")
        vm.addTag(key: "team", value: "platform")

        vm.syncTagItems()

        XCTAssertEqual(vm.tagItems.count, 2)
        XCTAssertTrue(vm.tagItems.contains { $0.key == "env" && $0.value == "prod" })
        XCTAssertTrue(vm.tagItems.contains { $0.key == "team" && $0.value == "platform" })
    }

    func testSyncTagItems_emptyTags_clearsItems() {
        let vm = CardEditorViewModel()
        vm.tagItems = [KeyValueItem(id: UUID(), key: "old", value: "val", isSecret: false)]

        vm.syncTagItems()

        XCTAssertTrue(vm.tagItems.isEmpty)
    }

    // MARK: - Agent fields

    func testLoad_nonAgentCard_clearsHasAgentConfigFlag() {
        let card = TerminalCard(columnId: UUID())
        let vm = CardEditorViewModel()
        vm.hasAgentConfig = true  // pretend it was set from a previous card

        vm.load(from: card)

        XCTAssertFalse(vm.hasAgentConfig)
    }

    func testLoad_agentCard_populatesAgentFields() {
        let config = AgentConfig(
            harness: "x",
            backend: .codex,
            mode: .act,
            interactionMode: .tweak,
            budget: AgentBudget(maxTurns: 50, maxTokens: 1_000_000, maxWallSeconds: 1800)
        )
        let card = TerminalCard(columnId: UUID(), agentConfig: config)
        let vm = CardEditorViewModel()

        vm.load(from: card)

        XCTAssertTrue(vm.hasAgentConfig)
        XCTAssertEqual(vm.agentBackend, .codex)
        XCTAssertEqual(vm.agentMode, .act)
        XCTAssertEqual(vm.agentInteractionMode, .tweak)
        XCTAssertEqual(vm.agentMaxTurns, 50)
        XCTAssertEqual(vm.agentMaxTokens, 1_000_000)
        XCTAssertEqual(vm.agentMaxWallMinutes, 30)
    }

    func testSave_agentCard_writesEditableFields() {
        let originalConfig = AgentConfig(harness: "x")
        let card = TerminalCard(columnId: UUID(), agentConfig: originalConfig)
        let vm = CardEditorViewModel()
        vm.load(from: card)

        // User edits.
        vm.title = card.title
        vm.agentBackend = .codex
        vm.agentMode = .act
        vm.agentInteractionMode = .auto
        vm.agentMaxTurns = 10
        vm.agentMaxTokens = 200_000
        vm.agentMaxWallMinutes = 15

        vm.save(to: card)

        let saved = card.agentConfig!
        XCTAssertEqual(saved.backend, .codex)
        XCTAssertEqual(saved.mode, .act)
        XCTAssertEqual(saved.interactionMode, .auto)
        XCTAssertEqual(saved.budget.maxTurns, 10)
        XCTAssertEqual(saved.budget.maxTokens, 200_000)
        XCTAssertEqual(saved.budget.maxWallSeconds, 15 * 60)
    }

    func testSave_agentCard_preservesIdentityFields() {
        // sessionId, harness, status are not user-editable; the editor must
        // round-trip them unchanged on save.
        let original = AgentConfig(
            sessionId: UUID(),
            harness: "kept-harness",
            backend: .claudeCode,
            status: .running
        )
        let card = TerminalCard(columnId: UUID(), agentConfig: original)
        let vm = CardEditorViewModel()
        vm.load(from: card)

        vm.title = card.title
        vm.agentBackend = .codex  // change a user-editable field
        vm.save(to: card)

        let saved = card.agentConfig!
        XCTAssertEqual(saved.sessionId, original.sessionId)
        XCTAssertEqual(saved.harness, "kept-harness")
        XCTAssertEqual(saved.status, .running)
        XCTAssertEqual(saved.backend, .codex)
    }

    func testLoadSave_loopDriverCommand_roundTrips() {
        let card = TerminalCard(
            columnId: UUID(),
            agentConfig: AgentConfig(harness: "x", loopDriverCommand: "/path/to/ynh-agent --task t.md")
        )
        let vm = CardEditorViewModel()

        vm.load(from: card)
        XCTAssertEqual(vm.agentLoopDriverCommand, "/path/to/ynh-agent --task t.md")

        vm.title = card.title  // satisfy isValid
        vm.agentLoopDriverCommand = "/different/path --flag"
        vm.save(to: card)

        XCTAssertEqual(card.agentConfig?.loopDriverCommand, "/different/path --flag")
    }

    func testLoad_loopDriverCommand_clearsForNonAgentCard() {
        let card = TerminalCard(columnId: UUID())
        let vm = CardEditorViewModel()
        vm.agentLoopDriverCommand = "stale value"

        vm.load(from: card)

        XCTAssertEqual(vm.agentLoopDriverCommand, "")
    }

    func testSave_nonAgentCard_doesNotInjectAgentConfig() {
        let card = TerminalCard(columnId: UUID())
        let vm = CardEditorViewModel()
        vm.load(from: card)
        vm.title = card.title

        // Even if the agent fields hold non-default values, save must not
        // create an agentConfig on a card that didn't already have one.
        vm.agentBackend = .codex
        vm.agentMaxTurns = 99

        vm.save(to: card)

        XCTAssertNil(card.agentConfig)
    }
}
