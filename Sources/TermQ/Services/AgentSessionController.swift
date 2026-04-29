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

    /// Override the base directory used when reading a persisted trajectory
    /// back via `loadPersistedEvents()`. `nil` resolves the default
    /// `<appSupport>/TermQ[-Debug]/agent-sessions/` location used by
    /// production. Tests inject a temp directory.
    public var transcriptBaseURL: URL?

    private var process: AgentLoopProcess?
    private var consumeTask: Task<Void, Never>?
    private var writer: TrajectoryWriter?

    public init(
        cardId: UUID,
        cardLookup: (() -> TerminalCard?)? = nil,
        writerFactory: ((UUID) -> TrajectoryWriter?)? = nil,
        transcriptBaseURL: URL? = nil
    ) {
        self.cardId = cardId
        self.cardLookup = cardLookup ?? { BoardViewModel.shared.card(for: cardId) }
        self.writerFactory = writerFactory
        self.transcriptBaseURL = transcriptBaseURL
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

    /// Read a previously-persisted trajectory.jsonl off disk and populate
    /// `events` with its parsed contents. No-op if events already populated,
    /// the session is currently running, the card has no agent config, or
    /// no trajectory file exists for this session id.
    public func loadPersistedEvents() {
        guard events.isEmpty else { return }
        if case .running = status { return }
        guard let sessionId = cardLookup()?.agentConfig?.sessionId else { return }

        let url = TrajectoryWriter.fileURL(for: sessionId, baseDirectory: transcriptBaseURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }

        events = contents.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { AgentLoopProcess.parseLine(String($0)) }
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
    /// apply it. Most events (turn_start, sensor_result, etc.) leave the
    /// status unchanged at `.running`; `.plan` flips the card into the
    /// approval-gated state; terminal-shaped events flip to a final state.
    ///
    /// Internal (not private) so unit tests can inject synthetic events
    /// without standing up a real subprocess — useful for the
    /// `.awaitingPlanApproval` flip which races with handleStreamEnd in
    /// short-lived stubs.
    func handleEventForCardStatus(_ event: TrajectoryEvent) {
        switch event.decoded() {
        case .plan:
            updateCardStatus(.awaitingPlanApproval)
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

    // MARK: - Plan approval

    /// Approve the pending plan. Writes a control message to the loop
    /// driver's stdin and flips the card status back to `.running`.
    ///
    /// Wire format (TermQ ↔ ynh-agent contract): NDJSON. The loop driver
    /// reads stdin line by line and acts on `action` strings. Today only
    /// `approve_plan` and `reject_plan` are defined; future actions
    /// (interrupt, edit-feedback, etc.) extend this surface.
    public func approvePlan() async {
        guard cardLookup()?.agentConfig?.status == .awaitingPlanApproval else { return }
        try? await process?.send(line: #"{"action":"approve_plan"}"#)
        updateCardStatus(.running)
    }

    /// Reject the pending plan. Sends `reject_plan` to stdin so the driver
    /// can clean up gracefully, then SIGTERMs and flips the card to
    /// `.errored`. The driver may exit before reading the message; either
    /// outcome leaves the card in a terminal state.
    public func rejectPlan() async {
        guard cardLookup()?.agentConfig?.status == .awaitingPlanApproval else { return }
        try? await process?.send(line: #"{"action":"reject_plan"}"#)
        await process?.stop()
        updateCardStatus(.errored)
    }

    /// Called once the subprocess has fully exited and the stream has
    /// drained. Behaviour is status-conditional:
    ///
    /// - Already terminal (`.converged` / `.stuck` / `.errored`) — leave
    ///   alone (no-downgrade guard).
    /// - `.awaitingPlanApproval` — the driver died before the user could
    ///   approve or reject the plan. The session is effectively dead;
    ///   flip to `.errored` regardless of exit code.
    /// - Anything else — infer from exit code: 0 → `.converged`, non-zero
    ///   → `.errored`.
    private func handleStreamEnd(finalStatus: AgentLoopProcessStatus) {
        guard let card = cardLookup(), let config = card.agentConfig else { return }
        switch config.status {
        case .converged, .stuck, .errored:
            return
        case .awaitingPlanApproval:
            updateCardStatus(.errored)
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
