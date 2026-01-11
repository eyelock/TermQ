import AppKit
import SwiftUI
import TermQCore
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = BoardViewModel.shared
    @EnvironmentObject var urlHandler: URLHandler
    @State private var isZoomed = false
    @State private var isSearching = false
    @State private var showCommandPalette = false
    @State private var showBin = false
    @State private var showColumnPicker = false

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
                    needsAttention: viewModel.needsAttention,
                    processingCards: viewModel.processingCards,
                    isZoomed: $isZoomed,
                    isSearching: $isSearching
                )
            } else {
                // Kanban board view
                KanbanBoardView(viewModel: viewModel)
            }

            // Command palette overlay
            if showCommandPalette {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showCommandPalette = false
                    }

                CommandPaletteView(
                    isPresented: $showCommandPalette,
                    terminals: viewModel.allTerminals,
                    columns: viewModel.board.columns,
                    currentTerminalId: viewModel.selectedCard?.id,
                    onSelectTerminal: { terminal in
                        viewModel.selectCard(terminal)
                    },
                    onAction: { action in
                        handlePaletteAction(action)
                    }
                )
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
                    viewModel.isEditingNewColumn = false
                    viewModel.isEditingColumn = nil
                },
                onCancel: {
                    // If cancelling a new column, delete it
                    if viewModel.isEditingNewColumn {
                        viewModel.deleteColumn(column)
                    }
                    viewModel.isEditingNewColumn = false
                    viewModel.isEditingColumn = nil
                }
            )
        }
        .sheet(isPresented: $showBin) {
            BinView(viewModel: viewModel)
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

            ToolbarItem(placement: .principal) {
                if let selectedCard = viewModel.selectedCard {
                    HStack(spacing: 8) {
                        Text(selectedCard.title)
                            .font(.headline)

                        // Display badges
                        ForEach(selectedCard.badges, id: \.self) { badge in
                            Text(badge)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            // Focused view controls
            ToolbarItemGroup(placement: .primaryAction) {
                if let selectedCard = viewModel.selectedCard {
                    // Move to column button with popover
                    if let currentColumn = viewModel.board.columns.first(where: { $0.id == selectedCard.columnId })
                    {
                        let columnColor = Color(hex: currentColumn.color) ?? .gray
                        let textColor = columnColor.isLight ? Color.black : Color.white
                        Button {
                            showColumnPicker.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Text(currentColumn.name)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(textColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(columnColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        .help("Move to column")
                        .popover(isPresented: $showColumnPicker, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(viewModel.board.columns.sorted { $0.orderIndex < $1.orderIndex }) { column in
                                    Button {
                                        viewModel.moveCard(selectedCard, to: column)
                                        showColumnPicker = false
                                    } label: {
                                        HStack {
                                            if column.id == selectedCard.columnId {
                                                Image(systemName: "checkmark")
                                                    .frame(width: 16)
                                            } else {
                                                Color.clear.frame(width: 16)
                                            }
                                            Text(column.name)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(column.id == selectedCard.columnId)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.leading, 4)
                            .frame(minWidth: 150)
                        }
                    }

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
                        showBin = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "trash")
                            if !viewModel.binCards.isEmpty {
                                Text("\(viewModel.binCards.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .help("Open Bin (\(viewModel.binCards.count) items)")

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
            Button("Move to Bin", role: .destructive) {
                if let selectedCard = viewModel.selectedCard {
                    viewModel.deleteTabCard(selectedCard)
                }
            }
        } message: {
            if let selectedCard = viewModel.selectedCard {
                Text("Move \"\(selectedCard.title)\" to the Bin? You can restore it later from the Bin.")
            } else {
                Text("Move this terminal to the Bin? You can restore it later.")
            }
        }
        .navigationTitle(viewModel.selectedCard == nil ? "TermQ" : "")
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
            goBack: {
                isZoomed = false
                isSearching = false
                viewModel.deselectCard()
            },
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
            },
            toggleZoom: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isZoomed.toggle()
                }
            },
            toggleSearch: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSearching.toggle()
                }
            },
            exportSession: {
                if let selectedCard = viewModel.selectedCard {
                    exportTerminalSession(for: selectedCard)
                }
            },
            showCommandPalette: {
                showCommandPalette = true
            },
            showBin: {
                showBin = true
            }
        )
    }

    /// Handle command palette actions
    private func handlePaletteAction(_ action: CommandPaletteView.PaletteAction) {
        switch action {
        case .newTerminal:
            viewModel.quickNewTerminal()
        case .newColumn:
            viewModel.addColumn()
        case .toggleZoom:
            withAnimation(.easeInOut(duration: 0.2)) {
                isZoomed.toggle()
            }
        case .toggleSearch:
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearching.toggle()
            }
        case .exportSession:
            if let selectedCard = viewModel.selectedCard {
                exportTerminalSession(for: selectedCard)
            }
        case .backToBoard:
            isZoomed = false
            isSearching = false
            viewModel.deselectCard()
        case .openInTerminalApp:
            if let selectedCard = viewModel.selectedCard {
                let currentDir =
                    TerminalSessionManager.shared.getCurrentDirectory(for: selectedCard.id)
                    ?? selectedCard.workingDirectory
                launchNativeTerminal(at: currentDir)
            }
        case .toggleFavourite:
            if let card = viewModel.selectedCard {
                viewModel.toggleFavourite(card)
            }
        }
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

    /// Export terminal session content to a file
    private func exportTerminalSession(for card: TerminalCard) {
        guard let terminalView = TerminalSessionManager.shared.getTerminalView(for: card.id) else {
            return
        }

        let terminal = terminalView.getTerminal()
        let bufferData = terminal.getBufferAsData()

        guard let content = String(data: bufferData, encoding: .utf8) else {
            return
        }

        // Show save panel
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(card.title).txt"
        panel.message = "Export terminal session content"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to export session: \(error)")
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
