import SwiftUI
import TermQCore

struct KanbanBoardView: View {
    @ObservedObject var viewModel: BoardViewModel

    private let minColumnWidth: CGFloat = 200
    private let columnSpacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 16

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
                            onTogglePin: { card in
                                viewModel.togglePin(card)
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
                            }
                        )
                        .frame(width: columnWidth)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
