import SwiftUI
import TermQCore

/// Sheet for pruning merged local branches. Loads candidates on appear so the sheet
/// opens immediately rather than blocking the sidebar while git runs.
struct PruneBranchesSheet: View {
    let repo: ObservableRepository
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mergedBranches: [String] = []
    @State private var isAnalysing = true
    @State private var isPruning = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.pruneBranchesTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(Strings.Sidebar.pruneBranchesExplanation)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            branchList

            if let msg = errorMessage {
                Text(msg)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isAnalysing || isPruning {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button(Strings.Sidebar.cancelButton) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(Strings.Sidebar.pruneBranchesConfirm) {
                    Task { await prune() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isAnalysing || isPruning || mergedBranches.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(isPruning)
        .task { await analyse() }
    }

    @ViewBuilder
    private var branchList: some View {
        if isAnalysing {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                Spacer()
            }
            .frame(minHeight: 60)
        } else if mergedBranches.isEmpty && errorMessage == nil {
            Text(Strings.Sidebar.pruneBranchesNothingMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(mergedBranches, id: \.self) { branch in
                    Text(branch)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if branch != mergedBranches.last {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private func analyse() async {
        isAnalysing = true
        errorMessage = nil
        do {
            mergedBranches = try await viewModel.mergedLocalBranches(repo: repo)
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalysing = false
    }

    private func prune() async {
        isPruning = true
        defer { isPruning = false }
        errorMessage = nil
        do {
            try await viewModel.deleteBranches(repo: repo, branches: mergedBranches)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
