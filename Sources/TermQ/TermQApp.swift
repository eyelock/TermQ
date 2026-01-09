import AppKit
import SwiftUI
import TermQCore

/// Shared state for handling URL-based terminal creation
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
        guard url.scheme == "termq",
            url.host == "open"
        else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

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
}

@main
struct TermQApp: App {
    @StateObject private var urlHandler = URLHandler.shared
    @FocusedValue(\.terminalActions) private var terminalActions

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(urlHandler)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
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

                Button("Toggle Pin") {
                    terminalActions?.togglePin()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Next Pinned Terminal") {
                    terminalActions?.nextPinnedTerminal()
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Previous Pinned Terminal") {
                    terminalActions?.previousPinnedTerminal()
                }
                .keyboardShortcut("[", modifiers: .command)
            }
        }
        .handlesExternalEvents(matching: ["termq"])

        Settings {
            SettingsView()
        }
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
