import SwiftUI
import TermQCore

// MARK: - Turn grouping model

struct SensorRunSummary {
    let name: String
    let exitCode: Int
    let durationMs: Int
    let summary: String?
}

struct TurnGroup: Identifiable {
    let id: Int
    let turnNumber: Int?
    let events: [TrajectoryEvent]

    var sensorResults: [SensorRunSummary] {
        events.compactMap {
            if case .sensorResult(let name, let code, let ms, let sum) = $0.decoded() {
                return SensorRunSummary(name: name, exitCode: code, durationMs: ms, summary: sum)
            }
            return nil
        }
    }

    var passCount: Int { sensorResults.filter { $0.exitCode == 0 }.count }
    var failCount: Int { sensorResults.filter { $0.exitCode != 0 }.count }
}

/// Groups a flat event list into per-turn buckets, preserving pre-turn events
/// (e.g. `session_start`, `plan`) in an initial group with no turn number.
func buildTurnGroups(from events: [TrajectoryEvent]) -> [TurnGroup] {
    guard !events.isEmpty else { return [] }
    var groups: [TurnGroup] = []
    var currentEvents: [TrajectoryEvent] = []
    var currentTurnNumber: Int?
    var groupIndex = 0

    for event in events {
        if case .turnStart(let n) = event.decoded() {
            groups.append(TurnGroup(id: groupIndex, turnNumber: currentTurnNumber, events: currentEvents))
            groupIndex += 1
            currentTurnNumber = n
            currentEvents = []
        } else {
            currentEvents.append(event)
        }
    }
    groups.append(TurnGroup(id: groupIndex, turnNumber: currentTurnNumber, events: currentEvents))
    return groups.filter { !$0.events.isEmpty || $0.turnNumber != nil }
}

// MARK: - Turn group view

struct TurnGroupView: View {
    let group: TurnGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let n = group.turnNumber {
                TurnHeaderRow(
                    turnNumber: n,
                    passCount: group.passCount,
                    failCount: group.failCount
                )
                Divider()
            }
            ForEach(Array(group.events.enumerated()), id: \.offset) { i, event in
                switch event.decoded() {
                case .sensorResult(let name, let code, let ms, let sum):
                    SensorResultRow(name: name, exitCode: code, durationMs: ms, summary: sum)
                default:
                    TrajectoryEventRow(event: event)
                }
                if i < group.events.count - 1 {
                    Divider()
                }
            }
        }
    }
}

// MARK: - Turn header row

struct TurnHeaderRow: View {
    let turnNumber: Int
    let passCount: Int
    let failCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("Turn \(turnNumber)")
                .font(.caption.weight(.semibold))
            Spacer()
            if failCount > 0 {
                Label("\(failCount) failed", systemImage: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if passCount > 0 {
                Label("all passed", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08))
    }
}

// MARK: - Sensor result row

struct SensorResultRow: View {
    let name: String
    let exitCode: Int
    let durationMs: Int
    let summary: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(exitCode == 0 ? Color.green : Color.red)
                .frame(width: 14)
            Text(name)
                .font(.caption.monospaced().weight(.medium))
                .frame(width: 80, alignment: .leading)
            Text("\(durationMs)ms")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(exitCode == 0 ? Color.green.opacity(0.04) : Color.red.opacity(0.06))
    }
}

// MARK: - Trajectory event row

struct TrajectoryEventRow: View {
    let event: TrajectoryEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(event.type)
                .font(.caption.monospaced().weight(.medium))
                .frame(width: 140, alignment: .leading)
            Text(eventSummary(event))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

func eventSummary(_ event: TrajectoryEvent) -> String {
    switch event.decoded() {
    case .sessionStart(_, let harness):
        return harness ?? ""
    case .plan(let content):
        return content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    case .turnStart(let turn):
        return "turn \(turn)"
    case .sensorResult(let name, let exitCode, let durationMs, let summary):
        let verdict = exitCode == 0 ? "✓" : "✗"
        return "\(verdict) \(name) — \(durationMs)ms\(summary.map { " — \($0)" } ?? "")"
    case .turnApprovalRequired(let turn, _):
        return "turn \(turn) — awaiting approval"
    case .stuckDetected(let reason):
        return reason
    case .budgetExceeded(let kind):
        return kind.rawValue
    case .converged:
        return "all sensors green"
    case .sessionEnd(let exitCode, let totalTurns, _):
        return "exit \(exitCode)\(totalTurns.map { " · \($0) turns" } ?? "")"
    case .other:
        return ""
    }
}
