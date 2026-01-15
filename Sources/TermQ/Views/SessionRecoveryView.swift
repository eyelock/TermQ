import SwiftUI
import TermQCore

/// View for recovering orphaned tmux sessions on app launch
struct SessionRecoveryView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.split.3x3")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovered Sessions")
                        .font(.headline)
                    Text("These tmux sessions were running when TermQ last closed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Dismiss All") {
                    viewModel.showSessionRecovery = false
                }
            }
            .padding()

            Divider()

            if viewModel.recoverableSessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("No sessions to recover")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.recoverableSessions) { session in
                            SessionRow(
                                session: session,
                                matchingCard: findMatchingCard(for: session),
                                onRecover: {
                                    viewModel.recoverSession(session)
                                },
                                onDismiss: {
                                    viewModel.dismissRecoverableSession(session)
                                },
                                onKill: {
                                    viewModel.killRecoverableSession(session)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(viewModel.recoverableSessions.count) session(s) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    /// Find a matching card for a session based on the card ID prefix
    private func findMatchingCard(for session: TmuxSessionInfo) -> TerminalCard? {
        // Session name is "termq-<cardIdPrefix>" where cardIdPrefix is first 8 chars of UUID
        let prefix = session.cardIdPrefix.lowercased()
        return viewModel.allTerminals.first { card in
            card.id.uuidString.prefix(8).lowercased() == prefix
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: TmuxSessionInfo
    let matchingCard: TerminalCard?
    let onRecover: () -> Void
    let onDismiss: () -> Void
    let onKill: () -> Void

    @State private var showKillConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "terminal")
                .font(.title2)
                .foregroundColor(matchingCard != nil ? .accentColor : .orange)
                .frame(width: 32)

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                if let card = matchingCard {
                    Text(card.title)
                        .font(.headline)
                } else {
                    Text(session.name)
                        .font(.headline)
                    Text("No matching terminal found")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                HStack(spacing: 8) {
                    if let path = session.currentPath {
                        Text(path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text("Created \(session.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if matchingCard != nil {
                    Button("Reattach") {
                        onRecover()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Open this terminal and reattach to the tmux session")
                }

                Button("Dismiss") {
                    onDismiss()
                }
                .help("Keep session running but hide from this list")

                Button {
                    showKillConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Terminate this tmux session")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .alert("Kill Session?", isPresented: $showKillConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Kill", role: .destructive) {
                onKill()
            }
        } message: {
            Text("This will terminate the tmux session '\(session.name)'. Any unsaved work will be lost.")
        }
    }
}
