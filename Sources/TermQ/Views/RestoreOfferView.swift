import SwiftUI

/// View shown on startup when backup exists but primary data is missing
struct RestoreOfferView: View {
    let backupURL: URL
    let onRestore: () -> Void
    let onSkip: () -> Void

    @State private var isRestoring = false
    @State private var backupDate: Date?

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            // Title
            Text("Welcome Back!")
                .font(.title)
                .fontWeight(.semibold)

            // Message
            VStack(spacing: 8) {
                Text("We found a backup of your TermQ board")
                    .font(.body)

                if let date = backupDate {
                    Text("from \(date, style: .date) at \(date, style: .time)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Text("Would you like to restore it?")
                .font(.body)
                .foregroundColor(.secondary)

            // Buttons
            HStack(spacing: 16) {
                Button("Start Fresh") {
                    onSkip()
                }
                .buttonStyle(.bordered)

                Button {
                    performRestore()
                } label: {
                    HStack {
                        if isRestoring {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRestoring ? "Restoring..." : "Restore")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRestoring)
            }
        }
        .padding(40)
        .frame(width: 400)
        .onAppear {
            loadBackupDate()
        }
    }

    private func loadBackupDate() {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: backupURL.path) {
            backupDate = attrs[.modificationDate] as? Date
        }
    }

    private func performRestore() {
        isRestoring = true
        Task {
            // Restore the backup
            let result = BackupManager.restore(from: backupURL)

            await MainActor.run {
                isRestoring = false
                switch result {
                case .success:
                    // Reload the board
                    BoardViewModel.shared.reloadFromDisk()
                    onRestore()
                case .failure:
                    // Still close and let them start fresh
                    onSkip()
                }
            }
        }
    }
}
