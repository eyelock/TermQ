import SwiftUI
import TermQCore

// MARK: - Wire types (ynh sensors ls / show JSON surface)

private struct SensorListEntry: Decodable, Identifiable {
    let name: String
    let category: String?
    let role: String?
    let sourceKind: String
    let format: String
    let inlineFocus: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, category, role, format
        case sourceKind = "source_kind"
        case inlineFocus = "inline_focus"
    }
}

private struct SensorShowEntry: Decodable {
    let name: String
    let role: String?
    let source: Source

    struct Source: Decodable {
        let command: String?
        let focus: Focus?
    }

    struct Focus: Decodable {
        let prompt: String
        let profile: String?
    }
}

// MARK: - View model

@MainActor
private final class OverlayEditorModel: ObservableObject {
    enum LoadState { case loading, loaded, failed(String) }

    @Published var sensors: [SensorListEntry] = []
    @Published var details: [String: SensorShowEntry] = [:]
    @Published var overlays: SensorOverlays = [:]
    @Published var loadState: LoadState = .loading

    let harness: String
    let sessionId: UUID

    init(harness: String, sessionId: UUID) {
        self.harness = harness
        self.sessionId = sessionId
    }

    func load() async {
        overlays = SensorOverlayStore.load(for: sessionId)

        guard case .ready(let ynhPath, _, _) = YNHDetector.shared.status else {
            loadState = .failed(Strings.OverlayEditor.errorYnhNotReady)
            return
        }

        do {
            let listResult = try await CommandRunner.run(
                executable: ynhPath,
                arguments: ["sensors", "ls", harness, "--format", "json"]
            )
            let decoder = JSONDecoder()
            let list = try decoder.decode(
                [SensorListEntry].self, from: Data(listResult.stdout.utf8))
            sensors = list

            for sensor in list where sensor.sourceKind == "focus" {
                if let detail = try? await fetchDetail(sensor.name, ynhPath: ynhPath) {
                    details[sensor.name] = detail
                }
            }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func fetchDetail(_ name: String, ynhPath: String) async throws -> SensorShowEntry {
        let result = try await CommandRunner.run(
            executable: ynhPath,
            arguments: ["sensors", "show", harness, name, "--format", "json"]
        )
        return try JSONDecoder().decode(SensorShowEntry.self, from: Data(result.stdout.utf8))
    }

    func save() {
        SensorOverlayStore.save(overlays.filter { !$0.value.isEmpty }, for: sessionId)
    }

    func focusPrompt(for name: String) -> String {
        overlays[name]?.source?.focus?.prompt ?? ""
    }

    func setFocusPrompt(_ prompt: String, for name: String) {
        var overlay = overlays[name] ?? SensorOverlay()
        overlay.source = prompt.isEmpty
            ? nil
            : SensorOverlaySource(focus: SensorOverlayFocus(prompt: prompt))
        overlays[name] = overlay.isEmpty ? nil : overlay
    }

    func role(for name: String) -> String {
        overlays[name]?.role ?? ""
    }

    func setRole(_ role: String, for name: String) {
        var overlay = overlays[name] ?? SensorOverlay()
        overlay.role = role.isEmpty ? nil : role
        overlays[name] = overlay.isEmpty ? nil : overlay
    }
}

// MARK: - Main view

struct AgentSensorOverlayEditorView: View {
    let harness: String
    let sessionId: UUID
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: OverlayEditorModel

    init(harness: String, sessionId: UUID) {
        self.harness = harness
        self.sessionId = sessionId
        _model = StateObject(
            wrappedValue: OverlayEditorModel(harness: harness, sessionId: sessionId))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { await model.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.OverlayEditor.title)
                    .font(.headline)
                Text(harness)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(Strings.OverlayEditor.loading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded:
            if model.sensors.isEmpty {
                Text(Strings.OverlayEditor.noSensors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.sensors) { sensor in
                            SensorOverlayRow(
                                sensor: sensor,
                                detail: model.details[sensor.name],
                                focusPrompt: model.focusPrompt(for: sensor.name),
                                role: model.role(for: sensor.name),
                                onFocusPromptChange: { model.setFocusPrompt($0, for: sensor.name) },
                                onRoleChange: { model.setRole($0, for: sensor.name) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(Strings.OverlayEditor.cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(Strings.OverlayEditor.save) {
                model.save()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled({
                if case .loaded = model.loadState { return false }
                return true
            }())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Sensor overlay row

private struct SensorOverlayRow: View {
    let sensor: SensorListEntry
    let detail: SensorShowEntry?
    let focusPrompt: String
    let role: String
    let onFocusPromptChange: (String) -> Void
    let onRoleChange: (String) -> Void

    private static let roles = ["", "regular", "convergence-verifier", "stuck-recovery"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(sensor.name)
                    .font(.subheadline.weight(.medium))
                SourceKindBadge(kind: sensor.sourceKind, inlineFocus: sensor.inlineFocus)
                Spacer()
                rolePicker
            }

            if sensor.sourceKind == "focus" {
                focusPromptEditor
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var rolePicker: some View {
        Picker(Strings.OverlayEditor.roleLabel, selection: Binding(
            get: { role },
            set: { onRoleChange($0) }
        )) {
            Text(Strings.OverlayEditor.roleInherited).tag("")
            ForEach(Self.roles.dropFirst(), id: \.self) { r in
                Text(r).tag(r)
            }
        }
        .labelsHidden()
        .frame(width: 180)
    }

    private var focusPromptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let harnessPrompt = detail?.source.focus?.prompt {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.OverlayEditor.promptHarnessLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(harnessPrompt)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.OverlayEditor.promptOverrideLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { focusPrompt },
                    set: { onFocusPromptChange($0) }
                ))
                .font(.callout)
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                if focusPrompt.isEmpty {
                    Text(Strings.OverlayEditor.promptOverridePlaceholder)
                        .font(.callout)
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: -80)
                        .frame(height: 0)
                }
            }
        }
    }
}

// MARK: - Source kind badge

private struct SourceKindBadge: View {
    let kind: String
    let inlineFocus: Bool

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch kind {
        case "focus": return inlineFocus
            ? Strings.OverlayEditor.sourceKindFocus + "*"
            : Strings.OverlayEditor.sourceKindFocus
        case "command": return Strings.OverlayEditor.sourceKindCommand
        default: return Strings.OverlayEditor.sourceKindFiles
        }
    }

    private var color: Color {
        switch kind {
        case "focus": return .purple
        case "command": return .blue
        default: return .orange
        }
    }
}
