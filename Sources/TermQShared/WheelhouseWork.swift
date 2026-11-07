import Foundation

/// A bead a seat has in progress, read from the Wheelhouse's work graph.
public struct WheelhouseBead: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let assignee: String
    /// The pull request the bead waits on, from a `PR: <url>` line in its notes.
    public let pullRequestURL: String?

    public init(id: String, title: String, assignee: String, pullRequestURL: String? = nil) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.pullRequestURL = pullRequestURL
    }

    /// Short form of the pull request URL, such as `ynh #754`.
    public var pullRequestShortName: String? {
        guard let url = pullRequestURL, let parsed = URL(string: url) else { return nil }
        let parts = parsed.path.split(separator: "/")
        guard parts.count >= 4, parts[2] == "pull" else { return nil }
        return "\(parts[1]) #\(parts[3])"
    }
}

/// What the seats of a Wheelhouse are working on.
///
/// Read with `bd list --status in_progress --json` in the Wheelhouse root:
/// read-only, no sync. Beads' JSON is an array, or `{"data": [...]}` with the
/// Beads 2.0 envelope; both are accepted.
public enum WheelhouseWork {
    /// In-progress beads keyed by assignee (the seat's command), each list in
    /// the order `bd` returned it.
    public static func parseInProgress(_ data: Data) -> [String: [WheelhouseBead]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        let items: [[String: Any]]
        if let array = json as? [[String: Any]] {
            items = array
        } else if let object = json as? [String: Any], let array = object["data"] as? [[String: Any]] {
            items = array
        } else {
            return [:]
        }
        var result: [String: [WheelhouseBead]] = [:]
        for item in items {
            guard
                let id = item["id"] as? String,
                let title = item["title"] as? String,
                let assignee = item["assignee"] as? String, !assignee.isEmpty
            else { continue }
            let notes = item["notes"] as? String ?? ""
            let bead = WheelhouseBead(
                id: id, title: title, assignee: assignee, pullRequestURL: lastPullRequestURL(in: notes))
            result[assignee, default: []].append(bead)
        }
        return result
    }

    /// The last `PR: <url>` in a bead's notes, as `wake.sh` reads it.
    public static func lastPullRequestURL(in notes: String) -> String? {
        var found: String?
        var searchRange = notes.startIndex..<notes.endIndex
        while let marker = notes.range(of: "PR: ", range: searchRange) {
            let rest = notes[marker.upperBound...]
            let url = rest.prefix { !$0.isWhitespace }
            if url.hasPrefix("http://") || url.hasPrefix("https://") { found = String(url) }
            searchRange = marker.upperBound..<notes.endIndex
        }
        return found
    }

    /// Where `bd` usually lives. A GUI app doesn't inherit the login shell's PATH.
    public static let bdCandidates = [
        "/opt/homebrew/bin/bd",
        "/usr/local/bin/bd",
        "\(NSHomeDirectory())/.local/bin/bd",
        "\(NSHomeDirectory())/go/bin/bd",
    ]

    public static func findBd(candidates: [String] = bdCandidates) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `bd list --status in_progress --json` in `root`. Returns nil when
    /// `bd` is missing or fails; never throws.
    public static func fetchInProgress(root: String) async -> [String: [WheelhouseBead]]? {
        guard let bd = findBd() else { return nil }
        guard
            let result = try? await StackProcessRunner.run(
                bd, ["list", "--status", "in_progress", "--json"], cwd: root,
                env: ["NO_COLOR": "1"]),
            result.exitCode == 0
        else { return nil }
        return parseInProgress(Data(result.stdout.utf8))
    }
}

extension WheelhouseGroup {
    /// Whether the human talks to this group's seats directly. Desk and crew
    /// are conversations; standing roles and workers run unattended and are
    /// reached through the desk and the dispatcher, so they show as status.
    public var isConversational: Bool {
        switch self {
        case .desk, .crew: return true
        case .standing, .workers: return false
        case .other: return true
        }
    }
}

/// Whether a seat has had its first session: the birth skill pins the seat's
/// identity in ynm (namespace `seat/<command>`, tag `identity`).
public enum WheelhouseIdentity {
    public static let ynmCandidates = [
        "\(NSHomeDirectory())/.ynm/bin/ynm",
        "/opt/homebrew/bin/ynm",
        "/usr/local/bin/ynm",
        "\(NSHomeDirectory())/.local/bin/ynm",
    ]

    /// `ynm recall --json` output → true when it holds a memory, false when it
    /// is an empty list, nil when it can't be read.
    public static func hasIdentity(recallOutput data: Data) -> Bool? {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        return !array.isEmpty
    }

    /// Asks ynm, from the Wheelhouse root, whether the seat has an identity.
    /// Nil when ynm is missing or fails: unknown, so no birth is offered.
    public static func isBorn(seatCommand: String, root: String) async -> Bool? {
        guard let ynm = ynmCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        guard
            let result = try? await StackProcessRunner.run(
                ynm,
                [
                    "recall", "--namespace", "seat/\(seatCommand)", "--subject", "seat:\(seatCommand)",
                    "--tags", "identity", "--limit", "1", "--json",
                ],
                cwd: root),
            result.exitCode == 0
        else { return nil }
        return hasIdentity(recallOutput: Data(result.stdout.utf8))
    }
}
