import SwiftUI
import TermQCore

struct KanbanBoardView: View {
    @ObservedObject var viewModel: BoardViewModel

    private let minColumnWidth: CGFloat = 200
    private let columnSpacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 16

    @State private var draggedColumnId: UUID?

    var body: some View {
        GeometryReader { geometry in
            let columnCount = max(1, viewModel.board.columns.count)
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let totalSpacing = columnSpacing * CGFloat(columnCount - 1)
            let calculatedWidth = (availableWidth - totalSpacing) / CGFloat(columnCount)
            let columnWidth = max(minColumnWidth, calculatedWidth)
            let needsScrolling = columnWidth == minColumnWidth

            ScrollView(.horizontal, showsIndicators: needsScrolling) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(viewModel.board.columns.sorted { $0.orderIndex < $1.orderIndex }) { column in
                        ColumnView(
                            column: column,
                            cards: viewModel.board.cards(for: column),
                            needsAttention: viewModel.needsAttention,
                            processingCards: viewModel.processingCards,
                            openTabs: Set(viewModel.sessionTabs),
                            onAddCard: {
                                viewModel.addTerminal(to: column)
                            },
                            onSelectCard: { card in
                                viewModel.selectCard(card)
                            },
                            onEditCard: { card in
                                viewModel.isEditingCard = card
                            },
                            onDeleteCard: { card in
                                viewModel.deleteCard(card)
                            },
                            onToggleFavourite: { card in
                                viewModel.toggleFavourite(card)
                            },
                            onEditColumn: {
                                viewModel.isEditingColumn = column
                            },
                            onDeleteColumn: {
                                viewModel.deleteColumn(column)
                            },
                            onDropCardId: { cardIdString in
                                guard let cardId = UUID(uuidString: cardIdString),
                                    let card = viewModel.board.cards.first(where: { $0.id == cardId })
                                else {
                                    return
                                }
                                viewModel.moveCard(card, to: column)
                            },
                            onDropCardBefore: { cardIdString, targetIndex in
                                guard let cardId = UUID(uuidString: cardIdString),
                                    let card = viewModel.board.cards.first(where: { $0.id == cardId })
                                else {
                                    return
                                }
                                viewModel.moveCard(card, to: column, at: targetIndex)
                            }
                        )
                        .frame(width: columnWidth)
                        .opacity(draggedColumnId == column.id ? 0.5 : 1.0)
                        .draggable(column.id.uuidString) {
                            // Drag preview
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: column.color)?.opacity(0.3) ?? Color.gray.opacity(0.3))
                                .frame(width: columnWidth, height: 100)
                                .overlay(
                                    Text(column.name)
                                        .font(.headline)
                                )
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let droppedIdString = items.first,
                                let droppedId = UUID(uuidString: droppedIdString),
                                let droppedColumn = viewModel.board.columns.first(where: { $0.id == droppedId }),
                                let targetIndex = viewModel.board.columns.firstIndex(where: { $0.id == column.id })
                            else {
                                return false
                            }
                            viewModel.moveColumn(droppedColumn, toIndex: targetIndex)
                            return true
                        } isTargeted: { isTargeted in
                            // Optional: visual feedback when hovering
                        }
                        .onDrag {
                            draggedColumnId = column.id
                            return NSItemProvider(object: column.id.uuidString as NSString)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .onChange(of: draggedColumnId) { _, _ in
            // Reset when drag ends
        }
    }
}
