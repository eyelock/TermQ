import AppKit
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
                    onSelectTab: { card in
                        viewModel.selectCard(card)
                    },
                    onEditTab: { card in
                        viewModel.isEditingCard = card
                    },
                    onCloseTab: { card in
                        viewModel.closeTab(card)
                    },
                    onDeleteTab: { card in
                        viewModel.deleteTabCard(card)
                    },
                    onMoveTab: { cardId, toIndex in
                        viewModel.moveTab(cardId, toIndex: toIndex)
                    },
                    onBell: { cardId in
                        viewModel.markNeedsAttention(cardId)
                    },
                    tabCards: viewModel.tabCards,
                    columns: viewModel.board.columns,
                    needsAttention: viewModel.needsAttention
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
                    // If cancelling a new card, delete it
                    if viewModel.isEditingNewCard {
                        viewModel.deleteCard(card)
                    }
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
                    .help("Back to board (⌘B)")
                }
            }

            // Focused view controls
            ToolbarItemGroup(placement: .primaryAction) {
                if let selectedCard = viewModel.selectedCard {
                    // Move to column menu
                    Menu {
                        ForEach(viewModel.board.columns.sorted { $0.orderIndex < $1.orderIndex }) { column in
                            Button {
                                viewModel.moveCard(selectedCard, to: column)
                            } label: {
                                HStack {
                                    if column.id == selectedCard.columnId {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(column.name)
                                }
                            }
                            .disabled(column.id == selectedCard.columnId)
                        }
                    } label: {
                        // Show current column name in menu label
                        if let currentColumn = viewModel.board.columns.first(where: { $0.id == selectedCard.columnId })
                        {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: currentColumn.color) ?? .gray)
                                    .frame(width: 8, height: 8)
                                Text(currentColumn.name)
                            }
                        } else {
                            Text("Move to")
                        }
                    }
                    .help("Move to column")

                    Divider()

                    Button {
                        // Use tracked current directory if available, otherwise fall back to card's starting directory
                        let currentDir =
                            TerminalSessionManager.shared.getCurrentDirectory(for: selectedCard.id)
                            ?? selectedCard.workingDirectory
                        launchNativeTerminal(at: currentDir)
                    } label: {
                        Image(systemName: "apple.terminal")
                    }
                    .help("Open in Terminal.app (⌘⇧T)")

                    Button {
                        viewModel.quickNewTerminal()
                    } label: {
                        Image(systemName: "plus.rectangle")
                    }
                    .help("Quick new terminal (⌘T)")

                    Button {
                        viewModel.isEditingCard = selectedCard
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Edit terminal details")

                    Button {
                        viewModel.toggleFavourite(selectedCard)
                    } label: {
                        Image(systemName: selectedCard.isFavourite ? "star.fill" : "star")
                    }
                    .foregroundColor(selectedCard.isFavourite ? .yellow : nil)
                    .help(selectedCard.isFavourite ? "Remove from favourites (⌘D)" : "Add to favourites (⌘D)")

                    Button {
                        viewModel.showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.red)
                    .help("Delete terminal (⌘⌫)")
                } else {
                    // Board view controls
                    Button {
                        launchNativeTerminal()
                    } label: {
                        Image(systemName: "apple.terminal")
                    }
                    .help("Open Terminal.app")

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
                    .help("Add new terminal or column")
                }
            }
        }
        .alert("Delete Terminal", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let selectedCard = viewModel.selectedCard {
                    viewModel.deleteTabCard(selectedCard)
                }
            }
        } message: {
            if let selectedCard = viewModel.selectedCard {
                Text("Are you sure you want to delete \"\(selectedCard.title)\"? This cannot be undone.")
            } else {
                Text("Are you sure you want to delete this terminal? This cannot be undone.")
            }
        }
        .navigationTitle(viewModel.selectedCard?.title ?? "TermQ")
        .focusedSceneValue(\.terminalActions, terminalActions)
    }

    private var terminalActions: TerminalActions {
        TerminalActions(
            quickNewTerminal: { viewModel.quickNewTerminal() },
            newTerminalWithDialog: {
                if let firstColumn = viewModel.board.columns.first {
                    viewModel.addTerminal(to: firstColumn)
                }
            },
            newColumn: { viewModel.addColumn() },
            goBack: { viewModel.deselectCard() },
            toggleFavourite: {
                if let card = viewModel.selectedCard {
                    viewModel.toggleFavourite(card)
                }
            },
            nextTab: { viewModel.nextTab() },
            previousTab: { viewModel.previousTab() },
            openInTerminalApp: {
                if let selectedCard = viewModel.selectedCard {
                    let currentDir =
                        TerminalSessionManager.shared.getCurrentDirectory(for: selectedCard.id)
                        ?? selectedCard.workingDirectory
                    launchNativeTerminal(at: currentDir)
                }
            },
            closeTab: {
                if let card = viewModel.selectedCard {
                    viewModel.closeTab(card)
                }
            },
            deleteTerminal: {
                if viewModel.selectedCard != nil {
                    viewModel.showDeleteConfirmation = true
                }
            }
        )
    }

    /// Launch native Terminal.app at the specified directory
    private func launchNativeTerminal(at directory: String? = nil) {
        let path = directory ?? NSHomeDirectory()
        let script = """
            tell application "Terminal"
                activate
                do script "cd '\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
            end tell
            """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
            }
        }
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
