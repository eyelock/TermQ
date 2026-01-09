import SwiftUI
import TermQCore

struct ExpandedTerminalView: View {
    @ObservedObject var card: TerminalCard
    let onSelectPinnedCard: (TerminalCard) -> Void
    let onEditPinnedCard: (TerminalCard) -> Void
    let onDeletePinnedCard: (TerminalCard) -> Void
    let pinnedCards: [TerminalCard]

    @State private var terminalExited = false

    var body: some View {
        VStack(spacing: 0) {
            // Pinned terminals tab bar (at the very top)
            if !pinnedCards.isEmpty {
                pinnedTabsBar
                Divider()
            }

            // Terminal view
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
                    .help("Start a new terminal session")
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
                .id(card.id)  // Force view recreation when switching terminals
            }
        }
    }

    // MARK: - Pinned Tabs Bar

    private var pinnedTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(pinnedCards) { pinnedCard in
                    PinnedTabView(
                        pinnedCard: pinnedCard,
                        isSelected: pinnedCard.id == card.id,
                        onSelect: {
                            if pinnedCard.id != card.id {
                                onSelectPinnedCard(pinnedCard)
                            }
                        },
                        onEdit: {
                            onEditPinnedCard(pinnedCard)
                        },
                        onDelete: {
                            onDeletePinnedCard(pinnedCard)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }
}

// MARK: - Pinned Tab View

private struct PinnedTabView: View {
    let pinnedCard: TerminalCard
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    // Fixed width for action buttons area to prevent size jumping
    private let actionButtonsWidth: CGFloat = 32

    var body: some View {
        HStack(spacing: 2) {
            // Main tab button
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.caption2)
                    Text(pinnedCard.title)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(isSelected ? .accentColor : .primary)

            // Action buttons area (fixed width to prevent jumping)
            HStack(spacing: 1) {
                if isHovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Edit terminal")

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Close terminal")
                }
            }
            .frame(width: actionButtonsWidth, alignment: .trailing)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.2)
                        : isHovering
                            ? Color.secondary.opacity(0.15)
                            : Color.secondary.opacity(0.1)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help(isSelected ? "Current terminal" : "Switch to \(pinnedCard.title)")
        .alert("Delete Terminal", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(pinnedCard.title)\"? This cannot be undone.")
        }
    }
}
