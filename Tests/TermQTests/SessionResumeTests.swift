import TermQCore
import XCTest

@testable import TermQ

/// Covers the persisted resume preference and the rule deciding when the
/// editor's toggle applies.
@MainActor
final class SessionResumeTests: XCTestCase {

    // MARK: - Persistence

    func test_autoResumeSession_defaultsToOff() {
        let card = TerminalCard(columnId: UUID())

        XCTAssertFalse(card.autoResumeSession)
    }

    func test_autoResumeSession_survivesRoundTrip() throws {
        let card = TerminalCard(columnId: UUID(), autoResumeSession: true)

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(TerminalCard.self, from: data)

        XCTAssertTrue(decoded.autoResumeSession)
    }

    /// Cards written before resume existed carry no key at all. They must keep
    /// the old cold-launch behaviour rather than silently opting in.
    func test_autoResumeSession_absentKeyDecodesToOff() throws {
        let json = """
            {
                "id": "\(UUID().uuidString)",
                "title": "Legacy",
                "description": "",
                "tags": [],
                "columnId": "\(UUID().uuidString)",
                "orderIndex": 0,
                "shellPath": "/bin/zsh",
                "workingDirectory": "/tmp"
            }
            """

        let decoded = try JSONDecoder().decode(TerminalCard.self, from: Data(json.utf8))

        XCTAssertFalse(decoded.autoResumeSession)
    }

    // MARK: - Duplicate

    /// Duplicating a harness card must carry the preference across, as it
    /// does every other per-card setting.
    func test_duplicateTerminal_copiesTheResumeSetting() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionResumeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let boardURL = tempDir.appendingPathComponent("board.json")
        let seed =
            #"{"columns":[{"id":"00000000-0000-0000-0000-000000000001","name":"To Do","orderIndex":0}],"cards":[]}"#
        try Data(seed.utf8).write(to: boardURL)

        let viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: boardURL))
        let source = TerminalCard(
            columnId: try XCTUnwrap(viewModel.board.columns.first?.id),
            autoResumeSession: true
        )
        viewModel.board.cards.append(source)

        viewModel.duplicateTerminal(source)

        let copy = try XCTUnwrap(viewModel.board.cards.first { $0.id != source.id })
        XCTAssertTrue(copy.autoResumeSession)
    }

    // MARK: - Editor availability rule

    private func viewModel(tags: [TermQCore.Tag]) -> CardEditorViewModel {
        let vm = CardEditorViewModel()
        vm.tags = tags
        return vm
    }

    func test_canResumeSession_trueForHarnessCardWithSupportingVendor() {
        let vm = viewModel(tags: [Tag(key: "vendor", value: "claude")])

        XCTAssertTrue(vm.canResumeSession(resumableVendorIDs: ["claude", "copilot"]))
    }

    /// A plain shell card has no LLM session to continue.
    func test_canResumeSession_falseWithoutAVendorTag() {
        let vm = viewModel(tags: [Tag(key: "shell", value: "zsh")])

        XCTAssertFalse(vm.canResumeSession(resumableVendorIDs: ["claude"]))
    }

    func test_canResumeSession_falseForEmptyVendorTag() {
        let vm = viewModel(tags: [Tag(key: "vendor", value: "")])

        XCTAssertFalse(vm.canResumeSession(resumableVendorIDs: ["claude"]))
    }

    /// The set is empty when the installed YNH predates `--resume` (it omits
    /// `supports_resume`, which decodes to false). Emitting the flag at such a
    /// binary would forward a bare `--resume` to the vendor CLI and hang the
    /// pane on its session picker, so the toggle must stay unavailable.
    func test_canResumeSession_falseWhenNoVendorReportsSupport() {
        let vm = viewModel(tags: [Tag(key: "vendor", value: "claude")])

        XCTAssertFalse(vm.canResumeSession(resumableVendorIDs: []))
    }

    func test_canResumeSession_falseWhenADifferentVendorSupportsIt() {
        let vm = viewModel(tags: [Tag(key: "vendor", value: "cursor")])

        XCTAssertFalse(vm.canResumeSession(resumableVendorIDs: ["claude"]))
    }

    // MARK: - Editor load / save

    func test_editor_loadsAndSavesTheFlag() {
        let card = TerminalCard(columnId: UUID(), autoResumeSession: true)
        let vm = CardEditorViewModel()

        vm.load(from: card)
        XCTAssertTrue(vm.autoResumeSession)

        vm.autoResumeSession = false
        vm.save(to: card)
        XCTAssertFalse(card.autoResumeSession)
    }
}
