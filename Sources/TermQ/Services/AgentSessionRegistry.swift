import Foundation

/// Lazily-allocated registry of `AgentSessionController` instances, keyed
/// by card id. Ensures the Inspector view and any other UI surface looking
/// at the same agent card observes the same controller (and therefore the
/// same event stream and status).
@MainActor
public final class AgentSessionRegistry: ObservableObject {
    public static let shared = AgentSessionRegistry()

    private var controllers: [UUID: AgentSessionController] = [:]

    public init() {}

    /// Return the controller for the given card id, creating one on first
    /// access. The default controller resolves its card via
    /// `BoardViewModel.shared` and persists trajectories to the standard
    /// app-support location. Tests construct controllers directly to
    /// inject `cardLookup` and `writerFactory`.
    public func controller(for cardId: UUID) -> AgentSessionController {
        if let existing = controllers[cardId] { return existing }
        let new = AgentSessionController(
            cardId: cardId,
            writerFactory: AgentSessionController.defaultWriterFactory
        )
        controllers[cardId] = new
        return new
    }

    /// Drop the controller for a card. Caller is responsible for calling
    /// `stop()` first if a process is still running.
    public func remove(cardId: UUID) {
        controllers.removeValue(forKey: cardId)
    }
}
