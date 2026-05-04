import AppKit
import Combine
import Sparkle
import SwiftUI
import TermQCore
import TermQShared

@MainActor
class URLHandler: ObservableObject {
    static let shared = URLHandler()

    private let boardViewModel: any BoardViewModelProtocol

    init(boardViewModel: any BoardViewModelProtocol = BoardViewModel.shared) {
        self.boardViewModel = boardViewModel
    }

    @Published var pendingTerminal: PendingTerminal?

    /// Whether to require user confirmation when external processes modify LLM context.
    /// Routes through `SettingsStore` so a Settings-panel toggle takes effect immediately.
    var confirmExternalLLMModifications: Bool {
        get { SettingsStore.shared.confirmExternalLLMModifications }
        set { SettingsStore.shared.confirmExternalLLMModifications = newValue }
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
        let qi = QueryItemExtractor(queryItems)
        let path = qi.string("path", default: NSHomeDirectory())
        let name = qi.optionalString("name")
        let description = qi.optionalString("description")
        let column = qi.optionalString("column")
        let llmPrompt = qi.optionalString("llmPrompt")
        let llmNextAction = qi.optionalString("llmNextAction")
        let initCommand = qi.optionalString("initCommand")
        let cardId = qi.uuid("id")

        // Parse tags — multiple items share the "tag" name, each with "key=value" format
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
        let qi = QueryItemExtractor(queryItems)
        guard let cardId = qi.uuid("id") else { return }

        let viewModel = boardViewModel

        guard let card = viewModel.card(for: cardId) else { return }

        let llmPromptChange = qi.optionalString("llmPrompt")
        let llmNextActionChange = qi.optionalString("llmNextAction")

        if confirmExternalLLMModifications && (llmPromptChange != nil || llmNextActionChange != nil) {
            let approved = confirmLLMModification(
                terminalName: card.title,
                llmPromptChange: llmPromptChange,
                llmNextActionChange: llmNextActionChange
            )
            if !approved { return }
        }

        if let name = qi.optionalString("name") { card.title = name }
        if let description = qi.optionalString("description") { card.description = description }
        if let badge = qi.optionalString("badge") { card.badge = badge }
        if let llmPrompt = llmPromptChange { card.llmPrompt = llmPrompt }
        if let llmNextAction = llmNextActionChange { card.llmNextAction = llmNextAction }
        if let initCommand = qi.optionalString("initCommand") { card.initCommand = initCommand }

        if let shouldBeFavourite = qi.optionalBool("favourite") {
            if card.isFavourite != shouldBeFavourite {
                viewModel.toggleFavourite(card)
            }
        }

        let shouldReplaceTags = qi.bool("replaceTags")

        // Parse tags — multiple items share the "tag" name, each with "key=value" format
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
            card.tags = []
        }

        if let columnName = qi.optionalString("column") {
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
        let qi = QueryItemExtractor(queryItems)
        guard let cardId = qi.uuid("id"),
            let columnName = qi.optionalString("column")
        else { return }

        let viewModel = boardViewModel
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
        let qi = QueryItemExtractor(queryItems)
        guard let cardId = qi.uuid("id") else { return }

        let viewModel = boardViewModel
        guard let card = viewModel.card(for: cardId) else { return }

        viewModel.selectCard(card)
    }

    private func handleDelete(queryItems: [URLQueryItem]) {
        let qi = QueryItemExtractor(queryItems)
        guard let cardId = qi.uuid("id") else { return }

        let viewModel = boardViewModel
        guard let card = viewModel.card(for: cardId) else { return }

        if qi.bool("permanent") {
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
