import SwiftUI
import TermQCore

/// Sheet for checking out an existing local branch as a new git worktree.
///
/// Two modes:
/// - **Pre-selected** (`preselectedBranch != nil`): branch shown as a read-only label;
///   user only confirms the path. Opened from a branch row in the "Local Branches" section.
/// - **Picker** (`preselectedBranch == nil`): typeahead branch field filtered to branches
///   without worktrees. Opened from the repo or main-worktree context menu.
struct CheckoutBranchSheet: View {
    let repo: ObservableRepository
    let preselectedBranch: String?
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBranch: String = ""
    @State private var path: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var showBranchPopover = false
    @FocusState private var branchFieldFocused: Bool

    private var isPickerMode: Bool { preselectedBranch == nil }

    private var branches: [String] {
        viewModel.availableBranches[repo.id] ?? []
    }

    private var filteredBranches: [String] {
        let query = selectedBranch.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return Array(branches.prefix(8)) }
        return branches.filter { $0.lowercased().contains(query) }
    }

    private var canCreate: Bool {
        !selectedBranch.isEmpty && !path.isEmpty && !isCreating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.checkoutBranchTitle)
                .font(.title2)
                .fontWeight(.semibold)

            if isPickerMode {
                branchPickerField
            } else {
                branchReadOnlyField
            }

            PathInputField(
                label: Strings.Sidebar.worktreePathLabel,
                path: $path,
                placeholder: viewModel.inferWorktreePath(
                    for: repo,
                    branchName: selectedBranch.isEmpty ? "branch-name" : selectedBranch
                ),
                validatePath: false
            )

            if let msg = errorMessage {
                Text(msg)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(Strings.Sidebar.cancelButton) { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button(Strings.Sidebar.checkoutBranchCreate) {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .help(
                    selectedBranch.isEmpty
                        ? Strings.Sidebar.checkoutBranchRequired
                        : path.isEmpty ? Strings.Sidebar.newWorktreePathRequired : ""
                )
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(isCreating)
        .task { setup() }
    }

    // MARK: - Branch Field Variants

    @ViewBuilder
    private var branchPickerField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Strings.Sidebar.checkoutBranchLabel)
                .foregroundColor(.primary)
            TextField(Strings.Sidebar.checkoutBranchPlaceholder, text: $selectedBranch)
                .textFieldStyle(.roundedBorder)
                .focused($branchFieldFocused)
                .onChange(of: branchFieldFocused) { _, focused in
                    if focused && !branches.isEmpty { showBranchPopover = true }
                }
                .onChange(of: selectedBranch) { _, newValue in
                    if branchFieldFocused && !filteredBranches.isEmpty { showBranchPopover = true }
                    path = viewModel.inferWorktreePath(for: repo, branchName: newValue)
                }
                .popover(isPresented: $showBranchPopover, arrowEdge: .bottom) {
                    branchSuggestionList
                }
        }
    }

    @ViewBuilder
    private var branchReadOnlyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Strings.Sidebar.checkoutBranchLabel)
                .foregroundColor(.primary)
            Text(selectedBranch)
                .font(.body)
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
        }
    }

    // MARK: - Branch Suggestion List

    private var branchSuggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredBranches, id: \.self) { branch in
                    Button {
                        selectedBranch = branch
                        path = viewModel.inferWorktreePath(for: repo, branchName: branch)
                        showBranchPopover = false
                    } label: {
                        Text(branch)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 300, maxHeight: 200)
        .padding(.vertical, 4)
    }

    // MARK: - Private

    private func setup() {
        if let branch = preselectedBranch {
            selectedBranch = branch
            path = viewModel.inferWorktreePath(for: repo, branchName: branch)
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        do {
            try await viewModel.checkoutBranchAsWorktree(repo: repo, branch: selectedBranch, path: path)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
