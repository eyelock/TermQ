import AppKit
import SwiftUI
import TermQCore
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = BoardViewModel.shared
    @StateObject private var sidebarViewModel = WorktreeSidebarViewModel.shared
    @StateObject private var ynhDetector = YNHDetector.shared
    @StateObject private var harnessRepo = HarnessRepository.shared
    @StateObject private var vendorService = VendorService.shared
    @EnvironmentObject var urlHandler: URLHandler
    @AppStorage("sidebarCollapsed") private var isSidebarCollapsed = false
    @State private var isZoomed = false
    @State private var isSearching = false
    @State private var showCommandPalette = false
    @State private var showBin = false
    @State private var showColumnPicker = false
    @State private var showLaunchSheet = false
    @State private var showInstallSheet = false
    @State private var installCardIDs: Set<UUID> = []
    @State private var uninstallCardNames: [UUID: String] = [:]
    @State private var updateCardNames: [UUID: String] = [:]
    @State private var launchWorkingDirectory: String?
    /// Card that was selected before navigating to a harness detail, restored on dismiss.
    @State private var cardBeforeHarness: TerminalCard?

    var body: some View {
        HSplitView {
            if !isSidebarCollapsed {
                SidebarView(
                    worktreeViewModel: sidebarViewModel,
                    detector: ynhDetector,
                    harnessRepository: harnessRepo,
                    onLaunchHarness: { harness in
                        harnessRepo.selectedHarnessName = harness.name
                        Task { await vendorService.refresh() }
                        showLaunchSheet = true
                    },
                    onLaunchHarnessInWorktree: { harnessName, path in
                        harnessRepo.selectedHarnessName = harnessName
                        launchWorkingDirectory = path
                        Task { await vendorService.refresh() }
                        showLaunchSheet = true
                    },
                    onInstall: { showInstallSheet = true },
                    onUninstall: { name in uninstallHarness(name: name) },
                    onUpdate: { name in updateHarness(name: name) },
                    onNewHarness: {}
                )
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
            }

            ZStack {
                if let harness = harnessRepo.selectedHarness {
                    HarnessDetailView(
                        harness: harness,
                        detail: harnessRepo.selectedDetail,
                        isLoadingDetail: harnessRepo.isLoadingDetail,
                        detailError: harnessRepo.detailError,
                        onDismiss: {
                            harnessRepo.selectedHarnessName = nil
                            if let card = cardBeforeHarness {
                                viewModel.selectCard(card)
                                cardBeforeHarness = nil
                            }
                        },
                        onLaunch: { path in
                            launchWorkingDirectory = path
                            Task { await vendorService.refresh() }
                            showLaunchSheet = true
                        },
                        onUpdate: { name in updateHarness(name: name) },
                        onUninstall: { name in uninstallHarness(name: name) }
                    )
                } else if let selectedCard = viewModel.selectedCard {
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
                        onDuplicateTab: { card in
                            viewModel.duplicateTerminal(card)
                        },
                        onCloseSession: { card in
                            viewModel.closeSession(for: card)
                        },
                        onKillSession: { card in
                            viewModel.killSession(for: card)
                        },
                        onRestartSession: { card in
                            viewModel.restartSession(for: card)
                        },
                        onMoveTab: { cardId, toIndex in
                            viewModel.moveTab(cardId, toIndex: toIndex)
                        },
                        onNewTab: {
                            viewModel.quickNewTerminal()
                        },
                        onBell: { cardId in
                            viewModel.markNeedsAttention(cardId)
                        },
                        tabCards: viewModel.tabCards,
                        columns: viewModel.board.columns,
                        needsAttention: viewModel.needsAttention,
                        processingCards: viewModel.processingCards,
                        activeSessionCards: viewModel.activeSessionCards,
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
            .onChange(of: viewModel.selectedCard?.id) { _, newValue in
                if newValue != nil {
                    harnessRepo.selectedHarnessName = nil
                }
            }
            .onChange(of: harnessRepo.selectedHarnessName) { _, newValue in
                if let name = newValue {
                    cardBeforeHarness = viewModel.selectedCard
                    viewModel.deselectCard()
                    Task { await harnessRepo.fetchDetail(for: name) }
                }
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
                        if viewModel.isEditingNewColumn {
                            // New column: add the draft to the board
                            viewModel.commitDraftColumn()
                        } else {
                            // Existing column: just update
                            viewModel.updateColumn(column)
                        }
                        viewModel.isEditingNewColumn = false
                        viewModel.isEditingColumn = nil
                    },
                    onCancel: {
                        if viewModel.isEditingNewColumn {
                            // New column: discard the draft (it was never added)
                            viewModel.discardDraftColumn()
                        }
                        viewModel.isEditingNewColumn = false
                        viewModel.isEditingColumn = nil
                    }
                )
            }
            .sheet(isPresented: $showBin) {
                BinView(viewModel: viewModel)
            }
            .sheet(
                isPresented: $showLaunchSheet,
                onDismiss: { launchWorkingDirectory = nil },
                content: {
                    if let harness = harnessRepo.selectedHarness {
                        HarnessLaunchSheet(
                            harness: harness,
                            detail: harnessRepo.selectedDetail,
                            vendors: vendorService.vendors,
                            initialWorkingDirectory: launchWorkingDirectory
                        ) { config in
                            launchHarness(config)
                        }
                    }
                }
            )
            .sheet(isPresented: $showInstallSheet) {
                HarnessInstallSheet(
                    installedNames: Set(harnessRepo.harnesses.map(\.name)),
                    harnesses: harnessRepo.harnesses
                ) { config in
                    installHarness(config)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .termqDirectSessionExited)
            ) { notif in
                guard let cardId = notif.userInfo?["cardId"] as? UUID else { return }
                let succeeded = (notif.userInfo?["exitCode"] as? Int) == 0

                if installCardIDs.remove(cardId) != nil {
                    if case .ready = ynhDetector.status {
                        Task { await harnessRepo.refresh() }
                    }
                    if succeeded { closeHarnessCard(cardId) }
                } else if let name = uninstallCardNames.removeValue(forKey: cardId) {
                    YNHPersistence.shared.removeAllAssociations(for: name)
                    if case .ready = ynhDetector.status {
                        Task { await harnessRepo.refresh() }
                    }
                    if succeeded { closeHarnessCard(cardId) }
                } else if let name = updateCardNames.removeValue(forKey: cardId) {
                    harnessRepo.invalidateDetail(for: name)
                    if case .ready = ynhDetector.status {
                        Task { await harnessRepo.refresh() }
                    }
                    if succeeded { closeHarnessCard(cardId) }
                }
            }
            .sheet(isPresented: $viewModel.showSessionRecovery) {
                SessionRecoveryView(viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        isSidebarCollapsed.toggle()
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help(Strings.Sidebar.toggleHelp)
                }

                ToolbarItem(placement: .navigation) {
                    if viewModel.selectedCard != nil || harnessRepo.selectedHarness != nil {
                        Button {
                            cardBeforeHarness = nil
                            harnessRepo.selectedHarnessName = nil
                            viewModel.deselectCard()
                        } label: {
                            Image(systemName: "rectangle.grid.2x2")
                        }
                        .help(Strings.Toolbar.backHelp)
                    }
                }

                ToolbarItem(placement: .principal) {
                    if let harness = harnessRepo.selectedHarness {
                        HStack(spacing: 8) {
                            Image(systemName: "puzzlepiece.extension")
                            Text(harness.name)
                                .font(.headline)
                            if !harness.defaultVendor.isEmpty {
                                Text(harness.defaultVendor)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.3))
                                    .foregroundColor(.purple)
                                    .clipShape(Capsule())
                            }
                        }
                    } else if let selectedCard = viewModel.selectedCard {
                        HStack(spacing: 8) {
                            // MCP status indicator
                            mcpStatusIndicator

                            Text(selectedCard.title)
                                .font(.headline)

                            // TMUX system badge (if using tmux backend)
                            if selectedCard.backend.usesTmux {
                                Text(Strings.Card.tmux)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.3))
                                    .foregroundColor(.purple)
                                    .clipShape(Capsule())
                                    .help(Strings.Card.tmuxHelp)
                            }

                            // Display user badges
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
                    } else {
                        // Board view - show MCP status in title area
                        HStack(spacing: 8) {
                            mcpStatusIndicator
                            Text(Strings.appName)
                                .font(.headline)
                        }
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
                            .help(Strings.Toolbar.moveTo)
                            .popover(isPresented: $showColumnPicker, arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(viewModel.board.columns.sorted { $0.orderIndex < $1.orderIndex }) {
                                        column in
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
                        .help(Strings.Toolbar.openTerminalAppHelp)

                        Button {
                            viewModel.quickNewTerminal()
                        } label: {
                            Image(systemName: "plus.rectangle")
                        }
                        .help(Strings.Toolbar.newQuickHelp)

                        Button {
                            viewModel.isEditingCard = selectedCard
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .help(Strings.Toolbar.editHelp)

                        Button {
                            viewModel.toggleFavourite(selectedCard)
                        } label: {
                            Image(systemName: selectedCard.isFavourite ? "star.fill" : "star")
                        }
                        .foregroundColor(selectedCard.isFavourite ? .yellow : nil)
                        .help(selectedCard.isFavourite ? Strings.Toolbar.unpinHelp : Strings.Toolbar.pinHelp)

                        Button {
                            viewModel.showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundColor(.red)
                        .help(Strings.Toolbar.deleteHelp)
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
                        .help(Strings.Toolbar.binCount(viewModel.binCards.count))

                        Button {
                            launchNativeTerminal()
                        } label: {
                            Image(systemName: "apple.terminal")
                        }
                        .help(Strings.Toolbar.openTerminalApp)

                        Menu {
                            if let firstColumn = viewModel.board.columns.first {
                                Button(Strings.Toolbar.newTerminal) {
                                    viewModel.addTerminal(to: firstColumn)
                                }
                            }
                            Button(Strings.Toolbar.newColumn) {
                                viewModel.addColumn()
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help(Strings.Toolbar.addHelp)
                    }
                }
            }
            .alert(Strings.Delete.title, isPresented: $viewModel.showDeleteConfirmation) {
                Button(Strings.Delete.cancel, role: .cancel) {}
                Button(Strings.Delete.moveToBin, role: .destructive) {
                    if let selectedCard = viewModel.selectedCard {
                        viewModel.deleteTabCard(selectedCard)
                    }
                }
            } message: {
                if let selectedCard = viewModel.selectedCard {
                    Text(Strings.Delete.binMessage(selectedCard.title))
                } else {
                    Text(Strings.Delete.binMessage(""))
                }
            }
            .navigationTitle(viewModel.selectedCard == nil ? Strings.appName : "")
            .focusedSceneValue(\.terminalActions, terminalActions)
        }
        .onAppear {
            let count = NSApplication.shared.windows.count
            TermQLogger.window.notice("ContentView appeared: \(count) window(s)")
        }
    }

}

// MARK: - Private Helpers

extension ContentView {
    /// MCP server status indicator
    var mcpStatusIndicator: some View {
        MCPStatusView(isWired: viewModel.selectedCard?.isWired ?? false)
    }

    var terminalActions: TerminalActions {
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
            },
            toggleSidebar: {
                isSidebarCollapsed.toggle()
            }
        )
    }

    /// Handle command palette actions
    func handlePaletteAction(_ action: CommandPaletteView.PaletteAction) {
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

    /// Wrap a string in single quotes for safe shell argument passing.
    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Close a transient harness operation card once its shell has exited.
    private func closeHarnessCard(_ cardId: UUID) {
        guard let card = viewModel.tabManager.card(for: cardId) else { return }
        viewModel.closeTab(card)
    }

    /// Launch native Terminal.app at the specified directory
    func launchNativeTerminal(at directory: String? = nil) {
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
                TermQLogger.session.error("AppleScript error: \(error)")
            }
        }
    }

}

// MARK: - Actions

extension ContentView {
    /// Export terminal session content to a file
    func exportTerminalSession(for card: TerminalCard) {
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
                TermQLogger.session.error("exportSession failed: \(error)")
            }
        }
    }

    func handlePendingTerminal() {
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
            targetColumn = viewModel.board.columns.first ?? Column(name: Constants.Columns.fallbackName, orderIndex: 0)
        }

        // Create the card with optional pre-generated ID (from CLI/MCP)
        let card = viewModel.board.addCard(
            to: targetColumn,
            title: pending.name ?? "Terminal",
            id: pending.cardId
        )
        card.workingDirectory = pending.path
        if let desc = pending.description {
            card.description = desc
        }
        card.tags = pending.tags

        // Set LLM fields
        if let llmPrompt = pending.llmPrompt {
            card.llmPrompt = llmPrompt
        }
        if let llmNextAction = pending.llmNextAction {
            card.llmNextAction = llmNextAction
        }
        if let initCommand = pending.initCommand {
            card.initCommand = initCommand
        }

        viewModel.objectWillChange.send()
        viewModel.save()

        // Clear the pending terminal
        urlHandler.pendingTerminal = nil

        // Optionally open the terminal immediately
        viewModel.selectCard(card)
    }

    /// Install a harness by creating a transient Card running `ynh install` so the user sees output.
    func installHarness(_ config: HarnessInstallConfig) {
        guard case .ready(let ynhPath, _, _) = ynhDetector.status else { return }
        let column: Column
        if let current = viewModel.selectedCard,
            let currentColumn = viewModel.board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
        } else if let firstColumn = viewModel.board.columns.first {
            column = firstColumn
        } else {
            return
        }
        let card = TerminalCard(
            title: "ynh install \(config.displayName)",
            tags: [],
            columnId: column.id,
            workingDirectory: NSHomeDirectory(),
            initCommand: config.command(ynhPath: ynhPath) + " && exit",
            backend: .direct
        )
        card.isTransient = true
        card.allowAutorun = true
        installCardIDs.insert(card.id)
        viewModel.tabManager.addTransientCard(card)
        if let current = viewModel.selectedCard {
            viewModel.tabManager.insertTab(card.id, after: current.id)
        } else {
            viewModel.tabManager.addTab(card.id)
        }
        harnessRepo.selectedHarnessName = nil
        viewModel.objectWillChange.send()
        viewModel.selectedCard = card
    }

    /// Uninstall a harness in a transient terminal; clears associations when the shell exits.
    func uninstallHarness(name: String) {
        guard case .ready(let ynhPath, _, _) = ynhDetector.status else { return }
        let column: Column
        if let current = viewModel.selectedCard,
            let currentColumn = viewModel.board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
        } else if let firstColumn = viewModel.board.columns.first {
            column = firstColumn
        } else {
            return
        }
        let card = TerminalCard(
            title: "ynh uninstall \(name)",
            tags: [],
            columnId: column.id,
            workingDirectory: NSHomeDirectory(),
            initCommand: "\(ynhPath) uninstall \(shellQuote(name)) && exit",
            backend: .direct
        )
        card.isTransient = true
        card.allowAutorun = true
        uninstallCardNames[card.id] = name
        viewModel.tabManager.addTransientCard(card)
        if let current = viewModel.selectedCard {
            viewModel.tabManager.insertTab(card.id, after: current.id)
        } else {
            viewModel.tabManager.addTab(card.id)
        }
        harnessRepo.selectedHarnessName = nil
        viewModel.objectWillChange.send()
        viewModel.selectedCard = card
    }

    /// Update a harness in a transient terminal; invalidates the detail cache when done.
    func updateHarness(name: String) {
        guard case .ready(let ynhPath, _, _) = ynhDetector.status else { return }
        let column: Column
        if let current = viewModel.selectedCard,
            let currentColumn = viewModel.board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
        } else if let firstColumn = viewModel.board.columns.first {
            column = firstColumn
        } else {
            return
        }
        let card = TerminalCard(
            title: "ynh update \(name)",
            tags: [],
            columnId: column.id,
            workingDirectory: NSHomeDirectory(),
            initCommand: "\(ynhPath) update \(shellQuote(name)) && exit",
            backend: .direct
        )
        card.isTransient = true
        card.allowAutorun = true
        updateCardNames[card.id] = name
        viewModel.tabManager.addTransientCard(card)
        if let current = viewModel.selectedCard {
            viewModel.tabManager.insertTab(card.id, after: current.id)
        } else {
            viewModel.tabManager.addTab(card.id)
        }
        viewModel.objectWillChange.send()
        viewModel.selectedCard = card
    }

    /// Launch a harness by creating a transient Card with `ynh run` as the init command.
    func launchHarness(_ config: HarnessLaunchConfig) {
        let column: Column
        if let current = viewModel.selectedCard,
            let currentColumn = viewModel.board.columns.first(where: { $0.id == current.columnId })
        {
            column = currentColumn
        } else if let firstColumn = viewModel.board.columns.first {
            column = firstColumn
        } else {
            return
        }

        let cardID = UUID()
        let sessionName = "termq-\(cardID.uuidString.prefix(8).lowercased())"
        let card = TerminalCard(
            id: cardID,
            title: config.harnessName,
            tags: config.tags.map { Tag(key: $0.key, value: $0.value) },
            columnId: column.id,
            workingDirectory: config.workingDirectory,
            initCommand: config.command(sessionName: sessionName),
            backend: config.backend
        )
        card.isTransient = true
        card.allowAutorun = true

        viewModel.tabManager.addTransientCard(card)

        if let current = viewModel.selectedCard {
            viewModel.tabManager.insertTab(card.id, after: current.id)
        } else {
            viewModel.tabManager.addTab(card.id)
        }

        // Clear harness selection and switch to the new Card.
        cardBeforeHarness = nil
        harnessRepo.selectedHarnessName = nil
        viewModel.objectWillChange.send()
        viewModel.selectedCard = card
    }
}
