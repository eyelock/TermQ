import SwiftUI
import TermQCore
import TermQShared

/// Sheet for "Publish to Repository…" — graduating a local harness into a
/// git repository via a fresh worktree, ready to commit.
///
/// Two phases, mirroring `ForkHarnessSheet`: a form (all decisions) and a
/// `CommandRunnerSheet` progress stream (worktree → copy → validate →
/// optional register script). All logic lives in
/// `PublishHarnessViewModel`; this view only renders state.
struct PublishHarnessSheet: View {
    @ObservedObject var viewModel: PublishHarnessViewModel
    /// Called after a successful publish is dismissed — the parent reveals
    /// the Repositories sidebar.
    let onCompleted: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .form
    @StateObject private var runnerState = CommandSheetState()

    private enum Phase { case form, running, succeeded, failed }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .form:
                sheetHeader
                Divider()
                formView
            case .running, .succeeded, .failed:
                CommandRunnerSheet(
                    title: Strings.HarnessPublish.progressTitle(viewModel.harness.name),
                    state: runnerState,
                    onRerun: nil,
                    onDismiss: {
                        if phase == .succeeded {
                            dismiss()
                            onCompleted()
                        } else {
                            phase = .form
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.prepare() }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Text(Strings.HarnessPublish.title(viewModel.harness.name))
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Text(Strings.HarnessPublish.explanation)
                        .font(.body)
                        .foregroundColor(.secondary)
                    if let preflight = viewModel.preflight, !preflight.isValid {
                        Label {
                            Text(Strings.HarnessPublish.preflightFailed)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                    }
                }

                Section {
                    Picker(
                        Strings.HarnessPublish.repoLabel,
                        selection: $viewModel.selectedRepoID
                    ) {
                        Text(Strings.HarnessPublish.repoPlaceholder)
                            .tag(UUID?.none)
                        ForEach(viewModel.worktreeViewModel.repositories) { repo in
                            Text(repo.name).tag(UUID?.some(repo.id))
                        }
                    }
                    destinationFields
                    destinationBanner
                }

                planSection
                changesSection
                worktreeSection
            }
            .formStyle(.grouped)

            Divider()

            footer
        }
    }

    @ViewBuilder
    private var destinationFields: some View {
        if viewModel.destinationState != .sameRepo {
            HStack {
                TextField(
                    Strings.HarnessPublish.parentDirLabel,
                    text: $viewModel.parentDir
                )
                .textFieldStyle(.roundedBorder)
                if let suggestions = viewModel.scan?.suggestedParentDirs, !suggestions.isEmpty {
                    Menu {
                        ForEach(suggestions, id: \.self) { dir in
                            Button(dir) { viewModel.parentDir = dir }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help(Strings.HarnessPublish.parentDirHint)
                }
            }
            TextField(Strings.HarnessPublish.nameLabel, text: $viewModel.publishName)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var destinationBanner: some View {
        switch viewModel.destinationState {
        case .scanning:
            if viewModel.selectedRepoID != nil {
                ProgressView().controlSize(.small)
            }
        case .newEntry:
            bannerLabel(Strings.HarnessPublish.stateNew, icon: "plus.circle", color: .green)
        case .updateExisting(let path):
            bannerLabel(
                Strings.HarnessPublish.stateUpdate(path), icon: "arrow.triangle.2.circlepath",
                color: .orange)
        case .clash(let name):
            bannerLabel(
                Strings.HarnessPublish.stateClash(name), icon: "exclamationmark.octagon",
                color: .red)
        case .directoryOccupied:
            bannerLabel(
                Strings.HarnessPublish.stateOccupied, icon: "exclamationmark.octagon", color: .red)
        case .sameRepo:
            VStack(alignment: .leading, spacing: 8) {
                bannerLabel(
                    Strings.HarnessPublish.stateSameRepo, icon: "checkmark.seal", color: .blue)
                Button(Strings.HarnessPublish.revealRepository) {
                    dismiss()
                    onCompleted()
                }
            }
        }
    }

    private func bannerLabel(_ text: String, icon: String, color: Color) -> some View {
        Label {
            Text(text).font(.caption)
        } icon: {
            Image(systemName: icon).foregroundColor(color)
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if viewModel.destinationState != .sameRepo {
            Section(Strings.HarnessPublish.filesLabel) {
                Picker(Strings.HarnessPublish.modeLabel, selection: $viewModel.copyMode) {
                    Text(Strings.HarnessPublish.modeEntire)
                        .tag(HarnessPublishPlan.CopyMode.entireDirectory)
                    Text(Strings.HarnessPublish.modeEnumerated)
                        .tag(HarnessPublishPlan.CopyMode.enumerated)
                }
                .pickerStyle(.segmented)
                if viewModel.copyMode == .enumerated {
                    Text(Strings.HarnessPublish.modeEnumeratedHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = viewModel.planError {
                    bannerLabel(error, icon: "exclamationmark.triangle.fill", color: .red)
                } else if let plan = viewModel.plan {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(plan.files, id: \.self) { file in
                                Text(file)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                    if !plan.unresolvedReferences.isEmpty {
                        bannerLabel(
                            Strings.HarnessPublish.unresolvedReferences(
                                plan.unresolvedReferences.count),
                            icon: "questionmark.folder", color: .orange)
                    }
                }

                if viewModel.scan?.hasRegisterScript == true {
                    bannerLabel(
                        Strings.HarnessPublish.willRunRegisterScript(
                            RepoHarnessScanner.registerScriptPath),
                        icon: "gearshape.2", color: .blue)
                }
            }
        }
    }

    @ViewBuilder
    private var changesSection: some View {
        if case .updateExisting = viewModel.destinationState {
            Section(Strings.HarnessPublish.changesLabel) {
                if viewModel.changes.isEmpty {
                    Text(Strings.HarnessPublish.changesNone)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(viewModel.changes, id: \.path) { change in
                                HStack(spacing: 6) {
                                    Text(changeTag(change.kind))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(changeColor(change.kind))
                                    Text(change.path)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                }
            }
        }
    }

    @ViewBuilder
    private var worktreeSection: some View {
        if viewModel.destinationState != .sameRepo, viewModel.selectedRepoID != nil {
            Section {
                TextField(Strings.HarnessPublish.branchLabel, text: $viewModel.branchName)
                    .textFieldStyle(.roundedBorder)
                TextField(Strings.HarnessPublish.baseBranchLabel, text: $viewModel.baseBranch)
                    .textFieldStyle(.roundedBorder)
                TextField(Strings.HarnessPublish.worktreePathLabel, text: $viewModel.worktreePath)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(Strings.Common.cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(publishButtonTitle) {
                phase = .running
                Task {
                    let succeeded = await viewModel.publish(runnerState: runnerState)
                    phase = succeeded ? .succeeded : .failed
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canPublish)
        }
        .padding()
    }

    private var publishButtonTitle: String {
        if case .updateExisting = viewModel.destinationState {
            return Strings.HarnessPublish.updateButton
        }
        return Strings.HarnessPublish.publishButton
    }

    private func changeTag(_ kind: PublishChange.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .modified: return "~"
        case .removed: return "-"
        }
    }

    private func changeColor(_ kind: PublishChange.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .modified: return .orange
        case .removed: return .red
        }
    }
}
