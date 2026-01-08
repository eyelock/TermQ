import SwiftUI
import TermQCore

struct KanbanBoardView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 16) {
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
                }

                // Spacer at the end for scrolling padding
                Spacer()
                    .frame(width: 20)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
