import SwiftUI
import TermQCore

/// Sidebar content for the Agent Sessions tab.
///
/// Lists cards on the current board that are acting as agent sessions
/// (i.e. `agentConfig != nil` and not soft-deleted). Empty state shown when
/// no agent sessions exist. Live launch UI lands in a later slice.
struct AgentSessionsSidebarTab: View {
    @ObservedObject var boardViewModel: BoardViewModel

    private var agentCards: [TerminalCard] {
        boardViewModel.board.cards
            .filter { $0.agentConfig != nil && !$0.isDeleted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if agentCards.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Agent Sessions")
                .font(.headline)
            Spacer()
            if !agentCards.isEmpty {
                Text("\(agentCards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No agent sessions yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Start one from a harness to drive a loop of edits → sensors → feedback.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(agentCards) { card in
                    AgentSessionRow(
                        card: card,
                        isSelected: boardViewModel.selectedCard?.id == card.id,
                        onSelect: { boardViewModel.selectCard(card) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// One row in the Agent Sessions sidebar list.
private struct AgentSessionRow: View {
    @ObservedObject var card: TerminalCard
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.body)
                        .lineLimit(1)
                    if let harness = card.agentConfig?.harness, !harness.isEmpty {
                        Text(harness)
                            .font(.caption)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let status = card.agentConfig?.status {
                    StatusBadge(status: status)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

private struct StatusBadge: View {
    let status: AgentStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .idle: return "idle"
        case .planning: return "planning"
        case .awaitingPlanApproval: return "plan?"
        case .running: return "running"
        case .awaitingTurnApproval: return "turn?"
        case .paused: return "paused"
        case .converged: return "done"
        case .stuck: return "stuck"
        case .errored: return "error"
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
