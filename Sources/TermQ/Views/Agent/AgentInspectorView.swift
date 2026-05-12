import SwiftUI
import TermQCore

/// Main-pane Inspector for an agent session card.
///
/// Shown when the selected card has `agentConfig != nil`. Surfaces session
/// config and live trajectory events streamed from an `AgentSessionController`.
/// The Run button spawns `/bin/sh -c "$cmd"` where `$cmd` is the value of the
/// `agent.loopDriverCommand` UserDefaults key (typically the path to
/// `ynh-agent` plus its arguments, but any command emitting NDJSON to stdout
/// works — useful for development against a stub).
struct AgentInspectorView: View {
    @ObservedObject var card: TerminalCard
    @StateObject private var registry = AgentSessionRegistry.shared
    @AppStorage("agent.loopDriverCommand") private var globalLoopDriverCommand: String = ""
    @State private var showingOverlayEditor = false

    private var controller: AgentSessionController {
        registry.controller(for: card.id)
    }

    /// Per-card override wins; empty falls back to the global default.
    private var effectiveCommand: String {
        let perCard =
            card.agentConfig?.loopDriverCommand.trimmingCharacters(in: .whitespaces) ?? ""
        return perCard.isEmpty ? globalLoopDriverCommand : perCard
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let planContent = pendingPlanContent {
                        planApprovalSection(content: planContent)
                    }
                    if let approval = pendingTurnApproval {
                        TurnApprovalSection(
                            turn: approval.turn,
                            feedback: approval.feedback
                        ) { edited in
                            await controller.approveTurn(feedback: edited)
                        }
                    }
                    configSection
                    if !lastSensorResults.isEmpty {
                        lastSensorsSection
                    }
                    trajectorySection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            controller.loadPersistedEvents()
        }
        .onChange(of: card.id) { _, _ in
            controller.loadPersistedEvents()
        }
        .sheet(isPresented: $showingOverlayEditor) {
            if let config = card.agentConfig {
                AgentSensorOverlayEditorView(
                    harness: config.harness,
                    sessionId: config.sessionId
                )
            }
        }
    }

    /// The latest `plan` event's content, surfaced only while the card is
    /// in the `.awaitingPlanApproval` state. Returns `nil` outside that
    /// state — the section disappears once the user approves or rejects.
    private var pendingPlanContent: String? {
        guard card.agentConfig?.status == .awaitingPlanApproval else { return nil }
        for event in controller.events.reversed() {
            if case .plan(let content) = event.decoded() { return content }
        }
        return nil
    }

    /// The latest `turn_approval_required` event, surfaced only while the
    /// card is in `.awaitingTurnApproval`. Returns `nil` otherwise.
    private var pendingTurnApproval: (turn: Int, feedback: String)? {
        guard card.agentConfig?.status == .awaitingTurnApproval else { return nil }
        for event in controller.events.reversed() {
            if case .turnApprovalRequired(let turn, let feedback) = event.decoded() {
                return (turn, feedback)
            }
        }
        return nil
    }

    private var canRun: Bool {
        !effectiveCommand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isRunning: Bool {
        if case .running = controller.status { return true }
        return false
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
                Button {
                    showingOverlayEditor = true
                } label: {
                    Label(Strings.Inspector.Agent.editSensors, systemImage: "slider.horizontal.3")
                }
                .disabled(card.agentConfig?.harness.isEmpty ?? true)
                .help(Strings.Inspector.Agent.editSensors)

                Divider().frame(height: 16)

                Button {
                    Task { try? await controller.start(command: effectiveCommand) }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(!canRun || isRunning)
                .help(
                    canRun
                        ? "Spawn the configured loop driver"
                        : "Set agent.loopDriverCommand globally or override per-card in the editor")
                Button {
                    Task { await controller.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!isRunning)
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

    // MARK: - Plan approval

    private func planApprovalSection(content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.orange)
                Text("Plan ready for review")
                    .font(.headline)
                Spacer()
            }

            ScrollView {
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxHeight: 320)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Spacer()
                Button {
                    Task { await controller.rejectPlan() }
                } label: {
                    Label("Reject", systemImage: "xmark")
                }
                Button {
                    Task { await controller.approvePlan() }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Last sensors strip

    /// Sensor results from the most recent turn that produced any.
    private var lastSensorResults: [SensorRunSummary] {
        for group in turnGroups.reversed() {
            let results = group.sensorResults
            if !results.isEmpty { return results }
        }
        return []
    }

    private var lastSensorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Sensors")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(lastSensorResults.enumerated()), id: \.offset) { i, r in
                    SensorResultRow(
                        name: r.name, exitCode: r.exitCode,
                        durationMs: r.durationMs, summary: r.summary)
                    if i < lastSensorResults.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Trajectory

    private var turnGroups: [TurnGroup] {
        buildTurnGroups(from: controller.events)
    }

    private var trajectorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trajectory")
                    .font(.headline)
                Spacer()
                if !controller.events.isEmpty {
                    Text("\(controller.events.count) event\(controller.events.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if controller.events.isEmpty {
                trajectoryEmptyState
            } else {
                turnGroupedList
            }
        }
    }

    private var trajectoryEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No trajectory yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(
                canRun
                    ? "Press Run to spawn the configured loop driver."
                    : "Configure agent.loopDriverCommand in defaults, then press Run."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var turnGroupedList: some View {
        VStack(spacing: 0) {
            ForEach(turnGroups) { group in
                TurnGroupView(group: group)
            }
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Turn approval section

private struct TurnApprovalSection: View {
    let turn: Int
    let feedback: String
    let onSend: (String) async -> Void

    @State private var editedFeedback: String

    init(turn: Int, feedback: String, onSend: @escaping (String) async -> Void) {
        self.turn = turn
        self.feedback = feedback
        self.onSend = onSend
        _editedFeedback = State(initialValue: feedback)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.blue)
                Text(Strings.Inspector.Agent.turnApprovalTitle(turn))
                    .font(.headline)
                Spacer()
            }

            TextEditor(text: $editedFeedback)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack(spacing: 8) {
                if editedFeedback != feedback {
                    Button(Strings.Inspector.Agent.turnApprovalReset) {
                        editedFeedback = feedback
                    }
                }
                Spacer()
                Button(Strings.Inspector.Agent.turnApprovalSend) {
                    Task { await onSend(editedFeedback) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
