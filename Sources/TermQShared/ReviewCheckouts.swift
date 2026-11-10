import Foundation

/// Rules for review checkouts: the disposable worktrees TermQ makes so a
/// harness can look at a pull request that isn't checked out.
///
/// A review checkout lives at
/// `~/.termq/focus-worktrees/termq-focus--<host>--<org>--<repo>--<branch>--<pr>`.
/// It has a detached HEAD at the pull request's head, so making one never
/// creates a local branch. Everything here is pure, so the decisions that
/// delete files can be tested.
public enum ReviewCheckouts {
    /// Every review checkout's folder name starts with this.
    public static let directoryPrefix = "termq-focus-"

    /// The folder that holds every review checkout, relative to the home folder.
    public static let baseRelativePath = ".termq/focus-worktrees"

    /// The folder that holds every review checkout.
    public static func baseDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(baseRelativePath, isDirectory: true)
    }

    /// The folder name for `prNumber`'s review checkout.
    public static func directoryName(repoKey: String, headRefName: String, prNumber: Int) -> String {
        let branchSlug = String(
            headRefName.lowercased().map {
                $0.isLetter || $0.isNumber || $0 == "-" ? $0 : Character("-")
            })
        return "\(directoryPrefix)-\(repoKey)--\(branchSlug)--\(prNumber)"
    }

    /// The pull request number at the end of a review checkout's folder name.
    public static func prNumber(fromDirectoryName name: String) -> Int? {
        guard name.hasPrefix(directoryPrefix),
            let range = name.range(of: "--", options: .backwards)
        else { return nil }
        return Int(name[range.upperBound...])
    }

    /// Whether a folder name belongs to `repoKey`'s review checkouts.
    public static func belongs(directoryName name: String, toRepoKey repoKey: String) -> Bool {
        name.hasPrefix("\(directoryPrefix)-\(repoKey)--")
    }

    /// Whether `path` is a review checkout folder directly inside `base`.
    /// Only such paths may ever be deleted from disk.
    public static func isManaged(path: String, base: URL) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return url.deletingLastPathComponent().path == base.standardizedFileURL.path
            && url.lastPathComponent.hasPrefix(directoryPrefix)
    }

    /// `host--org--repo` from a git remote URL, SSH or HTTPS.
    public static func repoKey(fromRemoteURL remoteURL: String) -> String? {
        var urlString = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlString.hasPrefix("git@") {
            urlString = String(urlString.dropFirst(4))
            if let colon = urlString.firstIndex(of: ":") {
                let host = String(urlString[urlString.startIndex..<colon])
                let path = String(urlString[urlString.index(after: colon)...])
                urlString = "https://\(host)/\(path)"
            }
        }
        if urlString.hasSuffix(".git") { urlString = String(urlString.dropLast(4)) }
        if urlString.hasSuffix("/") { urlString = String(urlString.dropLast()) }
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        let parts = url.pathComponents.filter { !$0.isEmpty && $0 != "/" }
        guard !parts.isEmpty else { return nil }
        return ([host] + parts).joined(separator: "--")
    }

    /// What is known about a pull request's state.
    public enum PRState: Sendable, Equatable {
        case open
        case closed
        /// The open list was cut short or failed, so absence says nothing.
        case unknown
    }

    /// The state of `prNumber`, given the open pull requests that were listed.
    /// A missing number means closed only when the list is complete.
    public static func state(of prNumber: Int?, openNumbers: Set<Int>, listIsComplete: Bool) -> PRState {
        guard let prNumber else { return .unknown }
        if openNumbers.contains(prNumber) { return .open }
        return listIsComplete ? .closed : .unknown
    }

    /// Whether a terminal open in `cardDirectories` is working inside `path`.
    public static func hasOpenTerminal(at path: String, cardDirectories: [String]) -> Bool {
        let root = URL(fileURLWithPath: path).standardizedFileURL.path
        return cardDirectories.contains { dir in
            let cardPath = URL(fileURLWithPath: dir).standardizedFileURL.path
            return cardPath == root || cardPath.hasPrefix(root + "/")
        }
    }

    /// Whether a refresh may remove a review checkout without asking:
    /// git lists it, its pull request is closed, nothing is open in it, and
    /// it has no changes. Anything else, folders git doesn't list included,
    /// waits for the Prune sheet.
    public static func canAutoPrune(_ candidate: FocusWorktreeCandidate) -> Bool {
        candidate.prState == .closed && !candidate.hasOpenTerminal && !candidate.isDirty && !candidate.isOrphan
    }

    /// Whether the folder at `path` is a live worktree of some repository: it
    /// has a `.git` file whose `gitdir:` still exists. Such a folder is never
    /// an orphan, even when this repository's list doesn't name it (another
    /// clone of the same remote shares the folder-name prefix).
    public static func isLiveWorktree(at path: String) -> Bool {
        let gitFile = URL(fileURLWithPath: path).appendingPathComponent(".git")
        guard let contents = try? String(contentsOf: gitFile, encoding: .utf8) else {
            // A `.git` folder means a full repository: not ours to delete.
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: gitFile.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        guard let line = contents.split(separator: "\n").first, line.hasPrefix("gitdir:") else { return true }
        let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let resolved =
            gitdir.hasPrefix("/") ? gitdir : URL(fileURLWithPath: path).appendingPathComponent(gitdir).path
        return FileManager.default.fileExists(atPath: resolved)
    }

    /// The folders in the review checkout folder that belong to `repoKey`
    /// but that git no longer lists as worktrees. `registeredPaths` must come
    /// from git itself, not a cache; callers also drop live worktrees
    /// (`isLiveWorktree`) before treating these as orphans.
    public static func orphans(
        directoryNames: [String], repoKey: String, registeredPaths: Set<String>, base: URL
    )
        -> [String]
    {
        let registered = Set(registeredPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        return
            directoryNames
            .filter { belongs(directoryName: $0, toRepoKey: repoKey) }
            .map { base.appendingPathComponent($0).standardizedFileURL.path }
            .filter { !registered.contains($0) }
            .sorted()
    }
}
