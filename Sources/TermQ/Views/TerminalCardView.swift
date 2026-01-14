import SwiftUI
import TermQCore

struct TerminalCardView: View {
    @ObservedObject var card: TerminalCard
    let columnColor: Color
    var needsAttention: Bool = false
    var isProcessing: Bool = false
    var isOpenAsTab: Bool = false
    var hasMCPActivity: Bool = false
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleFavourite: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    /// Background color - tinted with column color when open as tab
    private var cardBackground: Color {
        if isOpenAsTab {
            return columnColor.opacity(0.15)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    /// Parse comma-separated badges into individual strings
    private var badges: [String] {
        card.badge
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with title and status
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(columnColor)

                Text(card.title)
                    .font(.headline)
                    .lineLimit(1)

                // Open as tab indicator
                if isOpenAsTab {
                    Text("Open")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(columnColor.opacity(0.3))
                        )
                        .foregroundColor(columnColor)
                }

                // MCP activity indicator - shows when agent has modified board
                if hasMCPActivity {
                    Text("Wired")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.3))
                        )
                        .foregroundColor(.green)
                        .help("Agent activity detected")
                }

                Spacer()

                // Status indicators
                HStack(spacing: 6) {
                    // Needs attention indicator (bell received)
                    if needsAttention {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                            .help("Needs attention")
                    }

                    // Processing indicator (recent output activity)
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                            .help("Processing")
                    }

                    Button {
                        onToggleFavourite()
                    } label: {
                        Image(systemName: card.isFavourite ? "star.fill" : "star")
                            .foregroundColor(card.isFavourite ? .yellow : .secondary.opacity(0.5))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering || card.isFavourite ? 1 : 0)
                    .help(card.isFavourite ? "Remove from favourites" : "Add to favourites")

                    // Running status
                    if card.isRunning && !isProcessing {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .help("Terminal is running")
                    }
                }
            }

            // Badges (right after header)
            if !badges.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(columnColor.opacity(0.2))
                            )
                            .foregroundColor(columnColor)
                    }
                }
            }

            // Description
            if !card.description.isEmpty {
                Text(card.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Working directory hint
            Text(shortenPath(card.workingDirectory))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Tags (at bottom since they can be verbose)
            if !card.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(card.tags) { tag in
                        TagView(tag: tag)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackground)
                .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 4 : 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(isHovering ? 0.5 : 0), lineWidth: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Open Terminal") {
                onSelect()
            }
            Button("Edit Details...") {
                onEdit()
            }
            Divider()
            Button(card.isFavourite ? "Remove from Favourites" : "Add to Favourites") {
                onToggleFavourite()
            }
            Divider()
            Button("Delete", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .alert("Delete Terminal", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(card.title)\"? This cannot be undone.")
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

struct TagView: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 2) {
            Text(tag.key)
                .fontWeight(.medium)
            Text(":")
            Text(tag.value)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.2))
        )
    }
}

/// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                let position = result.positions[index]
                subview.place(
                    at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
            }
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint])
    {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}
