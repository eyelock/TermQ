import SwiftUI
import TermQCore

struct ExpandedTerminalView: View {
    @ObservedObject var card: TerminalCard
    let onSelectTab: (TerminalCard) -> Void
    let onEditTab: (TerminalCard) -> Void
    let onCloseTab: (TerminalCard) -> Void
    let onDeleteTab: (TerminalCard) -> Void
    let onMoveTab: (UUID, Int) -> Void
    let onBell: (UUID) -> Void
    let tabCards: [TerminalCard]
    let columns: [Column]
    let needsAttention: Set<UUID>

    @State private var terminalExited = false
    @Binding var isZoomed: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (at the very top) - hidden in zoom mode
            if !tabCards.isEmpty && !isZoomed {
                tabBar
                Divider()
            }

            // Zoom indicator bar
            if isZoomed {
                HStack {
                    Spacer()
                    Text("Zoom Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("⇧⌘Z to exit")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                .onTapGesture {
                    isZoomed = false
                }
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
                    },
                    onBell: {
                        onBell(card.id)
                    }
                )
                .id(card.id)  // Force view recreation when switching terminals
            }
        }
        .onChange(of: card.id) { _, _ in
            // Reset exit state when switching to a different terminal
            // Only show exit overlay if a session exists AND has terminated
            // If no session exists yet, let TerminalHostView create one
            if TerminalSessionManager.shared.sessionExists(for: card.id) {
                terminalExited = !TerminalSessionManager.shared.hasActiveSession(for: card.id)
            } else {
                terminalExited = false
            }
        }
        .onKeyPress(.escape) {
            if isZoomed {
                isZoomed = false
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Tab Bar

    private func columnInfo(for tabCard: TerminalCard) -> (color: Color, name: String) {
        if let column = columns.first(where: { $0.id == tabCard.columnId }) {
            return (Color(hex: column.color) ?? .gray, column.name)
        }
        return (.gray, "Unknown")
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(tabCards.enumerated()), id: \.element.id) { index, tabCard in
                    let info = columnInfo(for: tabCard)
                    TabItemView(
                        tabCard: tabCard,
                        columnColor: info.color,
                        columnName: info.name,
                        isSelected: tabCard.id == card.id,
                        needsAttention: needsAttention.contains(tabCard.id),
                        onSelect: {
                            if tabCard.id != card.id {
                                onSelectTab(tabCard)
                            }
                        },
                        onEdit: {
                            onEditTab(tabCard)
                        },
                        onClose: {
                            onCloseTab(tabCard)
                        },
                        onDelete: {
                            onDeleteTab(tabCard)
                        }
                    )
                    .draggable(tabCard.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let draggedIdString = items.first,
                            let draggedId = UUID(uuidString: draggedIdString),
                            draggedId != tabCard.id
                        else { return false }

                        onMoveTab(draggedId, index)
                        return true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }
}

// MARK: - Tab Item View

private struct TabItemView: View {
    let tabCard: TerminalCard
    let columnColor: Color
    let columnName: String
    let isSelected: Bool
    let needsAttention: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
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
                    // Attention indicator (bell was received)
                    if needsAttention {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                    // Show star for favourites
                    if tabCard.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    // Terminal icon colored by column
                    Image(systemName: "terminal")
                        .font(.caption2)
                        .foregroundColor(columnColor)
                    Text(tabCard.title)
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

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Close tab (⌘W)")
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
        .help("\(tabCard.title) • \(columnName)")
        .contextMenu {
            Button("Edit...") {
                onEdit()
            }
            Divider()
            Button("Close Tab") {
                onClose()
            }
            Button("Delete Terminal", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .alert("Delete Terminal", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(tabCard.title)\"? This cannot be undone.")
        }
    }
}
