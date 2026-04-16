import AppKit
import SwiftUI
import TermQShared

/// Sidebar content for the Harnesses tab.
///
/// Phase 1 placeholder — shows detection state only:
/// - `.binaryOnly` → "Run `ynh init`" call-to-action
/// - `.ready` → empty harness list placeholder (populated in Phase 2)
///
/// The `.missing` state is handled by the parent `SidebarView` which hides
/// the tab entirely, so this view never receives it.
struct HarnessesSidebarTab: View {
    @ObservedObject var detector: YNHDetector

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
                readyPlaceholder
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

            Button {
                Task { await detector.detect() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help(Strings.Harnesses.refreshHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    /// ynh fully operational — Phase 2 will populate this with the harness list.
    private var readyPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(Strings.Harnesses.emptyMessage)
                .font(.callout)
                .foregroundColor(.secondary)
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
