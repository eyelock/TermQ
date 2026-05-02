import SwiftUI
import TermQShared

/// Identifies a single include on a harness — the (sourceURL, path) tuple
/// matches how `ynh include remove/update` disambiguates entries.
struct IncludeEditTarget: Equatable, Identifiable {
    var id: String { "\(sourceURL)#\(path ?? "")" }
    let sourceURL: String
    let path: String?
    let ref: String?
    let picks: [String]
}

/// Coordinates inline include mutations for a harness detail pane.
///
/// Owns the `IncludeMutator` and the sheet/dialog state the dependency view
/// binds against. Logic lives here, not in the SwiftUI view, so it can be
/// driven by tests without spinning up a view hierarchy.
@MainActor
final class HarnessIncludeEditor: ObservableObject {
    /// The include the user has asked to edit. Non-nil triggers the edit sheet.
    @Published var editingTarget: IncludeEditTarget?

    /// The include the user has asked to remove. Non-nil triggers the confirm dialog.
    @Published var removalTarget: IncludeEditTarget?

    /// Mirrors `mutator.isRunning` for binding convenience.
    @Published private(set) var isMutating = false

    /// Last error surfaced from a mutation attempt — cleared on next request.
    @Published var errorMessage: String?

    /// True while the inline "Add Include" flow is shown below the includes
    /// section. Dep view binds against this; flow itself drives the toggle.
    @Published var isAddingInclude: Bool = false

    private let detector: any YNHDetectorProtocol
    private let repository: HarnessRepository
    private let mutator: IncludeMutator

    init(
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        repository: HarnessRepository = .shared,
        mutator: IncludeMutator = IncludeMutator()
    ) {
        self.detector = detector
        self.repository = repository
        self.mutator = mutator
    }

    func requestEdit(_ target: IncludeEditTarget) {
        errorMessage = nil
        editingTarget = target
    }

    func requestRemove(_ target: IncludeEditTarget) {
        errorMessage = nil
        removalTarget = target
    }

    func startAddingInclude() {
        errorMessage = nil
        isAddingInclude = true
    }

    /// Cancel the add flow and immediately open the edit sheet for an
    /// existing include. Used when the user clicks an already-installed
    /// plugin in the source picker — instead of being stuck, they jump
    /// straight to editing it.
    func switchToEditing(_ target: IncludeEditTarget) {
        isAddingInclude = false
        errorMessage = nil
        editingTarget = target
    }

    func cancelAddingInclude() {
        isAddingInclude = false
    }

    /// Called by the add flow on successful apply. Reloads detail and dismisses.
    func didFinishAddingInclude(harnessName: String) async {
        isAddingInclude = false
        await reloadDetail(harnessName: harnessName)
    }

    /// Apply a remove for the given target. Caller is responsible for passing
    /// the target captured *before* the confirmation dialog dismisses — the
    /// dismissal nils out `removalTarget` faster than the button action fires.
    func confirmRemove(target: IncludeEditTarget, harnessName: String) async {
        guard let ynhPath = readyYnhPath() else { return }
        let opts = IncludeRemoveOptions(
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

    /// Apply an update for the currently-pending `editingTarget` with the given
    /// new values. Empty strings/arrays are treated as "no change to that field".
    func confirmEdit(
        harnessName: String,
        newPath: String?,
        newRef: String?,
        newPicks: [String]?
    ) async {
        guard let target = editingTarget, let ynhPath = readyYnhPath() else { return }
        let opts = IncludeUpdateOptions(
            harness: harnessName,
            sourceURL: target.sourceURL,
            fromPath: target.path,
            path: newPath,
            pick: newPicks ?? [],
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

/// Sheet presented when the user clicks Edit on an include.
///
/// Picks editing reuses the same checkbox selector as the Add Include flow.
/// On appear the sheet looks up a matching marketplace plugin (via source
/// URL + path) so the full universe of artifacts is shown with the current
/// selection pre-checked. When no matching plugin can be found (e.g. raw
/// git-URL include), the available list falls back to the picks already on
/// the include — the user can deselect but cannot add new ones from the UI.
struct EditIncludeSheet: View {
    @ObservedObject var editor: HarnessIncludeEditor
    let harnessName: String
    let target: IncludeEditTarget

    @State private var refText: String = ""
    @State private var pathText: String = ""
    @State private var availablePicks: [String] = []
    @State private var selectedPicks: Set<String> = []
    @State private var isLoadingPicks: Bool = false
    @State private var picksLookupNote: String?
    /// True when the include's stored picks are empty — meaning "include all"
    /// per ynh semantics. The selector is pre-populated with every available
    /// artifact in this case so the user sees what's actually included.
    @State private var includeIsAllByDefault: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.Harnesses.editIncludeTitle)
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
                HStack {
                    Text(Strings.Harnesses.editIncludePicks)
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(picksCountLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(Strings.Harnesses.editIncludePicksExplainer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                IncludePicksSelector(
                    availablePicks: availablePicks,
                    selected: $selectedPicks,
                    isLoading: isLoadingPicks
                )
                if let note = picksLookupNote {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Command preview — exactly what will be sent to ynh on Save.
            // Removes ambiguity about what the action will do.
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
                            newRef: refText,
                            newPicks: picksArgument()
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .onAppear {
            refText = target.ref ?? ""
            pathText = target.path ?? ""
            includeIsAllByDefault = target.picks.isEmpty
            selectedPicks = Set(target.picks)
            availablePicks = target.picks
            Task { await resolveAvailablePicks() }
        }
    }

    private var refOrPathChanged: Bool {
        refText != (target.ref ?? "") || pathText != (target.path ?? "")
    }

    /// True when the user's pick selection differs from the include's current
    /// state. Handles the "include all" case where `target.picks=[]`
    /// represents every available artifact.
    private var picksChanged: Bool {
        if includeIsAllByDefault {
            // Stored picks empty = all included. Unchanged when every available
            // artifact is still checked.
            return selectedPicks != Set(availablePicks)
        }
        return Set(target.picks) != selectedPicks
    }

    private var hasChanges: Bool {
        refOrPathChanged || picksChanged
    }

    /// Save is enabled whenever the user has changed something. Empty picks
    /// is allowed (= "include all" per ynh semantics), so we don't gate on
    /// non-empty selection.
    private var canSave: Bool {
        !editor.isMutating && hasChanges
    }

    /// Localized "X of Y selected" hint shown above the picks list.
    private var picksCountLabel: String {
        Strings.Harnesses.editIncludePicksCount(selectedPicks.count, availablePicks.count)
    }

    /// Translate the selected set into the array passed to `ynh include update`.
    ///
    /// Returns `[]` (= no `--pick` flag, meaning "leave picks unchanged") when
    /// the user has not touched picks. Otherwise returns the exact selection,
    /// even if it equals the full universe — that's how the user expresses
    /// "switch this include to include all artifacts."
    private func picksArgument() -> [String] {
        guard picksChanged else { return [] }
        return Array(selectedPicks).sorted()
    }

    /// Pure preview of the `ynh include update` command that Save will run.
    /// Lets the user see exactly what's about to happen before clicking Save.
    private var commandPreview: String {
        let opts = IncludeUpdateOptions(
            harness: harnessName,
            sourceURL: target.sourceURL,
            fromPath: target.path,
            path: pathText,
            pick: picksArgument(),
            ref: refText
        )
        return (["ynh"] + IncludeMutator.buildIncludeUpdateArgs(opts)).joined(separator: " ")
    }

    private func resolveAvailablePicks() async {
        let marketplaces = MarketplaceStore.shared.marketplaces
        guard
            let match = IncludePluginLookup.find(
                sourceURL: target.sourceURL, path: target.path, in: marketplaces
            )
        else {
            picksLookupNote = Strings.Harnesses.editIncludePicksUnknownSource
            return
        }
        if match.plugin.skillsState == .eager && !match.plugin.picks.isEmpty {
            applyResolvedPicks(match.plugin.picks)
            return
        }
        isLoadingPicks = true
        defer { isLoadingPicks = false }
        do {
            let picks = try await MarketplaceFetcher.fetchSkills(for: match.plugin)
            applyResolvedPicks(picks)
        } catch {
            picksLookupNote = error.localizedDescription
        }
    }

    /// Apply the fetched universe of picks. When the include's stored pick
    /// list is empty (= "include all" in ynh semantics), pre-check every
    /// artifact so the user sees the actual current state.
    private func applyResolvedPicks(_ universe: [String]) {
        let merged = mergePicks(target.picks, universe)
        availablePicks = merged
        if includeIsAllByDefault {
            selectedPicks = Set(merged)
        }
    }

    /// Merge currently-included picks with the marketplace's full list. The
    /// user's existing picks always appear (even if not in the fetched list,
    /// e.g. orphaned), preserving the order: existing first, then any new.
    private func mergePicks(_ existing: [String], _ universe: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for pick in existing where !seen.contains(pick) {
            out.append(pick)
            seen.insert(pick)
        }
        for pick in universe where !seen.contains(pick) {
            out.append(pick)
            seen.insert(pick)
        }
        return out
    }
}
