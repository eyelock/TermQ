import Foundation
import TermQCore
import TermQShared

// MARK: - Headless Mode Support

extension BoardViewModel {
    /// Handle cards created via headless MCP that need tmux sessions
    /// Called on GUI startup to create background sessions for cards
    func handleHeadlessCards() async {
        let tmuxManager = TmuxManager.shared

        // Ensure tmux detection has completed
        await tmuxManager.detectTmux()

        guard tmuxManager.isAvailable else {
            // If tmux is not available, clear needsTmuxSession flags
            // Users won't be able to use these cards until tmux is installed
            for card in board.cards where card.needsTmuxSession {
                try? await clearNeedsTmuxSession(for: card)
            }
            return
        }

        // Check if tmux is enabled globally (default true)
        let tmuxEnabled = UserDefaults.standard.object(forKey: "tmuxEnabled") as? Bool ?? true
        guard tmuxEnabled else {
            // If tmux is disabled, don't create sessions
            return
        }

        // Find cards that need tmux sessions
        let needsSessions = board.cards.filter { $0.needsTmuxSession && !$0.isDeleted }

        for card in needsSessions {
            let sessionName = tmuxManager.sessionName(for: card.id)

            // Check if session already exists (user might have created manually)
            let sessionExists = await tmuxManager.sessionExists(name: sessionName)

            if !sessionExists {
                // Create new tmux session
                do {
                    // Get current environment with TermQ-specific variables
                    var env = ProcessInfo.processInfo.environment

                    // Add TermQ-specific environment variables
                    env["TERMQ_TERMINAL_ID"] = card.id.uuidString
                    env["TERMQ_BACKEND"] = TerminalBackend.tmuxAttach.rawValue

                    // Add tag environment variables
                    for tag in card.tags {
                        let sanitizedKey = sanitizeEnvVarName(tag.key)
                        if !sanitizedKey.isEmpty {
                            env["TERMQ_TERMINAL_TAG_\(sanitizedKey)"] = tag.value
                        }
                    }

                    // Create the session (detached)
                    try await tmuxManager.createSession(
                        name: sessionName,
                        workingDirectory: card.workingDirectory,
                        shell: card.shellPath,
                        environment: env
                    )

                    // Configure session for TermQ
                    try await tmuxManager.configureSession(name: sessionName)

                    // Sync card metadata to the session
                    let metadata = TerminalCardMetadata.from(card)
                    await tmuxManager.syncMetadataToSession(sessionName: sessionName, card: metadata)

                } catch {
                    print("BoardViewModel: Failed to create tmux session for \(card.title): \(error)")
                    continue
                }
            }

            // Clear the needsTmuxSession flag
            try? await clearNeedsTmuxSession(for: card)
        }
    }

    /// Clear the needsTmuxSession flag for a card
    private func clearNeedsTmuxSession(for card: TerminalCard) async throws {
        // Simply clear the flag and save - no need to use BoardWriter
        // The card is already in the board model
        card.needsTmuxSession = false
        save()  // save() now logs errors internally
    }

    /// Sanitize environment variable name (alphanumeric + underscore only)
    private func sanitizeEnvVarName(_ name: String) -> String {
        name.uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
