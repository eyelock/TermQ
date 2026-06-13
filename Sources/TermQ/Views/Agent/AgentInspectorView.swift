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
    @State private var showingRunSheet = false

    private var controller: AgentSessionController {
        registry.controller(for: card.id)
    }

    /// Default loop driver command — TermQ runs `ynh agent` from PATH unless
    /// the user has explicitly overridden the binary globally or per-card.
    static let defaultLoopDriverCommand = "ynh agent"

    /// Resolution: per-card override > global UserDefault > built-in default.
    /// Empty per-card and empty global both fall through to `ynh agent`.
    private var effectiveCommand: String {
        Self.effectiveCommand(card: card, globalOverride: globalLoopDriverCommand)
    }

    /// File-static so non-AgentInspectorView call sites (sidebar context
    /// menu Run, fleet launchers) can build the same command line without
    /// instantiating an Inspector. `globalOverride` is the value of the
    /// `agent.loopDriverCommand` UserDefault.
    static func effectiveCommand(card: TerminalCard, globalOverride: String) -> String {
        let perCard =
            card.agentConfig?.loopDriverCommand.trimmingCharacters(in: .whitespaces) ?? ""
        if !perCard.isEmpty { return perCard }
        let global = globalOverride.trimmingCharacters(in: .whitespaces)
        if !global.isEmpty { return global }
        return defaultLoopDriverCommand
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let lastError = controller.lastError {
                        errorSection(lastError)
                    }
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
        .sheet(isPresented: $showingRunSheet) {
            RunWithFocusSheet(
                mode: .agent(card: card),
                onLaunch: { payload in
                    if case .agent(_, _, let focus, let profile, let prompt) = payload {
                        let command = buildAgentCommand(
                            focus: focus, profile: profile, prompt: prompt
                        )
                        Task { try? await controller.start(command: command) }
                    }
                    showingRunSheet = false
                },
                // The payload's `prompt` is non-nil only when no focus was
                // selected (or when Customize was used to override one).
                // When `focus` is set, prompt is nil and the command builder
                // passes `--focus <name>` instead.
                onCancel: { showingRunSheet = false }
            )
        }
    }

    /// Build the `ynh agent run …` invocation from the card's locked config
    /// (harness, backend) plus the per-launch focus/profile/prompt the user
    /// just picked. Returns a shell-ready command string. The controller
    /// appends `--sensor-overlay '…'` when overlays exist; no need to add
    /// it here.
    ///
    /// Argument shape (mirrors `ynh run`'s mutual-exclusion rules):
    /// - `focus` non-nil → `--focus <name>` (focus carries prompt + profile;
    ///   profile arg is not added and a separate prompt is ignored)
    /// - otherwise → `--task <prompt>` plus optional `--profile <name>`
    private func buildAgentCommand(focus: String?, profile: String?, prompt: String?) -> String {
        Self.buildAgentCommand(
            card: card,
            globalLoopDriverCommand: globalLoopDriverCommand,
            focus: focus, profile: profile, prompt: prompt
        )
    }

    /// File-static so the sidebar context menu's Run flow can build the
    /// exact same command line. See instance overload's doc comment for
    /// argument shape.
    static func buildAgentCommand(
        card: TerminalCard,
        globalLoopDriverCommand: String = UserDefaults.standard.string(
            forKey: "agent.loopDriverCommand") ?? "",
        focus: String?, profile: String?, prompt: String?
    ) -> String {
        let cmd = effectiveCommand(card: card, globalOverride: globalLoopDriverCommand)
        guard let cfg = card.agentConfig else { return cmd }
        var parts: [String] = [cmd, "run", "--harness", shellQuote(cfg.harness)]
        let backend = cfg.backend.rawValue
        if !backend.isEmpty {
            parts.append(contentsOf: ["--backend", shellQuote(backend)])
        }
        // Budget: pass non-default values through. ynh agent run accepts
        // --max-turns, --max-tokens, --max-wall (e.g. "60m").
        parts.append(contentsOf: ["--max-turns", String(cfg.budget.maxTurns)])
        parts.append(contentsOf: ["--max-tokens", String(cfg.budget.maxTokens)])
        let wallMinutes = max(1, cfg.budget.maxWallSeconds / 60)
        parts.append(contentsOf: ["--max-wall", "\(wallMinutes)m"])

        // Per-turn approval gates: ynh emits turn_approval_required events
        // and reads NDJSON ControlMessages from stdin when --interactive is
        // set. ynh 0.5+ also emits dedicated plan_approval_required /
        // plan_revised events for the plan phase.
        if cfg.interactionMode == .confirm {
            parts.append("--interactive")
        }

        // Plan-iteration cap (ynh 0.5+). Older ynh ignores the flag.
        if cfg.budget.maxPlanIterations > 0 {
            parts.append(contentsOf: [
                "--max-plan-iterations", String(cfg.budget.maxPlanIterations),
            ])
        }

        if let focus, !focus.isEmpty {
            parts.append(contentsOf: ["--focus", shellQuote(focus)])
        } else {
            if let profile, !profile.isEmpty {
                parts.append(contentsOf: ["--profile", shellQuote(profile)])
            }
            if let prompt, !prompt.isEmpty {
                parts.append(contentsOf: ["--task", shellQuote(prompt)])
            }
        }
        return parts.joined(separator: " ")
    }

    /// Single-quote-wrap with internal single quotes escaped — safe for
    /// `/bin/sh -c`.
    static func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// The plan content awaiting approval. ynh 0.5+ emits a dedicated
    /// `plan_approval_required` event with the plan in its `plan` field;
    /// pre-0.5 ynh emitted it as `synthesized_feedback` on a
    /// `turn_approval_required` event with `turn=0`. The walk takes
    /// whichever arrived most recently — covers both wire versions and
    /// keeps the latest iteration visible during refine loops.
    private var pendingPlanContent: String? {
        guard card.agentConfig?.status == .awaitingPlanApproval else { return nil }
        for event in controller.events.reversed() {
            switch event.decoded() {
            case .planApprovalRequired(let plan, _):
                return plan
            case .turnApprovalRequired(let turn, let feedback) where turn == 0:
                return feedback
            case .plan(let content) where !content.isEmpty:
                return content
            default:
                continue
            }
        }
        return nil
    }

    /// The latest `turn_approval_required` event, surfaced only while the
    /// card is in `.awaitingTurnApproval`. Returns `nil` otherwise.
    private var pendingTurnApproval: (turn: Int, feedback: String)? {
        guard card.agentConfig?.status == .awaitingTurnApproval else { return nil }
        for event in controller.events.reversed() {
            if case .turnApprovalRequired(let turn, let feedback) = event.decoded(),
                turn > 0
            {
                return (turn, feedback)
            }
        }
        return nil
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
                    showingRunSheet = true
                } label: {
                    Label("Run…", systemImage: "play.fill")
                }
                .disabled(isRunning || (card.agentConfig?.harness.isEmpty ?? true))
                .help("Pick a focus or write a task, then run")
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
                let budgetValue =
                    "\(config.budget.maxTurns) turns"
                    + " · \(formatTokens(config.budget.maxTokens)) tokens"
                    + " · \(formatDuration(config.budget.maxWallSeconds))"
                ConfigRow(label: "Budget", value: budgetValue)
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

    // MARK: - Error banner

    @ViewBuilder
    private func errorSection(_ error: AgentSessionController.LastError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Loop driver failed")
                    .font(.headline)
                Spacer()
                if let code = error.exitCode {
                    Text("exit \(code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(error.stderrTail, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy stderr to clipboard")
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Command:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(error.resolvedCommand)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            if error.stderrTail.isEmpty {
                Text(
                    "No stderr output — the driver exited without writing diagnostics. "
                        + "Check that the command resolves on your PATH and try running it "
                        + "manually in a terminal to see what it does."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    Text(error.stderrTail)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 180)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Plan approval

    private func planApprovalSection(content: String) -> some View {
        PlanApprovalSection(
            content: content,
            iteration: latestPlanIteration,
            onApprove: { Task { await controller.approvePlan() } },
            onReject: { Task { await controller.rejectPlan() } },
            onRefine: { notes in Task { await controller.refinePlan(notes: notes) } }
        )
    }

    /// Iteration number of the most recent plan_approval_required event,
    /// or 1 if the only signal is the legacy turn=0 turn_approval_required
    /// path. Surfaced in the banner header so users see the refine loop.
    private var latestPlanIteration: Int {
        for event in controller.events.reversed() {
            if case .planApprovalRequired(_, let iteration) = event.decoded() {
                return iteration
            }
        }
        return 1
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

            // Process is alive AND the card isn't sitting on a human gate.
            // ynh is technically still "running" while blocked on stdin for
            // approval, but from the user's perspective nothing's happening
            // — they're the bottleneck — so "Working…" would be misleading.
            let isRunning: Bool = {
                guard case .running = controller.status else { return false }
                switch card.agentConfig?.status {
                case .awaitingPlanApproval, .awaitingTurnApproval:
                    return false
                default:
                    return true
                }
            }()

            if controller.events.isEmpty && !isRunning {
                trajectoryEmptyState
            } else if !controller.events.isEmpty {
                turnGroupedList
            }

            if isRunning {
                AgentWorkingFooter(
                    lastEventAt: controller.events.last?.timestamp
                )
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
            Text("Press Run to spawn the loop driver.")
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

// MARK: - Plan approval section

private struct PlanApprovalSection: View {
    let content: String
    let iteration: Int
    let onApprove: () -> Void
    let onReject: () -> Void
    let onRefine: (String) -> Void

    @State private var refineNotes: String = ""
    @State private var refineExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.orange)
                Text("Plan ready for review")
                    .font(.headline)
                if iteration > 1 {
                    Text("iteration \(iteration)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(Capsule())
                }
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

            if refineExpanded {
                TextEditor(text: $refineNotes)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 70, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            HStack(spacing: 8) {
                Button {
                    onReject()
                } label: {
                    Label("Reject", systemImage: "xmark")
                }
                Spacer()
                if refineExpanded {
                    Button("Cancel") {
                        refineExpanded = false
                        refineNotes = ""
                    }
                    Button {
                        let notes = refineNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !notes.isEmpty else { return }
                        onRefine(notes)
                        refineExpanded = false
                        refineNotes = ""
                    } label: {
                        Label("Send refinement", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(
                        refineNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button {
                        refineExpanded = true
                    } label: {
                        Label("Refine…", systemImage: "pencil")
                    }
                    Button {
                        onApprove()
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .keyboardShortcut(.defaultAction)
                }
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
        case .paused: return "Stopped"
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
