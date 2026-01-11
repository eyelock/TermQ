import AppKit
import SwiftUI
import TermQCore

/// Shared state for handling URL-based terminal creation and modification
@MainActor
class URLHandler: ObservableObject {
    static let shared = URLHandler()

    @Published var pendingTerminal: PendingTerminal?

    struct PendingTerminal: Identifiable {
        let id = UUID()
        let path: String
        let name: String?
        let description: String?
        let column: String?
        let tags: [Tag]
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "termq" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        switch url.host {
        case "open":
            handleOpen(queryItems: queryItems)
        case "update":
            handleUpdate(queryItems: queryItems)
        case "move":
            handleMove(queryItems: queryItems)
        default:
            break
        }
    }

    private func handleOpen(queryItems: [URLQueryItem]) {
        let path = queryItems.first { $0.name == "path" }?.value ?? NSHomeDirectory()
        let name = queryItems.first { $0.name == "name" }?.value
        let description = queryItems.first { $0.name == "description" }?.value
        let column = queryItems.first { $0.name == "column" }?.value

        // Parse tags
        let tags: [Tag] =
            queryItems
            .filter { $0.name == "tag" }
            .compactMap { item -> Tag? in
                guard let value = item.value,
                    let eqIndex = value.firstIndex(of: "=")
                else { return nil }
                let key = String(value[..<eqIndex])
                let val = String(value[value.index(after: eqIndex)...])
                return Tag(key: key, value: val)
            }

        pendingTerminal = PendingTerminal(
            path: path,
            name: name,
            description: description,
            column: column,
            tags: tags
        )
    }

    private func handleUpdate(queryItems: [URLQueryItem]) {
        guard let idString = queryItems.first(where: { $0.name == "id" })?.value,
            let cardId = UUID(uuidString: idString)
        else { return }

        let viewModel = BoardViewModel.shared

        guard let card = viewModel.card(for: cardId) else { return }

        // Update name
        if let name = queryItems.first(where: { $0.name == "name" })?.value {
            card.title = name
        }

        // Update description
        if let description = queryItems.first(where: { $0.name == "description" })?.value {
            card.description = description
        }

        // Update badge
        if let badge = queryItems.first(where: { $0.name == "badge" })?.value {
            card.badge = badge
        }

        // Update LLM prompt
        if let llmPrompt = queryItems.first(where: { $0.name == "llmPrompt" })?.value {
            card.llmPrompt = llmPrompt
        }

        // Update favourite status
        if let favouriteStr = queryItems.first(where: { $0.name == "favourite" })?.value {
            let shouldBeFavourite = favouriteStr.lowercased() == "true"
            if card.isFavourite != shouldBeFavourite {
                viewModel.toggleFavourite(card)
            }
        }

        // Parse and add tags
        let newTags: [Tag] =
            queryItems
            .filter { $0.name == "tag" }
            .compactMap { item -> Tag? in
                guard let value = item.value,
                    let eqIndex = value.firstIndex(of: "=")
                else { return nil }
                let key = String(value[..<eqIndex])
                let val = String(value[value.index(after: eqIndex)...])
                return Tag(key: key, value: val)
            }
        if !newTags.isEmpty {
            card.tags.append(contentsOf: newTags)
        }

        // Update column if specified
        if let columnName = queryItems.first(where: { $0.name == "column" })?.value {
            let columnLower = columnName.lowercased()
            if let targetColumn = viewModel.board.columns.first(where: {
                $0.name.lowercased() == columnLower
            }) {
                viewModel.moveCard(card, to: targetColumn)
            }
        }

        viewModel.updateCard(card)
    }

    private func handleMove(queryItems: [URLQueryItem]) {
        guard let idString = queryItems.first(where: { $0.name == "id" })?.value,
            let cardId = UUID(uuidString: idString),
            let columnName = queryItems.first(where: { $0.name == "column" })?.value
        else { return }

        let viewModel = BoardViewModel.shared

        guard let card = viewModel.card(for: cardId) else { return }

        let columnLower = columnName.lowercased()
        guard
            let targetColumn = viewModel.board.columns.first(where: {
                $0.name.lowercased() == columnLower
            })
        else { return }

        viewModel.moveCard(card, to: targetColumn)
    }
}

@main
struct TermQApp: App {
    @StateObject private var urlHandler = URLHandler.shared
    @FocusedValue(\.terminalActions) private var terminalActions
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(urlHandler)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Help menu
            CommandGroup(replacing: .help) {
                Button("TermQ Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Quick New Terminal") {
                    terminalActions?.quickNewTerminal()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Terminal...") {
                    terminalActions?.newTerminalWithDialog()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Column") {
                    terminalActions?.newColumn()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Back to Board") {
                    terminalActions?.goBack()
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                Button("Toggle Favourite") {
                    terminalActions?.toggleFavourite()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Next Tab") {
                    terminalActions?.nextTab()
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Previous Tab") {
                    terminalActions?.previousTab()
                }
                .keyboardShortcut("[", modifiers: .command)

                Divider()

                Button("Open in Terminal.app") {
                    terminalActions?.openInTerminalApp()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Close Tab") {
                    terminalActions?.closeTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Delete Terminal") {
                    terminalActions?.deleteTerminal()
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button("Toggle Zoom Mode") {
                    terminalActions?.toggleZoom()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button("Find...") {
                    terminalActions?.toggleSearch()
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Export Session...") {
                    terminalActions?.exportSession()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Command Palette...") {
                    terminalActions?.showCommandPalette()
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Show Bin") {
                    terminalActions?.showBin()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }

            #if DEBUG
            CommandMenu("Debug") {
                Button("Copy from Production Config") {
                    copyProductionConfig()
                }

                Divider()

                Button("Open Debug Data Folder") {
                    openDebugDataFolder()
                }

                Button("Open Production Data Folder") {
                    openProductionDataFolder()
                }
            }
            #endif
        }
        .handlesExternalEvents(matching: ["termq"])

        Settings {
            SettingsView()
        }

        Window("TermQ Help", id: "help") {
            HelpView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    init() {
        // Register URL handler
        NSAppleEventManager.shared().setEventHandler(
            URLEventHandler.shared,
            andSelector: #selector(URLEventHandler.handleURL(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
}

/// Handles Apple Events for URL schemes
class URLEventHandler: NSObject {
    static let shared = URLEventHandler()

    @objc func handleURL(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else { return }

        Task { @MainActor in
            URLHandler.shared.handleURL(url)
        }
    }
}

// MARK: - Debug Menu Helpers

#if DEBUG
/// Copy production config to debug data folder
private func copyProductionConfig() {
    let fileManager = FileManager.default
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

    let productionFolder = appSupport.appendingPathComponent("TermQ")
    let debugFolder = appSupport.appendingPathComponent("TermQ-Debug")
    let productionBoard = productionFolder.appendingPathComponent("board.json")
    let debugBoard = debugFolder.appendingPathComponent("board.json")

    // Ensure debug folder exists
    try? fileManager.createDirectory(at: debugFolder, withIntermediateDirectories: true)

    // Check if production config exists
    guard fileManager.fileExists(atPath: productionBoard.path) else {
        let alert = NSAlert()
        alert.messageText = "No Production Config"
        alert.informativeText = "Could not find board.json in the production folder."
        alert.alertStyle = .warning
        alert.runModal()
        return
    }

    // Confirm overwrite if debug config exists
    if fileManager.fileExists(atPath: debugBoard.path) {
        let alert = NSAlert()
        alert.messageText = "Replace Debug Config?"
        alert.informativeText = "This will replace your current debug board.json with the production version."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() != .alertFirstButtonReturn {
            return
        }

        try? fileManager.removeItem(at: debugBoard)
    }

    do {
        try fileManager.copyItem(at: productionBoard, to: debugBoard)

        let alert = NSAlert()
        alert.messageText = "Config Copied"
        alert.informativeText = "Production config has been copied to the debug folder. Restart TermQ to load it."
        alert.alertStyle = .informational
        alert.runModal()
    } catch {
        let alert = NSAlert()
        alert.messageText = "Copy Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
}

/// Open the debug data folder in Finder
private func openDebugDataFolder() {
    let fileManager = FileManager.default
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let debugFolder = appSupport.appendingPathComponent("TermQ-Debug")

    // Ensure folder exists
    try? fileManager.createDirectory(at: debugFolder, withIntermediateDirectories: true)

    NSWorkspace.shared.open(debugFolder)
}

/// Open the production data folder in Finder
private func openProductionDataFolder() {
    let fileManager = FileManager.default
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let productionFolder = appSupport.appendingPathComponent("TermQ")

    // Ensure folder exists
    try? fileManager.createDirectory(at: productionFolder, withIntermediateDirectories: true)

    NSWorkspace.shared.open(productionFolder)
}
#endif
