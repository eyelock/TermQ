import Foundation

// MARK: - Roster

/// The roster of a Wheelhouse, decoded from `skills/roster/assets/roster.json`.
///
/// A Wheelhouse (built with the `wheelhouse` plugin from eyelock/assistants) is a
/// repository whose seats are named ynh harnesses. TermQ only reads the roster;
/// unknown keys are ignored so the plugin can grow the file freely.
public struct WheelhouseRoster: Codable, Equatable, Sendable {
    /// Optional schema version of the roster file.
    public let version: Int?
    /// Optional Wheelhouse-level metadata (`"wheelhouse": {"title": …}`).
    public let wheelhouse: Meta?
    public let seats: [WheelhouseSeat]

    public struct Meta: Codable, Equatable, Sendable {
        public let title: String?

        public init(title: String?) {
            self.title = title
        }
    }

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case wheelhouse
        case seats
    }

    public init(version: Int? = nil, wheelhouse: Meta? = nil, seats: [WheelhouseSeat]) {
        self.version = version
        self.wheelhouse = wheelhouse
        self.seats = seats
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try? c.decodeIfPresent(Int.self, forKey: .version)
        wheelhouse = try? c.decodeIfPresent(Meta.self, forKey: .wheelhouse)
        // Skip individual seats that fail to decode rather than losing the whole roster.
        let raw = (try? c.decodeIfPresent([LossySeat].self, forKey: .seats)) ?? []
        seats = raw.compactMap(\.seat)
    }

    private struct LossySeat: Decodable {
        let seat: WheelhouseSeat?
        init(from decoder: Decoder) throws {
            seat = try? WheelhouseSeat(from: decoder)
        }
    }
}

/// One seat in a Wheelhouse roster.
public struct WheelhouseSeat: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let group: WheelhouseGroup
    /// The seat's command, also its ynh harness name (`~/.ynh/bin/<command>`).
    public let command: String
    /// Path of the seat's harness, relative to the Wheelhouse root.
    public let harness: String?
    /// One-sentence description of what the seat is for.
    public let mandate: String?
    /// The add-seat template the seat was made from, such as `reviewer`.
    public let role: WheelhouseRole?
    /// Bead labels the seat specialises in, such as `repo:ynh`.
    public let specialities: [String]
    public let pronouns: String?

    public var id: String { command }

    enum CodingKeys: String, CodingKey {
        case name, group, command, harness, mandate, role, specialities, pronouns
    }

    public init(
        name: String,
        group: WheelhouseGroup,
        command: String,
        harness: String? = nil,
        mandate: String? = nil,
        role: WheelhouseRole? = nil,
        specialities: [String] = [],
        pronouns: String? = nil
    ) {
        self.name = name
        self.group = group
        self.command = command
        self.harness = harness
        self.mandate = mandate
        self.role = role
        self.specialities = specialities
        self.pronouns = pronouns
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        command = try c.decode(String.self, forKey: .command)
        let groupRaw = try? c.decodeIfPresent(String.self, forKey: .group)
        group = WheelhouseGroup(rawValue: groupRaw ?? "")
        harness = try? c.decodeIfPresent(String.self, forKey: .harness)
        mandate = try? c.decodeIfPresent(String.self, forKey: .mandate)
        let roleRaw = try? c.decodeIfPresent(String.self, forKey: .role)
        role = roleRaw.flatMap { $0.isEmpty ? nil : WheelhouseRole(rawValue: $0) }
        specialities = (try? c.decodeIfPresent([String].self, forKey: .specialities)) ?? []
        pronouns = try? c.decodeIfPresent(String.self, forKey: .pronouns)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(group.rawValue, forKey: .group)
        try c.encode(command, forKey: .command)
        try c.encodeIfPresent(harness, forKey: .harness)
        try c.encodeIfPresent(mandate, forKey: .mandate)
        try c.encodeIfPresent(role?.rawValue, forKey: .role)
        if !specialities.isEmpty { try c.encode(specialities, forKey: .specialities) }
        try c.encodeIfPresent(pronouns, forKey: .pronouns)
    }

    /// The role to show: the roster's `role`, or the desk for a desk seat without one.
    public var effectiveRole: WheelhouseRole? {
        if let role { return role }
        return group == .desk ? .desk : nil
    }

    /// Repositories from `repo:<name>` specialities, in roster order.
    public var repositories: [String] {
        specialities.compactMap { label in
            guard label.hasPrefix("repo:") else { return nil }
            let repo = String(label.dropFirst("repo:".count))
            return repo.isEmpty ? nil : repo
        }
    }
}

// MARK: - Groups and roles

/// The seat groups the wheelhouse plugin defines, in display order.
public enum WheelhouseGroup: Equatable, Hashable, Sendable {
    case desk
    case crew
    case standing
    case workers
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "desk": self = .desk
        case "crew": self = .crew
        case "standing": self = .standing
        case "workers": self = .workers
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .desk: return "desk"
        case .crew: return "crew"
        case .standing: return "standing"
        case .workers: return "workers"
        case .other(let raw): return raw
        }
    }

    /// Sort key: known groups first in plugin order, others after.
    public var sortOrder: Int {
        switch self {
        case .desk: return 0
        case .crew: return 1
        case .standing: return 2
        case .workers: return 3
        case .other: return 4
        }
    }
}

/// A seat's role, from the add-seat template it was made from.
public enum WheelhouseRole: Equatable, Hashable, Sendable {
    case desk
    case designer
    case reviewer
    case dispatcher
    case ciWatcher
    case releaser
    case verifier
    case programmeManager
    case tutor
    case specialistWorker
    case worker
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "desk": self = .desk
        case "designer": self = .designer
        case "reviewer": self = .reviewer
        case "dispatcher": self = .dispatcher
        case "ci-watcher": self = .ciWatcher
        case "releaser": self = .releaser
        case "verifier": self = .verifier
        case "programme-manager", "program-manager": self = .programmeManager
        case "tutor": self = .tutor
        case "specialist-worker": self = .specialistWorker
        case "worker": self = .worker
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .desk: return "desk"
        case .designer: return "designer"
        case .reviewer: return "reviewer"
        case .dispatcher: return "dispatcher"
        case .ciWatcher: return "ci-watcher"
        case .releaser: return "releaser"
        case .verifier: return "verifier"
        case .programmeManager: return "programme-manager"
        case .tutor: return "tutor"
        case .specialistWorker: return "specialist-worker"
        case .worker: return "worker"
        case .other(let raw): return raw
        }
    }

    /// SF Symbol for the role.
    public var symbolName: String {
        switch self {
        case .desk: return "steeringwheel"
        case .designer: return "pencil.and.ruler"
        case .reviewer: return "checkmark.seal"
        case .dispatcher: return "arrow.left.arrow.right"
        case .ciWatcher: return "eye"
        case .releaser: return "shippingbox"
        case .verifier: return "checklist"
        case .programmeManager: return "map"
        case .tutor: return "graduationcap"
        case .specialistWorker, .worker: return "hammer"
        case .other: return "person"
        }
    }

    /// Fallback label for an unknown slug: `release-captain` → `Release Captain`.
    public var titleCasedSlug: String {
        rawValue
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// MARK: - Wheelhouse

/// A Wheelhouse discovered on disk: its root folder and its roster.
public struct Wheelhouse: Equatable, Sendable, Identifiable {
    /// Absolute path of the Wheelhouse repository root.
    public let root: String
    public let roster: WheelhouseRoster
    /// Each seat's harness focuses, keyed by seat command, read from its
    /// harness manifest. Seats whose manifest can't be read have none.
    public let harnesses: [String: WheelhouseSeatHarness]

    public var id: String { root }

    public init(root: String, roster: WheelhouseRoster, harnesses: [String: WheelhouseSeatHarness] = [:]) {
        self.root = root
        self.roster = roster
        self.harnesses = harnesses
    }

    /// The focuses a seat can be launched with, in manifest order.
    public func focuses(for seat: WheelhouseSeat) -> [WheelhouseFocus] {
        harnesses[seat.command]?.focuses ?? []
    }

    /// The roster's title, else the root folder's name.
    public var title: String {
        if let title = roster.wheelhouse?.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            return title
        }
        return URL(fileURLWithPath: root).lastPathComponent
    }

    /// Short name: the root folder's name.
    public var name: String {
        URL(fileURLWithPath: root).lastPathComponent
    }

    public var seats: [WheelhouseSeat] { roster.seats }

    /// Seats grouped by group, groups in plugin order, seats in roster order.
    public var seatsByGroup: [(group: WheelhouseGroup, seats: [WheelhouseSeat])] {
        var order: [WheelhouseGroup] = []
        var buckets: [WheelhouseGroup: [WheelhouseSeat]] = [:]
        for seat in roster.seats {
            if buckets[seat.group] == nil { order.append(seat.group) }
            buckets[seat.group, default: []].append(seat)
        }
        let sorted = order.enumerated().sorted { lhs, rhs in
            if lhs.element.sortOrder != rhs.element.sortOrder {
                return lhs.element.sortOrder < rhs.element.sortOrder
            }
            return lhs.offset < rhs.offset
        }
        return sorted.map { (group: $0.element, seats: buckets[$0.element] ?? []) }
    }
}

// MARK: - Loader

/// Finds and reads Wheelhouses on disk.
public enum WheelhouseLoader {
    /// Roster path relative to a Wheelhouse root.
    public static let rosterRelativePath = "skills/roster/assets/roster.json"

    public static func rosterURL(root: String) -> URL {
        URL(fileURLWithPath: root).appendingPathComponent(rosterRelativePath)
    }

    /// A folder path as typed or pasted: whitespace and wrapping quotes
    /// trimmed, `~` expanded, `file://` URLs read, and the result put in
    /// standard form. Nil when nothing usable is left.
    public static func normalizedRoot(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for quote in ["\"", "'"] where text.count >= 2 && text.hasPrefix(quote) && text.hasSuffix(quote) {
            text = String(text.dropFirst().dropLast())
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("file://"), let url = URL(string: text), url.isFileURL {
            text = url.path
        }
        text = (text as NSString).expandingTildeInPath
        guard text.hasPrefix("/") else { return nil }
        let path = URL(fileURLWithPath: text).standardizedFileURL.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Whether `root` holds a roster file.
    public static func isWheelhouse(root: String) -> Bool {
        FileManager.default.fileExists(atPath: rosterURL(root: root).path)
    }

    /// Reads the Wheelhouse at `root`. Returns nil when there is no roster;
    /// throws when the roster exists but cannot be read or decoded.
    public static func load(root: String) throws -> Wheelhouse? {
        let url = rosterURL(root: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let roster = try JSONDecoder().decode(WheelhouseRoster.self, from: data)
        var harnesses: [String: WheelhouseSeatHarness] = [:]
        for seat in roster.seats {
            if let harness = loadSeatHarness(root: root, seat: seat) { harnesses[seat.command] = harness }
        }
        return Wheelhouse(root: root, roster: roster, harnesses: harnesses)
    }

    /// Where a seat's harness manifest may live, relative to its harness folder.
    public static let manifestCandidates = [".agents/harness/plugin.json", ".ynh-plugin/plugin.json", "plugin.json"]

    /// Reads a seat's harness manifest; nil when it has no harness path or no
    /// readable manifest.
    public static func loadSeatHarness(root: String, seat: WheelhouseSeat) -> WheelhouseSeatHarness? {
        guard let harness = seat.harness, !harness.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: root).appendingPathComponent(harness)
        for candidate in manifestCandidates {
            let url = folder.appendingPathComponent(candidate)
            if let data = try? Data(contentsOf: url), let parsed = WheelhouseSeatHarness.parse(data) {
                return parsed
            }
        }
        return nil
    }

    /// Result of scanning candidate roots.
    public struct Discovery: Equatable, Sendable {
        public let wheelhouses: [Wheelhouse]
        /// Roots that have a roster that failed to load, with the reason.
        public let failures: [Failure]

        public struct Failure: Equatable, Sendable {
            public let root: String
            public let reason: String
        }
    }

    /// Scans `roots` (for example the registered repositories) for Wheelhouses,
    /// keeping the order given and skipping duplicates.
    public static func discover(roots: [String]) -> Discovery {
        var seen = Set<String>()
        var found: [Wheelhouse] = []
        var failures: [Discovery.Failure] = []
        for root in roots {
            let normalised = URL(fileURLWithPath: root).standardizedFileURL.path
            guard seen.insert(normalised).inserted else { continue }
            do {
                if let wheelhouse = try load(root: normalised) { found.append(wheelhouse) }
            } catch {
                failures.append(.init(root: normalised, reason: error.localizedDescription))
            }
        }
        return Discovery(wheelhouses: found, failures: failures)
    }
}

// MARK: - Seat harness manifest

/// A named focus from a seat's harness manifest: a prompt the seat can be
/// launched with, or asked to act on, such as `wake`, `design` or `next`.
public struct WheelhouseFocus: Equatable, Sendable, Identifiable {
    public let name: String
    public let prompt: String

    public var id: String { name }

    public init(name: String, prompt: String) {
        self.name = name
        self.prompt = prompt
    }
}

/// What TermQ reads from a seat's harness manifest.
public struct WheelhouseSeatHarness: Equatable, Sendable {
    /// The focus a plain launch uses (`launch_focus`).
    public let launchFocus: String?
    /// The manifest's focuses, sorted with the launch focus first, then by name.
    public let focuses: [WheelhouseFocus]

    public init(launchFocus: String?, focuses: [WheelhouseFocus]) {
        self.launchFocus = launchFocus
        self.focuses = focuses
    }

    /// Parses a ynh plugin manifest; nil when it isn't a JSON object.
    public static func parse(_ data: Data) -> WheelhouseSeatHarness? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let launch = object["launch_focus"] as? String
        let raw = object["focuses"] as? [String: Any] ?? [:]
        let focuses = raw.compactMap { name, value -> WheelhouseFocus? in
            guard let body = value as? [String: Any], let prompt = body["prompt"] as? String else { return nil }
            return WheelhouseFocus(name: name, prompt: prompt)
        }
        .sorted { lhs, rhs in
            if lhs.name == launch { return rhs.name != launch }
            if rhs.name == launch { return false }
            return lhs.name < rhs.name
        }
        return WheelhouseSeatHarness(launchFocus: launch, focuses: focuses)
    }
}
