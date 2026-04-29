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

    // MARK: - Helpers

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
