import SwiftUI
import TermQCore

/// Sheet for the STACKS section's "New Stack…" footer — seeds a worktree-less stack in
/// one of two modes (both always shown; the app-level `SettingsStore.newStackMode`
/// preference only chooses which one starts selected):
///
/// - **Branch off default**: the named branch is the first stacked branch, created off
///   the chosen base (default trunk) and tracked — a one-entry stack.
/// - **Branch off integration**: the name names the STACK; an EMPTY `stack/<name>`
///   integration branch is created off the base and tracked as the stack root, with an
///   optional first stacked branch created and tracked on top of it. Stacked-branch
///   pull requests then chain into the integration branch (gs bases CRs on parents),
///   leaving the default branch to the eventual integration→default PR.
///
/// Everything is plain git + track — no checkout, no worktree; launching into the
/// stack later creates its worktree implicitly.
struct NewStackSheet: View {
    let repo: ObservableRepository
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var mode: NewStackMode = .branchOffDefault
    @State private var didApplyPreferredMode = false
    @State private var branchName: String = ""
    @State private var firstBranch: String = ""
    @State private var baseBranch: String = ""
    @State private var existingBranches: [String] = []
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    /// The integration branch the current name derives to (integration mode only).
    private var integrationBranch: String {
        WorktreeSidebarViewModel.integrationBranchName(for: branchName)
    }

    /// Integration mode rejects a stack name whose derived `stack/<name>` branch
    /// already exists locally.
    private var integrationNameTaken: Bool {
        mode == .branchOffIntegration && !branchName.isEmpty
            && existingBranches.contains(integrationBranch)
    }

    private var canSubmit: Bool {
        !branchName.isEmpty && !baseBranch.isEmpty && !isCreating && !integrationNameTaken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Stacks.newStackTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Picker("", selection: $mode) {
                Text(Strings.Stacks.newStackModeIntegration).tag(NewStackMode.branchOffIntegration)
                Text(Strings.Stacks.newStackModeDefault).tag(NewStackMode.branchOffDefault)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    mode == .branchOffIntegration
                        ? Strings.Stacks.newStackStackNameLabel : Strings.Stacks.newStackNameLabel
                )
                .foregroundColor(.primary)
                TextField(Strings.Stacks.newStackNamePlaceholder, text: $branchName)
                    .textFieldStyle(.roundedBorder)
                if mode == .branchOffIntegration, !branchName.isEmpty {
                    Text(
                        integrationNameTaken
                            ? Strings.Stacks.newStackNameExists(integrationBranch)
                            : Strings.Stacks.newStackIntegrationPreview(integrationBranch)
                    )
                    .font(.caption)
                    .foregroundColor(integrationNameTaken ? .red : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Stacks.newStackBaseLabel)
                    .foregroundColor(.primary)
                TextField("", text: $baseBranch)
                    .textFieldStyle(.roundedBorder)
            }

            if mode == .branchOffIntegration {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Stacks.newStackFirstBranchLabel)
                        .foregroundColor(.primary)
                    TextField("", text: $firstBranch)
                        .textFieldStyle(.roundedBorder)
                    Text(
                        firstBranch.isEmpty
                            ? Strings.Stacks.newStackFirstBranchEmptyHint
                            : Strings.Stacks.newStackFirstBranchFilledHint
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(
                mode == .branchOffIntegration
                    ? Strings.Stacks.newStackIntegrationNote : Strings.Stacks.newStackNote
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let msg = errorMessage {
                Text(msg)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(Strings.Sidebar.cancelButton) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(Strings.Stacks.newStackButton) {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(isCreating)
        .task {
            if !didApplyPreferredMode {
                didApplyPreferredMode = true
                mode = settings.newStackMode
            }
            baseBranch = await viewModel.defaultBranch(for: repo)
            existingBranches = (try? await viewModel.listBranches(for: repo)) ?? []
        }
    }

    private func submit() async {
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        do {
            switch mode {
            case .branchOffDefault:
                try await viewModel.createStack(repo: repo, name: branchName, base: baseBranch)
            case .branchOffIntegration:
                try await viewModel.createIntegrationStack(
                    repo: repo, stackName: branchName, base: baseBranch,
                    firstBranch: firstBranch.isEmpty ? nil : firstBranch)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
