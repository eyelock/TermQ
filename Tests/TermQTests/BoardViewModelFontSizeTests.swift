import Foundation
import XCTest

@testable import TermQ

/// Unit tests for BoardViewModel's runtime font-size zoom logic
/// (`adjustSelectedFontSize` / `resetSelectedFontSize`). These cover the
/// per-card override math, clamping to `SettingsStore.fontSizeRange`, and the
/// reset-to-inherit behaviour. The live re-apply to the terminal NSView is a
/// no-op here because no session exists for the seeded card.
final class BoardViewModelFontSizeTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private let fontSizeKey = "defaultFontSize"
    private var savedFontSize: Any?
    private var tempBoardURL: URL!
    private var viewModel: BoardViewModel?

    override func setUp() {
        super.setUp()
        savedFontSize = defaults.object(forKey: fontSizeKey)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardViewModelFontSizeTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempBoardURL = tempDir.appendingPathComponent("board.json")
        let seedBoard =
            #"{"columns":[{"id":"00000000-0000-0000-0000-000000000001","name":"To Do","orderIndex":0}],"cards":[]}"#
        try? Data(seedBoard.utf8).write(to: tempBoardURL)
    }

    override func tearDown() {
        // Nil the viewModel first so its FileMonitor is cancelled before the
        // temp directory is deleted (avoids spurious post-teardown log noise).
        viewModel = nil
        if let tempDir = tempBoardURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: tempDir)
        }
        if let savedFontSize {
            defaults.set(savedFontSize, forKey: fontSizeKey)
        } else {
            defaults.removeObject(forKey: fontSizeKey)
        }
        Task { @MainActor in SettingsStore.shared.syncFromStore() }
        super.tearDown()
    }

    /// Seed a view model with one selected card and a known global default
    /// font size, so assertions are deterministic regardless of the shared
    /// store's prior state.
    @MainActor private func makeViewModelWithSelectedCard(
        defaultFontSize: CGFloat = 13
    ) -> BoardViewModel {
        defaults.set(Double(defaultFontSize), forKey: fontSizeKey)
        SettingsStore.shared.syncFromStore()
        let vm = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        vm.newTerminal(at: NSHomeDirectory())
        return vm
    }

    @MainActor func testIncrease_fromInheritedDefault_setsOverrideOnePointHigher() {
        let vm = makeViewModelWithSelectedCard(defaultFontSize: 13)
        viewModel = vm
        XCTAssertNil(vm.selectedCard?.fontSize)  // inheriting the global default

        vm.adjustSelectedFontSize(by: 1)

        XCTAssertEqual(vm.selectedCard?.fontSize, 14)
    }

    @MainActor func testDecrease_fromInheritedDefault_setsOverrideOnePointLower() {
        let vm = makeViewModelWithSelectedCard(defaultFontSize: 13)
        viewModel = vm

        vm.adjustSelectedFontSize(by: -1)

        XCTAssertEqual(vm.selectedCard?.fontSize, 12)
    }

    @MainActor func testIncrease_clampsAtMaximum() {
        let vm = makeViewModelWithSelectedCard()
        viewModel = vm
        vm.selectedCard?.fontSize = SettingsStore.Defaults.maxFontSize

        vm.adjustSelectedFontSize(by: 1)

        XCTAssertEqual(vm.selectedCard?.fontSize, SettingsStore.Defaults.maxFontSize)
    }

    @MainActor func testDecrease_clampsAtMinimum() {
        let vm = makeViewModelWithSelectedCard()
        viewModel = vm
        vm.selectedCard?.fontSize = SettingsStore.Defaults.minFontSize

        vm.adjustSelectedFontSize(by: -1)

        XCTAssertEqual(vm.selectedCard?.fontSize, SettingsStore.Defaults.minFontSize)
    }

    @MainActor func testIncrease_whenInheritingDefaultAtMaximum_doesNotCreateOverride() {
        let vm = makeViewModelWithSelectedCard(defaultFontSize: SettingsStore.Defaults.maxFontSize)
        viewModel = vm
        XCTAssertNil(vm.selectedCard?.fontSize)  // inheriting, already at the bound

        vm.adjustSelectedFontSize(by: 1)

        // No room to grow and nothing overridden — must stay inheriting
        // rather than writing a redundant override.
        XCTAssertNil(vm.selectedCard?.fontSize)
    }

    @MainActor func testReset_clearsOverrideToInheritDefault() {
        let vm = makeViewModelWithSelectedCard()
        viewModel = vm
        vm.selectedCard?.fontSize = 20

        vm.resetSelectedFontSize()

        XCTAssertNil(vm.selectedCard?.fontSize)
    }

    @MainActor func testAdjust_withNoSelectedCard_isNoOp() {
        let vm = BoardViewModel(persistence: BoardPersistence(saveURL: tempBoardURL))
        viewModel = vm
        vm.deselectCard()
        XCTAssertNil(vm.selectedCard)

        // Must not crash when there is nothing to act on.
        vm.adjustSelectedFontSize(by: 1)
        vm.resetSelectedFontSize()

        XCTAssertNil(vm.selectedCard)
    }
}
