import SwiftUI

/// Sheet for registering a new git repository in the sidebar.
///
/// Validates the path via `git rev-parse --git-dir` before adding.
/// Infers the display name from the remote URL when the user leaves the name field empty.
/// The worktree base path defaults to `.worktrees/` inside the repo; when the base path is
/// nested inside the repo a checkbox offers to add it to `.gitignore` automatically.
struct AddRepositorySheet: View {
    @ObservedObject var viewModel: WorktreeSidebarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var path: String = ""
    @State private var name: String = ""
    @State private var worktreeBasePath: String = ""
    /// Tracks the auto-derived base path so we know when the user has manually overridden it.
    @State private var derivedBasePath: String = ""
    @State private var addToGitignore: Bool = true
    @State private var isAdding: Bool = false
    @State private var errorMessage: String?

    /// Placeholder for the base path field — shows the derived default even before the
    /// user has typed anything, updating live as the repo path is filled in.
    private var basePathPlaceholder: String {
        path.isEmpty ? Strings.Sidebar.worktreeBasePathPlaceholder : path + "/.worktrees"
    }

    /// Non-nil when the worktree base path is invalid relative to the repo path.
    /// Blocks the Add button and shows an inline warning.
    private var basePathValidationError: String? {
        guard !path.isEmpty, !worktreeBasePath.isEmpty else { return nil }
        let base = URL(fileURLWithPath: worktreeBasePath).standardized.path
        let repo = URL(fileURLWithPath: path).standardized.path
        if base == repo {
            return Strings.Sidebar.basePathEqualsRepo
        }
        if repo.hasPrefix(base + "/") {
            return Strings.Sidebar.basePathIsParentOfRepo
        }
        return nil
    }

    /// Non-empty when `worktreeBasePath` is nested inside `path` — the relative segment
    /// to add to `.gitignore`, e.g. `.worktrees/`.
    private var gitignoreEntry: String? {
        guard !path.isEmpty, !worktreeBasePath.isEmpty else { return nil }
        let repoPath = URL(fileURLWithPath: path).standardized.path
        let basePath = URL(fileURLWithPath: worktreeBasePath).standardized.path
        let prefix = repoPath + "/"
        guard basePath.hasPrefix(prefix) else { return nil }
        let relative = String(basePath.dropFirst(prefix.count))
        guard !relative.isEmpty else { return nil }
        return relative.hasSuffix("/") ? relative : relative + "/"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.Sidebar.addRepositoryTitle)
                .font(.title2)
                .fontWeight(.semibold)

            PathInputField(
                label: Strings.Sidebar.pathLabel,
                path: $path,
                validatePath: true
            )
            .onChange(of: path) { _, newPath in
                let derived = newPath.isEmpty ? "" : newPath + "/.worktrees"
                // Follow the auto-derived path until the user manually overrides it.
                if worktreeBasePath == derivedBasePath {
                    worktreeBasePath = derived
                }
                derivedBasePath = derived
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Sidebar.nameLabel)
                    .foregroundColor(.primary)
                TextField(Strings.Sidebar.namePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            PathInputField(
                label: Strings.Sidebar.worktreeBasePathLabel,
                path: $worktreeBasePath,
                placeholder: basePathPlaceholder,
                helpText: Strings.Sidebar.worktreeBasePathHelp,
                validatePath: false
            )

            if let validationError = basePathValidationError {
                Text(validationError)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let entry = gitignoreEntry {
                Toggle(isOn: $addToGitignore) {
                    Text(Strings.Sidebar.addToGitignore(entry))
                        .font(.subheadline)
                }
                .toggleStyle(.checkbox)
            }

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

                Button(Strings.Sidebar.addButton) {
                    Task { await addRepository() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(path.isEmpty || isAdding || basePathValidationError != nil)
            }
        }
        .padding(24)
        .frame(width: 420)
        .disabled(isAdding)
    }

    private func addRepository() async {
        isAdding = true
        errorMessage = nil
        do {
            try await viewModel.addRepository(
                path: path,
                name: name.isEmpty ? nil : name,
                worktreeBasePath: worktreeBasePath.isEmpty ? nil : worktreeBasePath,
                addToGitignore: addToGitignore && gitignoreEntry != nil
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAdding = false
    }
}
