import SwiftUI
import TermQShared

// MARK: - Shared sheet result types

struct MCPAddResult {
    let name: String
    let command: String?
    let args: [String]
    let url: String?
}

// MARK: - AddHookSheet (shared by profile and harness editors)

/// Reusable "Add Hook" sheet. Used at both harness and profile level so
/// improvements flow to both surfaces at once.
struct AddHookSheet: View {
    let onAdd: (String, String, String?) -> Void
    let onCancel: () -> Void

    @State private var event = "before_tool"
    @State private var command = ""
    @State private var matcher = ""

    private let hookEvents = ["before_tool", "after_tool", "before_prompt", "on_stop"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.Harnesses.addHookTitle)
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.hookEvent)
                    .frame(width: 70, alignment: .trailing)
                    .foregroundColor(.secondary)
                Picker("", selection: $event) {
                    ForEach(hookEvents, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.hookCommand)
                    .frame(width: 70, alignment: .trailing)
                    .foregroundColor(.secondary)
                TextField(Strings.Harnesses.hookCommandPlaceholder, text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.hookMatcher)
                    .frame(width: 70, alignment: .trailing)
                    .foregroundColor(.secondary)
                TextField(Strings.Harnesses.hookMatcherPlaceholder, text: $matcher)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            HStack {
                Spacer()
                Button(Strings.Harnesses.focusCancelButton) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(Strings.Harnesses.addHookButton) {
                    let trimmedMatcher = matcher.trimmingCharacters(in: .whitespaces)
                    onAdd(event, command, trimmedMatcher.isEmpty ? nil : trimmedMatcher)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - AddMCPSheet (shared by profile and harness editors)

/// Reusable "Add MCP Server" sheet. Used at both harness and profile level so
/// improvements flow to both surfaces at once.
struct AddMCPSheet: View {
    let title: String
    let onAdd: (MCPAddResult) -> Void
    let onCancel: () -> Void

    @State private var nameText = ""
    @State private var commandText = ""
    @State private var argsText = ""
    @State private var urlText = ""
    @State private var useURL = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            field(label: Strings.Harnesses.mcpServerName) {
                TextField(Strings.Harnesses.mcpServerNamePlaceholder, text: $nameText)
                    .textFieldStyle(.roundedBorder)
            }

            Picker(Strings.Harnesses.mcpServerType, selection: $useURL) {
                Text(Strings.Harnesses.mcpServerTypeCommand).tag(false)
                Text(Strings.Harnesses.mcpServerTypeURL).tag(true)
            }
            .pickerStyle(.segmented)

            if useURL {
                field(label: Strings.Harnesses.mcpServerURL) {
                    TextField("https://...", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            } else {
                field(label: Strings.Harnesses.mcpServerCommand) {
                    TextField("npx", text: $commandText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                field(label: Strings.Harnesses.mcpServerArgs) {
                    TextField(Strings.Harnesses.mcpServerArgsPlaceholder, text: $argsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                Text(Strings.Harnesses.mcpServerArgsHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 78)
            }

            HStack {
                Spacer()
                Button(Strings.Harnesses.focusCancelButton) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(Strings.Harnesses.addMCPButton) {
                    let args =
                        argsText.isEmpty
                        ? []
                        : argsText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    onAdd(
                        MCPAddResult(
                            name: nameText.trimmingCharacters(in: .whitespaces),
                            command: useURL ? nil : commandText.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                            args: args,
                            url: useURL ? urlText.trimmingCharacters(in: .whitespaces).nilIfEmpty : nil
                        ))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isAddDisabled)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var isAddDisabled: Bool {
        guard !nameText.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        if useURL { return urlText.trimmingCharacters(in: .whitespaces).isEmpty }
        return commandText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            content()
        }
    }
}

// MARK: - HarnessHookEditor

@MainActor
final class HarnessHookEditor: ObservableObject {
    @Published var isAddingHook = false
    @Published var isAddingMCP = false
    @Published var errorMessage: String?
    @Published private(set) var isMutating = false

    private let repository: HarnessRepository
    private let detector: any YNHDetectorProtocol
    private let mutator: HarnessHookMutator

    init(
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        repository: HarnessRepository = .shared,
        mutator: HarnessHookMutator = HarnessHookMutator()
    ) {
        self.detector = detector
        self.repository = repository
        self.mutator = mutator
    }

    func requestAddHook() {
        errorMessage = nil
        isAddingHook = true
    }

    func requestAddMCP() {
        errorMessage = nil
        isAddingMCP = true
    }

    func confirmAddHook(
        harnessID: String, event: String, command: String, matcher: String?
    ) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.addHook(
            HarnessHookAddOptions(harness: harnessID, event: event, command: command, matcher: matcher),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            isAddingHook = false
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func confirmRemoveHook(harnessID: String, event: String, index: Int) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.removeHook(
            HarnessHookRemoveOptions(harness: harnessID, event: event, index: index),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func confirmRemoveMCP(harnessID: String, serverName: String) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.removeMCP(
            HarnessMCPRemoveOptions(harness: harnessID, serverName: serverName),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func confirmAddMCP(harnessID: String, result: MCPAddResult) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.addMCP(
            HarnessMCPAddOptions(
                harness: harnessID,
                serverName: result.name,
                command: result.command,
                args: result.args,
                env: [:],
                url: result.url,
                headers: [:]
            ),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            isAddingMCP = false
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    private func reloadDetail(harnessID: String) async {
        repository.invalidateDetail(for: harnessID)
        await repository.fetchDetail(for: harnessID)
    }

    private func readyYnhPath() -> String? {
        if case .ready(let ynhPath, _, _) = detector.status { return ynhPath }
        errorMessage = "YNH toolchain is not ready"
        return nil
    }

    private func ynhEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = detector.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }
}

// MARK: - Overlay modifier

struct HarnessHookEditorOverlay: ViewModifier {
    @ObservedObject var editor: HarnessHookEditor
    let harnessID: String

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $editor.isAddingHook) {
                AddHookSheet(
                    onAdd: { event, command, matcher in
                        Task {
                            await editor.confirmAddHook(
                                harnessID: harnessID, event: event,
                                command: command, matcher: matcher
                            )
                        }
                    },
                    onCancel: { editor.isAddingHook = false }
                )
            }
            .sheet(isPresented: $editor.isAddingMCP) {
                AddMCPSheet(
                    title: Strings.Harnesses.addMCPTitle,
                    onAdd: { result in
                        Task { await editor.confirmAddMCP(harnessID: harnessID, result: result) }
                    },
                    onCancel: { editor.isAddingMCP = false }
                )
            }
            .alert(
                Strings.Alert.error,
                isPresented: Binding(
                    get: { editor.errorMessage != nil },
                    set: { if !$0 { editor.errorMessage = nil } }
                )
            ) {
                Button(Strings.Common.ok) { editor.errorMessage = nil }
            } message: {
                Text(editor.errorMessage ?? "")
            }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
