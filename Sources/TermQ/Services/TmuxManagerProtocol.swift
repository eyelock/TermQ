import Foundation
import TermQCore

/// Protocol covering the `TmuxManager` methods called from `TerminalSessionManager`.
///
/// Conforming types must be `@MainActor` isolated, matching `TmuxManager`.
/// Introduce a test double that conforms to this protocol to exercise
/// `TerminalSessionManager` without spawning real tmux processes.
@MainActor
protocol TmuxManagerProtocol: AnyObject {

    // MARK: - Availability

    /// Whether tmux is available on the system.
    var isAvailable: Bool { get }

    /// Path to the tmux executable, or `nil` if not found.
    var tmuxPath: String? { get }

    // MARK: - Session Naming

    /// Generate the tmux session name for a terminal card.
    func sessionName(for cardId: UUID) -> String

    // MARK: - Session Lifecycle

    /// Kill a tmux session by name.
    func killSession(name: String) async throws

    // MARK: - Metadata

    /// Write all terminal-card metadata fields into the tmux session environment.
    func syncMetadataToSession(sessionName: String, card: TerminalCardMetadata) async

    /// Update individual metadata fields in the tmux session environment.
    func updateSessionMetadata(  // swiftlint:disable:this function_parameter_count
        sessionName: String,
        title: String?,
        description: String?,
        tags: [Tag]?,
        llmPrompt: String?,
        llmNextAction: String?,
        badge: String?,
        columnId: UUID?,
        isFavourite: Bool?
    ) async
}
