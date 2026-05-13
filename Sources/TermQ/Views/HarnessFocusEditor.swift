import SwiftUI
import TermQShared

struct FocusEditTarget: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let prompt: String
    let profile: String?
}

@MainActor
final class HarnessFocusEditor: ObservableObject {
    @Published var editingTarget: FocusEditTarget?
    @Published var removalTarget: FocusEditTarget?
    @Published var isAddingFocus = false
    @Published private(set) var isMutating = false
    @Published var errorMessage: String?

    private let repository: HarnessRepository
    private let detector: any YNHDetectorProtocol
    private let mutator: FocusMutator

    init(
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        repository: HarnessRepository = .shared,
        mutator: FocusMutator = FocusMutator()
    ) {
        self.detector = detector
        self.repository = repository
        self.mutator = mutator
    }

    func requestAdd() {
        errorMessage = nil
        isAddingFocus = true
    }

    func requestEdit(_ target: FocusEditTarget) {
        errorMessage = nil
        editingTarget = target
    }

    func requestRemove(_ target: FocusEditTarget) {
        errorMessage = nil
        removalTarget = target
    }

    func confirmAdd(harnessID: String, name: String, prompt: String, profile: String?) async {
        guard let ynhPath = readyYnhPath() else { return }
        let opts = FocusAddOptions(
            harness: harnessID, name: name, prompt: prompt,
            profile: profile.flatMap { $0.isEmpty ? nil : $0 }
        )
        isMutating = true
        await mutator.add(opts, ynhPath: ynhPath, environment: ynhEnvironment())
        isMutating = false

        if mutator.succeeded {
            isAddingFocus = false
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func confirmRemove(target: FocusRemoveOptions, harnessID: String) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.remove(target, ynhPath: ynhPath, environment: ynhEnvironment())
        isMutating = false

        if mutator.succeeded {
            removalTarget = nil
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func confirmEdit(harnessID: String, newPrompt: String?, newProfile: String?, clearProfile: Bool) async {
        guard let target = editingTarget, let ynhPath = readyYnhPath() else { return }
        let opts = FocusUpdateOptions(
            harness: harnessID, name: target.name,
            prompt: newPrompt,
            profile: clearProfile ? nil : newProfile,
            clearProfile: clearProfile
        )
        isMutating = true
        await mutator.update(opts, ynhPath: ynhPath, environment: ynhEnvironment())
        isMutating = false

        if mutator.succeeded {
            editingTarget = nil
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
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

    private func reloadDetail(harnessID: String) async {
        repository.invalidateDetail(for: harnessID)
        await repository.fetchDetail(for: harnessID)
    }
}

// MARK: - Add Focus Sheet

struct AddFocusSheet: View {
    @ObservedObject var editor: HarnessFocusEditor
    let harnessID: String
    let availableProfiles: [String]

    @State private var nameText = ""
    @State private var promptText = ""
    @State private var selectedProfile = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Strings.Harnesses.addFocusTitle)
                .font(.headline)

            LabeledField(label: Strings.Harnesses.focusName) {
                TextField(Strings.Harnesses.focusNamePlaceholder, text: $nameText)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledField(label: Strings.Harnesses.focusPrompt) {
                TextEditor(text: $promptText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            if !availableProfiles.isEmpty {
                LabeledField(label: Strings.Harnesses.focusProfile) {
                    HStack {
                        Picker("", selection: $selectedProfile) {
                            Text(Strings.Harnesses.focusProfileNone).tag("")
                            ForEach(availableProfiles, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                        Spacer()
                    }
                }
            }

            if let error = editor.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(Strings.Harnesses.focusCancelButton) {
                    editor.isAddingFocus = false
                    editor.errorMessage = nil
                }
                .keyboardShortcut(.cancelAction)

                Button(Strings.Harnesses.focusAddButton) {
                    Task {
                        await editor.confirmAdd(
                            harnessID: harnessID,
                            name: nameText.trimmingCharacters(in: .whitespaces),
                            prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines),
                            profile: selectedProfile.isEmpty ? nil : selectedProfile
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    nameText.trimmingCharacters(in: .whitespaces).isEmpty
                        || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editor.isMutating)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

// MARK: - Edit Focus Sheet

struct EditFocusSheet: View {
    @ObservedObject var editor: HarnessFocusEditor
    let harnessID: String
    let target: FocusEditTarget
    let availableProfiles: [String]

    @State private var promptText = ""
    @State private var selectedProfile = ""
    @State private var clearProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Strings.Harnesses.editFocusTitle)
                .font(.headline)

            LabeledField(label: Strings.Harnesses.focusName) {
                Text(target.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            LabeledField(label: Strings.Harnesses.focusPrompt) {
                TextEditor(text: $promptText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            LabeledField(label: Strings.Harnesses.focusProfile) {
                HStack {
                    Picker("", selection: $selectedProfile) {
                        Text(Strings.Harnesses.focusProfileNone).tag("")
                        ForEach(availableProfiles, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                    .disabled(clearProfile)
                    Spacer()
                }

                if target.profile != nil {
                    Toggle(Strings.Harnesses.focusClearProfile, isOn: $clearProfile)
                        .font(.caption)
                        .onChange(of: clearProfile) { _, on in
                            if on { selectedProfile = "" }
                        }
                }
            }

            if let error = editor.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(Strings.Harnesses.focusCancelButton) {
                    editor.editingTarget = nil
                    editor.errorMessage = nil
                }
                .keyboardShortcut(.cancelAction)

                Button(Strings.Harnesses.focusSaveButton) {
                    let updatedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let promptChanged = updatedPrompt != target.prompt
                    Task {
                        await editor.confirmEdit(
                            harnessID: harnessID,
                            newPrompt: promptChanged ? updatedPrompt : nil,
                            newProfile: selectedProfile.isEmpty ? nil : selectedProfile,
                            clearProfile: clearProfile
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editor.isMutating)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            promptText = target.prompt
            selectedProfile = target.profile ?? ""
        }
    }
}

// MARK: - Overlay modifier

struct FocusEditorOverlay: ViewModifier {
    @ObservedObject var editor: HarnessFocusEditor
    let harnessID: String
    let availableProfiles: [String]

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $editor.isAddingFocus) {
                AddFocusSheet(editor: editor, harnessID: harnessID, availableProfiles: availableProfiles)
            }
            .sheet(item: $editor.editingTarget) { target in
                EditFocusSheet(
                    editor: editor, harnessID: harnessID,
                    target: target, availableProfiles: availableProfiles
                )
            }
            .confirmationDialog(
                Strings.Harnesses.removeFocusConfirmTitle,
                isPresented: Binding(
                    get: { editor.removalTarget != nil },
                    set: { if !$0 { editor.removalTarget = nil } }
                ),
                presenting: editor.removalTarget
            ) { target in
                Button(Strings.Harnesses.removeFocusConfirmButton, role: .destructive) {
                    Task {
                        await editor.confirmRemove(
                            target: FocusRemoveOptions(harness: harnessID, name: target.name),
                            harnessID: harnessID
                        )
                    }
                }
                Button(Strings.Harnesses.focusCancelButton, role: .cancel) {
                    editor.removalTarget = nil
                }
            } message: { target in
                Text(Strings.Harnesses.removeFocusConfirmMessage(target.name))
            }
    }
}

// MARK: - Helpers

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
    }
}
