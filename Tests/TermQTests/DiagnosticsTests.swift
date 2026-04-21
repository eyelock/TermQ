import Foundation
import XCTest

@testable import TermQCore

final class DiagnosticsTests: XCTestCase {

    // MARK: - DiagnosticsLevel ordering

    func testLevelOrderIsDebugInfoNoticeWarningError() {
        XCTAssertLessThan(DiagnosticsLevel.debug, .info)
        XCTAssertLessThan(DiagnosticsLevel.info, .notice)
        XCTAssertLessThan(DiagnosticsLevel.notice, .warning)
        XCTAssertLessThan(DiagnosticsLevel.warning, .error)
    }

    func testLevelEqualityIsNotLessThan() {
        for level in DiagnosticsLevel.allCases {
            XCTAssertFalse(level < level)
        }
    }

    func testLevelComparableSymmetry() {
        XCTAssertFalse(DiagnosticsLevel.error < .debug)
        XCTAssertFalse(DiagnosticsLevel.notice < .info)
    }

    func testLevelLabel() {
        XCTAssertEqual(DiagnosticsLevel.debug.label, "DEBUG")
        XCTAssertEqual(DiagnosticsLevel.info.label, "INFO")
        XCTAssertEqual(DiagnosticsLevel.notice.label, "NOTICE")
        XCTAssertEqual(DiagnosticsLevel.warning.label, "WARNING")
        XCTAssertEqual(DiagnosticsLevel.error.label, "ERROR")
    }

    // MARK: - LogEntry

    func testLogEntryDefaults() {
        let entry = LogEntry(level: .notice, category: "window", message: "launched")
        XCTAssertFalse(entry.id.uuidString.isEmpty)
        XCTAssertEqual(entry.level, .notice)
        XCTAssertEqual(entry.category, "window")
        XCTAssertEqual(entry.message, "launched")
    }

    func testLogEntryIdentifiersAreUnique() {
        let a = LogEntry(level: .info, category: "session", message: "connect")
        let b = LogEntry(level: .info, category: "session", message: "connect")
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - Level filter predicate

    func testFilterAtNoticeExcludesDebugAndInfo() {
        let entries = DiagnosticsLevel.allCases.map { level in
            LogEntry(level: level, category: "test", message: "msg")
        }
        let threshold = DiagnosticsLevel.notice
        let filtered = entries.filter { $0.level >= threshold }
        let levels = filtered.map(\.level)
        XCTAssertFalse(levels.contains(.debug))
        XCTAssertFalse(levels.contains(.info))
        XCTAssertTrue(levels.contains(.notice))
        XCTAssertTrue(levels.contains(.warning))
        XCTAssertTrue(levels.contains(.error))
    }

    func testFilterAtDebugIncludesAll() {
        let entries = DiagnosticsLevel.allCases.map { level in
            LogEntry(level: level, category: "test", message: "msg")
        }
        let filtered = entries.filter { $0.level >= .debug }
        XCTAssertEqual(filtered.count, DiagnosticsLevel.allCases.count)
    }

    func testFilterAtErrorIncludesOnlyError() {
        let entries = DiagnosticsLevel.allCases.map { level in
            LogEntry(level: level, category: "test", message: "msg")
        }
        let filtered = entries.filter { $0.level >= .error }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].level, .error)
    }

    // MARK: - Category filter predicate

    func testCategoryFilterExactMatch() {
        let entries = [
            LogEntry(level: .notice, category: "window", message: "a"),
            LogEntry(level: .notice, category: "session", message: "b"),
            LogEntry(level: .notice, category: "window", message: "c"),
        ]
        let filtered = entries.filter { $0.category == "window" }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.category == "window" })
    }

    // MARK: - Search predicate

    func testSearchIsCaseInsensitive() {
        let entries = [
            LogEntry(level: .notice, category: "window", message: "Application Launched"),
            LogEntry(level: .notice, category: "window", message: "session connected"),
        ]
        let filtered = entries.filter { $0.message.localizedCaseInsensitiveContains("launched") }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].message, "Application Launched")
    }

    func testEmptySearchMatchesAll() {
        let entries = [
            LogEntry(level: .notice, category: "window", message: "a"),
            LogEntry(level: .notice, category: "session", message: "b"),
        ]
        let filtered = entries.filter { "".isEmpty || $0.message.localizedCaseInsensitiveContains("") }
        XCTAssertEqual(filtered.count, 2)
    }
}
