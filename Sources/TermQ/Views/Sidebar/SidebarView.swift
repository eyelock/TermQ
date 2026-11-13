import AppKit
import SwiftUI
import TermQShared

/// Top-level sidebar container with tab switching between Repositories, Harnesses, and Marketplaces.
///
/// When the `feature.harnessTab` flag is off (default), renders `WorktreeSidebarView` directly
/// with no tab picker. When on, a three-icon tab bar appears at the top.
struct SidebarView: View {
    @ObservedObject var worktreeViewModel: WorktreeSidebarViewModel
    @ObservedObject var detector: YNHDetector
    @ObservedObject var harnessRepository: HarnessRepository
    var onLaunchHarness: ((Harness) -> Void)?
    var onLaunchHarnessInWorktree: ((String, String, String?) -> Void)?
    var onAutoLaunchHarness: ((String, String, String?) -> Void)?
    var onRunWithFocus: ((HarnessLaunchConfig) -> Void)?
    var onInstall: (() -> Void)?
    var onUninstall: ((String) -> Void)?
    var onDeleteLocal: ((String) -> Void)?
    var onUpdate: ((String) -> Void)?
    var onExport: ((String, String) -> Void)?
    var onFork: ((String) -> Void)?
    var onPublish: ((String) -> Void)?
    var onNewHarness: (() -> Void)?
    var quarantinedEntries: [QuarantineEntry] = []
    var onRestoreQuarantine: ((String) -> Void)?
    var onDropQuarantine: ((String) -> Void)?
    var onSeatAction: ((Wheelhouse, WheelhouseSeat, WheelhouseSeatAction) -> Void)?
    @AppStorage("feature.harnessTab") private var harnessTabEnabled = false
    @AppStorage("feature.wheelhouseTab") private var wheelhouseTabEnabled = false
    @ObservedObject private var sidebarState = SidebarState.shared
    @ObservedObject private var boardVM: BoardViewModel = .shared
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    private static var hasResetOnLaunch = false

    private var activeHarnessId: String? {
        guard let card = boardVM.selectedCard else { return nil }
        let wd = card.workingDirectory
        guard !wd.isEmpty else { return nil }
        for repo in worktreeViewModel.repositories {
            let matched =
                wd == repo.path || wd.hasPrefix(repo.path + "/")
                || (worktreeViewModel.worktrees[repo.id] ?? []).contains { tree in
                    wd == tree.path || wd.hasPrefix(tree.path + "/")
                }
            guard matched else { continue }
            return ynhPersistence.runHarness(for: repo.path)
                ?? ynhPersistence.repoDefaultHarness(for: repo.path)
        }
        return nil
    }

    private var showHarnessesTab: Bool {
        SidebarTab.harnesses.isAvailable(
            harnessTabEnabled: harnessTabEnabled, ynhMissing: detector.status == .missing,
            wheelhouseTabEnabled: wheelhouseTabEnabled)
    }

    @ObservedObject private var wheelhouseStage: WheelhouseStage = .shared

    /// Wheelhouse focus mode shows only the Wheelhouse, with no other tabs.
    private var inWheelhouseFocus: Bool { wheelhouseTabEnabled && wheelhouseStage.focusMode }

    private var showTabPicker: Bool { (showHarnessesTab || wheelhouseTabEnabled) && !inWheelhouseFocus }

    /// Tabs shown in the picker, in order, for the enabled features.
    private var visibleTabs: [SidebarTab] {
        SidebarTab.allCases.filter {
            $0.isAvailable(
                harnessTabEnabled: harnessTabEnabled, ynhMissing: detector.status == .missing,
                wheelhouseTabEnabled: wheelhouseTabEnabled)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showTabPicker {
                tabPicker
                Divider()
            }

            switch inWheelhouseFocus ? .wheelhouses : sidebarState.selectedTab {
            case .repositories:
                WorktreeSidebarView(
                    viewModel: worktreeViewModel, onLaunchHarness: onLaunchHarnessInWorktree,
                    onAutoLaunchHarness: onAutoLaunchHarness,
                    onRunWithFocus: onRunWithFocus)
            case .harnesses where showHarnessesTab:
                HarnessesSidebarTab(
                    detector: detector,
                    repository: harnessRepository,
                    onLaunchHarness: onLaunchHarness,
                    onInstall: onInstall,
                    onUninstall: onUninstall,
                    onDeleteLocal: onDeleteLocal,
                    onUpdate: onUpdate,
                    onExport: onExport,
                    onFork: onFork,
                    onPublish: onPublish,
                    onNewHarness: onNewHarness,
                    quarantinedEntries: quarantinedEntries,
                    onRestoreQuarantine: onRestoreQuarantine,
                    onDropQuarantine: onDropQuarantine,
                    activeHarnessId: activeHarnessId,
                    wheelhouseRoots: worktreeViewModel.repositories.map(\.path)
                )
            case .marketplaces where showHarnessesTab:
                MarketplaceSidebarTab(
                    detector: detector,
                    harnessRepository: harnessRepository
                )
            case .wheelhouses where wheelhouseTabEnabled:
                WheelhouseSidebarTab(
                    worktreeViewModel: worktreeViewModel,
                    onSeatAction: onSeatAction
                )
            default:
                WorktreeSidebarView(
                    viewModel: worktreeViewModel, onLaunchHarness: onLaunchHarnessInWorktree,
                    onAutoLaunchHarness: onAutoLaunchHarness,
                    onRunWithFocus: onRunWithFocus)
            }
        }
        .onAppear {
            if !SidebarView.hasResetOnLaunch {
                sidebarState.selectedTab = .repositories
                SidebarView.hasResetOnLaunch = true
            }
            if harnessTabEnabled {
                Task { await detector.detect() }
            }
            Task { await GhCliProbe.shared.probe() }
        }
        .onChange(of: harnessTabEnabled) { _, enabled in
            if enabled {
                Task { await detector.detect() }
            } else if sidebarState.selectedTab == .harnesses || sidebarState.selectedTab == .marketplaces {
                sidebarState.selectedTab = .repositories
            }
        }
        .onChange(of: wheelhouseTabEnabled) { _, enabled in
            if !enabled && sidebarState.selectedTab == .wheelhouses {
                sidebarState.selectedTab = .repositories
            }
        }
        .onChange(of: sidebarState.selectedTab) { _, newTab in
            if newTab == .harnesses {
                if case .ready = detector.status {
                    Task { await harnessRepository.refresh() }
                }
            } else {
                harnessRepository.selectedHarnessId = nil
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await GhCliProbe.shared.probe() }
            guard harnessTabEnabled else { return }
            Task {
                await detector.detect()
                if case .ready = detector.status {
                    await harnessRepository.refresh()
                }
            }
        }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                Button {
                    sidebarState.selectedTab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .imageScale(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(sidebarState.selectedTab == tab ? .accentColor : .secondary)
                .help("\(tab.menuTitle) (⌃⌘\(tab.shortcutKey.uppercased()))")
                .background(
                    sidebarState.selectedTab == tab
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
