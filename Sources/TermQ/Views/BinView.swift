import SwiftUI
import TermQCore

struct BinView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("binRetentionDays") private var binRetentionDays = 14

    var body: some View {
        VStack(spacing: 0) {
            // Header with window controls
            HStack {
                // Close button (standard macOS sheet control)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")

                Spacer()

                Image(systemName: "trash")
                    .font(.title2)
                Text("Bin")
                    .font(.headline)

                Spacer()

                if !viewModel.binCards.isEmpty {
                    Button("Empty Bin", role: .destructive) {
                        viewModel.emptyBin()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    // Invisible placeholder to balance the close button
                    Color.clear.frame(width: 80)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if viewModel.binCards.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bin is Empty")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(
                        "Deleted terminals will appear here for \(binRetentionDays) days before being permanently removed."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // List of deleted items
                List {
                    ForEach(viewModel.binCards) { card in
                        BinItemRow(
                            card: card,
                            retentionDays: binRetentionDays,
                            onRestore: {
                                viewModel.restoreCard(card)
                            },
                            onDelete: {
                                viewModel.permanentlyDeleteCard(card)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 400, height: 350)
    }
}

// MARK: - Bin Item Row

struct BinItemRow: View {
    let card: TerminalCard
    let retentionDays: Int
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var daysRemaining: Int {
        guard let deletedAt = card.deletedAt else { return retentionDays }
        let expirationDate = Calendar.current.date(byAdding: .day, value: retentionDays, to: deletedAt) ?? Date()
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        return max(0, remaining)
    }

    private var deletedDateString: String {
        guard let deletedAt = card.deletedAt else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: deletedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("Deleted \(deletedDateString)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining")
                        .font(.caption)
                        .foregroundColor(daysRemaining <= 3 ? .orange : .secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    onRestore()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Restore terminal")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete permanently")
            }
        }
        .padding(.vertical, 4)
    }
}
