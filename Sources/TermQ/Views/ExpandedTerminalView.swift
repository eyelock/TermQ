import SwiftUI
import TermQCore

struct ExpandedTerminalView: View {
    @ObservedObject var card: TerminalCard
    let onClose: () -> Void
    let onEdit: () -> Void
    let onMoveToColumn: (Column) -> Void
    let columns: [Column]

    @State private var terminalExited = false

    var body: some View {
        VStack(spacing: 0) {
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
}
