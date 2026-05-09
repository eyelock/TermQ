import AppKit
import SwiftUI
import TermQShared

/// `SourcePickerContext` for adding a delegate to a harness.
///
/// **Library tab** lists installed harnesses (excluding the target itself —
/// you can't delegate a harness to itself). Picking a row enters a Configure
/// stage with optional ref + path inputs. A Browse… affordance lets the user
/// pick a local directory ad-hoc as a delegate source.
///
/// **Git URL tab** takes a direct URL plus optional ref / path. Apply
/// invokes `ynh delegate add` via `DelegateMutator`.
///
/// `sourceURL` for installed-harness picks comes from
/// `Harness.installedFrom.source` — the registry URL, git URL, or local path
/// the harness was originally installed from. (Plan decision: option (1) —
/// most general, works across all three install types.)
@MainActor
final class AddDelegateContext: SourcePickerContext {
    let title: String
    let targetHarnessID: String
    let installedHarnesses: [Harness]
    let onApplied: () -> Void

    let sourcesService = SourcesService()

    private let detector: any YNHDetectorProtocol
    private let mutator: DelegateMutator

    @Published var librarySearch: String = ""
    @Published var gitURL: String = ""
    @Published var gitRef: String = ""
    @Published var gitPath: String = ""
    @Published var libraryStage: LibraryStage = .browsing
    @Published var showManageSources: Bool = false
    @Published var isApplying: Bool = false
    @Published var errorMessage: String?

    enum LibraryStage {
        case browsing
        case configuring(PickedSource)
    }

    struct PickedSource: Equatable {
        let displayName: String
        let sourceURL: String
        let sourceType: String
        var ref: String
        var path: String
    }

    init(
        targetHarnessID: String,
        installedHarnesses: [Harness],
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        mutator: DelegateMutator = DelegateMutator(),
        onApplied: @escaping () -> Void
    ) {
        self.title = Strings.Harnesses.addDelegateTitle
        self.targetHarnessID = targetHarnessID
        self.installedHarnesses = installedHarnesses
        self.detector = detector
        self.mutator = mutator
        self.onApplied = onApplied
    }

    @ViewBuilder
    var library: some View { AddDelegateLibraryView(context: self) }

    @ViewBuilder
    var gitURLView: some View { AddDelegateGitURLView(context: self) }

    // MARK: - Library

    var filteredInstalled: [Harness] {
        let query =
            librarySearch
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return
            installedHarnesses
            .filter { $0.id != targetHarnessID }
            .filter {
                guard !query.isEmpty else { return true }
                if $0.name.lowercased().contains(query) { return true }
                if let description = $0.description,
                    description.lowercased().contains(query)
                {
                    return true
                }
                return false
            }
    }

    func pickHarness(_ harness: Harness) {
        let source = harness.installedFrom?.source ?? harness.id
        let sourceType = harness.installedFrom?.sourceType ?? "local"
        libraryStage = .configuring(
            PickedSource(
                displayName: harness.name,
                sourceURL: source,
                sourceType: sourceType,
                ref: "",
                path: ""
            )
        )
    }

    func pickLocalPath(_ path: String) {
        let displayName = (path as NSString).lastPathComponent
        libraryStage = .configuring(
            PickedSource(
                displayName: displayName,
                sourceURL: path,
                sourceType: "local",
                ref: "",
                path: ""
            )
        )
    }

    func backToBrowsing() {
        libraryStage = .browsing
        errorMessage = nil
    }

    // MARK: - Apply

    func applyLibrary(_ pick: PickedSource, dismiss: @escaping () -> Void) async {
        await apply(
            sourceURL: pick.sourceURL,
            ref: pick.ref,
            path: pick.path,
            dismiss: dismiss
        )
    }

    func applyGitURL(dismiss: @escaping () -> Void) async {
        let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { return }
        await apply(
            sourceURL: trimmedURL,
            ref: gitRef,
            path: gitPath,
            dismiss: dismiss
        )
    }

    func gitURLPreview() -> String {
        let trimmedURL = gitURL.trimmingCharacters(in: .whitespaces)
        let url = trimmedURL.isEmpty ? "<url>" : trimmedURL
        return commandPreview(sourceURL: url, ref: gitRef, path: gitPath)
    }

    func libraryConfigurePreview(_ pick: PickedSource) -> String {
        commandPreview(sourceURL: pick.sourceURL, ref: pick.ref, path: pick.path)
    }

    private func commandPreview(sourceURL: String, ref: String, path: String) -> String {
        let opts = DelegateAddOptions(
            harness: targetHarnessID,
            sourceURL: sourceURL,
            ref: ref.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            path: path.trimmingCharacters(in: .whitespaces).nilIfEmpty
        )
        return (["ynh"] + DelegateMutator.buildDelegateAddArgs(opts)).joined(separator: " ")
    }

    private func apply(
        sourceURL: String,
        ref: String,
        path: String,
        dismiss: @escaping () -> Void
    ) async {
        guard case .ready(let ynhPath, _, _) = detector.status else {
            errorMessage = "YNH toolchain is not ready"
            return
        }
        let opts = DelegateAddOptions(
            harness: targetHarnessID,
            sourceURL: sourceURL,
            ref: ref.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            path: path.trimmingCharacters(in: .whitespaces).nilIfEmpty
        )
        isApplying = true
        errorMessage = nil
        await mutator.add(opts, ynhPath: ynhPath, environment: ynhEnvironment())
        isApplying = false

        if mutator.succeeded {
            onApplied()
            dismiss()
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    private func ynhEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = detector.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Library content

private struct AddDelegateLibraryView: View {
    @ObservedObject var context: AddDelegateContext

    var body: some View {
        switch context.libraryStage {
        case .browsing:
            AddDelegateLibraryBrowseView(context: context)
        case .configuring(let pick):
            AddDelegateLibraryConfigureView(context: context, pick: pick)
        }
    }
}

private struct AddDelegateLibraryBrowseView: View {
    @ObservedObject var context: AddDelegateContext

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(
                    Strings.Harnesses.addDelegateLibrarySearchPlaceholder,
                    text: $context.librarySearch
                )
                .textFieldStyle(.roundedBorder)

                Button {
                    context.showManageSources = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help(Strings.Harnesses.installManageSourcesHelp)
                .sheet(isPresented: $context.showManageSources) {
                    SourcePickerManageSourcesSheet(sourcesService: context.sourcesService)
                        .frame(width: 420, height: 320)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            let installed = context.filteredInstalled
            if installed.isEmpty {
                emptyState
            } else {
                List(installed) { harness in
                    row(harness)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Button {
                    chooseLocalDirectory()
                } label: {
                    Label(
                        Strings.Harnesses.browseLocal,
                        systemImage: "folder.badge.plus"
                    )
                }
                .help(Strings.Harnesses.browseLocalHelp)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            Task { await context.sourcesService.refresh() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(Strings.Harnesses.addDelegateLibraryEmpty)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(_ harness: Harness) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(harness.name).font(.body).fontWeight(.medium)
                    if !harness.version.isEmpty {
                        Text(harness.version).font(.caption).foregroundColor(.secondary)
                    }
                }
                if let desc = harness.description, !desc.isEmpty {
                    Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                if let provenance = harness.installedFrom {
                    Text(provenance.sourceType)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            Button(Strings.Harnesses.addDelegatePick) {
                context.pickHarness(harness)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .contentShape(Rectangle())
    }

    private func chooseLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        Task {
            let response = await panel.begin()
            if response == .OK, let url = panel.url {
                context.pickLocalPath(url.path(percentEncoded: false))
            }
        }
    }
}

private struct AddDelegateLibraryConfigureView: View {
    @ObservedObject var context: AddDelegateContext
    let pick: AddDelegateContext.PickedSource
    @Environment(\.dismiss) private var dismiss

    @State private var ref: String = ""
    @State private var path: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    context.backToBrowsing()
                } label: {
                    Label(
                        Strings.Harnesses.addDelegateBack,
                        systemImage: "chevron.left"
                    )
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pick.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(pick.sourceURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.installGitRef)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    Strings.Harnesses.installGitRefPlaceholder,
                    text: $ref
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.installGitSubpath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    Strings.Harnesses.installGitSubpathPlaceholder,
                    text: $path
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.installCommandPreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(
                    context.libraryConfigurePreview(
                        AddDelegateContext.PickedSource(
                            displayName: pick.displayName,
                            sourceURL: pick.sourceURL,
                            sourceType: pick.sourceType,
                            ref: ref,
                            path: path
                        )
                    )
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let err = context.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button(Strings.Harnesses.addDelegateApply) {
                    Task {
                        var configured = pick
                        configured.ref = ref
                        configured.path = path
                        await context.applyLibrary(configured, dismiss: { dismiss() })
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(context.isApplying)
            }
        }
        .padding(16)
    }
}

// MARK: - Git URL content

private struct AddDelegateGitURLView: View {
    @ObservedObject var context: AddDelegateContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.installGitURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    Strings.Harnesses.installGitURLPlaceholder,
                    text: $context.gitURL
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.installGitRef)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    Strings.Harnesses.installGitRefPlaceholder,
                    text: $context.gitRef
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.installGitSubpath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    Strings.Harnesses.installGitSubpathPlaceholder,
                    text: $context.gitPath
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.installCommandPreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(context.gitURLPreview())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let err = context.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button(Strings.Harnesses.addDelegateApply) {
                    Task {
                        await context.applyGitURL(dismiss: { dismiss() })
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    context.isApplying
                        || context.gitURL.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(16)
    }
}
