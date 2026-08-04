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
