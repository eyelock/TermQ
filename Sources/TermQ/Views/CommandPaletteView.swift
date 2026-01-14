import AppKit
import SwiftUI
import TermQCore

/// Command palette for quick actions and terminal switching
struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let terminals: [TerminalCard]
    let columns: [Column]
    let currentTerminalId: UUID?
    let onSelectTerminal: (TerminalCard) -> Void
    let onAction: (PaletteAction) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    enum PaletteAction: Identifiable {
        case newTerminal
        case newColumn
        case toggleZoom
        case toggleSearch
        case exportSession
        case backToBoard
        case openInTerminalApp
        case toggleFavourite

        var id: String { title }

        var title: String {
            switch self {
            case .newTerminal: return Strings.CommandPalette.newTerminal
            case .newColumn: return Strings.CommandPalette.newColumn
            case .toggleZoom: return Strings.CommandPalette.toggleZoom
            case .toggleSearch: return Strings.CommandPalette.findInTerminal
            case .exportSession: return Strings.CommandPalette.exportSession
            case .backToBoard: return Strings.CommandPalette.backToBoard
            case .openInTerminalApp: return Strings.CommandPalette.openInTerminalApp
            case .toggleFavourite: return Strings.CommandPalette.toggleFavourite
            }
        }

        var icon: String {
            switch self {
            case .newTerminal: return "plus.rectangle"
            case .newColumn: return "rectangle.split.3x1"
            case .toggleZoom: return "arrow.up.left.and.arrow.down.right"
            case .toggleSearch: return "magnifyingglass"
            case .exportSession: return "square.and.arrow.up"
            case .backToBoard: return "rectangle.grid.2x2"
            case .openInTerminalApp: return "apple.terminal"
            case .toggleFavourite: return "star"
            }
        }

        var shortcut: String? {
            switch self {
            case .newTerminal: return "⌘T"
            case .newColumn: return "⇧⌘N"
            case .toggleZoom: return "⇧⌘Z"
            case .toggleSearch: return "⌘F"
            case .exportSession: return "⇧⌘S"
            case .backToBoard: return "⌘B"
            case .openInTerminalApp: return "⇧⌘T"
            case .toggleFavourite: return "⌘D"
            }
        }
    }

    private var allActions: [PaletteAction] {
        [
            .newTerminal, .newColumn, .toggleZoom, .toggleSearch,
            .exportSession, .backToBoard, .openInTerminalApp, .toggleFavourite,
        ]
    }

    private var filteredActions: [PaletteAction] {
        guard !searchText.isEmpty else { return allActions }
        return allActions.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredTerminals: [TerminalCard] {
        guard !searchText.isEmpty else { return terminals }
        return terminals.filter { terminal in
            terminal.title.localizedCaseInsensitiveContains(searchText)
                || terminal.description.localizedCaseInsensitiveContains(searchText)
                || terminal.workingDirectory.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var totalItemCount: Int {
        filteredTerminals.count + filteredActions.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(Strings.Palette.placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelectedItem()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isPresented = false
                } label: {
                    Text("ESC")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Terminals section
                        if !filteredTerminals.isEmpty {
                            sectionHeader("Terminals")
                            ForEach(Array(filteredTerminals.enumerated()), id: \.element.id) {
                                index, terminal in
                                terminalRow(terminal, isSelected: selectedIndex == index)
                                    .id("terminal-\(index)")
                            }
                        }

                        // Actions section
                        if !filteredActions.isEmpty {
                            sectionHeader("Actions")
                            ForEach(Array(filteredActions.enumerated()), id: \.element.id) {
                                index, action in
                                let actualIndex = filteredTerminals.count + index
                                actionRow(action, isSelected: selectedIndex == actualIndex)
                                    .id("action-\(index)")
                            }
                        }

                        if filteredTerminals.isEmpty && filteredActions.isEmpty {
                            Text(Strings.Palette.noResults)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    if newIndex < filteredTerminals.count {
                        proxy.scrollTo("terminal-\(newIndex)", anchor: .center)
                    } else {
                        let actionIndex = newIndex - filteredTerminals.count
                        proxy.scrollTo("action-\(actionIndex)", anchor: .center)
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard isPresented else { return event }

            switch event.keyCode {
            case 126:  // Up arrow
                if selectedIndex > 0 {
                    DispatchQueue.main.async {
                        selectedIndex -= 1
                    }
                }
                return nil  // Consume event
            case 125:  // Down arrow
                if selectedIndex < totalItemCount - 1 {
                    DispatchQueue.main.async {
                        selectedIndex += 1
                    }
                }
                return nil  // Consume event
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }

    private func terminalRow(_ terminal: TerminalCard, isSelected: Bool) -> some View {
        let columnColor =
            columns.first(where: { $0.id == terminal.columnId }).map { Color(hex: $0.color) ?? .gray }
            ?? .gray

        return Button {
            onSelectTerminal(terminal)
            isPresented = false
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(columnColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if terminal.isFavourite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                        Text(terminal.title)
                            .fontWeight(.medium)
                        if terminal.id == currentTerminalId {
                            Text("(current)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(terminal.workingDirectory)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if !terminal.badge.isEmpty {
                    Text(terminal.badge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(columnColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ action: PaletteAction, isSelected: Bool) -> some View {
        Button {
            onAction(action)
            isPresented = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .frame(width: 20)
                    .foregroundColor(.secondary)

                Text(action.title)

                Spacer()

                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func executeSelectedItem() {
        if selectedIndex < filteredTerminals.count {
            let terminal = filteredTerminals[selectedIndex]
            onSelectTerminal(terminal)
            isPresented = false
        } else {
            let actionIndex = selectedIndex - filteredTerminals.count
            if actionIndex < filteredActions.count {
                let action = filteredActions[actionIndex]
                onAction(action)
                isPresented = false
            }
        }
    }
}
