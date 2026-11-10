import Foundation

/// An open pull request that asks the human for a review, from
/// `gh search prs --review-requested=@me`.
public struct ReviewRequest: Equatable, Sendable, Identifiable {
    public let number: Int
    public let title: String
    public let url: String
    /// `owner/name`.
    public let repository: String
    public let author: String?
    public let isDraft: Bool
    public let createdAt: Date
    /// When the human was asked, from the PR's timeline; nil until known.
    public var requestedAt: Date?

    public var id: String { url }
    /// When the wait started: the request, else (unknown) the PR opening.
    public var waitingSince: Date { requestedAt ?? createdAt }

    public init(
        number: Int, title: String, url: String, repository: String, author: String?, isDraft: Bool,
        createdAt: Date, requestedAt: Date? = nil
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.author = author
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.requestedAt = requestedAt
    }
}

/// How long a review has been waiting, for grouping the Actions list.
public enum ReviewWait: Int, CaseIterable, Sendable, Comparable {
    case today, thisWeek, thisMonth, older

    public static func < (lhs: ReviewWait, rhs: ReviewWait) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func of(_ since: Date, now: Date) -> ReviewWait {
        let age = now.timeIntervalSince(since)
        switch age {
        case ..<(24 * 3600): return .today
        case ..<(7 * 24 * 3600): return .thisWeek
        case ..<(30 * 24 * 3600): return .thisMonth
        default: return .older
        }
    }
}

public enum ReviewRequests {
    /// The `gh search prs` fields this reads.
    public static let searchFields = "number,title,url,repository,author,isDraft,createdAt"

    /// Decodes `gh search prs --json <searchFields>` output.
    public static func decodeSearch(_ data: Data) -> [ReviewRequest]? {
        let date = DateParser()
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        return array.compactMap { item in
            guard let number = item["number"] as? Int, let title = item["title"] as? String,
                let url = item["url"] as? String,
                let repository = (item["repository"] as? [String: Any])?["nameWithOwner"] as? String,
                let created = (item["createdAt"] as? String).flatMap(date.callAsFunction)
            else { return nil }
            let author = (item["author"] as? [String: Any])?["login"] as? String
            return ReviewRequest(
                number: number, title: title, url: url, repository: repository, author: author,
                isDraft: item["isDraft"] as? Bool ?? false, createdAt: created)
        }
    }

    /// One GraphQL query asking each PR's review-request events, aliased
    /// `pr0`, `pr1`, … in the order given.
    public static func timelineQuery(for requests: [ReviewRequest]) -> String {
        let fields = requests.enumerated().compactMap { index, request -> String? in
            let parts = request.repository.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return """
                pr\(index): repository(owner: \(quoted(parts[0])), name: \(quoted(parts[1]))) { \
                pullRequest(number: \(request.number)) { \
                timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 50) { \
                nodes { ... on ReviewRequestedEvent { createdAt requestedReviewer { \
                ... on User { login } ... on Team { slug } } } } } } }
                """
        }
        return "query { " + fields.joined(separator: " ") + " }"
    }

    /// Each PR's review-request time from the GraphQL answer, by alias index:
    /// the latest request to `login`, else the latest request at all (made
    /// to a team the human is in). Reads partial `data` too: gh exits non-zero
    /// when one PR can't be read (SAML, no access), and the rest still count.
    public static func requestTimes(fromGraphQL data: Data, login: String) -> [Int: Date] {
        let date = DateParser()
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let dataObject = root["data"] as? [String: Any]
        else { return [:] }
        var times: [Int: Date] = [:]
        for (alias, value) in dataObject {
            guard alias.hasPrefix("pr"), let index = Int(alias.dropFirst(2)),
                let nodes =
                    (((value as? [String: Any])?["pullRequest"] as? [String: Any])?["timelineItems"]
                    as? [String: Any])?["nodes"] as? [[String: Any]]
            else { continue }
            let events = nodes.compactMap { node -> (Date, String?)? in
                guard let created = (node["createdAt"] as? String).flatMap(date.callAsFunction) else { return nil }
                let reviewer = node["requestedReviewer"] as? [String: Any]
                return (created, reviewer?["login"] as? String)
            }
            let mine = events.filter { $0.1?.caseInsensitiveCompare(login) == .orderedSame }
            if let latest = (mine.isEmpty ? events : mine).map(\.0).max() { times[index] = latest }
        }
        return times
    }

    /// The Actions list: groups by how long each review has waited, the
    /// longest wait first within each group.
    public static func grouped(
        _ requests: [ReviewRequest], now: Date
    ) -> [(wait: ReviewWait, requests: [ReviewRequest])] {
        let byWait = Dictionary(grouping: requests) { ReviewWait.of($0.waitingSince, now: now) }
        return ReviewWait.allCases.compactMap { wait in
            guard let items = byWait[wait], !items.isEmpty else { return nil }
            return (wait, items.sorted { $0.waitingSince < $1.waitingSince })
        }
    }

    /// `owner/name` from a GitHub remote URL, else nil: `https://github.com/o/r`,
    /// `ssh://git@github.com[:port]/o/r` or `git@github.com:o/r`, with or
    /// without `.git`. Only the github.com host counts.
    public static func nameWithOwner(fromRemote remote: String) -> String? {
        let text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if let url = URL(string: text), let host = url.host?.lowercased(), url.scheme != nil {
            guard host == "github.com" || host == "www.github.com" else { return nil }
            path = url.path
        } else if let colon = text.firstIndex(of: ":"), text[..<colon].lowercased().hasSuffix("@github.com") {
            path = String(text[text.index(after: colon)...])
        } else {
            return nil
        }
        var trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix(".git") { trimmed = String(trimmed.dropLast(4)) }
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    /// Keeps the requests in the TermQ repositories `names` (owner/name,
    /// any case).
    public static func inRepositories(_ requests: [ReviewRequest], names: Set<String>) -> [ReviewRequest] {
        let lowered = Set(names.map { $0.lowercased() })
        return requests.filter { lowered.contains($0.repository.lowercased()) }
    }

    /// Gives each request its time from `known` (by URL), and returns the
    /// indices still without one, to ask GitHub about.
    public static func applyKnown(_ requests: inout [ReviewRequest], known: [String: Date]) -> [Int] {
        for index in requests.indices { requests[index].requestedAt = known[requests[index].url] }
        return requests.indices.filter { requests[$0].requestedAt == nil }
    }

    /// Writes the GraphQL `times` (by position among `asked`) into
    /// `requests`. Ones it has no time for keep nil: grouped by opening.
    public static func applyTimes(_ times: [Int: Date], to requests: inout [ReviewRequest], asked: [Int]) {
        for (offset, index) in asked.enumerated() { requests[index].requestedAt = times[offset] }
    }

    /// The most `gh search prs` returns; a full page may be missing some.
    public static let searchLimit = 100

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Parses GitHub's timestamps, with or without fractional seconds. Two
    /// formatters per parse run, not per value.
    struct DateParser {
        private let plain = ISO8601DateFormatter()
        private let fractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        func callAsFunction(_ text: String) -> Date? { plain.date(from: text) ?? fractional.date(from: text) }
    }
}
