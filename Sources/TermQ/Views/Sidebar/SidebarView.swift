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
    @ObservedObject var boardViewModel: BoardViewModel
    var onLaunchHarness: ((Harness) -> Void)?
    var onLaunchHarnessInWorktree: ((String, String, String?) -> Void)?
    var onAutoLaunchHarness: ((String, String, String?) -> Void)?
    var onInstall: (() -> Void)?
    var onUninstall: ((String) -> Void)?
    var onUpdate: ((String) -> Void)?
    var onExport: ((String, String) -> Void)?
    var onNewHarness: (() -> Void)?
    @AppStorage("feature.harnessTab") private var harnessTabEnabled = false
    @AppStorage("feature.agentTab") private var agentTabEnabled = false
    @AppStorage("sidebar.selectedTab") private var selectedTab = SidebarTab.repositories
    private static var hasResetOnLaunch = false

    enum SidebarTab: String, CaseIterable {
        case repositories
        case harnesses
        case marketplaces
        case agents

        var icon: String {
            switch self {
            case .repositories: return "shippingbox"
            case .harnesses: return "puzzlepiece.extension"
            case .marketplaces: return "storefront"
            case .agents: return "sparkles"
            }
        }

        var label: String {
            switch self {
            case .repositories: return "Repositories"
            case .harnesses: return "Harnesses"
            case .marketplaces: return "Marketplaces"
            case .agents: return "Agent Sessions"
            }
        }
    }

    private var showHarnessesTab: Bool {
        guard harnessTabEnabled else { return false }
        return detector.status != .missing
    }

    private var showAgentsTab: Bool {
        agentTabEnabled
    }

    /// Tabs visible in the picker. `repositories` is always present;
    /// optional tabs appear only when their feature flag is on.
    private var visibleTabs: [SidebarTab] {
        var tabs: [SidebarTab] = [.repositories]
        if showHarnessesTab { tabs.append(.harnesses) }
        if showHarnessesTab { tabs.append(.marketplaces) }
        if showAgentsTab { tabs.append(.agents) }
        return tabs
    }

    private var showTabPicker: Bool {
        visibleTabs.count > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            if showTabPicker {
                tabPicker
                Divider()
            }

            switch selectedTab {
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
                    onNewHarness: onNewHarness
                )
            case .marketplaces where showHarnessesTab:
                MarketplaceSidebarTab(
                    detector: detector,
                    harnessRepository: harnessRepository
                )
            case .agents where showAgentsTab:
                AgentSessionsSidebarTab(boardViewModel: boardViewModel)
            default:
                WorktreeSidebarView(
                    viewModel: worktreeViewModel, onLaunchHarness: onLaunchHarnessInWorktree,
                    onAutoLaunchHarness: onAutoLaunchHarness)
            }
        }
        .onAppear {
            if !SidebarView.hasResetOnLaunch {
                selectedTab = .repositories
                SidebarView.hasResetOnLaunch = true
            }
            if harnessTabEnabled {
                Task { await detector.detect() }
            }
        }
        .onChange(of: harnessTabEnabled) { _, enabled in
            if enabled {
                Task { await detector.detect() }
            } else if !visibleTabs.contains(selectedTab) {
                selectedTab = .repositories
            }
        }
        .onChange(of: agentTabEnabled) { _, _ in
            if !visibleTabs.contains(selectedTab) {
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

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .imageScale(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                .help(tab.label)
                .background(
                    selectedTab == tab
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
