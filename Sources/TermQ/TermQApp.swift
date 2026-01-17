import AppKit
import Combine
import Sparkle
import SwiftUI
import TermQCore

/// Shared state for handling URL-based terminal creation and modification
@MainActor
class URLHandler: ObservableObject {
    static let shared = URLHandler()

    @Published var pendingTerminal: PendingTerminal?

    /// User preference key for requiring confirmation on external LLM context modifications
    private static let confirmExternalLLMModificationsKey = "confirmExternalLLMModifications"

    /// Whether to require user confirmation when external processes modify LLM context
    var confirmExternalLLMModifications: Bool {
        get {
            // Default to true for security
            if UserDefaults.standard.object(forKey: Self.confirmExternalLLMModificationsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.confirmExternalLLMModificationsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.confirmExternalLLMModificationsKey)
        }
    }

    struct PendingTerminal: Identifiable {
        /// Internal ID for SwiftUI identity (not the card ID)
        let id = UUID()
        /// Optional pre-generated card ID (from CLI/MCP)
        let cardId: UUID?
        let path: String
        let name: String?
        let description: String?
        let column: String?
        let tags: [Tag]
        let llmPrompt: String?
        let llmNextAction: String?
        let initCommand: String?
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
        case "focus":
            handleFocus(queryItems: queryItems)
        case "delete":
            handleDelete(queryItems: queryItems)
        default:
            break
        }
    }

    /// Show confirmation dialog for external LLM context modifications
    /// Returns true if user approves the modification
    private func confirmLLMModification(
        terminalName: String,
        llmPromptChange: String?,
        llmNextActionChange: String?
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = Strings.Security.externalModificationTitle
        alert.alertStyle = .warning

        var changes: [String] = []
        if let prompt = llmPromptChange {
            let preview = String(prompt.prefix(100))
            changes.append("• LLM Prompt: \(preview)\(prompt.count > 100 ? "..." : "")")
        }
        if let action = llmNextActionChange {
            let preview = String(action.prefix(100))
            changes.append("• LLM Next Action: \(preview)\(action.count > 100 ? "..." : "")")
        }

        alert.informativeText = String(
            format: Strings.Security.externalModificationMessage,
            terminalName,
            changes.joined(separator: "\n")
        )

        alert.addButton(withTitle: Strings.Security.allow)
        alert.addButton(withTitle: Strings.Security.deny)
        alert.addButton(withTitle: Strings.Security.allowAndDisablePrompt)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return true
        case .alertThirdButtonReturn:
            // Allow and disable future prompts
            confirmExternalLLMModifications = false
            return true
        default:
            return false
        }
    }

    private func handleOpen(queryItems: [URLQueryItem]) {
        let path = queryItems.first { $0.name == "path" }?.value ?? NSHomeDirectory()
        let name = queryItems.first { $0.name == "name" }?.value
        let description = queryItems.first { $0.name == "description" }?.value
        let column = queryItems.first { $0.name == "column" }?.value
        let llmPrompt = queryItems.first { $0.name == "llmPrompt" }?.value
        let llmNextAction = queryItems.first { $0.name == "llmNextAction" }?.value
        let initCommand = queryItems.first { $0.name == "initCommand" }?.value

        // Parse optional card ID (for MCP/CLI to track created terminals)
        let cardId: UUID?
        if let idString = queryItems.first(where: { $0.name == "id" })?.value {
            cardId = UUID(uuidString: idString)
        } else {
            cardId = nil
        }

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
            cardId: cardId,
            path: path,
            name: name,
            description: description,
            column: column,
            tags: tags,
            llmPrompt: llmPrompt,
            llmNextAction: llmNextAction,
            initCommand: initCommand
        )
    }

    private func handleUpdate(queryItems: [URLQueryItem]) {
        guard let idString = queryItems.first(where: { $0.name == "id" })?.value,
            let cardId = UUID(uuidString: idString)
        else { return }

        let viewModel = BoardViewModel.shared

        guard let card = viewModel.card(for: cardId) else { return }

        // Check for sensitive LLM context modifications that require user confirmation
        let llmPromptChange = queryItems.first(where: { $0.name == "llmPrompt" })?.value
        let llmNextActionChange = queryItems.first(where: { $0.name == "llmNextAction" })?.value

        // If LLM fields are being modified and confirmation is enabled, ask user
        if confirmExternalLLMModifications && (llmPromptChange != nil || llmNextActionChange != nil) {
            let approved = confirmLLMModification(
                terminalName: card.title,
                llmPromptChange: llmPromptChange,
                llmNextActionChange: llmNextActionChange
            )
            if !approved {
                return  // User denied the modification
            }
        }

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

        // Update LLM prompt (already confirmed if needed)
        if let llmPrompt = llmPromptChange {
            card.llmPrompt = llmPrompt
        }

        // Update LLM next action (already confirmed if needed)
        if let llmNextAction = llmNextActionChange {
            card.llmNextAction = llmNextAction
        }

        // Update init command
        if let initCommand = queryItems.first(where: { $0.name == "initCommand" })?.value {
            card.initCommand = initCommand
        }

        // Update favourite status
        if let favouriteStr = queryItems.first(where: { $0.name == "favourite" })?.value {
            let shouldBeFavourite = favouriteStr.lowercased() == "true"
            if card.isFavourite != shouldBeFavourite {
                viewModel.toggleFavourite(card)
            }
        }

        // Check if we should replace tags or add to existing
        let shouldReplaceTags =
            queryItems.first(where: { $0.name == "replaceTags" })?.value?.lowercased() == "true"

        // Parse tags
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
            if shouldReplaceTags {
                card.tags = newTags
            } else {
                card.tags.append(contentsOf: newTags)
            }
        } else if shouldReplaceTags {
            // replaceTags with no tags means clear all tags
            card.tags = []
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

    private func handleFocus(queryItems: [URLQueryItem]) {
        guard let idString = queryItems.first(where: { $0.name == "id" })?.value,
            let cardId = UUID(uuidString: idString)
        else { return }

        let viewModel = BoardViewModel.shared

        guard let card = viewModel.card(for: cardId) else { return }

        viewModel.selectCard(card)
    }

    private func handleDelete(queryItems: [URLQueryItem]) {
        guard let idString = queryItems.first(where: { $0.name == "id" })?.value,
            let cardId = UUID(uuidString: idString)
        else { return }

        let viewModel = BoardViewModel.shared

        guard let card = viewModel.card(for: cardId) else { return }

        // Check for permanent deletion flag
        let permanent =
            queryItems.first(where: { $0.name == "permanent" })?.value?.lowercased() == "true"

        if permanent {
            viewModel.permanentlyDeleteCard(card)
        } else {
            viewModel.deleteCard(card)
        }
    }
}

/// Sparkle updater delegate to provide dynamic feed URL based on user preferences
final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// Returns the appcast feed URL based on whether beta releases are enabled
    func feedURLString(for updater: SPUUpdater) -> String? {
        let includeBeta = UserDefaults.standard.bool(forKey: "SUIncludeBetaReleases")
        let feedFile = includeBeta ? "appcast-beta.xml" : "appcast.xml"
        return "https://eyelock.github.io/TermQ/\(feedFile)"
    }
}

/// App delegate to handle quit confirmation, auto-updates, and enforce single window
@MainActor
class TermQAppDelegate: NSObject, NSApplicationDelegate {
    /// Sparkle updater delegate for dynamic feed URL
    private let sparkleDelegate = SparkleUpdaterDelegate()

    /// Sparkle updater controller for automatic updates
    let updaterController: SPUStandardUpdaterController

    /// Reference to the main window (first window created)
    private var mainWindow: NSWindow?

    override init() {
        // Initialize Sparkle updater with delegate for dynamic feed URL
        // SUPublicEDKey is read from Info.plist
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: sparkleDelegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Store reference to the main window
        mainWindow = NSApplication.shared.mainWindow

        // If no main window yet, wait for it
        if mainWindow == nil {
            DispatchQueue.main.async { [weak self] in
                self?.mainWindow = NSApplication.shared.mainWindow
            }
        }
    }

    /// Prevent creating new windows when user tries to open the app again
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            // Bring existing window to front
            mainWindow?.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }

    /// Keep app running even if last window closes (user can reopen from Dock)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check for running direct (non-tmux) sessions
        let sessionManager = TerminalSessionManager.shared
        let activeCards = sessionManager.activeSessionCardIds()

        // Count direct and tmux sessions separately
        let directSessionCount = activeCards.filter { cardId in
            sessionManager.getBackend(for: cardId) == .direct
        }.count

        let tmuxSessionCount = activeCards.filter { cardId in
            sessionManager.getBackend(for: cardId) == .tmux
        }.count

        if directSessionCount > 0 {
            // Show confirmation alert
            let alert = NSAlert()
            alert.messageText = Strings.Alert.quitWithDirectSessions

            // Only mention tmux persistence if there are tmux sessions
            if tmuxSessionCount > 0 {
                alert.informativeText = Strings.Alert.quitWithDirectSessionsMessageWithTmux(directSessionCount)
            } else {
                alert.informativeText = Strings.Alert.quitWithDirectSessionsMessage(directSessionCount)
            }

            alert.addButton(withTitle: Strings.Common.quit)
            alert.addButton(withTitle: Strings.Common.cancel)
            alert.alertStyle = .warning

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }

        // Clean up all sessions before quitting
        sessionManager.removeAllSessions()
        return .terminateNow
    }
}

@main
struct TermQApp: App {
    @NSApplicationDelegateAdaptor(TermQAppDelegate.self) var appDelegate
    @StateObject private var urlHandler = URLHandler.shared
    @FocusedValue(\.terminalActions) private var terminalActions
    @Environment(\.openWindow) private var openWindow

    // Restore offer state - using IdentifiableURL wrapper for sheet(item:)
    @State private var backupToRestore: IdentifiableURL?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(urlHandler)
                .onAppear {
                    checkForOrphanedBackup()
                }
                .sheet(item: $backupToRestore) { item in
                    RestoreOfferView(
                        backupURL: item.url,
                        onRestore: { backupToRestore = nil },
                        onSkip: { backupToRestore = nil }
                    )
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Check for Updates in App menu (after About)
            CommandGroup(after: .appInfo) {
                Button(Strings.Menu.checkForUpdates) {
                    appDelegate.updaterController.checkForUpdates(nil)
                }
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button(Strings.Menu.help) {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            // Replace entire "New" section to remove default "New Window" command
            // TermQ only supports single window - multiple windows cause issues
            // because terminal NSViews can only have one parent
            CommandGroup(replacing: .newItem) {
                Button(Strings.Menu.newTerminalQuick) {
                    terminalActions?.quickNewTerminal()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button(Strings.Menu.newTerminal) {
                    terminalActions?.newTerminalWithDialog()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(Strings.Menu.newColumn) {
                    terminalActions?.newColumn()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button(Strings.Menu.back) {
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

    /// Check if we should offer to restore from backup on startup
    private func checkForOrphanedBackup() {
        if let backupURL = BackupManager.checkAndOfferRestore() {
            backupToRestore = IdentifiableURL(url: backupURL)
        }
    }
}

/// Wrapper to make URL identifiable for sheet(item:) usage
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Sparkle Updater Access

/// Observable wrapper for Sparkle's updater to use in SwiftUI
@MainActor
final class UpdaterViewModel: ObservableObject {
    /// Shared instance - initialized lazily when first accessed
    static var shared: UpdaterViewModel? {
        guard let appDelegate = NSApp.delegate as? TermQAppDelegate else {
            return nil
        }
        return UpdaterViewModel(updater: appDelegate.updaterController.updater)
    }

    private let updater: SPUUpdater
    private var cancellables = Set<AnyCancellable>()

    /// Whether automatic update checks are enabled (defaults to true)
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Whether the user can check for updates (e.g., not currently checking)
    @Published var canCheckForUpdates: Bool = false

    /// Whether to include beta releases in update checks
    /// The actual feed URL is determined by SparkleUpdaterDelegate based on this preference
    @Published var includeBetaReleases: Bool {
        didSet {
            UserDefaults.standard.set(includeBetaReleases, forKey: "SUIncludeBetaReleases")
        }
    }

    init(updater: SPUUpdater) {
        self.updater = updater
        // Default to true for automatic checks if not previously set
        let hasExistingPreference = UserDefaults.standard.object(forKey: "SUAutomaticallyChecksForUpdates") != nil
        if !hasExistingPreference {
            updater.automaticallyChecksForUpdates = true
        }
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.includeBetaReleases = UserDefaults.standard.bool(forKey: "SUIncludeBetaReleases")
        self.canCheckForUpdates = updater.canCheckForUpdates

        // Observe changes to canCheckForUpdates
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)
    }

    /// Manually check for updates
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

/// Handles Apple Events for URL schemes
@MainActor
final class URLEventHandler: NSObject, @unchecked Sendable {
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
    @MainActor private func copyProductionConfig() {
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
    @MainActor private func openDebugDataFolder() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let debugFolder = appSupport.appendingPathComponent("TermQ-Debug")

        // Ensure folder exists
        try? fileManager.createDirectory(at: debugFolder, withIntermediateDirectories: true)

        NSWorkspace.shared.open(debugFolder)
    }

    /// Open the production data folder in Finder
    @MainActor private func openProductionDataFolder() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let productionFolder = appSupport.appendingPathComponent("TermQ")

        // Ensure folder exists
        try? fileManager.createDirectory(at: productionFolder, withIntermediateDirectories: true)

        NSWorkspace.shared.open(productionFolder)
    }
#endif
