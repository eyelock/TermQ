import SwiftUI
import TermQShared

/// Request to launch a harness, captured before the harness list may be loaded.
///
/// On a cold launch the user can click Launch from a worktree row before
/// `HarnessRepository.refresh()` has populated `harnesses`. Holding the request
/// here lets us resolve it once the list lands without ever presenting an
/// empty-content sheet (the source of the white-pill bug).
struct PendingLaunch: Equatable {
    let harnessId: String
    let workingDirectory: String?
    let branch: String?
}

/// Fully resolved data for the harness launch sheet.
///
/// Constructed only when both the repository is `.loaded` and the requested
/// `harnessId` resolves to a `Harness`. The sheet is presented via
/// `.sheet(item:)` against this — when nil, no sheet is presented at all,
/// avoiding the SwiftUI empty-content footgun.
struct LaunchSheetTarget: Identifiable, Equatable {
    let harness: Harness
    let workingDirectory: String?
    let branch: String?
    let vendorOverride: String?

    var id: String { harness.id }
}

extension ContentView {
    /// Entry point for every launch path (worktree row, default-harness
    /// context menu, sidebar, command palette). Records the request and
    /// tries to resolve it immediately; if the repo isn't loaded yet, the
    /// `.onChange(of: harnessRepo.listState)` observer in `body` will
    /// resolve it when data lands.
    func requestLaunch(harnessId: String, workingDirectory: String?, branch: String?) {
        pendingLaunch = PendingLaunch(
            harnessId: harnessId,
            workingDirectory: workingDirectory,
            branch: branch
        )
        launchWorkingDirectory = workingDirectory
        launchWorktreeBranch = branch
        Task { await vendorService.refresh() }
        // Reflect the selection in the repo so detail-view-driven UI (and
        // the existing fetchDetail flow) sees the new selection.
        harnessRepo.selectedHarnessId = harnessId
        tryResolvePendingLaunch()
    }

    /// Materialize `pendingLaunch` into `launchSheetTarget` when both the
    /// repo is `.loaded` and the harness id resolves. Idempotent.
    func tryResolvePendingLaunch() {
        guard let pending = pendingLaunch else { return }
        guard harnessRepo.listState.isLoaded else { return }
        // Tolerate ids and bare names (legacy worktree associations may still
        // hold a pre-migration value during the same session). The repository
        // selection above used the same string so this stays consistent.
        let key = pending.harnessId
        let resolved =
            harnessRepo.harnesses.first { $0.id == key }
            ?? harnessRepo.harnesses.first { $0.name == key }
        guard let harness = resolved else {
            // Repo loaded but the requested id isn't installed — drop the
            // request silently rather than holding it forever.
            pendingLaunch = nil
            return
        }
        launchSheetTarget = LaunchSheetTarget(
            harness: harness,
            workingDirectory: pending.workingDirectory,
            branch: pending.branch,
            vendorOverride: YNHPersistence.shared.vendorOverride(for: harness.id)
        )
        pendingLaunch = nil
    }
}
