import Foundation

/// Something that stops a Wheelhouse seat from running, and that the human
/// can fix.
public enum WheelhouseSeatIssue: Equatable, Sendable {
    /// ynh has no harness by the seat's command: `ynh run` says "not found".
    case notInstalled
    /// Delegates read from the Wheelhouse's own repository (`"git": "."`)
    /// whose paths are on disk but not committed. ynh reads them from git, so
    /// `ynh run` fails with "assembling delegates: … not found".
    case delegatesNotCommitted([String])
    /// Own-repository delegates whose paths are neither committed nor on disk.
    case delegatesMissing([String])
    /// The seat's last launch ended without its harness running, with the
    /// error line ynh printed.
    case launchFailed(String)
}

/// Checks a Wheelhouse seat can run. Reads the seat's harness manifest and
/// asks git; nothing here changes anything.
public enum WheelhouseSeatHealth {
    /// The seat's harness directory: its roster path, else the conventional
    /// `harnesses/<command>`, under the Wheelhouse root.
    public static func harnessDirectory(root: String, seat: WheelhouseSeat) -> String {
        URL(fileURLWithPath: root).appendingPathComponent(seat.harness ?? "harnesses/\(seat.command)").path
    }

    /// Paths of the delegates a manifest reads from its own repository: a
    /// `delegates_to` entry whose `git` is relative ("." or "./…") and that
    /// names a `path`.
    public static func ownRepoDelegatePaths(manifest data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let delegates = object["delegates_to"] as? [[String: Any]]
        else { return [] }
        return delegates.compactMap { entry in
            guard let git = entry["git"] as? String, git.hasPrefix("."),
                let path = entry["path"] as? String, !path.isEmpty
            else { return nil }
            return path
        }
    }

    /// Sorts own-repository delegate paths into issues, given which are
    /// committed and which are on disk.
    public static func delegateIssues(
        paths: [String], committed: (String) -> Bool, onDisk: (String) -> Bool
    ) -> [WheelhouseSeatIssue] {
        let absent = paths.filter { !committed($0) }
        let uncommitted = absent.filter(onDisk)
        let missing = absent.filter { !onDisk($0) }
        var issues: [WheelhouseSeatIssue] = []
        if !uncommitted.isEmpty { issues.append(.delegatesNotCommitted(uncommitted)) }
        if !missing.isEmpty { issues.append(.delegatesMissing(missing)) }
        return issues
    }

    /// The seat's delegate issues, read from its manifest and the git tree at
    /// HEAD. Empty when it has no own-repository delegates or git can't say.
    public static func delegateIssues(root: String, seat: WheelhouseSeat) async -> [WheelhouseSeatIssue] {
        let harnessDir = harnessDirectory(root: root, seat: seat)
        guard let manifestURL = HarnessManifestLayout.manifestURL(at: harnessDir),
            let data = try? Data(contentsOf: manifestURL)
        else { return [] }
        let paths = ownRepoDelegatePaths(manifest: data)
        guard !paths.isEmpty,
            let top = try? await StackProcessRunner.run(git, ["rev-parse", "--show-toplevel"], cwd: harnessDir),
            top.exitCode == 0
        else { return [] }
        let toplevel = top.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var committed: Set<String> = []
        for path in paths {
            if let tree = try? await StackProcessRunner.run(git, ["ls-tree", "HEAD", "--", path], cwd: toplevel),
                tree.exitCode == 0, !tree.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                committed.insert(path)
            }
        }
        return delegateIssues(
            paths: paths, committed: committed.contains,
            onDisk: {
                FileManager.default.fileExists(atPath: URL(fileURLWithPath: toplevel).appendingPathComponent($0).path)
            })
    }

    /// The last `Error:` line in a terminal's recent lines: what ynh printed
    /// when a run failed. Nil when there is none.
    public static func launchError(fromLines lines: [String]) -> String? {
        lines.reversed()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Error:") }
            .map { String($0.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces) }
    }

    /// The delegates (by their path's last component, such as `io`) a seat
    /// waits on, for "Install (needs io first)".
    public static func blockingDelegates(in issues: [WheelhouseSeatIssue]) -> [String] {
        issues.flatMap { issue -> [String] in
            switch issue {
            case .delegatesNotCommitted(let paths), .delegatesMissing(let paths):
                return paths.map { URL(fileURLWithPath: $0).lastPathComponent }
            case .notInstalled, .launchFailed:
                return []
            }
        }
    }

    private static let git = "/usr/bin/git"
}
