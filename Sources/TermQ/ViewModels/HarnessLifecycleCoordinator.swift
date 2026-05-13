import Foundation
import Observation
import TermQCore
import TermQShared

/// Owns the harness install / uninstall / update / export / fork flows.
///
/// All long-running YNH operations run through `CommandRunnerSheet`-backed
/// progress sheets. This coordinator holds the `@Observable` state that
/// gates each sheet; the actual command execution lives in the sheet view.
///
/// Held by `ContentView` via `@State` with services injected at construction.
/// Sub-views participate via `@Environment(HarnessLifecycleCoordinator.self)`.
@MainActor
@Observable
final class HarnessLifecycleCoordinator {
    /// Canonical id of the harness pending a fork-to-local operation.
    var harnessIDToFork: String?

    /// Controls `ForkHarnessSheet` visibility.
    var showForkSheet = false

    /// Canonical id of the harness pending an update.
    var harnessIDToUpdate: String?

    /// Controls `UpdateHarnessSheet` visibility.
    var showUpdateSheet = false

    /// Controls the install picker (`HarnessInstallSheet`) visibility.
    var showInstallSheet = false

    /// Config selected by the install picker; non-nil drives the install
    /// progress sheet.
    var harnessConfigToInstall: HarnessInstallConfig?

    /// Controls `HarnessInstallProgressSheet` visibility.
    var showInstallProgressSheet = false

    /// Canonical id of the harness pending an uninstall.
    var harnessIDToUninstall: String?

    /// Controls `HarnessUninstallSheet` visibility.
    var showUninstallSheet = false

    /// Pending export request; non-nil drives `HarnessExportSheet`.
    var pendingExport: PendingExport?

    /// Controls `HarnessExportSheet` visibility.
    var showExportSheet = false

    struct PendingExport: Equatable {
        let harnessName: String
        let harnessPath: String
        let outputDir: String
    }

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

    /// Triggered from the install picker. Hands the config off to the
    /// progress sheet which actually runs `ynh install`.
    func installHarness(_ config: HarnessInstallConfig) {
        guard case .ready = ynhDetector.status else { return }
        harnessConfigToInstall = config
        showInstallProgressSheet = true
    }

    // MARK: - Uninstall

    /// Uninstall a harness. Harnesses with no YNH install record are deleted
    /// directly from the filesystem; YNH-managed harnesses route through
    /// `HarnessUninstallSheet` which clears associations on success.
    func uninstallHarness(id: String) {
        let harness = harnessRepo.harnesses.first(where: { $0.id == id })

        if let harness, harness.installedFrom == nil {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: harness.path))
            ynhPersistence.removeAllAssociations(for: harness.name)
            harnessRepo.selectedHarnessId = nil
            Task { await harnessRepo.refresh() }
            return
        }

        guard case .ready = ynhDetector.status else { return }
        harnessIDToUninstall = id
        showUninstallSheet = true
    }

    // MARK: - Update

    /// Update a harness via `UpdateHarnessSheet` — a CommandRunner-based
    /// progress sheet, no transient terminal in the user's board.
    func updateHarness(id: String) {
        guard case .ready = ynhDetector.status else { return }
        harnessIDToUpdate = id
        showUpdateSheet = true
    }

    // MARK: - Export

    func exportHarness(id: String, outputDir: String) {
        guard case .ready(_, .some, _) = ynhDetector.status,
            let harness = harnessRepo.harnesses.first(where: { $0.id == id })
        else { return }
        pendingExport = PendingExport(
            harnessName: harness.name, harnessPath: harness.path, outputDir: outputDir)
        showExportSheet = true
    }

    // MARK: - Fork

    func forkHarness(id: String) {
        harnessIDToFork = id
        showForkSheet = true
    }

    // MARK: - Sheet completion

    /// Called from the fork sheet's completion handler. Closes the sheet,
    /// clears the pending id, and selects the newly-forked harness.
    func handleForkCompleted(newID: String) {
        showForkSheet = false
        harnessIDToFork = nil
        harnessRepo.selectedHarnessId = newID
    }
}
