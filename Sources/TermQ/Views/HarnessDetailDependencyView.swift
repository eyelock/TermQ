import AppKit
import SwiftUI
import TermQShared

/// Dependency section for the harness detail pane: includes and delegates
/// with resolved status, clickable git links, and pick pills.
///
/// Shows composed dependency data when available (from `ynd compose`),
/// falling back to basic data from `ynh ls` while detail loads.
struct HarnessDetailDependencyView: View {
    let harness: Harness
    let detail: HarnessDetail?
    var updateSignal: HarnessUpdateSignal = .none
    /// When non-nil, each include row shows Edit / Remove affordances backed
    /// by this coordinator. Registry harnesses receive `nil` here.
    var includeEditor: HarnessIncludeEditor?
    /// Same shape as `includeEditor` but for delegate cards.
    var delegateEditor: HarnessDelegateEditor?

    /// Returns the drift entry for this row, if any. Matches on whichever
    /// identifier the badge store recorded — `path` when the include has
    /// one, otherwise the git URL — so includes that span the whole repo
    /// (no subpath) still light up their row.
    private func driftEntry(git: String, path: String?) -> HarnessUpdateSignal.DriftedInclude? {
        guard case .unversionedDrift(let drifted) = updateSignal else { return nil }
        if let path, !path.isEmpty,
            let match = drifted.first(where: { $0.path == path })
        {
            return match
        }
        return drifted.first(where: { $0.path == git })
    }

    /// Tooltip body for the drift triangle — names the SHAs so the user can
    /// see *which* commit drifted, not just *that* one did.
    private func driftTooltip(for drift: HarnessUpdateSignal.DriftedInclude) -> String {
        Strings.Harnesses.unversionedDriftIncludeTooltip(
            String(drift.installedSHA.prefix(7)),
            String(drift.availableSHA.prefix(7))
        )
    }

    @ViewBuilder
    private func resolutionBadge(
        resolved: Bool,
        drift: HarnessUpdateSignal.DriftedInclude?
    ) -> some View {
        if let drift {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.yellow)
                .help(driftTooltip(for: drift))
        } else if resolved {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.green)
                .help(Strings.Harnesses.detailResolved)
        } else {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
                .help(Strings.Harnesses.detailUnresolved)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Harnesses.detailDependencies)
                .font(.headline)

            if let detail {
                composedDependencies(detail.composition)
            } else {
                basicDependencies
            }

            if let includeEditor {
                addIncludeSection(editor: includeEditor)
            }
            if let delegateEditor {
                addDelegateSection(editor: delegateEditor)
            }
        }
        .modifier(IncludeEditorOverlay(editor: includeEditor, harnessName: harness.name))
        .modifier(DelegateEditorOverlay(editor: delegateEditor, harnessName: harness.name))
    }

    /// Whether the dependencies section should render at all.
    /// When an editor is provided, we always render so the Add Include entry
    /// point is reachable even on a harness with no current dependencies.
    var hasDependencies: Bool {
        if includeEditor != nil || delegateEditor != nil { return true }
        if let detail {
            return !detail.composition.includes.isEmpty || !detail.composition.delegatesTo.isEmpty
        }
        return !harness.includes.isEmpty || !harness.delegatesTo.isEmpty
    }

    // MARK: - Composed Dependencies

    private func composedDependencies(_ comp: HarnessComposition) -> some View {
        Group {
            if !comp.includes.isEmpty {
                Text(Strings.Harnesses.detailIncludes(comp.includes.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(comp.includes.indices, id: \.self) { idx in
                    composedIncludeCard(comp.includes[idx])
                }
            }

            if !comp.delegatesTo.isEmpty {
                Text(Strings.Harnesses.detailDelegates(comp.delegatesTo.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(comp.delegatesTo.indices, id: \.self) { idx in
                    composedDelegateCard(comp.delegatesTo[idx])
                }
            }
        }
    }

    private func composedIncludeCard(_ include: ComposedInclude) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)

                GitSourceLabel(source: include.git)

                if let ref = include.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                resolutionBadge(
                    resolved: include.resolved,
                    drift: driftEntry(git: include.git, path: include.path)
                )

                Spacer()

                GitActionButtons(source: include.git, path: include.path)
                includeEditMenu(
                    sourceURL: include.git,
                    path: include.path,
                    ref: include.ref,
                    picks: include.pick ?? []
                )
            }

            if let path = include.path, !path.isEmpty {
                subpathRow(path)
            }

            if let picks = include.pick, !picks.isEmpty {
                picksBlock(picks, source: include.git, ref: include.ref)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func composedDelegateCard(_ delegate: ComposedDelegate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)

                GitSourceLabel(source: delegate.git)

                if let ref = delegate.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                GitActionButtons(source: delegate.git, path: delegate.path)
                delegateEditMenu(
                    sourceURL: delegate.git, path: delegate.path, ref: delegate.ref
                )
            }

            if let path = delegate.path, !path.isEmpty {
                subpathRow(path)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Basic Dependencies (fallback)

    private var basicDependencies: some View {
        Group {
            if !harness.includes.isEmpty {
                Text(Strings.Harnesses.detailIncludes(harness.includes.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(harness.includes.indices, id: \.self) { idx in
                    basicIncludeCard(harness.includes[idx])
                }
            }

            if !harness.delegatesTo.isEmpty {
                Text(Strings.Harnesses.detailDelegates(harness.delegatesTo.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(harness.delegatesTo.indices, id: \.self) { idx in
                    basicDelegateCard(harness.delegatesTo[idx])
                }
            }
        }
    }

    private func basicIncludeCard(_ include: HarnessInclude) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)

                GitSourceLabel(source: include.git)

                if let ref = include.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                GitActionButtons(source: include.git, path: include.path)
                includeEditMenu(
                    sourceURL: include.git,
                    path: include.path,
                    ref: include.ref,
                    picks: include.pick ?? []
                )
            }

            if let path = include.path, !path.isEmpty {
                subpathRow(path)
            }

            if let picks = include.pick, !picks.isEmpty {
                picksBlock(picks, source: include.git, ref: include.ref)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func basicDelegateCard(_ delegate: HarnessDelegate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)

                GitSourceLabel(source: delegate.git)

                if let ref = delegate.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                GitActionButtons(source: delegate.git, path: delegate.path)
                delegateEditMenu(
                    sourceURL: delegate.git, path: delegate.path, ref: delegate.ref
                )
            }

            if let path = delegate.path, !path.isEmpty {
                subpathRow(path)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Add Include section (only shown when an editor is provided)

    private func addIncludeSection(editor: HarnessIncludeEditor) -> some View {
        AddIncludeSectionView(
            harnessName: harness.name,
            editor: editor,
            existingIncludes: existingIncludeTargets
        )
    }

    private func addDelegateSection(editor: HarnessDelegateEditor) -> some View {
        Button {
            editor.requestAdd()
        } label: {
            Label(Strings.Harnesses.addDelegateButton, systemImage: "plus.circle")
                .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .foregroundColor(.accentColor)
    }

    /// Edit targets for already-installed includes. Used by AddIncludeFlow
    /// to mark matching plugins and to drive the "click to edit" jump.
    private var existingIncludeTargets: [IncludeEditTarget] {
        if let detail {
            return detail.composition.includes.map {
                IncludeEditTarget(
                    sourceURL: $0.git, path: $0.path,
                    ref: $0.ref, picks: $0.pick ?? []
                )
            }
        }
        return harness.includes.map {
            IncludeEditTarget(
                sourceURL: $0.git, path: $0.path,
                ref: $0.ref, picks: $0.pick ?? []
            )
        }
    }

    // MARK: - Include Edit Menu (only shown when an editor is provided)

    @ViewBuilder
    private func includeEditMenu(
        sourceURL: String, path: String?, ref: String?, picks: [String]
    ) -> some View {
        if let editor = includeEditor {
            let target = IncludeEditTarget(
                sourceURL: sourceURL, path: path, ref: ref, picks: picks
            )
            Menu {
                Button {
                    editor.requestEdit(target)
                } label: {
                    Label(Strings.Harnesses.editIncludeButton, systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    editor.requestRemove(target)
                } label: {
                    Label(Strings.Harnesses.removeIncludeButton, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Strings.Harnesses.includeActionsHelp)
        }
    }

    // MARK: - Delegate Edit Menu (only shown when an editor is provided)

    @ViewBuilder
    private func delegateEditMenu(
        sourceURL: String, path: String?, ref: String?
    ) -> some View {
        if let editor = delegateEditor {
            let target = DelegateEditTarget(sourceURL: sourceURL, path: path, ref: ref)
            Menu {
                Button {
                    editor.requestEdit(target)
                } label: {
                    Label(Strings.Harnesses.editDelegateButton, systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    editor.requestRemove(target)
                } label: {
                    Label(Strings.Harnesses.removeDelegateButton, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Strings.Harnesses.delegateActionsHelp)
        }
    }

    // MARK: - Shared Card Components

    private func subpathRow(_ path: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.leading, 20)
    }

    private func picksBlock(_ picks: [String], source: String, ref: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Strings.Harnesses.detailPicks(picks.count))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            FlowLayout(spacing: 4) {
                ForEach(picks, id: \.self) { pick in
                    GitPickPill(pick: pick, source: source)
                }
            }
            .padding(.leading, 20)
        }
    }
}

// MARK: - Git Source Helpers

/// Clickable git source label — links to browser for remote URLs, selectable text for local paths.
struct GitSourceLabel: View {
    let source: String

    var body: some View {
        if let url = GitURLHelper.browserURL(for: source) {
            Link(destination: url) {
                Text(GitURLHelper.shortURL(source))
                    .font(.system(size: 12, weight: .medium))
                    .underline()
            }
            .pointingHandCursor()
        } else {
            Text(source)
                .font(.system(size: 12, weight: .medium))
                .textSelection(.enabled)
        }
    }
}

/// Action buttons for a git source: open in browser and/or reveal in Finder.
struct GitActionButtons: View {
    let source: String
    let path: String?

    var body: some View {
        HStack(spacing: 4) {
            if let url = GitURLHelper.browserURL(for: source, path: path) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()
                .help(Strings.Harnesses.openInBrowser)
            }

            if source.hasPrefix("/") {
                Button {
                    let fullPath = path.map { "\(source)/\($0)" } ?? source
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fullPath)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()
                .help(Strings.Harnesses.revealInFinder)
            }
        }
    }
}

/// A clickable pick pill — opens in browser for remote, reveals in Finder for local.
struct GitPickPill: View {
    let pick: String
    let source: String

    var body: some View {
        if let url = GitURLHelper.browserURL(for: source, path: pick) {
            Link(destination: url) {
                pillLabel
            }
            .pointingHandCursor()
            .help(Strings.Harnesses.openInBrowser)
        } else if source.hasPrefix("/") {
            Button {
                let fullPath = "\(source)/\(pick)"
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fullPath)
            } label: {
                pillLabel
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(Strings.Harnesses.revealInFinder)
        } else {
            pillLabel
        }
    }

    private var pillLabel: some View {
        Text(pick)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Add Include Section

/// Inline section rendered when an editor is provided. Shows the Add Include
/// button by default; expands into the full `AddIncludeFlow` panel when
/// the user clicks it. Wrapped as a small @ObservedObject view so SwiftUI
/// re-renders on `editor.isAddingInclude` changes.
private struct AddIncludeSectionView: View {
    let harnessName: String
    @ObservedObject var editor: HarnessIncludeEditor
    let existingIncludes: [IncludeEditTarget]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editor.isAddingInclude {
                AddIncludeFlow(
                    harnessName: harnessName,
                    editor: editor,
                    existingIncludes: existingIncludes
                )
            } else {
                Button {
                    editor.startAddingInclude()
                } label: {
                    Label(Strings.Harnesses.addIncludeButton, systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
            }
        }
    }
}

// MARK: - Include Editor Overlay

/// Hosts the remove-confirmation dialog and edit sheet driven by
/// `HarnessIncludeEditor`. Applied as a modifier so it can vanish entirely
/// (no extra view in the hierarchy) when no editor is provided.
private struct IncludeEditorOverlay: ViewModifier {
    let editor: HarnessIncludeEditor?
    let harnessName: String

    func body(content: Content) -> some View {
        if let editor {
            content
                .modifier(IncludeEditorActiveOverlay(editor: editor, harnessName: harnessName))
        } else {
            content
        }
    }
}

private struct IncludeEditorActiveOverlay: ViewModifier {
    @ObservedObject var editor: HarnessIncludeEditor
    let harnessName: String

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Strings.Harnesses.removeIncludeConfirmTitle,
                isPresented: removeBinding,
                titleVisibility: .visible,
                presenting: editor.removalTarget
            ) { target in
                // Capture target by value here — the dialog dismissal nils
                // editor.removalTarget before the destructive action's body
                // runs, so reading from the editor after dismissal is too late.
                Button(Strings.Harnesses.removeIncludeConfirm, role: .destructive) {
                    Task { await editor.confirmRemove(target: target, harnessName: harnessName) }
                }
                Button(Strings.Harnesses.installCancel, role: .cancel) {
                    editor.removalTarget = nil
                }
            } message: { target in
                Text(Strings.Harnesses.removeIncludeConfirmMessage(GitURLHelper.shortURL(target.sourceURL)))
            }
            .sheet(item: $editor.editingTarget) { target in
                EditIncludeSheet(editor: editor, harnessName: harnessName, target: target)
                    .frame(width: 540, height: 620)
            }
    }

    private var removeBinding: Binding<Bool> {
        Binding(
            get: { editor.removalTarget != nil },
            set: { if !$0 { editor.removalTarget = nil } }
        )
    }
}

// MARK: - Delegate Editor Overlay

private struct DelegateEditorOverlay: ViewModifier {
    let editor: HarnessDelegateEditor?
    let harnessName: String

    func body(content: Content) -> some View {
        if let editor {
            content.modifier(
                DelegateEditorActiveOverlay(editor: editor, harnessName: harnessName)
            )
        } else {
            content
        }
    }
}

private struct DelegateEditorActiveOverlay: ViewModifier {
    @ObservedObject var editor: HarnessDelegateEditor
    @ObservedObject private var harnessRepo = HarnessRepository.shared
    let harnessName: String

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Strings.Harnesses.removeDelegateConfirmTitle,
                isPresented: removeBinding,
                titleVisibility: .visible,
                presenting: editor.removalTarget
            ) { target in
                Button(Strings.Harnesses.removeIncludeConfirm, role: .destructive) {
                    Task {
                        await editor.confirmRemove(target: target, harnessName: harnessName)
                    }
                }
                Button(Strings.Harnesses.installCancel, role: .cancel) {
                    editor.removalTarget = nil
                }
            } message: { target in
                Text(
                    Strings.Harnesses.removeDelegateConfirmMessage(GitURLHelper.shortURL(target.sourceURL))
                )
            }
            .sheet(item: $editor.editingTarget) { target in
                EditDelegateSheet(editor: editor, harnessName: harnessName, target: target)
                    .frame(width: 540, height: 360)
            }
            .sheet(isPresented: $editor.isAddingDelegate) {
                AddDelegateSheetHost(
                    targetHarnessName: harnessName,
                    installedHarnesses: harnessRepo.harnesses,
                    onApplied: {
                        Task { await editor.reloadAfterAdd(harnessName: harnessName) }
                    }
                )
                .frame(width: 520, height: 540)
            }
    }

    private var removeBinding: Binding<Bool> {
        Binding(
            get: { editor.removalTarget != nil },
            set: { if !$0 { editor.removalTarget = nil } }
        )
    }
}

// MARK: - Add Delegate sheet host

/// Thin host that constructs an `AddDelegateContext` and presents the
/// unified `SourcePicker`. Mirrors `HarnessInstallSheet`.
private struct AddDelegateSheetHost: View {
    let targetHarnessName: String
    let installedHarnesses: [Harness]
    let onApplied: () -> Void

    @StateObject private var context: AddDelegateContext

    init(
        targetHarnessName: String,
        installedHarnesses: [Harness],
        onApplied: @escaping () -> Void
    ) {
        self.targetHarnessName = targetHarnessName
        self.installedHarnesses = installedHarnesses
        self.onApplied = onApplied
        _context = StateObject(
            wrappedValue: AddDelegateContext(
                targetHarnessName: targetHarnessName,
                installedHarnesses: installedHarnesses,
                onApplied: onApplied
            )
        )
    }

    var body: some View {
        SourcePicker(context: context)
    }
}
