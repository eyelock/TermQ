import SwiftUI
import TermQCore

struct ContentView: View {
    @StateObject private var viewModel = BoardViewModel()
    @EnvironmentObject var urlHandler: URLHandler

    var body: some View {
        ZStack {
            if let selectedCard = viewModel.selectedCard {
                // Expanded terminal view
                ExpandedTerminalView(
                    card: selectedCard,
                    onClose: {
                        viewModel.deselectCard()
                    },
                    onEdit: {
                        viewModel.isEditingCard = selectedCard
                    },
                    onDelete: {
                        viewModel.deleteCard(selectedCard)
                    },
                    onMoveToColumn: { column in
                        viewModel.moveCard(selectedCard, to: column)
                    },
                    onTogglePin: {
                        viewModel.togglePin(selectedCard)
                    },
                    onSelectPinnedCard: { card in
                        viewModel.selectCard(card)
                    },
                    columns: viewModel.board.columns,
                    pinnedCards: viewModel.pinnedCards
                )
            } else {
                // Kanban board view
                KanbanBoardView(viewModel: viewModel)
            }
        }
        .onChange(of: urlHandler.pendingTerminal?.id) { _, _ in
            handlePendingTerminal()
        }
        .sheet(item: $viewModel.isEditingCard) { card in
            CardEditorView(
                card: card,
                columns: viewModel.board.columns,
                isNewCard: viewModel.isEditingNewCard,
                onSave: { switchToTerminal in
                    viewModel.updateCard(card)
                    if switchToTerminal {
                        viewModel.selectCard(card)
                    }
                    viewModel.isEditingNewCard = false
                    viewModel.isEditingCard = nil
                },
                onCancel: {
                    viewModel.isEditingNewCard = false
                    viewModel.isEditingCard = nil
                }
            )
        }
        .sheet(item: $viewModel.isEditingColumn) { column in
            ColumnEditorView(
                column: column,
                onSave: {
                    viewModel.updateColumn(column)
                    viewModel.isEditingColumn = nil
                },
                onCancel: {
                    viewModel.isEditingColumn = nil
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if viewModel.selectedCard != nil {
                    Button {
                        viewModel.deselectCard()
                    } label: {
                        Image(systemName: "rectangle.grid.2x2")
                    }
                    .help("Back to board")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let firstColumn = viewModel.board.columns.first {
                        Button("New Terminal") {
                            viewModel.addTerminal(to: firstColumn)
                        }
                    }
                    Button("New Column") {
                        viewModel.addColumn()
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationTitle(viewModel.selectedCard?.title ?? "TermQ")
    }

    private func handlePendingTerminal() {
        guard let pending = urlHandler.pendingTerminal else { return }

        // Find the target column
        let targetColumn: Column
        if let columnName = pending.column,
            let found = viewModel.board.columns.first(where: {
                $0.name.lowercased() == columnName.lowercased()
            })
        {
            targetColumn = found
        } else {
            // Default to first column
            targetColumn = viewModel.board.columns.first ?? Column(name: "To Do", orderIndex: 0)
        }

        // Create the card
        let card = viewModel.board.addCard(to: targetColumn, title: pending.name ?? "Terminal")
        card.workingDirectory = pending.path
        if let desc = pending.description {
            card.description = desc
        }
        card.tags = pending.tags

        viewModel.objectWillChange.send()
        viewModel.save()

        // Clear the pending terminal
        urlHandler.pendingTerminal = nil

        // Optionally open the terminal immediately
        viewModel.selectCard(card)
    }
}
