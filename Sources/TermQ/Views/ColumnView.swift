import SwiftUI
import TermQCore

struct ColumnView: View {
    @ObservedObject var column: Column
    let cards: [TerminalCard]
    let needsAttention: Set<UUID>
    let processingCards: Set<UUID>
    let activeSessionCards: Set<UUID>
    let openTabs: Set<UUID>
    let onAddCard: () -> Void
    let onSelectCard: (TerminalCard) -> Void
    let onEditCard: (TerminalCard) -> Void
    let onDeleteCard: (TerminalCard) -> Void
    let onDuplicateCard: (TerminalCard) -> Void
    let onToggleFavourite: (TerminalCard) -> Void
    let onCloseSession: (TerminalCard) -> Void
    let onRestartSession: (TerminalCard) -> Void
    let onKillTerminal: (TerminalCard) -> Void
    let onEditColumn: () -> Void
    let onDeleteColumn: () -> Void
    let onDropCardId: (String) -> Void  // Takes card ID string (for end of column)
    let onDropCardBefore: (String, Int) -> Void  // Takes card ID string and target index
    let onDropColumnId: (String) -> Void  // Takes column ID string (for column reordering)

    @State private var isTargeted = false
    @State private var targetedCardIndex: Int?

    var columnColor: Color {
        Color(hex: column.color) ?? .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Circle()
                    .fill(columnColor)
                    .frame(width: 12, height: 12)

                Text(column.name)
                    .font(.headline)

                Text("\(cards.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                    )

                Spacer()

                Menu {
                    Button(Strings.Board.editColumn) {
                        onEditColumn()
                    }
                    Divider()
                    if cards.isEmpty {
                        Button(Strings.Board.columnDelete, role: .destructive) {
                            onDeleteColumn()
                        }
                    } else {
                        Text(Strings.Board.columnDeleteDisabled)
                            .foregroundColor(.secondary)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help(Strings.Board.columnOptions)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(columnColor.opacity(0.1))

            Divider()

            // Cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        TerminalCardView(
                            card: card,
                            columnColor: columnColor,
                            needsAttention: needsAttention.contains(card.id),
                            isProcessing: processingCards.contains(card.id),
                            isOpenAsTab: openTabs.contains(card.id),
                            hasActiveSession: activeSessionCards.contains(card.id),
                            onSelect: { onSelectCard(card) },
                            onEdit: { onEditCard(card) },
                            onDelete: { onDeleteCard(card) },
                            onDuplicate: { onDuplicateCard(card) },
                            onToggleFavourite: { onToggleFavourite(card) },
                            onCloseSession: { onCloseSession(card) },
                            onRestartSession: { onRestartSession(card) },
                            onKillTerminal: { onKillTerminal(card) }
                        )
                        .overlay(alignment: .top) {
                            // Drop indicator line above this card
                            if targetedCardIndex == index {
                                Rectangle()
                                    .fill(columnColor)
                                    .frame(height: 3)
                                    .offset(y: -5)
                            }
                        }
                        .draggable(card.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let uuidString = items.first,
                                uuidString != card.id.uuidString,  // Don't drop on self
                                UUID(uuidString: uuidString) != nil
                            else {
                                return false
                            }
                            onDropCardBefore(uuidString, index)
                            return true
                        } isTargeted: { targeted in
                            targetedCardIndex = targeted ? index : nil
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(isTargeted ? columnColor.opacity(0.1) : Color.clear)
            )

            Divider()

            // Add button
            Button(action: onAddCard) {
                HStack {
                    Image(systemName: "plus")
                    Text(Strings.Board.addTerminal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help(Strings.Board.addTerminalHelp)
        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(RoundedRectangle(cornerRadius: 8))  // Define hit-test area for drop
        .dropDestination(for: String.self) { items, _ in
            guard let droppedItem = items.first else {
                return false
            }

            // Check if this is a column being dropped (for reordering)
            if droppedItem.hasPrefix("column:") {
                let columnIdString = String(droppedItem.dropFirst("column:".count))
                onDropColumnId(columnIdString)
                return true
            }

            // Otherwise, treat as a card drop
            guard UUID(uuidString: droppedItem) != nil else {
                return false
            }
            onDropCardId(droppedItem)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    /// Returns true if the color is perceived as light (for text contrast decisions)
    var isLight: Bool {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB) else { return false }
        // Calculate relative luminance using sRGB formula
        let luminance =
            0.299 * components.redComponent + 0.587 * components.greenComponent
            + 0.114 * components.blueComponent
        return luminance > 0.5
    }
}
