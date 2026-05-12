import SwiftUI
import UniformTypeIdentifiers
import TermQCore

/// Sidebar content for the Agent Sessions tab.
///
/// Shows standalone sessions as individual rows and fleet sessions grouped
/// under a collapsible fleet header with aggregate status. A "New Fleet"
/// button in the header opens the fleet launch sheet.
struct AgentSessionsSidebarTab: View {
    @ObservedObject var boardViewModel: BoardViewModel
    @State private var showingFleetLaunch = false
    @State private var expandedFleets: Set<UUID> = []
    @State private var showingTranscriptImporter = false
    @State private var transcriptViewerEvents: [TrajectoryEvent]?
    @State private var transcriptViewerFileName: String = ""

    private var agentCards: [TerminalCard] {
        boardViewModel.board.cards
            .filter { $0.agentConfig != nil && !$0.isDeleted }
    }

    /// Cards not in any fleet.
    private var standaloneCards: [TerminalCard] {
        agentCards
            .filter { $0.agentConfig?.fleetId == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Fleet groups: keyed by fleetId, sorted by the first card's title.
    private var fleetGroups: [(id: UUID, cards: [TerminalCard])] {
        var groups: [UUID: [TerminalCard]] = [:]
        for card in agentCards {
            guard let fid = card.agentConfig?.fleetId else { continue }
            groups[fid, default: []].append(card)
        }
        return groups
            .map { (id: $0.key, cards: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.cards.first?.title ?? "" < $1.cards.first?.title ?? "" }
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
        .sheet(isPresented: $showingFleetLaunch) {
            AgentFleetLaunchSheet(
                boardViewModel: boardViewModel,
                onDismiss: { showingFleetLaunch = false }
            )
        }
        .sheet(isPresented: Binding(
            get: { transcriptViewerEvents != nil },
            set: { if !$0 { transcriptViewerEvents = nil } }
        )) {
            if let events = transcriptViewerEvents {
                AgentTranscriptViewerView(
                    events: events,
                    fileName: transcriptViewerFileName,
                    onDismiss: { transcriptViewerEvents = nil }
                )
            }
        }
        .fileImporter(
            isPresented: $showingTranscriptImporter,
            allowedContentTypes: [.plainText, .json, UTType(filenameExtension: "jsonl") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let events = AgentTranscriptViewerView.loadEvents(from: url) {
                transcriptViewerFileName = url.lastPathComponent
                transcriptViewerEvents = events
            }
        }
    }

    private var header: some View {
        HStack {
            Text(Strings.Fleet.sidebarTitle)
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
            Button {
                showingTranscriptImporter = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .help(Strings.Fleet.openTranscriptHelp)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button {
                showingFleetLaunch = true
            } label: {
                Image(systemName: "square.stack.3d.up.badge.automatic")
                    .help(Strings.Fleet.newFleetHelp)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
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
            Text(Strings.Fleet.emptyTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(Strings.Fleet.emptyBody)
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
                ForEach(fleetGroups, id: \.id) { group in
                    FleetGroupView(
                        fleetId: group.id,
                        cards: group.cards,
                        isExpanded: expandedFleets.contains(group.id),
                        selectedCardId: boardViewModel.selectedCard?.id,
                        onToggle: { toggleFleet(group.id) },
                        onSelect: { boardViewModel.selectCard($0) },
                        onPromote: { boardViewModel.selectCard($0) }
                    )
                }

                ForEach(standaloneCards) { card in
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

    private func toggleFleet(_ id: UUID) {
        if expandedFleets.contains(id) {
            expandedFleets.remove(id)
        } else {
            expandedFleets.insert(id)
        }
    }
}

// MARK: - Fleet group

private struct FleetGroupView: View {
    @ObservedObject var cards: ObservableCardList
    let fleetId: UUID
    let isExpanded: Bool
    let selectedCardId: UUID?
    let onToggle: () -> Void
    let onSelect: (TerminalCard) -> Void
    let onPromote: (TerminalCard) -> Void

    init(
        fleetId: UUID,
        cards: [TerminalCard],
        isExpanded: Bool,
        selectedCardId: UUID?,
        onToggle: @escaping () -> Void,
        onSelect: @escaping (TerminalCard) -> Void,
        onPromote: @escaping (TerminalCard) -> Void
    ) {
        self.fleetId = fleetId
        self.cards = ObservableCardList(cards)
        self.isExpanded = isExpanded
        self.selectedCardId = selectedCardId
        self.onToggle = onToggle
        self.onSelect = onSelect
        self.onPromote = onPromote
    }

    private var convergedCards: [TerminalCard] {
        cards.items.filter { $0.agentConfig?.status == .converged }
    }

    private var aggregateStatus: String {
        let running = cards.items.filter {
            if case .running = $0.agentConfig?.status { return true }
            return $0.agentConfig?.status == .running
        }.count
        let converged = convergedCards.count
        let total = cards.items.count

        if converged > 0 {
            return Strings.Fleet.aggregateConverged(converged, total)
        } else if running > 0 {
            return Strings.Fleet.aggregateRunning(running, total)
        } else {
            return Strings.Fleet.aggregateIdle(total)
        }
    }

    private var aggregateColor: Color {
        if !convergedCards.isEmpty { return .green }
        let hasRunning = cards.items.contains {
            $0.agentConfig?.status == .running
                || $0.agentConfig?.status == .awaitingTurnApproval
                || $0.agentConfig?.status == .awaitingPlanApproval
        }
        if hasRunning { return .accentColor }
        let hasError = cards.items.contains {
            $0.agentConfig?.status == .errored || $0.agentConfig?.status == .stuck
        }
        if hasError { return .red }
        return .secondary
    }

    var body: some View {
        VStack(spacing: 0) {
            fleetHeader
            if isExpanded {
                ForEach(cards.items) { card in
                    AgentSessionRow(
                        card: card,
                        isSelected: selectedCardId == card.id,
                        onSelect: { onSelect(card) },
                        indent: true
                    )
                }
                if !convergedCards.isEmpty {
                    promoteSection
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var fleetHeader: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                Image(systemName: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(aggregateColor)

                Text(Strings.Fleet.fleetLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                Text(aggregateStatus)
                    .font(.caption2)
                    .foregroundStyle(aggregateColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var promoteSection: some View {
        VStack(spacing: 2) {
            ForEach(convergedCards) { card in
                Button {
                    onPromote(card)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(Strings.Fleet.promoteWinner(card.title))
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(Color.green.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 0)
    }
}

/// Thin wrapper so `FleetGroupView` can observe card changes via `@ObservedObject`.
private final class ObservableCardList: ObservableObject {
    @Published var items: [TerminalCard]
    init(_ cards: [TerminalCard]) { self.items = cards }
}

// MARK: - Session row

struct AgentSessionRow: View {
    @ObservedObject var card: TerminalCard
    let isSelected: Bool
    let onSelect: () -> Void
    var indent: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                if indent {
                    Spacer().frame(width: 12)
                }
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

// MARK: - Status badge

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
