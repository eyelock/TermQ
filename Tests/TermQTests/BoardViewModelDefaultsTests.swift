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
        super.tearDown()
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    // MARK: - newTerminal(at:)

    @MainActor func testNewTerminal_safePasteDisabled_cardInheritsDisabled() {
        defaults.set(false, forKey: safePasteKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.safePasteEnabled, false)
    }

    @MainActor func testNewTerminal_safePasteEnabled_cardInheritsEnabled() {
        defaults.set(true, forKey: safePasteKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.safePasteEnabled, true)
    }

    @MainActor func testNewTerminal_allowAutorunEnabled_cardInheritsEnabled() {
        defaults.set(true, forKey: allowAutorunKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.allowAutorun, true)
    }

    @MainActor func testNewTerminal_allowAutorunDisabled_cardInheritsDisabled() {
        defaults.set(false, forKey: allowAutorunKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.allowAutorun, false)
    }

    @MainActor func testNewTerminal_oscClipboardDisabled_cardInheritsDisabled() {
        defaults.set(false, forKey: allowOscClipboardKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.allowOscClipboard, false)
    }

    @MainActor func testNewTerminal_confirmExternalModificationsDisabled_cardInheritsDisabled() {
        defaults.set(false, forKey: confirmExternalModificationsKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.newTerminal(at: NSHomeDirectory())
        XCTAssertEqual(viewModel?.selectedCard?.confirmExternalModifications, false)
    }

    // MARK: - quickNewTerminal()

    @MainActor func testQuickNewTerminal_safePasteDisabled_cardInheritsDisabled() {
        defaults.set(false, forKey: safePasteKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.safePasteEnabled, false)
    }

    @MainActor func testQuickNewTerminal_safePasteEnabled_cardInheritsEnabled() {
        defaults.set(true, forKey: safePasteKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.safePasteEnabled, true)
    }

    @MainActor func testQuickNewTerminal_allowAutorunEnabled_cardInheritsEnabled() {
        defaults.set(true, forKey: allowAutorunKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.allowAutorun, true)
    }

    @MainActor func testQuickNewTerminal_allowAutorunDisabled_cardInheritsDisabled() {
        defaults.set(false, forKey: allowAutorunKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.allowAutorun, false)
    }

    @MainActor func testQuickNewTerminal_oscClipboardDisabled_cardInheritsDisabled() {
        defaults.set(false, forKey: allowOscClipboardKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.allowOscClipboard, false)
    }

    @MainActor func testQuickNewTerminal_confirmExternalModificationsDisabled_cardInheritsDisabled() {
        defaults.set(false, forKey: confirmExternalModificationsKey)
        viewModel = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel?.quickNewTerminal()
        XCTAssertEqual(viewModel?.selectedCard?.confirmExternalModifications, false)
    }
}
