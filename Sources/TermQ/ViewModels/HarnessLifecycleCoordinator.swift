import Foundation
import Observation
import TermQCore
import TermQShared

/// Owns the harness install / uninstall / update / export / fork flows —
/// the transient utility cards spawned by ynh operations and the sheet
/// state that drives them.
///
/// Like `HarnessLaunchCoordinator`, held by `ContentView` via `@State`
/// with services injected at construction. Sub-views participate via
/// `@Environment(HarnessLifecycleCoordinator.self)`.
@MainActor
@Observable
final class HarnessLifecycleCoordinator {
    /// Card IDs of in-flight `ynh install` transient cards. Tracked so
    /// the post-exit notification can refresh the harness list and close
    /// the card on success.
    var installCardIDs: Set<UUID> = []

    /// Map from in-flight `ynh uninstall` transient card IDs to the
    /// harness name being uninstalled. Used to clear YNHPersistence
    /// associations on success.
    var uninstallCardNames: [UUID: String] = [:]

    /// Name of the harness pending a fork-to-local operation.
    var harnessNameToFork: String?

    /// Controls `ForkHarnessSheet` visibility.
    var showForkSheet = false

    /// Name of the harness pending an update.
    var harnessNameToUpdate: String?

    /// Controls `UpdateHarnessSheet` visibility.
    var showUpdateSheet = false

    /// Controls `HarnessInstallSheet` visibility.
    var showInstallSheet = false

    @ObservationIgnored private let ynhDetector: any YNHDetectorProtocol
    @ObservationIgnored private let harnessRepo: HarnessRepository
    @ObservationIgnored private let boardViewModel: BoardViewModel
    @ObservationIgnored private let ynhPersistence: YNHPersistence

    init(
        ynhDetector: any YNHDetectorProtocol = YNHDetector.shared,
        harnessRepo: HarnessRepository = .shared,
        boardViewModel: BoardViewModel = .shared,
        ynhPersistence: YNHPersistence = .shared
    ) {
        self.ynhDetector = ynhDetector
        self.harnessRepo = harnessRepo
        self.boardViewModel = boardViewModel
        self.ynhPersistence = ynhPersistence
    }

    // MARK: - Install

    /// Install a harness by creating a transient card running `ynh install`
    /// so the user sees output.
    func installHarness(_ config: HarnessInstallConfig) {
        guard case .ready(let ynhPath, _, _) = ynhDetector.status else { return }
        guard let column = pickColumn() else { return }

        let store = SettingsStore.shared
        let card = TerminalCard(
            title: "ynh install \(config.displayName)",
            tags: [],
            columnId: column.id,
            workingDirectory: NSHomeDirectory(),
            initCommand: config.command(ynhPath: ynhPath) + " && exit",
            safePasteEnabled: nil,
            allowOscClipboard: store.allowOscClipboard,
            confirmExternalModifications: store.confirmExternalLLMModifications,
            // Forced direct: ynh install runs synchronously and exits;
            // not a user backend preference, so we override here rather
            // than inherit from SettingsStore.
            backend: .direct
        )
        card.isTransient = true
        card.allowAutorun = true
        installCardIDs.insert(card.id)
        boardViewModel.tabManager.addTransientCard(card)
        if let current = boardViewModel.selectedCard {
            boardViewModel.tabManager.insertTab(card.id, after: current.id)
        } else {
            boardViewModel.tabManager.addTab(card.id)
        }
        harnessRepo.selectedHarnessId = nil
        boardViewModel.objectWillChange.send()
        boardViewModel.selectedCard = card
    }

    // MARK: - Uninstall

    /// Uninstall a harness. Harnesses with no YNH install record are
    /// deleted directly from the filesystem; YNH-managed harnesses use
    /// a transient terminal and clear associations when the shell exits.
    func uninstallHarness(name: String) {
        let harness = harnessRepo.harnesses.first(where: { $0.name == name })

        // Harnesses with no YNH install record can't be uninstalled via
        // `ynh uninstall`. Delete them directly and clean up associations.
        if let harness, harness.installedFrom == nil {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: harness.path))
            ynhPersistence.removeAllAssociations(for: name)
            harnessRepo.selectedHarnessId = nil
            Task { await harnessRepo.refresh() }
            return
        }

        guard case .ready(let ynhPath, _, _) = ynhDetector.status else { return }
        guard let column = pickColumn() else { return }

        let store = SettingsStore.shared
        let card = TerminalCard(
            title: "ynh uninstall \(name)",
            tags: [],
            columnId: column.id,
            workingDirectory: NSHomeDirectory(),
            initCommand: "\(ynhPath) uninstall \(Self.shellQuote(name)) && exit",
            safePasteEnabled: nil,
            allowOscClipboard: store.allowOscClipboard,
            confirmExternalModifications: store.confirmExternalLLMModifications,
            // Forced direct: ynh uninstall is a one-shot; not a user choice.
            backend: .direct
        )
        card.isTransient = true
        card.allowAutorun = true
        uninstallCardNames[card.id] = name
        boardViewModel.tabManager.addTransientCard(card)
        if let current = boardViewModel.selectedCard {
            boardViewModel.tabManager.insertTab(card.id, after: current.id)
        } else {
            boardViewModel.tabManager.addTab(card.id)
        }
        harnessRepo.selectedHarnessId = nil
        boardViewModel.objectWillChange.send()
        boardViewModel.selectedCard = card
    }

    // MARK: - Update

    /// Update a harness via `UpdateHarnessSheet` — a CommandRunner-based
    /// progress sheet, no transient terminal in the user's board.
    func updateHarness(name: String) {
        guard case .ready = ynhDetector.status else { return }
        harnessNameToUpdate = name
        showUpdateSheet = true
    }

    // MARK: - Export

    func exportHarness(name: String, outputDir: String) {
        guard case .ready(_, let yndPath?, _) = ynhDetector.status,
            let harness = harnessRepo.harnesses.first(where: { $0.name == name }),
            let column = boardViewModel.selectedCard.flatMap({ c in
                boardViewModel.board.columns.first { $0.id == c.columnId }
            }) ?? boardViewModel.board.columns.first
        else { return }

        let store = SettingsStore.shared
        let card = TerminalCard(
            title: "ynd export \(name)",
            tags: [],
            columnId: column.id,
            workingDirectory: harness.path,
            initCommand:
                "\(yndPath) export \(Self.shellQuote(harness.path)) -o \(Self.shellQuote(outputDir)) && exit",
            safePasteEnabled: nil,
            allowOscClipboard: store.allowOscClipboard,
            confirmExternalModifications: store.confirmExternalLLMModifications,
            // Forced direct: ynd export is a one-shot; not a user choice.
            backend: .direct
        )
        card.isTransient = true
        card.allowAutorun = true
        boardViewModel.tabManager.addTransientCard(card)
        boardViewModel.tabManager.addTab(card.id)
        boardViewModel.objectWillChange.send()
        boardViewModel.selectedCard = card
    }

    // MARK: - Fork

    func forkHarness(name: String) {
        harnessNameToFork = name
        showForkSheet = true
    }

    // MARK: - Lifecycle session-exited handling

    /// Called when a transient session exits. If the card is one of our
    /// install/uninstall trackers, refresh the harness list, clear
    /// associations as appropriate, and report whether the card should be
    /// closed on success.
    ///
    /// Returns `true` if the caller should close the card (success path),
    /// `false` if the caller should leave it open for inspection.
    /// Returns `nil` if the card isn't tracked by this coordinator.
    func handleTransientSessionExit(cardId: UUID, succeeded: Bool) -> Bool? {
        if installCardIDs.remove(cardId) != nil {
            if case .ready = ynhDetector.status {
                Task { await harnessRepo.refresh() }
            }
            return succeeded
        }
        if let name = uninstallCardNames.removeValue(forKey: cardId) {
            ynhPersistence.removeAllAssociations(for: name)
            if case .ready = ynhDetector.status {
                Task { await harnessRepo.refresh() }
            }
            return succeeded
        }
        return nil
    }

    /// Called from the fork sheet's completion handler. Closes the sheet,
    /// clears the pending name, and selects the newly-forked harness.
    func handleForkCompleted(newName: String) {
        showForkSheet = false
        harnessNameToFork = nil
        harnessRepo.selectedHarnessId = newName
    }

    // MARK: - Helpers

    private func pickColumn() -> TermQCore.Column? {
        if let current = boardViewModel.selectedCard,
            let currentColumn = boardViewModel.board.columns.first(where: {
                $0.id == current.columnId
            })
        {
            return currentColumn
        }
        return boardViewModel.board.columns.first
    }

    /// Wrap a string in single quotes for safe shell argument passing.
    private static func shellQuote(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
