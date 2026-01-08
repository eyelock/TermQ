import SwiftUI
import TermQCore

struct TerminalCardView: View {
    @ObservedObject var card: TerminalCard
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with title and status
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.green)

                Text(card.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if card.isRunning {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
            }

            // Description
            if !card.description.isEmpty {
                Text(card.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Tags
            if !card.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(card.tags) { tag in
                        TagView(tag: tag)
                    }
                }
            }

            // Working directory hint
            Text(shortenPath(card.workingDirectory))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
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
            Button("Delete", role: .destructive) {
                onDelete()
            }
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
