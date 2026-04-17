import AppKit
import SwiftUI
import TermQShared

/// Top-level sidebar container with tab switching between Repositories and Harnesses.
///
/// When the `feature.harnessTab` flag is off (default), this renders the
/// `WorktreeSidebarView` directly with no tab picker visible. When on and
/// YNH detection succeeds, a segmented picker appears at the top.
struct SidebarView: View {
    @ObservedObject var worktreeViewModel: WorktreeSidebarViewModel
    @ObservedObject var detector: YNHDetector
    @ObservedObject var harnessRepository: HarnessRepository
    var onLaunchHarness: ((Harness) -> Void)?
    var onLaunchHarnessInWorktree: ((String, String) -> Void)?
    var onInstall: (() -> Void)?
    var onUninstall: ((String) -> Void)?
    var onUpdate: ((String) -> Void)?
    @AppStorage("feature.harnessTab") private var harnessTabEnabled = false
    @AppStorage("sidebar.selectedTab") private var selectedTab = SidebarTab.repositories

    enum SidebarTab: String, CaseIterable {
        case repositories
        case harnesses
    }

    /// Whether the Harnesses tab should be visible.
    ///
    /// Requires the feature flag AND the ynh binary to be detected.
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

            switch selectedTab {
            case .repositories:
                WorktreeSidebarView(viewModel: worktreeViewModel, onLaunchHarness: onLaunchHarnessInWorktree)
            case .harnesses where showHarnessesTab:
                HarnessesSidebarTab(
                    detector: detector,
                    repository: harnessRepository,
                    onLaunchHarness: onLaunchHarness,
                    onInstall: onInstall,
                    onUninstall: onUninstall,
                    onUpdate: onUpdate
                )
            default:
                // Feature flag off but selectedTab persisted as harnesses — fall back.
                WorktreeSidebarView(viewModel: worktreeViewModel, onLaunchHarness: onLaunchHarnessInWorktree)
            }
        }
        .onAppear {
            if harnessTabEnabled {
                Task { await detector.detect() }
            }
        }
        .onChange(of: harnessTabEnabled) { _, enabled in
            if enabled {
                Task { await detector.detect() }
            } else {
                selectedTab = .repositories
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .harnesses {
                if case .ready = detector.status {
                    Task { await harnessRepository.refresh() }
                }
            } else {
                harnessRepository.selectedHarnessName = nil
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

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text(Strings.Sidebar.title).tag(SidebarTab.repositories)
            Text(Strings.Harnesses.title).tag(SidebarTab.harnesses)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
