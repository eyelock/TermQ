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
        XCTAssertFalse(vm.safePasteEnabled)
        XCTAssertEqual(vm.themeId, "dark")
        XCTAssertTrue(vm.allowAutorun)
        XCTAssertFalse(vm.allowOscClipboard)
        XCTAssertFalse(vm.confirmExternalModifications)
        XCTAssertEqual(vm.backend, .tmuxAttach)
    }

    func testLoad_fontSizeZero_defaultsTo13() {
        let card = TerminalCard(columnId: UUID())
        card.fontSize = 0

        let vm = CardEditorViewModel()
        vm.load(from: card)

        XCTAssertEqual(vm.fontSize, 13)
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
        XCTAssertFalse(card.safePasteEnabled)
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
}
