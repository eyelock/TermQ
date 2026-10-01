import Darwin
import Foundation
import TermQCore

/// Gathers the data for a `MemoryReport`: in-process numbers (footprint, sessions,
/// board shape) plus the output of the system `footprint`, `heap` and `leaks` tools
/// run against TermQ itself.
@MainActor
enum MemoryReportCollector {
    enum Step: Sendable {
        case inProcess, footprint, heap, leaks
    }

    static func collect(onStep: @MainActor (Step) -> Void) async -> MemoryReport.Snapshot {
        onStep(.inProcess)
        var snapshot = inProcessSnapshot()

        let pid = String(getpid())
        let home = NSHomeDirectory()
        let user = NSUserName()

        onStep(.footprint)
        if let output = await runTool("/usr/bin/footprint", [pid]) {
            snapshot.tools.append(
                .init(
                    title: "footprint",
                    body: MemoryReport.redact(MemoryReport.footprintExcerpt(output), home: home, user: user)))
        }

        // heap and leaks suspend TermQ while they inspect it, so the UI pauses briefly.
        // Stop early if the panel was closed: there is no point pausing TermQ again.
        if Task.isCancelled { return snapshot }
        onStep(.heap)
        if let output = await runTool("/usr/bin/heap", ["-sortBySize", pid]) {
            snapshot.tools.append(
                .init(
                    title: "heap — largest object types (type names only)",
                    body: MemoryReport.redact(MemoryReport.heapTopTypes(output), home: home, user: user)))
        }

        if Task.isCancelled { return snapshot }
        onStep(.leaks)
        if let output = await runTool("/usr/bin/leaks", [pid]) {
            snapshot.tools.append(
                .init(title: "leaks — summary only", body: MemoryReport.leaksSummary(output)))
        }

        let missing = ["footprint", "heap", "leaks"].filter { name in
            !snapshot.tools.contains { $0.title.hasPrefix(name) }
        }
        if !missing.isEmpty {
            snapshot.tools.append(
                .init(title: "Unavailable tools", body: missing.joined(separator: ", ")))
        }
        return snapshot
    }

    // MARK: - In-process

    private static func inProcessSnapshot() -> MemoryReport.Snapshot {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let footprint = currentFootprint()

        let boardViewModel = BoardViewModel.shared
        let openTabIds = Set(boardViewModel.sessionTabs)

        return MemoryReport.Snapshot(
            generated: Date(),
            appVersion: "\(version) (build \(build))",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            processUptime: processUptime(),
            footprintBytes: footprint?.current,
            peakFootprintBytes: footprint?.peak,
            liveCards: boardViewModel.board.activeCards.count,
            deletedCards: boardViewModel.board.deletedCards.count,
            openTabs: openTabIds.count,
            scrollbackSetting: SettingsStore.shared.terminalScrollbackLines,
            sessions: TerminalSessionManager.shared.memoryReportSessions(openTabIds: openTabIds),
            tools: []
        )
    }

    /// Physical footprint (what Activity Monitor's "Memory" column shows) and its peak.
    private static func currentFootprint() -> (current: UInt64, peak: UInt64)? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (info.phys_footprint, UInt64(max(0, info.ledger_phys_footprint_peak)))
    }

    private static func processUptime() -> TimeInterval? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &process, &size, nil, 0) == 0 else { return nil }
        let start = process.kp_proc.p_un.__p_starttime
        let started = Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        return Date().timeIntervalSince(started)
    }

    // MARK: - System tools

    /// Run a system tool and return its stdout, or nil if it is missing or fails to launch.
    ///
    /// Output goes to a private temporary file rather than a pipe: `heap` and `leaks`
    /// suspend this process while they inspect it, and a pipe that only TermQ drains
    /// could fill and deadlock the tool. The file is deleted as soon as it is read.
    nonisolated private static func runTool(_ path: String, _ arguments: [String]) async -> String? {
        let name = (path as NSString).lastPathComponent
        guard FileManager.default.isExecutableFile(atPath: path) else {
            TermQLogger.process.notice("Memory report: \(name) not available")
            return nil
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("termq-memory-\(UUID().uuidString).txt")
        guard
            FileManager.default.createFile(
                atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { return nil }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else { return nil }

        let start = Date()
        let exitCode: Int32? = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = outputHandle
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
        try? outputHandle.close()

        guard let exitCode else {
            TermQLogger.process.notice("Memory report: \(name) failed to launch")
            return nil
        }
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))
        // leaks exits 1 when it finds leaks, so a non-zero exit is not a failure here.
        TermQLogger.process.notice("Memory report: \(name) exited \(exitCode) in \(elapsed)s")
        return try? String(contentsOf: outputURL, encoding: .utf8)
    }
}

// MARK: - Session inventory

extension TerminalSessionManager {
    /// Describe every terminal session held in memory, without card titles or output.
    func memoryReportSessions(openTabIds: Set<UUID>) -> [MemoryReport.SessionInfo] {
        sessions.map { cardId, session in
            // A copied snapshot: SwiftTerm 2.x does not expose the live terminal.
            let state = session.terminal.terminalStateSnapshot()
            let sessionState: MemoryReport.SessionInfo.State =
                !session.isRunning ? .exited : openTabIds.contains(cardId) ? .openTab : .closedTab
            return MemoryReport.SessionInfo(
                backend: session.backend.rawValue,
                state: sessionState,
                approximateLines: state.viewportRow + state.dimensions.rows,
                paneCount: paneTerminals[cardId]?.count ?? 0
            )
        }
        .sorted { lhs, rhs in
            let order = MemoryReport.SessionInfo.State.allCases
            let lhsIndex = order.firstIndex(of: lhs.state) ?? 0
            let rhsIndex = order.firstIndex(of: rhs.state) ?? 0
            return lhsIndex != rhsIndex ? lhsIndex < rhsIndex : lhs.approximateLines > rhs.approximateLines
        }
    }
}
