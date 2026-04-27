import SwiftUI
import TermQCore

/// Sheet for creating a new git worktree from the sidebar.
///
/// Loads branches in the background; the Base Branch field is a typeahead
/// text input that defaults to the repo's default branch and filters as you type.
struct NewWorktreeSheet: View {
    let repo: ObservableRepository
    let initialBaseBranch: String?
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var branchName: String = ""
    @State private var baseBranch: String = ""
    @State private var path: String = ""
    @State private var availableBranches: [String] = []
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var showBranchPopover = false
    @FocusState private var baseBranchFocused: Bool

    private var filteredBranches: [String] {
        let query = baseBranch.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return Array(availableBranches.prefix(8)) }
        return availableBranches.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.newWorktreeTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Sidebar.branchNameLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Sidebar.branchNamePlaceholder, text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: branchName) { _, newValue in
                        path = viewModel.inferWorktreePath(for: repo, branchName: newValue)
                        // inferWorktreePath returns "" for empty input, so path clears too
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Sidebar.baseBranchLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Sidebar.baseBranchPlaceholder, text: $baseBranch)
                    .textFieldStyle(.roundedBorder)
                    .focused($baseBranchFocused)
                    .onChange(of: baseBranchFocused) { _, focused in
                        if focused && !availableBranches.isEmpty {
                            showBranchPopover = true
                        }
                    }
                    .onChange(of: baseBranch) { _, newValue in
                        if baseBranchFocused && !filteredBranches.isEmpty {
                            showBranchPopover = true
                        }
                        // Restore default branch when field is cleared
                        if newValue.isEmpty {
                            Task { baseBranch = await viewModel.defaultBranch(for: repo) }
                        }
                    }
                    .popover(isPresented: $showBranchPopover, arrowEdge: .bottom) {
                        branchSuggestionList
                    }
            }

            PathInputField(
                label: Strings.Sidebar.worktreePathLabel,
                path: $path,
                placeholder: viewModel.inferWorktreePath(for: repo, branchName: Strings.Sidebar.branchNamePlaceholder),
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
                Button(Strings.Sidebar.cancelButton) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(Strings.Sidebar.createButton) {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.isEmpty || path.isEmpty || isCreating)
                .help(
                    branchName.isEmpty
                        ? Strings.Sidebar.newWorktreeBranchRequired
                        : path.isEmpty ? Strings.Sidebar.newWorktreePathRequired : ""
                )
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(isCreating)
        .task { await loadData() }
    }

    // MARK: - Branch Suggestion List

    private var branchSuggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredBranches, id: \.self) { branch in
                    Button {
                        baseBranch = branch
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

    private func loadData() async {
        do {
            availableBranches = try await viewModel.listBranches(for: repo)
        } catch {
            errorMessage = error.localizedDescription
        }
        guard baseBranch.isEmpty else { return }
        if let initial = initialBaseBranch, !initial.isEmpty {
            baseBranch = initial
        } else {
            baseBranch = await viewModel.defaultBranch(for: repo)
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        do {
            try await viewModel.createWorktree(
                repo: repo,
                branchName: branchName,
                baseBranch: baseBranch.isEmpty ? nil : baseBranch,
                path: path
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
