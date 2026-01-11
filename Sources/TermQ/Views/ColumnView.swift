import SwiftUI
import TermQCore

struct ColumnView: View {
    @ObservedObject var column: Column
    let cards: [TerminalCard]
    let needsAttention: Set<UUID>
    let processingCards: Set<UUID>
    let onAddCard: () -> Void
    let onSelectCard: (TerminalCard) -> Void
    let onEditCard: (TerminalCard) -> Void
    let onDeleteCard: (TerminalCard) -> Void
    let onToggleFavourite: (TerminalCard) -> Void
    let onEditColumn: () -> Void
    let onDeleteColumn: () -> Void
    let onDropCardId: (String) -> Void  // Takes card ID string

    @State private var isTargeted = false

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
                    Button("Rename Column...") {
                        onEditColumn()
                    }
                    Divider()
                    if cards.isEmpty {
                        Button("Delete Column", role: .destructive) {
                            onDeleteColumn()
                        }
                    } else {
                        Text("Delete Column (move terminals first)")
                            .foregroundColor(.secondary)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Column options")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(columnColor.opacity(0.1))

            Divider()

            // Cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        TerminalCardView(
                            card: card,
                            columnColor: columnColor,
                            needsAttention: needsAttention.contains(card.id),
                            isProcessing: processingCards.contains(card.id),
                            onSelect: { onSelectCard(card) },
                            onEdit: { onEditCard(card) },
                            onDelete: { onDeleteCard(card) },
                            onToggleFavourite: { onToggleFavourite(card) }
                        )
                        .draggable(card.id.uuidString)
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
                    Text("Add Terminal")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Add new terminal to this column")
        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(RoundedRectangle(cornerRadius: 8))  // Define hit-test area for drop
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                let _ = UUID(uuidString: uuidString)
            else {
                return false
            }
            // Call the callback with the card ID
            onDropCardId(uuidString)
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
