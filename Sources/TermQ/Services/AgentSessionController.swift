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

    private var process: AgentLoopProcess?
    private var consumeTask: Task<Void, Never>?

    public init(cardId: UUID) {
        self.cardId = cardId
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

        consumeTask = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
            // Stream finished — pull the final status off the actor.
            let finalStatus = await p.status
            self?.status = finalStatus
            self?.process = nil
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
}
