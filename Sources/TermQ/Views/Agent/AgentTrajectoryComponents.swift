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
                case .assistantMessage(_, let content):
                    AssistantMessageRow(content: content, timestamp: event.timestamp)
                case .planRevised(let iteration, let notes):
                    PlanRevisedRow(iteration: iteration, notes: notes)
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
        if content.isEmpty {
            return "plan mode entered"
        }
        return content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    case .planApprovalRequired(_, let iteration):
        return "iteration \(iteration) — awaiting approval"
    case .planRevised(let iteration, _):
        return "revising — iteration \(iteration)"
    case .turnStart(let turn):
        return "turn \(turn)"
    case .assistantMessage(_, let content):
        // Rendered by `AssistantMessageRow`, not by the generic row that
        // calls this — kept here for completeness in case the row falls
        // back to the default path.
        return content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
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

// MARK: - Assistant message row

/// Multi-line row that displays the agent's natural-language output. Unlike
/// the compact one-line `TrajectoryEventRow`, this row wraps and lets
/// long messages occupy the height they need so users can actually read
/// what the agent said. Tap-to-expand isn't needed yet — content typically
/// fits in 4-8 lines.
struct AssistantMessageRow: View {
    let content: String
    let timestamp: Date

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Self.timeFormatter.string(from: timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(width: 14)
            Text(content)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.05))
    }
}

// MARK: - Plan revised row

/// Trajectory boundary between plan iterations. Surfaces the iteration
/// number we're about to produce and the user's refinement notes that
/// triggered the revision. Visually distinct from `AssistantMessageRow`
/// because it represents a *human* contribution, not the agent's output.
struct PlanRevisedRow: View {
    let iteration: Int
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Plan iteration \(iteration) — revising")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }
            Text(notes)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - Working footer

/// Live "the agent is working, please wait" indicator. Shown whenever the
/// session is in the `.running` state. Ticks a 1Hz timer so the elapsed
/// counter advances even when no trajectory events arrive — vendors can sit
/// silent for tens of seconds between events while the LLM is generating, so
/// users need *something* moving on screen to know the process isn't wedged.
struct AgentWorkingFooter: View {
    let lastEventAt: Date?

    @State private var now: Date = .init()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsedString: String {
        let reference = lastEventAt ?? now
        let secs = max(0, Int(now.timeIntervalSince(reference)))
        if secs < 60 { return "\(secs)s" }
        let m = secs / 60
        let s = secs % 60
        return "\(m)m \(s)s"
    }

    private var label: String {
        if lastEventAt == nil {
            return "Starting agent…"
        }
        return "Working… (\(elapsedString) since last event)"
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .progressViewStyle(.circular)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onReceive(timer) { now = $0 }
    }
}
