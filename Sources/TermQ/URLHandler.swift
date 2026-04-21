import AppKit
import Combine
import Sparkle
import SwiftUI
import TermQCore
import TermQShared

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
        let tags: [TermQCore.Tag]
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
        let tags: [TermQCore.Tag] =
            queryItems
            .filter { $0.name == "tag" }
            .compactMap { item -> TermQCore.Tag? in
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
        let newTags: [TermQCore.Tag] =
            queryItems
            .filter { $0.name == "tag" }
            .compactMap { item -> TermQCore.Tag? in
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
