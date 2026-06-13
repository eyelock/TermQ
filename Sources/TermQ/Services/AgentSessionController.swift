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

    /// Captured stderr tail and exit code from the most recent session that
    /// ended in `.errored`. Cleared when a new session starts. `nil` means
    /// no error to surface — either we haven't run yet, the last run is
    /// in progress, or it converged cleanly.
    @Published public private(set) var lastError: LastError?

    public struct LastError: Equatable, Sendable {
        public let exitCode: Int32?
        public let stderrTail: String
        public let resolvedCommand: String
    }

    /// Source of trajectory events.
    ///
    /// - `.file` — production. The controller appends `--emit-jsonl <path>`
    ///   to the spawned command and tells `AgentLoopProcess` to tail that
    ///   file. ynh becomes the single writer of the canonical
    ///   `trajectory.jsonl`; the controller is a read-only consumer.
    /// - `.stdout` — tests. The spawned command (typically a shell fixture
    ///   that uses `echo`) writes JSONL straight to stdout; `AgentLoopProcess`
    ///   parses each line as it arrives. No file is written by the
    ///   subprocess in this mode; the controller's `writerFactory` provides
    ///   any persistence the test needs.
    public enum TrajectoryMode: Sendable {
        case file
        case stdout
    }

    /// Trajectory transport. Production callers (via `AgentSessionRegistry`)
    /// pick `.file`; tests default to `.stdout`.
    public let trajectoryMode: TrajectoryMode

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

    /// Set by `stop()` so the subprocess exit (typically SIGTERM = code 15)
    /// is treated as a user-initiated halt, not a driver crash. Cleared at
    /// the start of every run.
    private var userStopRequested = false

    public init(
        cardId: UUID,
        cardLookup: (() -> TerminalCard?)? = nil,
        writerFactory: ((UUID) -> TrajectoryWriter?)? = nil,
        transcriptBaseURL: URL? = nil,
        trajectoryMode: TrajectoryMode = .stdout
    ) {
        self.cardId = cardId
        self.cardLookup = cardLookup ?? { BoardViewModel.shared.card(for: cardId) }
        self.writerFactory = writerFactory
        self.transcriptBaseURL = transcriptBaseURL
        self.trajectoryMode = trajectoryMode
    }

    /// Default writer factory used by `AgentSessionRegistry`: opens
    /// `<appSupport>/TermQ[-Debug]/agent-sessions/<sessionId>/trajectory.jsonl`
    /// in append mode. Returns `nil` if the writer fails to open (silent —
    /// in-memory events remain the source of truth).
    public static func defaultWriterFactory(_ sessionId: UUID) -> TrajectoryWriter? {
        try? TrajectoryWriter(sessionId: sessionId)
    }

    /// Spawn `/bin/sh -c "<command>"` and stream NDJSON trajectory events
    /// into `events`. No-op if a process is already running. Throws if the
    /// subprocess fails to launch.
    ///
    /// In `.file` mode (production), this appends `--emit-jsonl <path>` to
    /// the command so ynh writes events to a real file under the session's
    /// app-support directory; `AgentLoopProcess` tails that file via
    /// `DispatchSource`. In `.stdout` mode (tests), the subprocess is
    /// expected to write JSONL directly to stdout — see `TrajectoryMode`.
    ///
    /// If the session has a saved sensor overlay file, appends
    /// `--sensor-overlay <json>` to the command before launching so the
    /// loop driver picks up the session-local sensor mutations.
    public func start(command: String) async throws {
        guard process == nil else { return }

        userStopRequested = false
        let baseCommand = resolveCommand(command)
        let sessionId = cardLookup()?.agentConfig?.sessionId

        // In file-mode, the trajectory path is the canonical
        // <appSupport>/agent-sessions/<id>/trajectory.jsonl that ynh writes
        // to — same path `loadPersistedEvents()` reads from. There's no
        // separate `TrajectoryWriter` in this mode: ynh is the writer.
        let trajectoryFile: URL?
        let resolvedCommand: String
        switch trajectoryMode {
        case .file:
            if let sessionId {
                let url = TrajectoryWriter.fileURL(
                    for: sessionId, baseDirectory: transcriptBaseURL)
                trajectoryFile = url
                let escapedPath = url.path.replacingOccurrences(of: "'", with: "'\\''")
                resolvedCommand = "\(baseCommand) --emit-jsonl '\(escapedPath)'"
            } else {
                trajectoryFile = nil
                resolvedCommand = baseCommand
            }
        case .stdout:
            trajectoryFile = nil
            resolvedCommand = baseCommand
        }

        // Run ynh in the card's working directory if one is configured.
        // Otherwise the subprocess inherits TermQ's CWD, which is virtually
        // never what the user wants. Empty or non-existent paths fall back
        // to inherit (we don't want to silently rewrite to home).
        let workingDirectoryURL: URL? = {
            guard let card = cardLookup(),
                !card.workingDirectory.isEmpty,
                FileManager.default.fileExists(atPath: card.workingDirectory)
            else { return nil }
            return URL(fileURLWithPath: card.workingDirectory)
        }()

        let startSummary =
            "controller.start mode=\(String(describing: trajectoryMode))"
            + " cmdLen=\(resolvedCommand.count)"
            + " cwd=\(workingDirectoryURL?.path ?? "<inherit>")"
        TermQLogger.agent.notice(startSummary)

        let loopProcess = AgentLoopProcess()
        let stream = try await loopProcess.start(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", resolvedCommand],
            currentDirectory: workingDirectoryURL,
            trajectoryFile: trajectoryFile
        )
        process = loopProcess
        status = await loopProcess.status
        events.removeAll()
        lastError = nil
        updateCardStatus(.running)

        // Stdout-mode persistence: tests opt in via writerFactory. In
        // file-mode the trajectory file IS the persisted artifact, so we
        // don't create a second writer.
        if trajectoryMode == .stdout, let sid = sessionId {
            writer = writerFactory?(sid)
        }

        consumeTask = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
                self?.writer?.append(event)
                self?.handleEventForCardStatus(event)
            }
            // Stream finished — pull the final status off the actor.
            let finalStatus = await loopProcess.status
            let stderrTail = await loopProcess.stderrTail
            self?.status = finalStatus
            self?.process = nil
            self?.writer?.close()
            self?.writer = nil
            self?.captureLastErrorIfNeeded(
                finalStatus: finalStatus,
                stderrTail: stderrTail,
                resolvedCommand: resolvedCommand
            )
            self?.handleStreamEnd(finalStatus: finalStatus)
        }
    }

    private func captureLastErrorIfNeeded(
        finalStatus: AgentLoopProcessStatus,
        stderrTail: String,
        resolvedCommand: String
    ) {
        // User pressed Stop — the non-zero exit is the SIGTERM we sent, not
        // a driver crash. Suppress the error banner.
        guard !userStopRequested else { return }
        let exitCode: Int32?
        let isError: Bool
        switch finalStatus {
        case .exited(let code):
            exitCode = code
            isError = code != 0
        case .failed:
            exitCode = nil
            isError = true
        default:
            return
        }
        guard isError else { return }
        lastError = LastError(
            exitCode: exitCode,
            stderrTail: stderrTail.trimmingCharacters(in: .whitespacesAndNewlines),
            resolvedCommand: resolvedCommand
        )
    }

    /// Graceful stop: send an `interrupt` action to the loop driver's
    /// stdin so it can flush trajectory state and exit cleanly, then
    /// fall back to SIGTERM after a short grace period if the driver
    /// hasn't died on its own.
    ///
    /// Wire format: NDJSON action message, same channel as approve_plan
    /// (see plan §6.1 control protocol).
    public func stop(graceSeconds: Double = 1.5) async {
        guard let loopProcess = process else { return }
        userStopRequested = true
        try? await loopProcess.send(line: #"{"action":"interrupt"}"#)
        try? await Task.sleep(nanoseconds: UInt64(graceSeconds * 1_000_000_000))
        // If the driver responded to interrupt and exited, process is nil now.
        // Otherwise fall back to SIGTERM.
        if process != nil {
            await loopProcess.stop()
        }
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
    /// apply it. Most events (turn_start, sensor_result, assistant_message,
    /// etc.) leave the status unchanged at `.running`; `turn_approval_required`
    /// flips into the approval-gated state; terminal-shaped events flip to a
    /// final state.
    ///
    /// Note on plan mode: ynh emits a bare `plan` marker the moment the
    /// agent enters plan mode — *not* an approval gate. The user shouldn't
    /// be prompted to approve a non-existent plan; instead the agent will
    /// produce `assistant_message` events containing the plan text and
    /// then either converge on its own or emit an explicit approval-gate
    /// event. We do nothing on bare `plan` for that reason.
    ///
    /// Internal (not private) so unit tests can inject synthetic events
    /// without standing up a real subprocess.
    func handleEventForCardStatus(_ event: TrajectoryEvent) {
        switch event.decoded() {
        case .plan(let content):
            // Only treat as an approval gate if ynh attaches inline plan
            // content. Bare `{"type":"plan"}` markers (the current ynh
            // behaviour) are ignored — see method doc.
            if !content.isEmpty {
                updateCardStatus(.awaitingPlanApproval)
            }
        case .planApprovalRequired:
            // ynh 0.5+ plan-phase gate. Carries the plan content + iteration
            // directly; UI sources content from the event.
            updateCardStatus(.awaitingPlanApproval)
        case .turnApprovalRequired(let turn, _):
            // Pre-0.5 ynh emitted turn=0 for the plan-phase approval gate;
            // we keep that path so older installs still work. Turn ≥1 is
            // unambiguous: act-phase per-turn gate.
            if turn == 0 {
                updateCardStatus(.awaitingPlanApproval)
            } else {
                updateCardStatus(.awaitingTurnApproval)
            }
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
    /// reads stdin line by line and acts on `action` strings. Unknown
    /// actions are ignored (forward-compat), so pre-registering
    /// `replace_feedback` here is safe against older loop driver builds.
    public func approvePlan() async {
        guard cardLookup()?.agentConfig?.status == .awaitingPlanApproval else { return }
        try? await process?.send(line: #"{"action":"approve_plan"}"#)
        updateCardStatus(.running)
    }

    /// Refine the pending plan. Sends `replace_feedback` carrying the
    /// user's notes; ynh 0.5+ consumes this and re-enters the plan loop
    /// (emits `plan_revised` + a fresh `assistant_message` +
    /// `plan_approval_required` for the next iteration). The card stays
    /// in `.awaitingPlanApproval` momentarily — ynh's act-phase
    /// `waitForApproval` treats `replace_feedback` as an implicit
    /// approval, but in plan phase it triggers a new iteration so the
    /// gate just refreshes. We optimistically drop to `.running` so the
    /// "Working…" footer shows while the next plan is generating.
    public func refinePlan(notes: String) async {
        guard cardLookup()?.agentConfig?.status == .awaitingPlanApproval else { return }
        guard !notes.isEmpty else { return }
        if let data = try? JSONSerialization.data(
            withJSONObject: ["action": "replace_feedback", "feedback": notes]),
            let line = String(data: data, encoding: .utf8)
        {
            try? await process?.send(line: line)
        }
        updateCardStatus(.running)
    }

    // MARK: - Turn approval

    /// Approve the pending turn, optionally replacing the sensor-synthesized
    /// feedback with the user's version. ynh's protocol treats
    /// `replace_feedback` as an *implicit approval* — so we send exactly one
    /// message: either `replace_feedback` (with the edited text) OR plain
    /// `approve_turn`. Sending both would queue an extra approve_turn that
    /// silently auto-approves the next turn.
    public func approveTurn(feedback: String? = nil) async {
        guard cardLookup()?.agentConfig?.status == .awaitingTurnApproval else { return }
        if let feedback, !feedback.isEmpty,
            let data = try? JSONSerialization.data(
                withJSONObject: ["action": "replace_feedback", "feedback": feedback]),
            let line = String(data: data, encoding: .utf8)
        {
            try? await process?.send(line: line)
        } else {
            try? await process?.send(line: #"{"action":"approve_turn"}"#)
        }
        updateCardStatus(.running)
    }

    // MARK: -

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
        // User pressed Stop — treat the exit as a paused session rather than
        // an error, regardless of the underlying exit code (typically SIGTERM).
        if userStopRequested {
            switch config.status {
            case .converged, .stuck, .errored:
                return
            default:
                updateCardStatus(.paused)
                return
            }
        }
        switch config.status {
        case .converged, .stuck, .errored:
            return
        case .awaitingPlanApproval, .awaitingTurnApproval:
            updateCardStatus(.errored)
            return
        default:
            break
        }
        if case .exited(let code) = finalStatus {
            updateCardStatus(code == 0 ? .converged : .errored)
        }
    }

    /// Append `--sensor-overlay <json>` to `base` if the session has saved
    /// overlays, quoting the JSON for safe passing to `/bin/sh -c`.
    /// Internal (not private) so tests can exercise the overlay injection
    /// logic without spawning a real subprocess.
    func resolveCommand(_ base: String) -> String {
        guard let sessionId = cardLookup()?.agentConfig?.sessionId,
            let overlayJSON = SensorOverlayStore.serialise(
                SensorOverlayStore.load(for: sessionId, baseDirectory: transcriptBaseURL))
        else { return base }
        let escaped = overlayJSON.replacingOccurrences(of: "'", with: "'\\''")
        return "\(base) --sensor-overlay '\(escaped)'"
    }

    private func updateCardStatus(_ newStatus: AgentStatus) {
        guard let card = cardLookup(), var config = card.agentConfig else { return }
        guard config.status != newStatus else { return }
        config.status = newStatus
        card.agentConfig = config
    }
}
