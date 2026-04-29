import Foundation
import TermQCore

/// Per-card observable controller for an agent loop session.
///
/// Wraps an `AgentLoopProcess` and exposes `@Published` event/status
/// streams suitable for SwiftUI binding. One controller per agent card,
/// vended by `AgentSessionRegistry`.
///
/// The controller is MainActor-isolated so SwiftUI can observe its state
/// directly. The underlying `AgentLoopProcess` is an actor; this class
/// bridges between actor isolation and the MainActor by consuming the
/// process's NDJSON stream into a `@Published` events array.
@MainActor
public final class AgentSessionController: ObservableObject {
    public let cardId: UUID

    @Published public private(set) var events: [TrajectoryEvent] = []
    @Published public private(set) var status: AgentLoopProcessStatus = .notStarted

    /// Resolves a `TerminalCard` for the controller's `cardId`. Defaults to
    /// `BoardViewModel.shared.card(for:)`; tests inject their own.
    public var cardLookup: () -> TerminalCard?

    /// Builds a TrajectoryWriter for a session id when start() runs. Tests
    /// inject a writer pointed at a temp directory. When `nil`, no
    /// persistence happens — useful for tests that don't care about disk.
    public var writerFactory: ((UUID) -> TrajectoryWriter?)?

    private var process: AgentLoopProcess?
    private var consumeTask: Task<Void, Never>?
    private var writer: TrajectoryWriter?

    public init(
        cardId: UUID,
        cardLookup: (() -> TerminalCard?)? = nil,
        writerFactory: ((UUID) -> TrajectoryWriter?)? = nil
    ) {
        self.cardId = cardId
        self.cardLookup = cardLookup ?? { BoardViewModel.shared.card(for: cardId) }
        self.writerFactory = writerFactory
    }

    /// Default writer factory used by `AgentSessionRegistry`: opens
    /// `<appSupport>/TermQ[-Debug]/agent-sessions/<sessionId>/trajectory.jsonl`
    /// in append mode. Returns `nil` if the writer fails to open (silent —
    /// in-memory events remain the source of truth).
    public static func defaultWriterFactory(_ sessionId: UUID) -> TrajectoryWriter? {
        try? TrajectoryWriter(sessionId: sessionId)
    }

    /// Spawn `/bin/sh -c "<command>"` and stream its NDJSON output into
    /// `events`. No-op if a process is already running. Throws if the
    /// subprocess fails to launch.
    public func start(command: String) async throws {
        guard process == nil else { return }
        let p = AgentLoopProcess()
        let stream = try await p.start(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command]
        )
        process = p
        status = await p.status
        events.removeAll()
        updateCardStatus(.running)

        // Open per-session trajectory file. Falls back to nil if the
        // factory returns nil or no card/session can be resolved — events
        // still flow in-memory.
        if let sessionId = cardLookup()?.agentConfig?.sessionId {
            writer = writerFactory?(sessionId)
        }

        consumeTask = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
                self?.writer?.append(event)
                self?.handleEventForCardStatus(event)
            }
            // Stream finished — pull the final status off the actor.
            let finalStatus = await p.status
            self?.status = finalStatus
            self?.process = nil
            self?.writer?.close()
            self?.writer = nil
            self?.handleStreamEnd(finalStatus: finalStatus)
        }
    }

    /// Send SIGTERM to the running subprocess, if any.
    public func stop() async {
        await process?.stop()
    }

    /// Reset the controller for a fresh run. Cancels any in-flight stream
    /// consumer; does not terminate the underlying subprocess (call
    /// `stop()` first if needed).
    public func reset() {
        consumeTask?.cancel()
        consumeTask = nil
        events.removeAll()
        status = .notStarted
        process = nil
    }

    // MARK: - Card status writeback

    /// Decide whether an incoming event implies a new card status, and
    /// apply it. Most events (turn_start, sensor_result, plan, etc.) leave
    /// the status unchanged at `.running`; only terminal-shaped events
    /// flip the card.
    private func handleEventForCardStatus(_ event: TrajectoryEvent) {
        switch event.decoded() {
        case .converged:
            updateCardStatus(.converged)
        case .stuckDetected:
            updateCardStatus(.stuck)
        case .budgetExceeded:
            updateCardStatus(.errored)
        default:
            break
        }
    }

    /// Called once the subprocess has fully exited and the stream has
    /// drained. If a terminal-state event already flipped the card, leave
    /// that status alone — otherwise infer from the exit code.
    private func handleStreamEnd(finalStatus: AgentLoopProcessStatus) {
        guard let card = cardLookup(), let config = card.agentConfig else { return }
        switch config.status {
        case .converged, .stuck, .errored:
            // Terminal already; don't downgrade.
            return
        default:
            break
        }
        if case .exited(let code) = finalStatus {
            updateCardStatus(code == 0 ? .converged : .errored)
        }
    }

    private func updateCardStatus(_ newStatus: AgentStatus) {
        guard let card = cardLookup(), var config = card.agentConfig else { return }
        guard config.status != newStatus else { return }
        config.status = newStatus
        card.agentConfig = config
    }
}
