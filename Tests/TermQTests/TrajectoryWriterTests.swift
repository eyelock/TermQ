import Foundation
import XCTest

@testable import TermQ
@testable import TermQCore

final class TrajectoryWriterTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrajectoryWriterTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        super.tearDown()
    }

    func testInit_createsSessionDirectoryAndFile() throws {
        let sessionId = UUID()
        let writer = try TrajectoryWriter(sessionId: sessionId, baseDirectory: tempDir)
        defer { writer.close() }

        let expected = tempDir.appendingPathComponent(sessionId.uuidString)
            .appendingPathComponent("trajectory.jsonl")
        XCTAssertEqual(writer.fileURL, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: writer.fileURL.path))
    }

    func testAppend_writesOneJSONLineWithTrailingNewline() throws {
        let writer = try TrajectoryWriter(sessionId: UUID(), baseDirectory: tempDir)
        let event = TrajectoryEvent(
            type: "turn_start",
            timestamp: Date(),
            payloadJSON: #"{"type":"turn_start","turn":1}"#
        )
        writer.append(event)
        writer.close()

        let contents = try String(contentsOf: writer.fileURL, encoding: .utf8)
        XCTAssertEqual(contents, #"{"type":"turn_start","turn":1}"# + "\n")
    }

    func testAppend_multipleEventsAppendInOrder() throws {
        let writer = try TrajectoryWriter(sessionId: UUID(), baseDirectory: tempDir)
        for i in 1...3 {
            let event = TrajectoryEvent(
                type: "turn_start",
                timestamp: Date(),
                payloadJSON: #"{"type":"turn_start","turn":\#(i)}"#
            )
            writer.append(event)
        }
        writer.close()

        let contents = try String(contentsOf: writer.fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains(#""turn":1"#))
        XCTAssertTrue(lines[1].contains(#""turn":2"#))
        XCTAssertTrue(lines[2].contains(#""turn":3"#))
    }

    func testAppend_secondWriterAppendsToExistingFile() throws {
        let sessionId = UUID()
        let first = try TrajectoryWriter(sessionId: sessionId, baseDirectory: tempDir)
        first.append(
            TrajectoryEvent(
                type: "x", timestamp: Date(), payloadJSON: #"{"type":"x"}"#))
        first.close()

        let second = try TrajectoryWriter(sessionId: sessionId, baseDirectory: tempDir)
        second.append(
            TrajectoryEvent(
                type: "y", timestamp: Date(), payloadJSON: #"{"type":"y"}"#))
        second.close()

        let contents = try String(contentsOf: first.fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(#""type":"x""#))
        XCTAssertTrue(contents.contains(#""type":"y""#))
    }

    func testAppend_afterClose_isNoOp() throws {
        let writer = try TrajectoryWriter(sessionId: UUID(), baseDirectory: tempDir)
        writer.append(
            TrajectoryEvent(
                type: "before", timestamp: Date(), payloadJSON: #"{"type":"before"}"#))
        writer.close()
        writer.append(
            TrajectoryEvent(
                type: "after", timestamp: Date(), payloadJSON: #"{"type":"after"}"#))

        let contents = try String(contentsOf: writer.fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("before"))
        XCTAssertFalse(contents.contains("after"))
    }
}
