import AppKit
import SwiftUI
import TermQCore
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var viewModel = BoardViewModel.shared
    @StateObject private var sidebarViewModel = WorktreeSidebarViewModel.shared
    @StateObject var ynhDetector = YNHDetector.shared
    @StateObject var harnessRepo = HarnessRepository.shared
    @StateObject var vendorService = VendorService.shared
    @StateObject var updateAvailabilityService = LiveUpdateAvailabilityService.shared
    @EnvironmentObject var urlHandler: URLHandler
    @AppStorage("sidebarCollapsed") private var isSidebarCollapsed = false
    @State private var isZoomed = false
    @State private var isSearching = false
    @State private var showCommandPalette = false
    @State private var showBin = false
    @State private var showColumnPicker = false
    @State private var showInstallSheet = false
    @State private var installCardIDs: Set<UUID> = []
    @State private var uninstallCardNames: [UUID: String] = [:]
    @State var launchWorkingDirectory: String?
    @State var launchWorktreeBranch: String?
    /// Pending launch request — set by every launch entry point. Held until
    /// the harness id resolves against `harnessRepo.harnesses`, at which
    /// point it materializes into `launchSheetTarget` and the sheet
    /// presents. This is the cold-start race fix for the white-pill bug:
    /// presentation is gated on actual data, not just a Bool.
    @State var pendingLaunch: PendingLaunch?
    /// Resolved data backing the launch sheet. The sheet uses `.sheet(item:)`
    /// against this — when nil, no sheet is presented (so an unsized empty
    /// content closure can never be presented).
    @State var launchSheetTarget: LaunchSheetTarget?
    /// Card that was selected before navigating to a harness detail, restored on dismiss.
    @State var cardBeforeHarness: TerminalCard?
    /// Name of the harness pending a fork-to-local operation.
    @State var harnessNameToFork: String?
    /// Controls `ForkHarnessSheet` visibility.
    @State var showForkSheet = false
    /// Name of the harness pending an update.
    @State var harnessNameToUpdate: String?
    /// Controls `UpdateHarnessSheet` visibility.
    @State var showUpdateSheet = false

    var body: some View {
        HSplitView {
            if !isSidebarCollapsed {
                SidebarView(
                    worktreeViewModel: sidebarViewModel,
                    detector: ynhDetector,
                    harnessRepository: harnessRepo,
                    onLaunchHarness: { harness in
                        requestLaunch(harnessId: harness.id, workingDirectory: nil, branch: nil)
                    },
                    onLaunchHarnessInWorktree: { harnessIdOrName, path, branch in
                        requestLaunch(
                            harnessId: harnessIdOrName, workingDirectory: path, branch: branch)
                    },
                    onAutoLaunchHarness: { harnessIdOrName, path, branch in
                        let harness = harnessRepo.harnesses.first {
                            $0.id == harnessIdOrName || $0.name == harnessIdOrName
                        }
                        let bareName = harness?.name ?? harnessIdOrName
                        let config = HarnessLaunchConfig(
                            harnessName: bareName,
                            vendorID: "",
                            defaultVendor: harness?.defaultVendor ?? "",
                            focus: nil,
                            workingDirectory: path,
                            prompt: nil,
                            backend: TerminalBackend(
                                rawValue: UserDefaults.standard.string(forKey: "defaultBackend") ?? "direct")
                                ?? .direct,
                            branch: branch
                        )
                        launchHarness(config)
                    },
                    onInstall: { showInstallSheet = true },
                    onUninstall: { name in uninstallHarness(name: name) },
                    onUpdate: { name in updateHarness(name: name) },
                    onExport: { name, dir in exportHarness(name: name, outputDir: dir) },
                    onFork: { name in forkHarness(name: name) },
                    onNewHarness: {}
                )
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
            }

            ZStack {
                if harnessRepo.selectedHarness != nil {
                    harnessDetailView()
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
                    harnessRepo.selectedHarnessId = nil
                }
            }
            .onChange(of: harnessRepo.selectedHarnessId) { _, newValue in
                if let name = newValue {
                    cardBeforeHarness = viewModel.selectedCard
                    viewModel.deselectCard()
                    Task { await harnessRepo.fetchDetail(for: name) }
                }
            }
            .onChange(of: harnessRepo.harnesses.count) { _, count in
                guard count > 0 else { return }
                Task { await updateAvailabilityService.refreshAll() }
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
                item: $launchSheetTarget,
                onDismiss: {
                    launchWorkingDirectory = nil
                    launchWorktreeBranch = nil
                    pendingLaunch = nil
                },
                content: { target in
                    HarnessLaunchSheet(
                        harness: target.harness,
                        detail: harnessRepo.selectedDetail,
                        vendors: vendorService.vendors,
                        initialWorkingDirectory: target.workingDirectory,
                        initialBranch: target.branch,
                        initialVendorOverride: target.vendorOverride
                    ) { config in
                        launchHarness(config, reuseExisting: false)
                    }
                }
            )
            .onChange(of: harnessRepo.listState) { _, _ in
                tryResolvePendingLaunch()
            }
            .sheet(isPresented: $showInstallSheet) {
                HarnessInstallSheet(
                    installedNames: Set(harnessRepo.harnesses.map(\.name)),
                    harnesses: harnessRepo.harnesses
                ) { config in
                    installHarness(config)
                }
                .frame(width: 520, height: 540)
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
                }
            }
            .sheet(isPresented: $showForkSheet) {
                // Frame applied at the .sheet content closure (the absolute
                // outermost view NSWindow sees) so the window has a definitive
                // intrinsic size at first paint. Frame inside the sheet view's
                // body races against SwiftUI's layout pass and produces a
                // small placeholder until resolved.
                Group {
                    if let name = harnessNameToFork { forkSheet(for: name) }
                }
                .frame(width: 560, height: 420)
            }
            .sheet(isPresented: $showUpdateSheet) {
                Group {
                    if let name = harnessNameToUpdate { updateSheet(for: name) }
                }
                .frame(width: 560, height: 420)
            }
            .sheet(isPresented: $viewModel.showSessionRecovery) {
                SessionRecoveryView(viewModel: viewModel)
                    .frame(width: 500, height: 400)
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
                            harnessRepo.selectedHarnessId = nil
                            viewModel.deselectCard()
                        } label: {
                            Image(systemName: "rectangle.grid.2x2")
                                .frame(width: 16)
                        }
                        .help(Strings.Toolbar.backHelp)
                    } else {
                        Button {
                            if let first = viewModel.tabCards.first {
                                viewModel.selectCard(first)
                            }
                        } label: {
                            Image(systemName: "terminal")
                                .frame(width: 16)
                        }
                        .help(Strings.Toolbar.openTerminalsHelp)
                        .disabled(viewModel.tabCards.isEmpty)
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
                    } else {
                        mcpStatusIndicator
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
            .navigationTitle(Strings.appName)
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
    private func shellQuote(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
        let defaultSafePaste = UserDefaults.standard.object(forKey: "defaultSafePaste") as? Bool ?? true
        let defaultAllowAutorun = UserDefaults.standard.object(forKey: "enableTerminalAutorun") as? Bool ?? false
        let defaultAllowOscClipboard = UserDefaults.standard.object(forKey: "allowOscClipboard") as? Bool ?? false
        let defaultConfirmExternalModifications =
            UserDefaults.standard.object(forKey: "confirmExternalLLMModifications") as? Bool ?? true
        let card = viewModel.board.addCard(
            to: targetColumn,
            title: pending.name ?? "Terminal",
            id: pending.cardId,
            safePasteEnabled: defaultSafePaste,
            allowAutorun: defaultAllowAutorun,
            allowOscClipboard: defaultAllowOscClipboard,
            confirmExternalModifications: defaultConfirmExternalModifications
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
        let defaultSafePaste = UserDefaults.standard.object(forKey: "defaultSafePaste") as? Bool ?? true
        let defaultAllowOscClipboard = UserDefaults.standard.object(forKey: "allowOscClipboard") as? Bool ?? false
        let defaultConfirmExternalModifications =
            UserDefaults.standard.object(forKey: "confirmExternalLLMModifications") as? Bool ?? true
        let card = TerminalCard(
            title: "ynh install \(config.displayName)",
            tags: [],
            columnId: column.id,
            workingDirectory: NSHomeDirectory(),
            initCommand: config.command(ynhPath: ynhPath) + " && exit",
            safePasteEnabled: defaultSafePaste,
            allowOscClipboard: defaultAllowOscClipboard,
            confirmExternalModifications: defaultConfirmExternalModifications,
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
        harnessRepo.selectedHarnessId = nil
        viewModel.objectWillChange.send()
        viewModel.selectedCard = card
    }

    /// Uninstall a harness. Harnesses with no YNH install record are deleted directly
    /// from the filesystem; YNH-managed harnesses use a transient terminal and clear
    /// associations when the shell exits.
    func uninstallHarness(name: String) {
        let harness = harnessRepo.harnesses.first(where: { $0.name == name })

        // Harnesses with no YNH install record can't be uninstalled via `ynh uninstall`.
        // Delete them directly and clean up associations.
        if let harness, harness.installedFrom == nil {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: harness.path))
            YNHPersistence.shared.removeAllAssociations(for: name)
            harnessRepo.selectedHarnessId = nil
            Task { await harnessRepo.refresh() }
            return
        }

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
        let defaultSafePaste = UserDefaults.standard.object(forKey: "defaultSafePaste") as? Bool ?? true
        let defaultAllowOscClipboard = UserDefaults.standard.object(forKey: "allowOscClipboard") as? Bool ?? false
        let defaultConfirmExternalModifications =
            UserDefaults.standard.object(forKey: "confirmExternalLLMModifications") as? Bool ?? true
        let card = TerminalCard(
            title: "ynh uninstall \(name)",
            tags: [],
            columnId: column.id,
            workingDirectory: NSHomeDirectory(),
            initCommand: "\(ynhPath) uninstall \(shellQuote(name)) && exit",
            safePasteEnabled: defaultSafePaste,
            allowOscClipboard: defaultAllowOscClipboard,
            confirmExternalModifications: defaultConfirmExternalModifications,
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
        harnessRepo.selectedHarnessId = nil
        viewModel.objectWillChange.send()
        viewModel.selectedCard = card
    }

    /// Update a harness via `UpdateHarnessSheet` (CommandRunner-based progress
    /// sheet — no transient terminal in the user's board).
    func updateHarness(name: String) {
        guard case .ready = ynhDetector.status else { return }
        harnessNameToUpdate = name
        showUpdateSheet = true
    }

    func exportHarness(name: String, outputDir: String) {
        guard case .ready(_, let yndPath?, _) = ynhDetector.status,
            let harness = harnessRepo.harnesses.first(where: { $0.name == name }),
            let column = viewModel.selectedCard.flatMap({ c in
                viewModel.board.columns.first { $0.id == c.columnId }
            }) ?? viewModel.board.columns.first
        else { return }
        let defaultSafePaste = UserDefaults.standard.object(forKey: "defaultSafePaste") as? Bool ?? true
        let defaultAllowOscClipboard = UserDefaults.standard.object(forKey: "allowOscClipboard") as? Bool ?? false
        let defaultConfirmExternalModifications =
            UserDefaults.standard.object(forKey: "confirmExternalLLMModifications") as? Bool ?? true
        let card = TerminalCard(
            title: "ynd export \(name)",
            tags: [],
            columnId: column.id,
            workingDirectory: harness.path,
            initCommand: "\(yndPath) export \(shellQuote(harness.path)) -o \(shellQuote(outputDir)) && exit",
            safePasteEnabled: defaultSafePaste,
            allowOscClipboard: defaultAllowOscClipboard,
            confirmExternalModifications: defaultConfirmExternalModifications,
            backend: .direct
        )
        card.isTransient = true
        card.allowAutorun = true
        viewModel.tabManager.addTransientCard(card)
        viewModel.tabManager.addTab(card.id)
        viewModel.objectWillChange.send()
        viewModel.selectedCard = card
    }

    /// Launch a harness by creating a persistent Card with `ynh run` as the init command.
    /// If `reuseExisting` is true and a matching card already exists (same harness + working
    /// directory), switches to it instead of creating a duplicate.
    func launchHarness(_ config: HarnessLaunchConfig, reuseExisting: Bool = true) {
        if reuseExisting,
            let existing = viewModel.allTerminals.first(where: { card in
                card.workingDirectory == config.workingDirectory
                    && card.tags.contains(where: { $0.key == "harness" && $0.value == config.harnessName })
            })
        {
            cardBeforeHarness = nil
            harnessRepo.selectedHarnessId = nil
            viewModel.tabManager.addTab(existing.id)
            viewModel.objectWillChange.send()
            viewModel.selectedCard = existing
            return
        }

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
        let shell =
            ProcessInfo.processInfo.environment["SHELL"]
            .map { URL(fileURLWithPath: $0).lastPathComponent } ?? "sh"
        var allTags = config.tags.map { Tag(key: $0.key, value: $0.value) }
        allTags.append(Tag(key: "backend", value: config.backend.tagValue))
        allTags.append(Tag(key: "shell", value: shell))
        if config.backend.usesTmux {
            allTags.append(Tag(key: "session", value: sessionName))
            allTags.append(Tag(key: "window", value: "0"))
        }
        let defaultSafePaste = UserDefaults.standard.object(forKey: "defaultSafePaste") as? Bool ?? true
        let defaultAllowOscClipboard = UserDefaults.standard.object(forKey: "allowOscClipboard") as? Bool ?? false
        let defaultConfirmExternalModifications =
            UserDefaults.standard.object(forKey: "confirmExternalLLMModifications") as? Bool ?? true
        let card = TerminalCard(
            id: cardID,
            title: config.branch ?? config.harnessName,
            tags: allTags,
            columnId: column.id,
            workingDirectory: config.workingDirectory,
            initCommand: config.command(sessionName: sessionName),
            safePasteEnabled: defaultSafePaste,
            allowOscClipboard: defaultAllowOscClipboard,
            confirmExternalModifications: defaultConfirmExternalModifications,
            backend: config.backend
        )
        card.allowAutorun = true

        viewModel.board.cards.append(card)
        viewModel.save()

        if let current = viewModel.selectedCard {
            viewModel.tabManager.insertTab(card.id, after: current.id)
        } else {
            viewModel.tabManager.addTab(card.id)
        }

        // Clear harness selection and switch to the new Card.
        cardBeforeHarness = nil
        harnessRepo.selectedHarnessId = nil
        viewModel.objectWillChange.send()
        viewModel.selectedCard = card
    }
}
