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
                }
            }
            .listStyle(.sidebar)
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
