import SwiftUI
import TermQShared

/// Identifies a single delegate on a harness — the (sourceURL, path) tuple
/// matches how `ynh delegate remove/update` disambiguates entries.
struct DelegateEditTarget: Equatable, Identifiable {
    var id: String { "\(sourceURL)#\(path ?? "")" }
    let sourceURL: String
    let path: String?
    let ref: String?
}

/// Coordinates per-row delegate mutations (Edit, Remove) on the harness
/// detail pane. Sibling to `HarnessIncludeEditor` minus the picks step
/// (delegates can't narrow with `--pick`). The "Add Delegate" entry point
/// is intentionally absent here — that flow will be reintroduced once the
/// project has a unified source-picker design.
@MainActor
final class HarnessDelegateEditor: ObservableObject {
    @Published var editingTarget: DelegateEditTarget?
    @Published var removalTarget: DelegateEditTarget?
    /// When `true`, the detail pane presents the unified `SourcePicker` for
    /// adding a delegate. The flow itself lives in `AddDelegateContext`;
    /// this editor only owns the lifecycle flag and the post-apply reload.
    @Published var isAddingDelegate: Bool = false
    @Published private(set) var isMutating = false
    @Published var errorMessage: String?

    private let repository: HarnessRepository
    private let detector: any YNHDetectorProtocol
    private let mutator: DelegateMutator

    init(
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        repository: HarnessRepository = .shared,
        mutator: DelegateMutator = DelegateMutator()
    ) {
        self.detector = detector
        self.repository = repository
        self.mutator = mutator
    }

    func requestAdd() {
        errorMessage = nil
        isAddingDelegate = true
    }

    func requestEdit(_ target: DelegateEditTarget) {
        errorMessage = nil
        editingTarget = target
    }

    /// Refresh detail after an externally-driven add (the unified picker
    /// owns the mutation; we own the reload).
    func reloadAfterAdd(harnessName: String) async {
        await reloadDetail(harnessName: harnessName)
    }

    func requestRemove(_ target: DelegateEditTarget) {
        errorMessage = nil
        removalTarget = target
    }

    /// Apply a remove for the given target. Caller is responsible for
    /// passing the target captured *before* the confirmation dialog
    /// dismisses — the dismissal nils `removalTarget` faster than the
    /// destructive button's action runs.
    func confirmRemove(target: DelegateEditTarget, harnessName: String) async {
        guard let ynhPath = readyYnhPath() else { return }
        let opts = DelegateRemoveOptions(
            harness: harnessName, sourceURL: target.sourceURL, path: target.path
        )
        isMutating = true
        await mutator.remove(opts, ynhPath: ynhPath, environment: ynhEnvironment())
        isMutating = false

        if mutator.succeeded {
            removalTarget = nil
            await reloadDetail(harnessName: harnessName)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func confirmEdit(
        harnessName: String,
        newPath: String?,
        newRef: String?
    ) async {
        guard let target = editingTarget, let ynhPath = readyYnhPath() else { return }
        let opts = DelegateUpdateOptions(
            harness: harnessName,
            sourceURL: target.sourceURL,
            fromPath: target.path,
            path: newPath,
            ref: newRef
        )
        isMutating = true
        await mutator.update(opts, ynhPath: ynhPath, environment: ynhEnvironment())
        isMutating = false

        if mutator.succeeded {
            editingTarget = nil
            await reloadDetail(harnessName: harnessName)
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
        if let override = YNHDetector.shared.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }

    private func reloadDetail(harnessName: String) async {
        repository.invalidateDetail(for: harnessName)
        await repository.fetchDetail(for: harnessName)
    }
}

// MARK: - Edit sheet

/// Sheet presented when the user clicks Edit on a delegate. Edits ref + path.
struct EditDelegateSheet: View {
    @ObservedObject var editor: HarnessDelegateEditor
    let harnessName: String
    let target: DelegateEditTarget

    @State private var refText: String = ""
    @State private var pathText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.Harnesses.editDelegateTitle)
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.editIncludeSource)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Text(GitURLHelper.shortURL(target.sourceURL))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.editIncludeRef)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField(Strings.Harnesses.editIncludeRefPlaceholder, text: $refText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.editIncludePath)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField(Strings.Harnesses.editIncludePathPlaceholder, text: $pathText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Marketplace.Picker.commandPreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let error = editor.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(Strings.Harnesses.installCancel) {
                    editor.editingTarget = nil
                }
                .keyboardShortcut(.cancelAction)
                .disabled(editor.isMutating)

                Button(Strings.Harnesses.editIncludeSave) {
                    Task {
                        await editor.confirmEdit(
                            harnessName: harnessName,
                            newPath: pathText,
                            newRef: refText
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editor.isMutating || !hasChanges)
            }
        }
        .padding(20)
        .onAppear {
            refText = target.ref ?? ""
            pathText = target.path ?? ""
        }
    }

    private var hasChanges: Bool {
        refText != (target.ref ?? "") || pathText != (target.path ?? "")
    }

    private var commandPreview: String {
        let opts = DelegateUpdateOptions(
            harness: harnessName,
            sourceURL: target.sourceURL,
            fromPath: target.path,
            path: pathText,
            ref: refText
        )
        return (["ynh"] + DelegateMutator.buildDelegateUpdateArgs(opts)).joined(separator: " ")
    }
}
