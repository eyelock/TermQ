import XCTest

@testable import TermQ

final class MemoryReportTests: XCTestCase {

    // MARK: - leaks

    private let leaksOutput = """
        Process 13893: 7824 leaks for 1280800 total leaked bytes.

            8646 (1.34M) << TOTAL >>
              1371 (207K) ROOT CYCLE: <ContextMenuResponder.AppKitMenuDelegate 0x74e137aee0> [32]
                 1368 (207K) __strong menuResponder --> ROOT CYCLE: <ContextMenuResponder 0x74e43b1a40> [320]
                    12 (1.2K) <CFString 0x600000c0a0a0> [48]  "secret terminal output"
              1 (32 bytes) ROOT LEAK: <_NSMenuIntelligentAssistantConfiguration 0x6000002b0> [32]
              1 (32 bytes) ROOT LEAK: <_NSMenuIntelligentAssistantConfiguration 0x6000002c0> [32]
        """

    func testLeaksSummary_keepsSummaryLine() {
        let summary = MemoryReport.leaksSummary(leaksOutput)
        XCTAssertTrue(summary.hasPrefix("Process 13893: 7824 leaks for 1280800 total leaked bytes."))
    }

    func testLeaksSummary_countsRootTypes_mostFrequentFirst() {
        let lines = MemoryReport.leaksSummary(leaksOutput).components(separatedBy: "\n")
        XCTAssertEqual(
            Array(lines.dropFirst()),
            [
                "Leak roots by type:",
                "  2  _NSMenuIntelligentAssistantConfiguration",
                "  1  ContextMenuResponder",
                "  1  ContextMenuResponder.AppKitMenuDelegate",
            ])
    }

    func testLeaksSummary_dropsObjectContents() {
        let summary = MemoryReport.leaksSummary(leaksOutput)
        XCTAssertFalse(summary.contains("secret"))
        XCTAssertFalse(summary.contains("0x"))
    }

    func testLeaksSummary_withoutSummaryLine_saysSo() {
        XCTAssertEqual(MemoryReport.leaksSummary("garbage"), "No leak summary found.")
    }

    // MARK: - heap

    private let heapOutput = """
        Process:         TermQ [13893]
        Physical footprint:         222.0M
        ----

        All zones: 616597 nodes malloced - Sizes: 896KB[12] 304KB[2]

        Found:  2400 ObjC classes  3419 Swift classes

        -----------------------------------------------------------------------
        All zones: 665479 nodes (117975803 bytes)

           COUNT      BYTES       AVG   CLASS_NAME                                        TYPE    BINARY
           =====      =====       ===   ==========                                        ====    ======
          202561   22029049     108.8   non-object
              14   12845056  917504.0   CellArena.attributes (malloc)                             TermQ
           70998   10948768     154.2   PropertyList.Element                              Swift   SwiftUICore
            7138    9136640    1280.0   CellStoragePage.cells._position (malloc)                  TermQ
        """

    func testHeapTopTypes_keepsTotalsAndHeaderAndLimitedRows() {
        let lines = MemoryReport.heapTopTypes(heapOutput, limit: 2).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0], "All zones: 665479 nodes (117975803 bytes)")
        XCTAssertTrue(lines[1].contains("COUNT"))
        XCTAssertTrue(lines[2].contains("====="))
        XCTAssertTrue(lines[3].contains("non-object"))
        XCTAssertTrue(lines[4].contains("CellArena.attributes"))
    }

    func testHeapTopTypes_skipsSizeHistogramLine() {
        XCTAssertFalse(MemoryReport.heapTopTypes(heapOutput).contains("malloced - Sizes"))
    }

    // MARK: - footprint

    func testFootprintExcerpt_limitsLines() {
        let output = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let excerpt = MemoryReport.footprintExcerpt(output, maxLines: 3)
        XCTAssertEqual(excerpt, "line 1\nline 2\nline 3")
    }

    // MARK: - Redaction

    func testRedact_replacesHomeAndUser() {
        let text = "/Users/alex/Apps/TermQ.app owned by alex; alexander unaffected"
        let redacted = MemoryReport.redact(text, home: "/Users/alex", user: "alex")
        XCTAssertEqual(redacted, "~/Apps/TermQ.app owned by USER; alexander unaffected")
    }

    func testRedact_emptyValues_leaveTextUnchanged() {
        XCTAssertEqual(MemoryReport.redact("unchanged", home: "", user: ""), "unchanged")
    }

    // MARK: - Formatting

    func testFormatBytes() {
        XCTAssertEqual(MemoryReport.formatBytes(272 * 1_048_576), "272.0 MB")
        XCTAssertEqual(MemoryReport.formatBytes(16 * 1024 * 1_048_576), "16.0 GB")
    }

    func testFormatDuration() {
        XCTAssertEqual(MemoryReport.formatDuration(5 * 60), "0h 5m")
        XCTAssertEqual(MemoryReport.formatDuration(44 * 3600 + 23 * 60), "1d 20h 23m")
    }

    // MARK: - Rendering

    private func makeSnapshot() -> MemoryReport.Snapshot {
        MemoryReport.Snapshot(
            generated: Date(timeIntervalSince1970: 0),
            appVersion: "0.13.0 (build 1)",
            osVersion: "Version 27.0",
            physicalMemoryBytes: 16 * 1024 * 1_048_576,
            processUptime: 3600,
            footprintBytes: 272 * 1_048_576,
            peakFootprintBytes: nil,
            liveCards: 13,
            deletedCards: 18,
            openTabs: 2,
            scrollbackSetting: 5000,
            sessions: [
                .init(backend: "direct", state: .openTab, approximateLines: 120, paneCount: 0),
                .init(backend: "direct", state: .closedTab, approximateLines: 5040, paneCount: 0),
                .init(backend: "tmuxControl", state: .exited, approximateLines: 40, paneCount: 3),
            ],
            tools: [.init(title: "leaks — summary only", body: "Process 1: 0 leaks for 0 total leaked bytes.")]
        )
    }

    func testRender_includesHeadlineNumbersAndSessions() {
        let report = MemoryReport.render(makeSnapshot())
        XCTAssertTrue(report.contains("Footprint:      272.0 MB"))
        XCTAssertTrue(report.contains("Peak footprint: unknown"))
        XCTAssertTrue(report.contains("Cards (live / deleted): 13 / 18"))
        XCTAssertTrue(report.contains("Sessions: 3 (1 open tab, 1 closed tab, still in memory, 1 process exited)"))
        XCTAssertTrue(report.contains("#2 direct, closed tab, still in memory, ~5040 lines"))
        XCTAssertTrue(report.contains("#3 tmuxControl, process exited, ~40 lines, 3 panes"))
        XCTAssertTrue(report.contains("==== leaks — summary only ===="))
    }

    func testSessionCountsLine_noSessions() {
        XCTAssertEqual(
            MemoryReport.sessionCountsLine([]),
            "Sessions: 0 (0 open tab, 0 closed tab, still in memory, 0 process exited)")
    }
}
