import SwiftUI
import TermQCore

/// Main-pane Inspector for an agent session card.
///
/// Skeleton view shown when the selected card has `agentConfig != nil`.
/// Surfaces session config and a trajectory placeholder; real per-turn wire
/// (sensor results, editable feedback, controls) lands in later slices once
/// the loop driver subprocess plumbing exists.
struct AgentInspectorView: View {
    @ObservedObject var card: TerminalCard

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    configSection
                    trajectorySection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.title3.weight(.semibold))
                if let harness = card.agentConfig?.harness, !harness.isEmpty {
                    Text(harness)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let status = card.agentConfig?.status {
                StatusPill(status: status)
            }
            HStack(spacing: 8) {
                Button(action: {}) {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(true)
                .help("Loop driver not yet wired")
                Button(action: {}) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Config section

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration")
                .font(.headline)

            if let config = card.agentConfig {
                ConfigRow(label: "Backend", value: config.backend.rawValue)
                ConfigRow(label: "Mode", value: config.mode.rawValue)
                ConfigRow(label: "Interaction", value: config.interactionMode.rawValue)
                ConfigRow(
                    label: "Budget",
                    value:
                        "\(config.budget.maxTurns) turns · \(formatTokens(config.budget.maxTokens)) tokens · \(formatDuration(config.budget.maxWallSeconds))"
                )
                ConfigRow(label: "Session", value: config.sessionId.uuidString.prefix(8).description)
            }
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return "\(tokens / 1_000_000)M" }
        if tokens >= 1_000 { return "\(tokens / 1_000)k" }
        return "\(tokens)"
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600)h" }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    // MARK: - Trajectory placeholder

    private var trajectorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trajectory")
                .font(.headline)

            VStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No trajectory yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("The loop driver will emit per-turn sensor runs and feedback here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Subviews

private struct ConfigRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline.monospaced())
        }
    }
}

private struct StatusPill: View {
    let status: AgentStatus

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .idle: return "Idle"
        case .planning: return "Planning"
        case .awaitingPlanApproval: return "Plan approval"
        case .running: return "Running"
        case .awaitingTurnApproval: return "Turn approval"
        case .paused: return "Paused"
        case .converged: return "Converged"
        case .stuck: return "Stuck"
        case .errored: return "Errored"
        }
    }

    private var color: Color {
        switch status {
        case .idle: return .secondary
        case .planning, .running: return .accentColor
        case .awaitingPlanApproval, .awaitingTurnApproval, .paused: return .orange
        case .converged: return .green
        case .stuck, .errored: return .red
        }
    }
}
