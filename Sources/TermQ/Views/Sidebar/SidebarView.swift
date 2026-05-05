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
    var onInstall: (() -> Void)?
    var onUninstall: ((String) -> Void)?
    var onUpdate: ((String) -> Void)?
    var onExport: ((String, String) -> Void)?
    var onFork: ((String) -> Void)?
    var onNewHarness: (() -> Void)?
    @AppStorage("feature.harnessTab") private var harnessTabEnabled = false
    @ObservedObject private var sidebarState = SidebarState.shared
    private static var hasResetOnLaunch = false

    private var showHarnessesTab: Bool {
        guard harnessTabEnabled else { return false }
        return detector.status != .missing
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHarnessesTab {
                tabPicker
                Divider()
            }

            switch sidebarState.selectedTab {
            case .repositories:
                WorktreeSidebarView(
                    viewModel: worktreeViewModel, onLaunchHarness: onLaunchHarnessInWorktree,
                    onAutoLaunchHarness: onAutoLaunchHarness)
            case .harnesses where showHarnessesTab:
                HarnessesSidebarTab(
                    detector: detector,
                    repository: harnessRepository,
                    onLaunchHarness: onLaunchHarness,
                    onInstall: onInstall,
                    onUninstall: onUninstall,
                    onUpdate: onUpdate,
                    onExport: onExport,
                    onFork: onFork,
                    onNewHarness: onNewHarness
                )
            case .marketplaces where showHarnessesTab:
                MarketplaceSidebarTab(
                    detector: detector,
                    harnessRepository: harnessRepository
                )
            default:
                WorktreeSidebarView(
                    viewModel: worktreeViewModel, onLaunchHarness: onLaunchHarnessInWorktree,
                    onAutoLaunchHarness: onAutoLaunchHarness)
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
        }
        .onChange(of: harnessTabEnabled) { _, enabled in
            if enabled {
                Task { await detector.detect() }
            } else {
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
            ForEach(SidebarTab.allCases, id: \.self) { tab in
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
                .help(tab.label)
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
