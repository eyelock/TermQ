import Foundation

/// A bead waiting on the human: ready (nothing blocks it) and assigned to a
/// name the human answers to in the Wheelhouse.
public struct WheelhouseInboxItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let details: String?
    public let notes: String?
    /// The `inbox:<kind>` label, such as `merge` or `credential`.
    public let kind: String?
    public let priority: Int
    /// The seat that filed it (`created_by`).
    public let askedBy: String?
    /// The name it is assigned to: the general human name or the human's own.
    public let assignee: String
    /// The link it is about (`external_ref`), such as a pull request.
    public let externalRef: String?
    /// How many beads wait on this one.
    public let unblocks: Int

    public init(
        id: String, title: String, details: String? = nil, notes: String? = nil, kind: String? = nil,
        priority: Int = 2, askedBy: String? = nil, assignee: String, externalRef: String? = nil, unblocks: Int = 0
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.notes = notes
        self.kind = kind
        self.priority = priority
        self.askedBy = askedBy
        self.assignee = assignee
        self.externalRef = externalRef
        self.unblocks = unblocks
    }

    /// The link's short form, as the wheelhouse inbox script writes it:
    /// `<repo> #<n>` for a pull request or issue, `<repo> run <id>` for a CI
    /// run, `<repo> <sha>` for a commit. Nil for other links.
    public var externalRefShortName: String? {
        guard let externalRef, let url = URL(string: externalRef), url.host == "github.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 4 else { return nil }
        let repo = parts[1]
        switch parts[2] {
        case "pull", "issues": return "\(repo) #\(parts[3])"
        case "commit": return "\(repo) \(parts[3].prefix(7))"
        case "actions" where parts.count >= 5 && parts[3] == "runs": return "\(repo) run \(parts[4])"
        default: return nil
        }
    }

    /// Reports are for reading; they sort after beads that need doing.
    public var isReport: Bool { kind == "report" }
}

/// The human's inbox in a Wheelhouse: `bd ready --assignee <name> --json`,
/// read-only, for each name the human answers to.
public enum WheelhouseInbox {
    /// The general name a Wheelhouse uses for "a human", by default.
    public static let defaultHumanName = "stakker"

    /// The names to read, in order: the general human name, then the human's
    /// own, trimmed, without blanks or repeats.
    public static func assignees(humanName: String, ownName: String) -> [String] {
        var names: [String] = []
        for name in [humanName, ownName] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !names.contains(trimmed) { names.append(trimmed) }
        }
        return names
    }

    /// `bd ready --json` output → the beads assigned to `assignee`, epics left
    /// out. Nil when the output can't be read, so a failed read is never
    /// shown as an empty inbox.
    public static func parse(_ data: Data, assignee: String) -> [WheelhouseInboxItem]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let items: [[String: Any]]
        if let array = json as? [[String: Any]] {
            items = array
        } else if let object = json as? [String: Any], let array = object["data"] as? [[String: Any]] {
            items = array
        } else {
            return nil
        }
        return items.compactMap { item in
            guard
                let id = item["id"] as? String,
                let title = item["title"] as? String,
                (item["issue_type"] as? String) != "epic"
            else { return nil }
            let labels = item["labels"] as? [String] ?? []
            let kind = labels.first { $0.hasPrefix("inbox:") }.map { String($0.dropFirst("inbox:".count)) }
            return WheelhouseInboxItem(
                id: id, title: title,
                details: nonEmpty(item["description"] as? String),
                notes: nonEmpty(item["notes"] as? String),
                kind: kind,
                priority: item["priority"] as? Int ?? 2,
                askedBy: nonEmpty(item["created_by"] as? String),
                assignee: nonEmpty(item["assignee"] as? String) ?? assignee,
                externalRef: nonEmpty(item["external_ref"] as? String),
                unblocks: item["dependent_count"] as? Int ?? 0)
        }
    }

    /// One list from several names' reads: each bead once, beads to do before
    /// reports, then by priority, then in read order.
    public static func merge(_ lists: [[WheelhouseInboxItem]]) -> [WheelhouseInboxItem] {
        var seen: Set<String> = []
        let unique = lists.joined().filter { seen.insert($0.id).inserted }
        return unique.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element
                let right = rhs.element
                if left.isReport != right.isReport { return !left.isReport }
                if left.priority != right.priority { return left.priority < right.priority }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Reads the inbox for `assignees` in `root`. Nil when `bd` is missing or
    /// any read fails; never throws.
    public static func fetch(root: String, assignees: [String]) async -> [WheelhouseInboxItem]? {
        guard !assignees.isEmpty else { return [] }
        guard let bd = WheelhouseWork.findBd() else { return nil }
        var lists: [[WheelhouseInboxItem]] = []
        for assignee in assignees {
            guard
                let result = try? await StackProcessRunner.run(
                    bd, ["ready", "--assignee", assignee, "--json"], cwd: root, env: ["NO_COLOR": "1"]),
                result.exitCode == 0,
                let items = parse(Data(result.stdout.utf8), assignee: assignee)
            else { return nil }
            lists.append(items)
        }
        return merge(lists)
    }

    // MARK: - Responding

    /// What the human can do to an inbox bead from TermQ.
    public enum Response: Equatable, Sendable {
        /// Adds a comment, such as the answer to a decision; the bead stays open.
        case comment(String)
        /// Closes the bead, with an optional reason.
        case close(reason: String)
    }

    /// The `bd` arguments for `response` on bead `id`, or nil when a comment
    /// has no text. It runs as `actor`, the name the bead is assigned to and
    /// the human answers to, since bd only lets the assignee close a bead.
    public static func arguments(for response: Response, id: String, actor: String) -> [String]? {
        switch response {
        case .comment(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            // `--` ends the flags, so a comment such as "-1 on this" stays text.
            return ["comments", "add", id, "--actor", actor, "--", trimmed]
        case .close(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = trimmed.isEmpty ? [] : ["--reason", trimmed]
            return ["close", id] + reason + ["--actor", actor]
        }
    }

    /// Runs `response` on `item` in `root`. Returns nil on success, or what
    /// went wrong.
    public static func respond(_ response: Response, to item: WheelhouseInboxItem, root: String) async -> String? {
        guard let args = arguments(for: response, id: item.id, actor: item.assignee) else { return nil }
        guard let bd = WheelhouseWork.findBd() else { return "bd not found" }
        do {
            let result = try await StackProcessRunner.run(bd, args, cwd: root, env: ["NO_COLOR": "1"])
            guard result.exitCode != 0 else { return nil }
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "bd exited with status \(result.exitCode)" : message
        } catch {
            return error.localizedDescription
        }
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }
}
