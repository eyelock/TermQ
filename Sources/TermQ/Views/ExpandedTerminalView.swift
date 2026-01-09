import SwiftUI
import TermQCore

struct ExpandedTerminalView: View {
    @ObservedObject var card: TerminalCard
    let onClose: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveToColumn: (Column) -> Void
    let onTogglePin: () -> Void
    let onSelectPinnedCard: (TerminalCard) -> Void
    let columns: [Column]
    let pinnedCards: [TerminalCard]

    @State private var terminalExited = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Pinned terminals tab bar (at the very top)
            if !pinnedCards.isEmpty {
                pinnedTabsBar
                Divider()
            }

            // Header bar
            HStack {
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back to Board")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                // Card title and current column
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundColor(.green)
                        Text(card.title)
                            .font(.headline)
                    }

                    // Show current column
                    if let currentColumn = columns.first(where: { $0.id == card.columnId }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: currentColumn.color) ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(currentColumn.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                        )
                    }
                }

                Spacer()

                // Move to column menu
                Menu {
                    ForEach(columns) { column in
                        Button {
                            onMoveToColumn(column)
                        } label: {
                            HStack {
                                if column.id == card.columnId {
                                    Image(systemName: "checkmark")
                                }
                                Text(column.name)
                            }
                        }
                        .disabled(column.id == card.columnId)
                    }
                } label: {
                    HStack {
                        Text("Move to")
                        Image(systemName: "chevron.down")
                    }
                }
                .menuStyle(.borderlessButton)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit terminal details")

                Button(action: onTogglePin) {
                    Image(systemName: card.isPinned ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .foregroundColor(card.isPinned ? .yellow : .secondary)
                .help(card.isPinned ? "Unpin terminal" : "Pin terminal")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Delete terminal")
            }
            .alert("Delete Terminal", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            } message: {
                Text("Are you sure you want to delete \"\(card.title)\"? This cannot be undone.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Terminal view with padding
            if terminalExited {
                VStack {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Terminal session ended")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Restart Terminal") {
                        terminalExited = false
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                TerminalHostView(
                    card: card,
                    onExit: {
                        terminalExited = true
                    }
                )
            }
        }
    }

    // MARK: - Pinned Tabs Bar

    private var pinnedTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(pinnedCards) { pinnedCard in
                    Button {
                        if pinnedCard.id != card.id {
                            onSelectPinnedCard(pinnedCard)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.caption)
                            Text(pinnedCard.title)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    pinnedCard.id == card.id
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.1)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    pinnedCard.id == card.id
                                        ? Color.accentColor
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(pinnedCard.id == card.id ? .accentColor : .primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }
}
