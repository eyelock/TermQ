import SwiftUI
import UniformTypeIdentifiers
import TermQCore

/// Read-only replay of a saved agent trajectory.
///
/// Accepts any `.jsonl` file (or plain text) previously emitted by
/// `ynh agent run --emit-jsonl`. Shows the same turn-grouped trajectory
/// view used by the live Inspector, but without controls — purely for
/// post-mortem review or replaying CI artifacts locally.
struct AgentTranscriptViewerView: View {
    let events: [TrajectoryEvent]
    let fileName: String
    let onDismiss: () -> Void

    private var turnGroups: [TurnGroup] {
        buildTurnGroups(from: events)
    }

    private var sessionSummary: SessionSummary {
        SessionSummary(events: events)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryBanner
                    trajectoryList
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 660, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Summary banner

    private var summaryBanner: some View {
        HStack(spacing: 20) {
            if let harness = sessionSummary.harness {
                summaryChip(label: "Harness", value: harness)
            }
            if let turns = sessionSummary.totalTurns {
                summaryChip(label: "Turns", value: "\(turns)")
            }
            if let tokens = sessionSummary.totalTokens {
                summaryChip(label: "Tokens", value: formatTokens(tokens))
            }
            if let exitCode = sessionSummary.exitCode {
                summaryChip(
                    label: "Result",
                    value: exitCode == 0 ? "converged" : "exit \(exitCode)",
                    color: exitCode == 0 ? .green : .red
                )
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func summaryChip(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
    }

    // MARK: - Trajectory

    private var trajectoryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trajectory")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(turnGroups) { group in
                    TurnGroupView(group: group)
                }
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }
}

// MARK: - Session summary

private struct SessionSummary {
    let harness: String?
    let totalTurns: Int?
    let totalTokens: Int?
    let exitCode: Int?

    init(events: [TrajectoryEvent]) {
        var harness: String?
        var totalTurns: Int?
        var totalTokens: Int?
        var exitCode: Int?

        for event in events {
            switch event.decoded() {
            case .sessionStart(_, let h):
                harness = h
            case .sessionEnd(let code, let turns, let tokens):
                exitCode = code
                totalTurns = turns
                totalTokens = tokens
            default:
                break
            }
        }
        self.harness = harness
        self.totalTurns = totalTurns
        self.totalTokens = totalTokens
        self.exitCode = exitCode
    }
}

// MARK: - JSONL loading

extension AgentTranscriptViewerView {
    /// Parse a `.jsonl` file at `url` into trajectory events. Returns `nil`
    /// if the file can't be read or contains no recognisable events.
    static func loadEvents(from url: URL) -> [TrajectoryEvent]? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let events = contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { AgentLoopProcess.parseLine(String($0)) }
        return events.isEmpty ? nil : events
    }
}
