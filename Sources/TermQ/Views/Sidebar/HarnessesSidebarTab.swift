import AppKit
import SwiftUI
import TermQShared

/// Sidebar content for the Harnesses tab.
///
/// Shows detection state and, when YNH is ready, the installed harness list
/// populated from `ynh ls --format json`.
///
/// The `.missing` state is handled by the parent `SidebarView` which hides
/// the tab entirely, so this view never receives it.
struct HarnessesSidebarTab: View {
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    var onLaunchHarness: ((Harness) -> Void)?
    var onInstall: (() -> Void)?
    var onUninstall: ((String) -> Void)?
    var onUpdate: ((String) -> Void)?
    @ObservedObject private var ynhPersistence: YNHPersistence = .shared
    @State private var harnessToUninstall: Harness?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            switch detector.status {
            case .missing:
                // Should not be visible — parent hides the tab. Defensive fallback.
                emptyState(
                    icon: "exclamationmark.triangle",
                    message: Strings.Harnesses.notInstalled
                )

            case .binaryOnly:
                initRequiredState

            case .ready:
                harnessList
            }
        }
        .onAppear {
            if case .ready = detector.status, repository.harnesses.isEmpty {
                Task { await repository.refresh() }
            }
        }
        .onChange(of: detector.status) { _, newStatus in
            if case .ready = newStatus {
                Task { await repository.refresh() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Strings.Harnesses.title)
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            if repository.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if case .ready = detector.status {
                Button {
                    onInstall?()
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help(Strings.Harnesses.installToolbarHelp)
            }

            Button {
                Task {
                    await detector.detect()
                    await repository.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help(Strings.Harnesses.refreshHelp)
            .disabled(repository.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Harness List

    @ViewBuilder
    private var harnessList: some View {
        if repository.harnesses.isEmpty && !repository.isLoading {
            emptyState(
                icon: "puzzlepiece.extension",
                message: Strings.Harnesses.emptyMessage
            )
        } else {
            List(selection: $repository.selectedHarnessName) {
                ForEach(repository.harnesses) { harness in
                    HarnessRowView(harness: harness)
                        .tag(harness.name)
                        .contextMenu {
                            Button {
                                onLaunchHarness?(harness)
                            } label: {
                                Label(Strings.Harnesses.launchButton, systemImage: "play.fill")
                            }
                            Divider()
                            Button {
                                onUpdate?(harness.name)
                            } label: {
                                Label(Strings.Harnesses.updateButton, systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button(role: .destructive) {
                                harnessToUninstall = harness
                            } label: {
                                Label(Strings.Harnesses.uninstallButton, systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .confirmationDialog(
                harnessToUninstall.map { Strings.Harnesses.uninstallAlertTitle($0.name) } ?? "",
                isPresented: Binding(
                    get: { harnessToUninstall != nil },
                    set: { if !$0 { harnessToUninstall = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let harness = harnessToUninstall {
                    Button(Strings.Harnesses.uninstallAlertConfirm, role: .destructive) {
                        onUninstall?(harness.name)
                        harnessToUninstall = nil
                    }
                    Button(Strings.Harnesses.installCancel, role: .cancel) {
                        harnessToUninstall = nil
                    }
                }
            } message: {
                if let harness = harnessToUninstall {
                    let linked = ynhPersistence.worktrees(for: harness.name).count
                    Text(
                        linked > 0
                            ? Strings.Harnesses.uninstallAlertWorktrees(linked)
                            : Strings.Harnesses.uninstallAlertMessage
                    )
                }
            }
        }
    }

    // MARK: - States

    /// ynh binary found but not initialised — prompt the user.
    private var initRequiredState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(Strings.Harnesses.initRequired)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(Strings.Harnesses.initHint)
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
