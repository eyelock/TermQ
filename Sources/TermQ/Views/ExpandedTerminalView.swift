import SwiftUI
import TermQCore

struct ExpandedTerminalView: View {
    @ObservedObject var card: TerminalCard
    let onSelectTab: (TerminalCard) -> Void
    let onEditTab: (TerminalCard) -> Void
    let onCloseTab: (TerminalCard) -> Void
    let onDeleteTab: (TerminalCard) -> Void
    let onDuplicateTab: (TerminalCard) -> Void
    let onCloseSession: (TerminalCard) -> Void
    let onRestartSession: (TerminalCard) -> Void
    let onMoveTab: (UUID, Int) -> Void
    let onNewTab: () -> Void
    let onBell: (UUID) -> Void
    let tabCards: [TerminalCard]
    let columns: [Column]
    let needsAttention: Set<UUID>
    let processingCards: Set<UUID>
    let activeSessionCards: Set<UUID>

    @State private var terminalExited = false
    @Binding var isZoomed: Bool
    @Binding var isSearching: Bool
    @State private var searchText = ""
    @State private var searchResults: [String] = []
    @State private var currentResultIndex = 0
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showPaneControls = false
    @ObservedObject private var sessionManager = TerminalSessionManager.shared

    /// Whether the current terminal is using tmux backend
    private var isTmuxSession: Bool {
        sessionManager.getBackend(for: card.id) == .tmux
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (at the very top) - hidden in zoom mode
            if !tabCards.isEmpty && !isZoomed {
                tabBar
                Divider()
            }

            // Zoom indicator bar
            if isZoomed {
                HStack {
                    Spacer()
                    Text(Strings.Terminal.current)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("⇧⌘Z")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                .onTapGesture {
                    isZoomed = false
                }
            }

            // Search bar
            if isSearching {
                searchBar
            }

            // Pane controls bar (only for tmux sessions)
            if isTmuxSession && showPaneControls {
                paneControlsBar
            }

            // Terminal view
            if terminalExited {
                VStack {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(Strings.Terminal.ended)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button(Strings.Terminal.restart) {
                        terminalExited = false
                    }
                    .padding(.top, 8)
                    .help(Strings.Terminal.restartHelp)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                TerminalHostView(
                    card: card,
                    onExit: {
                        terminalExited = true
                    },
                    onBell: {
                        onBell(card.id)
                    },
                    isSearching: isSearching
                )
                .id(card.id)  // Force view recreation when switching terminals
            }
        }
        .onChange(of: card.id) { _, _ in
            // Reset exit state when switching to a different terminal
            // Only show exit overlay if a session exists AND has terminated
            // If no session exists yet, let TerminalHostView create one
            if TerminalSessionManager.shared.sessionExists(for: card.id) {
                terminalExited = !TerminalSessionManager.shared.hasActiveSession(for: card.id)
            } else {
                terminalExited = false
            }
        }
        .onKeyPress(.escape) {
            if isSearching {
                isSearching = false
                searchText = ""
                return .handled
            }
            if isZoomed {
                isZoomed = false
                return .handled
            }
            return .ignored
        }
    }

    /// Toggle search mode
    func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isSearching.toggle()
            if isSearching {
                // Focus search field after a brief delay for animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFieldFocused = true
                }
            } else {
                searchText = ""
                isSearchFieldFocused = false
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(Strings.Help.searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    performSearch()
                }

            if !searchText.isEmpty {
                Text("\(searchResults.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    previousResult()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(searchResults.isEmpty)

                Button {
                    nextResult()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(searchResults.isEmpty)
            }

            Button {
                isSearching = false
                searchText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Pane Controls Bar

    private var paneControlsBar: some View {
        HStack(spacing: 12) {
            // Split controls
            HStack(spacing: 4) {
                Text("Split:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    sessionManager.splitPaneHorizontally(cardId: card.id)
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Split horizontally (top/bottom)")

                Button {
                    sessionManager.splitPaneVertically(cardId: card.id)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Split vertically (left/right)")
            }

            Divider()
                .frame(height: 16)

            // Navigate controls
            HStack(spacing: 4) {
                Text("Navigate:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    sessionManager.selectPane(direction: .up, cardId: card.id)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Move to pane above")

                Button {
                    sessionManager.selectPane(direction: .down, cardId: card.id)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Move to pane below")

                Button {
                    sessionManager.selectPane(direction: .left, cardId: card.id)
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Move to pane on left")

                Button {
                    sessionManager.selectPane(direction: .right, cardId: card.id)
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Move to pane on right")
            }

            Divider()
                .frame(height: 16)

            // Zoom and close
            HStack(spacing: 4) {
                Button {
                    sessionManager.togglePaneZoom(cardId: card.id)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Zoom pane (toggle fullscreen)")

                Button {
                    sessionManager.closeCurrentPane(cardId: card.id)
                } label: {
                    Image(systemName: "xmark.rectangle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.8))
                .help("Close current pane")
            }

            Spacer()

            // Close button for the bar
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showPaneControls = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
    }

    /// Toggle pane controls visibility
    func togglePaneControls() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showPaneControls.toggle()
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        // Get the terminal content and search
        if let terminalView = TerminalSessionManager.shared.getTerminalView(for: card.id) {
            let terminal = terminalView.getTerminal()
            let bufferData = terminal.getBufferAsData()
            if let content = String(data: bufferData, encoding: .utf8) {
                let lines = content.components(separatedBy: CharacterSet.newlines)
                searchResults = lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
                currentResultIndex = 0
            }
        }
    }

    private func nextResult() {
        guard !searchResults.isEmpty else { return }
        currentResultIndex = (currentResultIndex + 1) % searchResults.count
    }

    private func previousResult() {
        guard !searchResults.isEmpty else { return }
        currentResultIndex = currentResultIndex > 0 ? currentResultIndex - 1 : searchResults.count - 1
    }

    // MARK: - Tab Bar

    private func columnInfo(for tabCard: TerminalCard) -> (color: Color, name: String) {
        if let column = columns.first(where: { $0.id == tabCard.columnId }) {
            return (Color(hex: column.color) ?? .gray, column.name)
        }
        return (.gray, "Unknown")
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(tabCards.enumerated()), id: \.element.id) { index, tabCard in
                        let info = columnInfo(for: tabCard)
                        TabItemView(
                            tabCard: tabCard,
                            columnColor: info.color,
                            columnName: info.name,
                            isSelected: tabCard.id == card.id,
                            needsAttention: needsAttention.contains(tabCard.id),
                            isProcessing: processingCards.contains(tabCard.id),
                            hasActiveSession: activeSessionCards.contains(tabCard.id),
                            onSelect: {
                                if tabCard.id != card.id {
                                    onSelectTab(tabCard)
                                }
                            },
                            onEdit: {
                                onEditTab(tabCard)
                            },
                            onClose: {
                                onCloseTab(tabCard)
                            },
                            onDelete: {
                                onDeleteTab(tabCard)
                            },
                            onDuplicate: {
                                onDuplicateTab(tabCard)
                            },
                            onCloseSession: {
                                onCloseSession(tabCard)
                            },
                            onRestartSession: {
                                onRestartSession(tabCard)
                            }
                        )
                        .draggable(tabCard.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedIdString = items.first,
                                let draggedId = UUID(uuidString: draggedIdString),
                                draggedId != tabCard.id
                            else { return false }

                            onMoveTab(draggedId, index)
                            return true
                        }
                    }

                    // New tab button
                    Button(action: onNewTab) {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(Strings.Terminal.newTabHelp)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // tmux pane controls toggle (only for tmux sessions)
            if isTmuxSession {
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)

                Button {
                    togglePaneControls()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.split.3x3")
                            .font(.caption)
                        Text("Panes")
                            .font(.caption)
                    }
                    .foregroundColor(showPaneControls ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("Toggle tmux pane controls")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }
}

// MARK: - Tab Item View

private struct TabItemView: View {
    let tabCard: TerminalCard
    let columnColor: Color
    let columnName: String
    let isSelected: Bool
    let needsAttention: Bool
    let isProcessing: Bool
    let hasActiveSession: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onCloseSession: () -> Void
    let onRestartSession: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    // Fixed width for action buttons area to prevent size jumping
    private let actionButtonsWidth: CGFloat = 32

    var body: some View {
        HStack(spacing: 2) {
            // Main tab button
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    // Processing indicator (recent output activity)
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 10, height: 10)
                    }
                    // Attention indicator (bell was received)
                    if needsAttention && !isProcessing {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                    // Show star for favourites
                    if tabCard.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    // Terminal icon colored by column
                    Image(systemName: "terminal")
                        .font(.caption2)
                        .foregroundColor(columnColor)
                    Text(tabCard.title)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(isSelected ? .accentColor : .primary)

            // Action buttons area (fixed width to prevent jumping)
            HStack(spacing: 1) {
                if isHovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help(Strings.Terminal.editHelp)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help(Strings.Terminal.closeTabHelp)
                }
            }
            .frame(width: actionButtonsWidth, alignment: .trailing)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.2)
                        : isHovering
                            ? Color.secondary.opacity(0.15)
                            : Color.secondary.opacity(0.1)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help(Strings.Terminal.tabHelp(tabCard.title, columnName))
        .contextMenu {
            Button(Strings.Card.edit) {
                onEdit()
            }
            Button(Strings.Card.duplicate) {
                onDuplicate()
            }
            if hasActiveSession {
                Divider()
                Button(Strings.Card.closeSession) {
                    onCloseSession()
                }
                Button(Strings.Card.restartSession) {
                    onRestartSession()
                }
            }
            Divider()
            Button(Strings.Common.close) {
                onClose()
            }
            Button(Strings.Card.delete, role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .alert(Strings.Delete.title, isPresented: $showDeleteConfirmation) {
            Button(Strings.Delete.cancel, role: .cancel) {}
            Button(Strings.Delete.confirm, role: .destructive) {
                onDelete()
            }
        } message: {
            Text(Strings.Delete.message(tabCard.title))
        }
    }
}
