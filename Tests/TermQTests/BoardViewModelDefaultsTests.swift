import Foundation
import XCTest

@testable import TermQ

/// Verifies that terminal creation methods inherit per-terminal security settings from UserDefaults.
///
/// Covers BoardViewModel's creation paths (newTerminal, quickNewTerminal). The harness functions
/// in ContentView follow the same pattern but are not unit-testable without app infrastructure.
final class BoardViewModelDefaultsTests: XCTestCase {

    private let defaults = UserDefaults.standard

    private let safePasteKey = "defaultSafePaste"
    private let allowAutorunKey = "enableTerminalAutorun"
    private let allowOscClipboardKey = "allowOscClipboard"
    private let confirmExternalModificationsKey = "confirmExternalLLMModifications"

    private var savedSafePaste: Any?
    private var savedAllowAutorun: Any?
    private var savedAllowOscClipboard: Any?
    private var savedConfirmExternalModifications: Any?

    private var tempBoardURL: URL!
    private var viewModel: BoardViewModel?

    override func setUp() {
        super.setUp()
        savedSafePaste = defaults.object(forKey: safePasteKey)
        savedAllowAutorun = defaults.object(forKey: allowAutorunKey)
        savedAllowOscClipboard = defaults.object(forKey: allowOscClipboardKey)
        savedConfirmExternalModifications = defaults.object(forKey: confirmExternalModificationsKey)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardViewModelTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempBoardURL = tempDir.appendingPathComponent("board.json")
        let seedBoard =
            #"{"columns":[{"id":"00000000-0000-0000-0000-000000000001","name":"To Do","orderIndex":0}],"cards":[]}"#
        try? Data(seedBoard.utf8).write(to: tempBoardURL)
    }

    override func tearDown() {
        // Nil the viewModel first so its FileMonitor is cancelled before the temp
        // directory is deleted. Without this, the dispatch source fires a delete
        // event after tearDown removes the directory, which causes spurious
        // [FileMonitor] and [BoardPersistence] log noise in test output.
        viewModel = nil

        if let tempDir = tempBoardURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: tempDir)
        }
        restore(savedSafePaste, forKey: safePasteKey)
        restore(savedAllowAutorun, forKey: allowAutorunKey)
        restore(savedAllowOscClipboard, forKey: allowOscClipboardKey)
        restore(savedConfirmExternalModifications, forKey: confirmExternalModificationsKey)
        // Re-pull the shared SettingsStore in case earlier tests left it
        // holding test-specific values. The notification path is async
        // (Task @MainActor) so synchronous teardown can't rely on it.
        Task { @MainActor in SettingsStore.shared.syncFromStore() }
        super.tearDown()
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// Set a UserDefaults value AND immediately reconcile `SettingsStore.shared`
    /// so synchronous test assertions see the new value. The production
    /// notification path is async, which the test runner's synchronous
    /// `XCTAssert` calls would otherwise race ahead of.
    @MainActor private func setAndSync(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        SettingsStore.shared.syncFromStore()
    }

    // MARK: - newTerminal(at:)

    @MainActor func testNewTerminal_safePaste_cardOverrideIsNilInheriting() {
        // Post-SettingsStore migration: BoardViewModel no longer snapshots
        // safePaste at card-create time. The card's override is `nil`
        // (inherit) and resolution happens at session-create time via
        // SettingsStore. The UserDefaults pref is exercised through the
        // store's effectiveSafePaste(card:) call, not the card field.
        defaults.set(false, forKey: safePasteKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertNil(viewModel?.selectedCard?.safePasteEnabled)
        XCTAssertEqual(SettingsStore().effectiveSafePaste(card: nil), false)

        defaults.set(true, forKey: safePasteKey)
        XCTAssertEqual(SettingsStore().effectiveSafePaste(card: nil), true)
    }

    @MainActor func testNewTerminal_allowAutorunEnabled_cardInheritsEnabled() {
        setAndSync(true, forKey: allowAutorunKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.allowAutorun, true)
    }

    @MainActor func testNewTerminal_allowAutorunDisabled_cardInheritsDisabled() {
        setAndSync(false, forKey: allowAutorunKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.allowAutorun, false)
    }

    @MainActor func testNewTerminal_oscClipboardDisabled_cardInheritsDisabled() {
        setAndSync(false, forKey: allowOscClipboardKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.allowOscClipboard, false)
    }

    @MainActor func testNewTerminal_confirmExternalModificationsDisabled_cardInheritsDisabled() {
        setAndSync(false, forKey: confirmExternalModificationsKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.confirmExternalModifications, false)
    }

    // MARK: - quickNewTerminal()

    @MainActor func testQuickNewTerminal_safePaste_cardOverrideIsNilInheriting() {
        // Same contract as newTerminal — quickNewTerminal also stops
        // snapshotting; resolution moves to SettingsStore.
        defaults.set(false, forKey: safePasteKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertNil(viewModel?.selectedCard?.safePasteEnabled)
        XCTAssertEqual(SettingsStore().effectiveSafePaste(card: nil), false)
    }

    @MainActor func testQuickNewTerminal_allowAutorunEnabled_cardInheritsEnabled() {
        setAndSync(true, forKey: allowAutorunKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.allowAutorun, true)
    }

    @MainActor func testQuickNewTerminal_allowAutorunDisabled_cardInheritsDisabled() {
        setAndSync(false, forKey: allowAutorunKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.allowAutorun, false)
    }

    @MainActor func testQuickNewTerminal_oscClipboardDisabled_cardInheritsDisabled() {
        setAndSync(false, forKey: allowOscClipboardKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.allowOscClipboard, false)
    }

    @MainActor func testQuickNewTerminal_confirmExternalModificationsDisabled_cardInheritsDisabled() {
        setAndSync(false, forKey: confirmExternalModificationsKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.confirmExternalModifications, false)
    }
}
