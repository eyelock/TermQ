import AppKit
import Combine
import Sparkle
import SwiftUI
import TermQCore
import TermQShared

@main
struct TermQApp: App {
    @NSApplicationDelegateAdaptor(TermQAppDelegate.self) var appDelegate
    @StateObject private var urlHandler = URLHandler.shared
    @FocusedValue(\.terminalActions) private var terminalActions
    @Environment(\.openWindow) private var openWindow

    // Restore offer state - using IdentifiableURL wrapper for sheet(item:)
    @State private var backupToRestore: IdentifiableURL?

    var body: some Scene {
        Window("TermQ", id: "main") {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(urlHandler)
                .onAppear {
                    // Validate AppProfile matches actual bundle (debug builds only)
                    AppProfileValidator.validateAtStartup()
                    checkForOrphanedBackup()
                    let count = NSApplication.shared.windows.count
                    TermQLogger.window.notice("Window onAppear: \(count) window(s)")
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
            // Check for Updates in App menu (after About) — hidden in debug builds
            #if !TERMQ_DEBUG_BUILD
                CommandGroup(after: .appInfo) {
                    Button(Strings.Menu.checkForUpdates) {
                        appDelegate.updaterController.checkForUpdates(nil)
                    }
                }
            #endif

            // Window commands - enable Cmd+W to close window (hides it, preserving session)
            CommandGroup(after: .windowArrangement) {
                Button(Strings.Common.closeWindow) {
                    // Close the current window (won't quit app due to applicationShouldTerminateAfterLastWindowClosed)
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // Utilities menu — developer tools available in all builds
            CommandMenu(Strings.Menu.utilities) {
                Button(Strings.Menu.utilitiesLogging) {
                    DiagnosticsWindowController.shared.show()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
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
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(terminalActions == nil)

                Button("Delete Terminal") {
                    terminalActions?.deleteTerminal()
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button("Toggle Zoom Mode") {
                    terminalActions?.toggleZoom()
                }
                .keyboardShortcut("z", modifiers: [.command, .option])

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

                Divider()

                Button(Strings.Sidebar.menuToggle) {
                    terminalActions?.toggleSidebar()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
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
        Settings {
            SettingsView()
                .environmentObject(appDelegate.updaterViewModel)
        }

        Window("TermQ Help", id: "help") {
            HelpView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    init() {
        UserDefaults.standard.register(defaults: [
            "protectedBranches": "main,master,develop"
        ])
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
    /// Shared instance - accessed from app delegate
    static var shared: UpdaterViewModel? {
        guard let appDelegate = NSApp.delegate as? TermQAppDelegate else {
            return nil
        }
        return appDelegate.updaterViewModel
    }

    private let provider: any UpdaterProviding
    private var cancellables = Set<AnyCancellable>()

    /// Whether automatic update checks are enabled (defaults to true)
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            provider.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Whether the user can check for updates (e.g., not currently checking)
    @Published var canCheckForUpdates: Bool = true

    /// Whether to include beta releases in update checks
    /// The actual feed URL is determined by SparkleUpdaterDelegate based on this preference
    @Published var includeBetaReleases: Bool {
        didSet {
            UserDefaults.standard.set(includeBetaReleases, forKey: "SUIncludeBetaReleases")
        }
    }

    convenience init(updater: SPUUpdater, controller: SPUStandardUpdaterController? = nil) {
        self.init(provider: LiveUpdaterProvider(updater: updater, controller: controller))
    }

    init(provider: any UpdaterProviding) {
        self.provider = provider
        // Default to true for automatic checks if not previously set
        let hasExistingPreference = UserDefaults.standard.object(forKey: "SUAutomaticallyChecksForUpdates") != nil
        if !hasExistingPreference {
            provider.automaticallyChecksForUpdates = true
        }
        self.automaticallyChecksForUpdates = provider.automaticallyChecksForUpdates
        self.includeBetaReleases = UserDefaults.standard.bool(forKey: "SUIncludeBetaReleases")
        self.canCheckForUpdates = provider.canCheckForUpdates

        // Observe changes to canCheckForUpdates
        provider.canCheckForUpdatesPublisher
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)
    }

    /// Manually check for updates
    func checkForUpdates() {
        provider.checkForUpdates()
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
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {

            fatalError("Unable to access Application Support directory")

        }

        let productionFolder = appSupport.appendingPathComponent("TermQ")
        let debugFolder = appSupport.appendingPathComponent("TermQ-Debug")
        let productionBoard = productionFolder.appendingPathComponent("board.json")
        let debugBoard = debugFolder.appendingPathComponent("board.json")

        // Ensure debug folder exists
        try? fileManager.createDirectory(at: debugFolder, withIntermediateDirectories: true)

        // Check if production config exists
        guard fileManager.fileExists(atPath: productionBoard.path) else {
            AlertBuilder.show(
                title: "No Production Config",
                message: "Could not find board.json in the production folder.",
                style: .warning)
            return
        }

        // Confirm overwrite if debug config exists
        if fileManager.fileExists(atPath: debugBoard.path) {
            guard
                AlertBuilder.confirm(
                    title: "Replace Debug Config?",
                    message: "This will replace your current debug board.json with the production version.",
                    confirmButton: "Replace")
            else { return }

            try? fileManager.removeItem(at: debugBoard)
        }

        do {
            try fileManager.copyItem(at: productionBoard, to: debugBoard)
            AlertBuilder.show(
                title: "Config Copied",
                message: "Production config has been copied to the debug folder. Restart TermQ to load it.",
                style: .informational)
        } catch {
            AlertBuilder.show(
                title: "Copy Failed",
                message: error.localizedDescription,
                style: .critical)
        }
    }

    /// Open the debug data folder in Finder
    @MainActor private func openDebugDataFolder() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {

            fatalError("Unable to access Application Support directory")

        }
        let debugFolder = appSupport.appendingPathComponent("TermQ-Debug")

        // Ensure folder exists
        try? fileManager.createDirectory(at: debugFolder, withIntermediateDirectories: true)

        NSWorkspace.shared.open(debugFolder)
    }

    /// Open the production data folder in Finder
    @MainActor private func openProductionDataFolder() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {

            fatalError("Unable to access Application Support directory")

        }
        let productionFolder = appSupport.appendingPathComponent("TermQ")

        // Ensure folder exists
        try? fileManager.createDirectory(at: productionFolder, withIntermediateDirectories: true)

        NSWorkspace.shared.open(productionFolder)
    }
#endif
