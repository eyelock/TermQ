import Foundation
import XCTest

@testable import TermQ
@testable import TermQCore

final class AgentLoopProcessTests: XCTestCase {

    // MARK: - parseLine

    func testParseLine_validJSONWithType_yieldsEvent() {
        let line = #"{"type":"turn_start","timestamp":"2026-04-29T10:00:00Z","turn":1}"#
        let event = AgentLoopProcess.parseLine(line)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, "turn_start")
        XCTAssertEqual(event?.payloadJSON, line)
    }

    func testParseLine_missingType_returnsNil() {
        let line = #"{"foo":"bar"}"#
        XCTAssertNil(AgentLoopProcess.parseLine(line))
    }

    func testParseLine_invalidJSON_returnsNil() {
        XCTAssertNil(AgentLoopProcess.parseLine("not json"))
    }

    func testParseLine_emptyLine_returnsNil() {
        XCTAssertNil(AgentLoopProcess.parseLine(""))
    }

    // MARK: - Subprocess streaming

    /// Spawns `/bin/sh` with a small script that emits two NDJSON events,
    /// then verifies both are streamed in order and the stream finishes.
    func testStart_streamsNDJSONEvents() async throws {
        let process = AgentLoopProcess()
        let stream = try await process.start(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                #"echo '{"type":"start","turn":0}'; echo '{"type":"turn_start","turn":1}'"#,
            ]
        )

        var events: [TrajectoryEvent] = []
        for await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].type, "start")
        XCTAssertEqual(events[1].type, "turn_start")

        let status = await process.status
        if case .exited(let code) = status {
            XCTAssertEqual(code, 0)
        } else {
            XCTFail("Expected exited status, got \(status)")
        }
    }

    /// Lines without a `type` field are dropped silently rather than
    /// breaking the stream.
    func testStart_invalidLinesAreDropped() async throws {
        let process = AgentLoopProcess()
        let stream = try await process.start(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                #"echo 'plain text'; echo '{"type":"good"}'; echo '{"no":"type"}'"#,
            ]
        )

        var events: [TrajectoryEvent] = []
        for await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, "good")
    }

    /// Calling `start` twice on the same instance throws `alreadyStarted`.
    func testStart_calledTwice_throws() async throws {
        let process = AgentLoopProcess()
        _ = try await process.start(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 0.1"]
        )

        do {
            _ = try await process.start(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "true"]
            )
            XCTFail("Expected alreadyStarted error")
        } catch AgentLoopProcessError.alreadyStarted {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// `send(line:)` before `start` throws `notRunning`.
    func testSend_beforeStart_throws() async {
        let process = AgentLoopProcess()
        do {
            try await process.send(line: "hello")
            XCTFail("Expected notRunning error")
        } catch AgentLoopProcessError.notRunning {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
