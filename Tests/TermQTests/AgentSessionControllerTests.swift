import Foundation
import XCTest

@testable import TermQ
@testable import TermQCore

final class AgentSessionControllerTests: XCTestCase {

    @MainActor
    func testStart_streamsEventsIntoPublishedArray() async throws {
        let controller = AgentSessionController(cardId: UUID())
        let command = #"echo '{"type":"start"}'; echo '{"type":"end"}'"#
        try await controller.start(command: command)

        // Wait briefly for the consume task to drain the stream.
        try await waitUntil { controller.events.count >= 2 }

        XCTAssertEqual(controller.events.count, 2)
        XCTAssertEqual(controller.events[0].type, "start")
        XCTAssertEqual(controller.events[1].type, "end")

        try await waitUntil {
            if case .exited = controller.status { return true }
            return false
        }
    }

    @MainActor
    func testStart_clearsPreviousEventsOnNewRun() async throws {
        let controller = AgentSessionController(cardId: UUID())
        try await controller.start(command: #"echo '{"type":"a"}'"#)
        try await waitUntil { controller.events.count == 1 }

        // Wait for first run to fully exit before starting a new one.
        try await waitUntil {
            if case .exited = controller.status { return true }
            return false
        }

        try await controller.start(command: #"echo '{"type":"b"}'"#)
        try await waitUntil { controller.events.count == 1 && controller.events[0].type == "b" }

        XCTAssertEqual(controller.events.count, 1)
        XCTAssertEqual(controller.events.first?.type, "b")
    }

    // MARK: - Card status writeback

    @MainActor
    func testStart_setsCardStatusToRunning() async throws {
        let columnId = UUID()
        let card = TerminalCard(columnId: columnId, agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        try await controller.start(command: "sleep 0.5")

        XCTAssertEqual(card.agentConfig?.status, .running)
        await controller.stop(graceSeconds: 0)
    }

    @MainActor
    func testEvent_convergedSetsCardStatusToConverged() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        try await controller.start(command: #"echo '{"type":"converged"}'"#)

        try await waitUntil { card.agentConfig?.status == .converged }
        XCTAssertEqual(card.agentConfig?.status, .converged)
    }

    @MainActor
    func testEvent_stuckDetectedSetsCardStatusToStuck() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        try await controller.start(
            command: #"echo '{"type":"stuck_detected","reason":"edit-loop"}'"#)

        try await waitUntil { card.agentConfig?.status == .stuck }
        XCTAssertEqual(card.agentConfig?.status, .stuck)
    }

    @MainActor
    func testEvent_budgetExceededSetsCardStatusToErrored() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        try await controller.start(
            command: #"echo '{"type":"budget_exceeded","budget":"turns"}'"#)

        try await waitUntil { card.agentConfig?.status == .errored }
        XCTAssertEqual(card.agentConfig?.status, .errored)
    }

    @MainActor
    func testStreamEnd_nonZeroExitCode_setsErrored() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        // Emit no terminal event; exit non-zero. Controller should infer .errored.
        try await controller.start(command: "exit 1")

        try await waitUntil { card.agentConfig?.status == .errored }
        XCTAssertEqual(card.agentConfig?.status, .errored)
    }

    @MainActor
    func testStreamEnd_zeroExitCode_setsConvergedWhenNoTerminalEvent() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        // Emit no terminal event; exit clean. Controller should infer .converged.
        try await controller.start(command: "true")

        try await waitUntil { card.agentConfig?.status == .converged }
        XCTAssertEqual(card.agentConfig?.status, .converged)
    }

    @MainActor
    func testStreamEnd_whileAwaitingPlanApproval_flipsToErrored() async throws {
        // If the loop driver dies while the user is still deciding on the
        // plan, the session is effectively dead — must NOT be reported as
        // .converged on exit 0. Verify the awaitingPlanApproval branch in
        // handleStreamEnd.
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        // Run-then-exit-0 stub. Force the status to awaiting before the
        // stream ends so handleStreamEnd sees that branch.
        try await controller.start(command: "true")
        forceCardStatus(.awaitingPlanApproval, on: card)

        try await waitUntil { card.agentConfig?.status == .errored }
        XCTAssertEqual(card.agentConfig?.status, .errored)
    }

    @MainActor
    func testStreamEnd_doesNotDowngradeTerminalCardStatus() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        // Stuck event flips card to .stuck; non-zero exit must NOT clobber that.
        try await controller.start(
            command: #"echo '{"type":"stuck_detected","reason":"oscillation"}'; exit 1"#)

        // Wait for stream end (both stuck propagation and exit).
        try await waitUntil {
            if case .exited = controller.status { return true }
            return false
        }
        XCTAssertEqual(card.agentConfig?.status, .stuck)
    }

    // MARK: - Trajectory persistence

    @MainActor
    func testStart_persistsEventsViaWriter() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ControllerWriterTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let sessionId = card.agentConfig!.sessionId

        let controller = AgentSessionController(
            cardId: card.id,
            cardLookup: { card },
            writerFactory: { try? TrajectoryWriter(sessionId: $0, baseDirectory: tempDir) }
        )

        try await controller.start(
            command: #"echo '{"type":"a"}'; echo '{"type":"b"}'"#)

        // Wait for stream to drain.
        try await waitUntil {
            if case .exited = controller.status { return true }
            return false
        }

        let path = tempDir.appendingPathComponent(sessionId.uuidString)
            .appendingPathComponent("trajectory.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        let contents = try String(contentsOf: path, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains(#""type":"a""#))
        XCTAssertTrue(lines[1].contains(#""type":"b""#))
    }

    // MARK: - Graceful stop

    @MainActor
    func testStop_interruptThenTerminate_driverSelfExitsOnInterrupt() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        // Stub reads stdin and exits when it sees the interrupt action.
        // Tests the graceful path: send action, driver exits cleanly,
        // SIGTERM is never needed.
        try await controller.start(
            command: "while read line; do case \"$line\" in *interrupt*) exit 0;; esac; done; sleep 30")

        await controller.stop(graceSeconds: 1.0)

        if case .exited(let code) = controller.status {
            XCTAssertEqual(code, 0)
        } else {
            XCTFail("Expected exited status, got \(controller.status)")
        }
    }

    // MARK: - Plan approval

    @MainActor
    func testEvent_planFlipsCardToAwaitingApproval() {
        // Direct unit test: a transient subprocess race made this flaky —
        // the stub exits, handleStreamEnd fires, and status flips past
        // .awaitingPlanApproval before any polling could observe it.
        // In production the loop driver doesn't exit while awaiting, so
        // this race is a test artefact only. Inject the event directly.
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        let planEvent = TrajectoryEvent(
            type: "plan",
            timestamp: Date(),
            payloadJSON: ##"{"type":"plan","content":"# do x"}"##
        )
        controller.handleEventForCardStatus(planEvent)

        XCTAssertEqual(card.agentConfig?.status, .awaitingPlanApproval)
    }

    @MainActor
    func testApprovePlan_returnsCardToRunning() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        // Long-running stub keeps the subprocess alive so approvePlan has a
        // real stdin to write to. Status is flipped manually to avoid
        // shell-buffering races between echo and the next blocking command;
        // the plan→awaitingPlanApproval transition itself is covered by
        // testEvent_planFlipsCardToAwaitingApproval.
        try await controller.start(command: "sleep 30")
        forceCardStatus(.awaitingPlanApproval, on: card)

        await controller.approvePlan()

        XCTAssertEqual(card.agentConfig?.status, .running)
        await controller.stop(graceSeconds: 0)
    }

    @MainActor
    func testRejectPlan_terminatesAndFlipsToErrored() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        try await controller.start(command: "sleep 30")
        forceCardStatus(.awaitingPlanApproval, on: card)

        await controller.rejectPlan()

        XCTAssertEqual(card.agentConfig?.status, .errored)
    }

    @MainActor
    func testApprovePlan_noOp_whenNotAwaitingApproval() async throws {
        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(cardId: card.id, cardLookup: { card })

        // No process running; no plan event seen.
        await controller.approvePlan()

        // Nothing flipped — stays at .idle.
        XCTAssertEqual(card.agentConfig?.status, .idle)
    }

    // MARK: - Trajectory hydration

    @MainActor
    func testLoadPersistedEvents_populatesEventsFromDisk() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HydrationTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let sessionId = card.agentConfig!.sessionId

        // Pre-populate a trajectory.jsonl file via the writer.
        let writer = try TrajectoryWriter(sessionId: sessionId, baseDirectory: tempDir)
        writer.append(
            TrajectoryEvent(type: "a", timestamp: Date(), payloadJSON: #"{"type":"a"}"#))
        writer.append(
            TrajectoryEvent(type: "b", timestamp: Date(), payloadJSON: #"{"type":"b"}"#))
        writer.close()

        // Fresh controller sees no events until hydrated.
        let controller = AgentSessionController(
            cardId: card.id,
            cardLookup: { card },
            transcriptBaseURL: tempDir
        )
        XCTAssertTrue(controller.events.isEmpty)

        controller.loadPersistedEvents()

        XCTAssertEqual(controller.events.count, 2)
        XCTAssertEqual(controller.events[0].type, "a")
        XCTAssertEqual(controller.events[1].type, "b")
    }

    @MainActor
    func testLoadPersistedEvents_noOp_whenEventsAlreadyPopulated() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HydrationTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let writer = try TrajectoryWriter(
            sessionId: card.agentConfig!.sessionId, baseDirectory: tempDir)
        writer.append(
            TrajectoryEvent(type: "disk", timestamp: Date(), payloadJSON: #"{"type":"disk"}"#))
        writer.close()

        let controller = AgentSessionController(
            cardId: card.id,
            cardLookup: { card },
            transcriptBaseURL: tempDir
        )

        // Manually load once, then call again — second call must not double up.
        controller.loadPersistedEvents()
        XCTAssertEqual(controller.events.count, 1)

        controller.loadPersistedEvents()
        XCTAssertEqual(controller.events.count, 1)
    }

    @MainActor
    func testLoadPersistedEvents_noOp_whenNoFileExists() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HydrationTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(
            cardId: card.id,
            cardLookup: { card },
            transcriptBaseURL: tempDir
        )

        controller.loadPersistedEvents()
        XCTAssertTrue(controller.events.isEmpty)
    }

    @MainActor
    func testLoadPersistedEvents_noOp_whenCardHasNoAgentConfig() {
        let cardWithoutAgent = TerminalCard(columnId: UUID())
        let controller = AgentSessionController(
            cardId: cardWithoutAgent.id,
            cardLookup: { cardWithoutAgent }
        )

        controller.loadPersistedEvents()
        XCTAssertTrue(controller.events.isEmpty)
    }

    @MainActor
    func testReset_clearsState() async throws {
        let controller = AgentSessionController(cardId: UUID())
        try await controller.start(command: #"echo '{"type":"x"}'"#)
        try await waitUntil { controller.events.count == 1 }
        try await waitUntil {
            if case .exited = controller.status { return true }
            return false
        }

        controller.reset()
        XCTAssertTrue(controller.events.isEmpty)
        XCTAssertEqual(controller.status, .notStarted)
    }

    // MARK: - Overlay injection

    @MainActor
    func testResolveCommand_noOverlays_returnsBaseCommandUnchanged() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverlayTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let controller = AgentSessionController(
            cardId: card.id, cardLookup: { card }, transcriptBaseURL: tempDir)

        XCTAssertEqual(controller.resolveCommand("ynh agent run"), "ynh agent run")
    }

    @MainActor
    func testResolveCommand_withOverlays_appendsSensorOverlayFlag() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverlayTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let sessionId = card.agentConfig!.sessionId

        let overlays: SensorOverlays = [
            "build": SensorOverlay(role: "regular", source: nil)
        ]
        SensorOverlayStore.save(overlays, for: sessionId, baseDirectory: tempDir)

        let controller = AgentSessionController(
            cardId: card.id, cardLookup: { card }, transcriptBaseURL: tempDir)

        let resolved = controller.resolveCommand("ynh agent run")
        XCTAssertTrue(resolved.hasPrefix("ynh agent run --sensor-overlay '"))
        XCTAssertTrue(resolved.contains("\"build\""))
    }

    @MainActor
    func testResolveCommand_overlayJSONWithSingleQuote_isEscaped() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverlayTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let sessionId = card.agentConfig!.sessionId

        let focus = SensorOverlayFocus(prompt: "it's a test", profile: nil)
        let overlays: SensorOverlays = [
            "judge": SensorOverlay(role: nil, source: SensorOverlaySource(focus: focus))
        ]
        SensorOverlayStore.save(overlays, for: sessionId, baseDirectory: tempDir)

        let controller = AgentSessionController(
            cardId: card.id, cardLookup: { card }, transcriptBaseURL: tempDir)

        let resolved = controller.resolveCommand("ynh agent run")
        // Single quotes in the JSON must be shell-escaped so /bin/sh -c doesn't break.
        XCTAssertFalse(resolved.contains("it's"))
        XCTAssertTrue(resolved.contains("it'\\''s"))
    }

    @MainActor
    func testResolveCommand_emptyOverlays_returnsBaseCommandUnchanged() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverlayTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let card = TerminalCard(columnId: UUID(), agentConfig: AgentConfig(harness: "x"))
        let sessionId = card.agentConfig!.sessionId

        // All overlays are empty (no role, no source) — serialise returns nil.
        let overlays: SensorOverlays = [
            "build": SensorOverlay(role: nil, source: nil)
        ]
        SensorOverlayStore.save(overlays, for: sessionId, baseDirectory: tempDir)

        let controller = AgentSessionController(
            cardId: card.id, cardLookup: { card }, transcriptBaseURL: tempDir)

        XCTAssertEqual(controller.resolveCommand("ynh agent run"), "ynh agent run")
    }

    // MARK: - Helpers

    /// Set a card's agent status without going through the controller — used
    /// by tests that need to exercise approval/reject paths without setting
    /// up a real plan-emitting subprocess.
    @MainActor
    private func forceCardStatus(_ status: AgentStatus, on card: TerminalCard) {
        guard var config = card.agentConfig else { return }
        config.status = status
        card.agentConfig = config
    }

    /// Poll a condition every 10ms up to 2 seconds. XCTest async expectations
    /// are heavier than necessary for state we know flips quickly.
    @MainActor
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: TimeInterval = 2.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

final class AgentSessionRegistryTests: XCTestCase {

    @MainActor
    func testController_returnsSameInstanceForSameCardId() {
        let registry = AgentSessionRegistry()
        let id = UUID()
        let a = registry.controller(for: id)
        let b = registry.controller(for: id)
        XCTAssertTrue(a === b)
    }

    @MainActor
    func testController_returnsDistinctInstancesForDifferentCardIds() {
        let registry = AgentSessionRegistry()
        let a = registry.controller(for: UUID())
        let b = registry.controller(for: UUID())
        XCTAssertFalse(a === b)
    }

    @MainActor
    func testRemove_dropsController() {
        let registry = AgentSessionRegistry()
        let id = UUID()
        let original = registry.controller(for: id)
        registry.remove(cardId: id)
        let fresh = registry.controller(for: id)
        XCTAssertFalse(original === fresh)
    }
}
