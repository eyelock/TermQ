import Foundation
import TermQCore
import TermQShared

/// The Wheelhouses among the registered repositories, and what their seats
/// are working on.
///
/// Discovery and `bd` run off the main actor; results are published on it.
@MainActor
final class WheelhouseStore: ObservableObject {
    static let shared = WheelhouseStore()

    /// How often the work graph is re-read while someone is looking.
    static let workRefreshInterval: Duration = .seconds(60)

    @Published private(set) var wheelhouses: [Wheelhouse] = []

    /// `wheelhouses` seeds the store for tests; the app loads them with
    /// `refresh(roots:)`.
    init(wheelhouses: [Wheelhouse] = []) {
        self.wheelhouses = wheelhouses
    }
    @Published private(set) var failures: [WheelhouseLoader.Discovery.Failure] = []
    @Published private(set) var isLoading = false
    /// In-progress beads per Wheelhouse root, keyed by assignee.
    @Published private(set) var work: [String: [String: [WheelhouseBead]]] = [:]
    /// Wheelhouse roots whose work graph could not be read (no `bd`, or it failed).
    @Published private(set) var workUnavailable: Set<String> = []
    /// Beads waiting on the human, per Wheelhouse root.
    @Published private(set) var inbox: [String: [WheelhouseInboxItem]] = [:]
    /// Wheelhouse roots whose inbox could not be read.
    @Published private(set) var inboxUnavailable: Set<String> = []
    /// Whether the work graph and inbox are being read right now.
    @Published private(set) var isRefreshingWork = false

    /// Settings: the name a Wheelhouse gives "a human", and the human's own.
    static let inboxHumanNameKey = "wheelhouse.inbox.humanName"
    static let inboxOwnNameKey = "wheelhouse.inbox.ownName"

    /// The names whose ready beads make up the inbox.
    static func inboxAssignees(defaults: UserDefaults = .standard) -> [String] {
        WheelhouseInbox.assignees(
            humanName: defaults.string(forKey: inboxHumanNameKey) ?? WheelhouseInbox.defaultHumanName,
            ownName: defaults.string(forKey: inboxOwnNameKey) ?? "")
    }

    /// Seat commands per Wheelhouse root known to have had no first session yet.
    @Published private(set) var unborn: [String: Set<String>] = [:]

    /// Delegate issues per Wheelhouse root and seat command, from the seats'
    /// manifests and git. Refreshed with every load.
    @Published private(set) var delegateIssues: [String: [String: [WheelhouseSeatIssue]]] = [:]

    /// The error line of a seat's last failed launch, per root and command.
    @Published private(set) var launchFailures: [String: [String: String]] = [:]

    private var refreshTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var identityTask: Task<Void, Never>?
    private var identityChecked: Set<String> = []

    func refresh(roots: [String]) {
        refreshTask?.cancel()
        isLoading = true
        refreshTask = Task { [weak self] in
            let discovery = await Task.detached(priority: .userInitiated) {
                WheelhouseLoader.discover(roots: roots)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.wheelhouses = discovery.wheelhouses
            self.failures = discovery.failures
            self.isLoading = false
            self.refreshWork()
            self.refreshIdentities()
            self.refreshDelegateIssues()
        }
    }

    // MARK: - Seat health

    /// Re-reads every seat's own-repository delegates against git.
    func refreshDelegateIssues() {
        healthTask?.cancel()
        let seats = wheelhouses.flatMap { wheelhouse in wheelhouse.seats.map { (wheelhouse.root, $0) } }
        healthTask = Task { [weak self] in
            var found: [String: [String: [WheelhouseSeatIssue]]] = [:]
            for (root, seat) in seats {
                if Task.isCancelled { return }
                let issues = await WheelhouseSeatHealth.delegateIssues(root: root, seat: seat)
                if !issues.isEmpty { found[root, default: [:]][seat.command] = issues }
            }
            guard !Task.isCancelled, let self else { return }
            self.delegateIssues = found
        }
    }

    /// How long after a session starts its launch is judged: an `Error:` line
    /// from ynh shows up within seconds, and anything older in the
    /// scrollback says nothing about the seat now.
    static let launchWindow: TimeInterval = 90

    /// Looks at each seat terminal. A young session whose harness is not
    /// running records ynh's `Error:` line as the seat's launch failure; a
    /// recorded failure clears once the harness runs or the terminal is gone.
    func checkLaunches(
        cards: [TerminalCard], probe: any TerminalForegroundProbing, now: Date = Date(),
        lines: (UUID) -> [String] = { TerminalSessionManager.shared.recentLines(for: $0) }
    ) async {
        let seatCards = seatCards(in: cards)
        // Failures whose seat no longer has a terminal are over.
        for (root, failures) in launchFailures {
            for command in failures.keys
            where !seatCards.contains(where: {
                WheelhouseCardMatcher.matches($0, wheelhouseRoot: root, seatCommand: command)
                    && probe.sessionStart(for: $0.id) != nil
            }) {
                launchFailures[root]?[command] = nil
            }
        }
        for card in seatCards {
            guard let found = seat(for: card), let started = probe.sessionStart(for: card.id) else { continue }
            let young = now.timeIntervalSince(started) < Self.launchWindow
            let failed = launchFailures[found.wheelhouse.root]?[found.seat.command] != nil
            // An old session is only asked about to clear a failure.
            guard young || failed else { continue }
            let running = await probe.isForegroundProgramRunning(for: card)
            // The answer is about this session only.
            guard probe.sessionStart(for: card.id) == started else { continue }
            let check = Self.launchCheck(running: running, lines: { young ? lines(card.id) : [] })
            switch check {
            case .record(nil):
                if running == true || young { recordLaunchFailure(nil, for: found.seat, in: found.wheelhouse) }
            case .record(let message?):
                recordLaunchFailure(message, for: found.seat, in: found.wheelhouse)
            case .unknown:
                break
            }
        }
    }

    /// What a launch check concludes about a seat's terminal.
    enum LaunchCheck: Equatable {
        /// Can't tell: leave the seat as it is.
        case unknown
        /// Record this failure; nil when the harness runs, or the shell is
        /// idle without an `Error:` line.
        case record(String?)
    }

    nonisolated static func launchCheck(running: Bool?, lines: () -> [String]) -> LaunchCheck {
        switch running {
        case nil: return .unknown
        case true?: return .record(nil)
        case false?: return .record(WheelhouseSeatHealth.launchError(fromLines: lines()))
        }
    }

    func recordLaunchFailure(_ message: String?, for seat: WheelhouseSeat, in wheelhouse: Wheelhouse) {
        guard launchFailures[wheelhouse.root]?[seat.command] != message else { return }
        launchFailures[wheelhouse.root, default: [:]][seat.command] = message
    }

    /// What stops a seat from running. `installed` is nil while the installed
    /// harnesses aren't known, so nothing is claimed about them.
    func issues(for seat: WheelhouseSeat, in wheelhouse: Wheelhouse, installed: Bool?) -> [WheelhouseSeatIssue] {
        Self.issues(
            installed: installed, delegates: delegateIssues[wheelhouse.root]?[seat.command] ?? [],
            launchFailure: launchFailures[wheelhouse.root]?[seat.command])
    }

    nonisolated static func issues(
        installed: Bool?, delegates: [WheelhouseSeatIssue], launchFailure: String?
    ) -> [WheelhouseSeatIssue] {
        var issues: [WheelhouseSeatIssue] = installed == false ? [.notInstalled] : []
        issues += delegates
        if let launchFailure { issues.append(.launchFailed(launchFailure)) }
        return issues
    }

    /// Re-reads every Wheelhouse's in-progress beads and the human's inbox.
    func refreshWork() {
        workTask?.cancel()
        let roots = wheelhouses.map(\.root)
        let assignees = Self.inboxAssignees()
        isRefreshingWork = true
        workTask = Task { [weak self] in
            var results: [String: [String: [WheelhouseBead]]] = [:]
            var unavailable: Set<String> = []
            var inbox: [String: [WheelhouseInboxItem]] = [:]
            var inboxUnavailable: Set<String> = []
            for root in roots {
                if Task.isCancelled { return }
                if let beads = await WheelhouseWork.fetchInProgress(root: root) {
                    results[root] = beads
                } else {
                    unavailable.insert(root)
                }
                if let items = await WheelhouseInbox.fetch(root: root, assignees: assignees) {
                    inbox[root] = items
                } else {
                    inboxUnavailable.insert(root)
                }
            }
            guard !Task.isCancelled, let self else { return }
            let beads = results.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
            TermQLogger.ui.debug(
                "wheelhouse work: roots=\(roots.count) read=\(results.count)"
                    + " unavailable=\(unavailable.count) beads=\(beads)")
            self.work = results
            self.workUnavailable = unavailable
            self.inbox = inbox
            self.inboxUnavailable = inboxUnavailable
            self.isRefreshingWork = false
        }
    }

    /// Comments on or closes an inbox bead, then re-reads the inbox. Returns
    /// nil on success, or what went wrong.
    func respond(_ response: WheelhouseInbox.Response, to item: WheelhouseInboxItem, root: String) async -> String? {
        let failure = await WheelhouseInbox.respond(response, to: item, root: root)
        if failure != nil {
            TermQLogger.ui.warning("wheelhouse inbox: bd update failed for \(item.id)")
        } else {
            TermQLogger.ui.info("wheelhouse inbox: updated \(item.id)")
            // A closed bead leaves at once; the re-read below confirms it.
            if case .close = response { inbox[root]?.removeAll { $0.id == item.id } }
        }
        refreshWork()
        return failure
    }

    /// Checks, once per Wheelhouse, which seats have never had a first session.
    /// ynm is slow per call, so seats are checked a few at a time.
    func refreshIdentities(force: Bool = false) {
        let pending = wheelhouses.filter { force || !identityChecked.contains($0.root) }
        guard !pending.isEmpty else { return }
        identityTask?.cancel()
        let jobs = pending.flatMap { wheelhouse in wheelhouse.seats.map { (wheelhouse.root, $0.command) } }
        identityTask = Task { [weak self] in
            var found: [String: Set<String>] = [:]
            await withTaskGroup(of: (String, String, Bool?).self) { group in
                var iterator = jobs.makeIterator()
                for _ in 0..<4 {
                    guard let (root, command) = iterator.next() else { break }
                    group.addTask { (root, command, await WheelhouseIdentity.isBorn(seatCommand: command, root: root)) }
                }
                for await (root, command, born) in group {
                    if born == false { found[root, default: []].insert(command) }
                    if let (nextRoot, nextCommand) = iterator.next() {
                        group.addTask {
                            (
                                nextRoot, nextCommand,
                                await WheelhouseIdentity.isBorn(seatCommand: nextCommand, root: nextRoot)
                            )
                        }
                    }
                }
            }
            guard !Task.isCancelled, let self else { return }
            for root in Set(jobs.map(\.0)) {
                self.unborn[root] = found[root] ?? []
                // Only now is the root checked: a cancelled run is retried.
                self.identityChecked.insert(root)
            }
        }
    }

    func isUnborn(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> Bool {
        unborn[wheelhouse.root]?.contains(seat.command) ?? false
    }

    /// The bead a seat is on: the first in-progress bead assigned to it.
    func currentBead(for seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> WheelhouseBead? {
        work[wheelhouse.root]?[seat.command]?.first
    }

    /// Whether the seat checked in on any of its beads recently: it is
    /// working, even with no terminal of its own (a dispatcher may run it).
    func isWorking(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse, now: Date = Date()) -> Bool {
        work[wheelhouse.root]?[seat.command]?.contains(where: { $0.isWorking(now: now) }) ?? false
    }

    func beadCount(for seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> Int {
        work[wheelhouse.root]?[seat.command]?.count ?? 0
    }

    /// The Wheelhouse and seat a card was launched for, from its tags.
    func seat(for card: TerminalCard) -> (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        Self.seat(for: card, tagKey: WheelhouseCardMatcher.seatTagKey, in: wheelhouses)
    }

    /// The inbox for `root`, or every Wheelhouse's when nil.
    func inboxItems(root: String?) -> [(wheelhouse: Wheelhouse, item: WheelhouseInboxItem)] {
        wheelhouses
            .filter { root == nil || $0.root == root }
            .flatMap { wheelhouse in (inbox[wheelhouse.root] ?? []).map { (wheelhouse, $0) } }
    }

    /// The seat a Quick Terminal was opened for, from its tags.
    func parentSeat(of card: TerminalCard) -> (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        Self.seat(for: card, tagKey: WheelhouseCardMatcher.quickTerminalTagKey, in: wheelhouses)
    }

    /// The seat a card belongs to: its own, or a Quick Terminal's parent.
    func owningSeat(of card: TerminalCard) -> (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        Self.owningSeat(of: card, in: wheelhouses)
    }

    /// The seat of the card `id` among `cards`: what the stage's shortcuts
    /// act on for the focused pane. Nil for the inbox or a deleted card.
    func owningSeat(ofCardId id: UUID?, in cards: [TerminalCard]) -> (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        Self.owningSeat(ofCardId: id, in: cards, wheelhouses: wheelhouses)
    }

    nonisolated static func owningSeat(
        of card: TerminalCard, in wheelhouses: [Wheelhouse]
    ) -> (
        wheelhouse: Wheelhouse, seat: WheelhouseSeat
    )? {
        seat(for: card, tagKey: WheelhouseCardMatcher.seatTagKey, in: wheelhouses)
            ?? seat(for: card, tagKey: WheelhouseCardMatcher.quickTerminalTagKey, in: wheelhouses)
    }

    nonisolated static func owningSeat(
        ofCardId id: UUID?, in cards: [TerminalCard], wheelhouses: [Wheelhouse]
    ) -> (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        guard let id, let card = cards.first(where: { $0.id == id && $0.deletedAt == nil }) else { return nil }
        return owningSeat(of: card, in: wheelhouses)
    }

    /// The seat named by the card's `tagKey` tag (a seat's own, or a Quick
    /// Terminal's parent) in the card's Wheelhouse.
    nonisolated private static func seat(
        for card: TerminalCard, tagKey: String, in wheelhouses: [Wheelhouse]
    ) -> (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        guard
            let root = card.tags.first(where: { $0.key == WheelhouseCardMatcher.wheelhouseTagKey })?.value,
            let command = card.tags.first(where: { $0.key == tagKey })?.value,
            let wheelhouse = wheelhouses.first(where: { $0.root == root }),
            let seat = wheelhouse.seats.first(where: { $0.command == command })
        else { return nil }
        return (wheelhouse, seat)
    }

    /// In Split placement, the seat card a Quick Terminal sits beneath: its
    /// seat's card, when the seat has one. Nil for anything else.
    func splitHost(of card: TerminalCard, in cards: [TerminalCard]) -> TerminalCard? {
        Self.splitHost(of: card, in: cards, wheelhouses: wheelhouses)
    }

    nonisolated static func splitHost(
        of card: TerminalCard, in cards: [TerminalCard], wheelhouses: [Wheelhouse]
    ) -> TerminalCard? {
        guard let parent = seat(for: card, tagKey: WheelhouseCardMatcher.quickTerminalTagKey, in: wheelhouses)
        else { return nil }
        return WheelhouseCardMatcher.card(
            in: cards, wheelhouseRoot: parent.wheelhouse.root, seatCommand: parent.seat.command)
    }

    /// The cards the stage shows as panes: in Split, a Quick Terminal whose
    /// seat has a card sits beneath it instead.
    nonisolated static func paneCards(
        _ stageCards: [TerminalCard], placement: WheelhouseQuickTerminalPlacement, all: [TerminalCard],
        wheelhouses: [Wheelhouse]
    ) -> [TerminalCard] {
        guard placement == .split else { return stageCards }
        return stageCards.filter { splitHost(of: $0, in: all, wheelhouses: wheelhouses) == nil }
    }

    /// Cards that can go on the stage: seat cards and their Quick Terminals,
    /// limited to `root` when given.
    func stageCards(in cards: [TerminalCard], root: String? = nil) -> [TerminalCard] {
        cards.filter { card in
            guard card.deletedAt == nil, let found = owningSeat(of: card) else { return false }
            return root == nil || found.wheelhouse.root == root
        }
    }

    /// The open seats among `cards` (on stage, running, or ringing), limited
    /// to `root`, in the tab strip's order: what ⌘1–9 jump to on the stage.
    func openSeatCards(
        in cards: [TerminalCard], root: String?, stage: WheelhouseStage, running: Set<UUID>, ringing: Set<UUID>
    ) -> [TerminalCard] {
        // A card that survived a relaunch with nothing running isn't open.
        let open = seatCards(in: cards, root: root).filter { card in
            stage.isOnStage(card.id) || running.contains(card.id) || ringing.contains(card.id)
        }
        return Self.stripOrder(open, wheelhouses: wheelhouses)
    }

    /// The Window menu's ⌘1–9 items on the stage: the first nine open seats,
    /// by seat name.
    nonisolated static func stageMenuItems(_ cards: [TerminalCard], wheelhouses: [Wheelhouse]) -> [OpenTerminalItem] {
        cards.prefix(9).map { card in
            let name = seat(for: card, tagKey: WheelhouseCardMatcher.seatTagKey, in: wheelhouses)?.seat.name
            return OpenTerminalItem(id: card.id, title: name ?? card.title, isFavourite: false)
        }
    }

    /// Seat cards by Wheelhouse in sidebar order, then desk first, then crew,
    /// standing and workers, each in roster order. Cards that aren't seats
    /// are left out.
    nonisolated static func stripOrder(_ cards: [TerminalCard], wheelhouses: [Wheelhouse]) -> [TerminalCard] {
        struct Keyed {
            let card: TerminalCard
            let wheelhouseOrder: Int
            let group: Int
            let order: Int
        }
        return cards.compactMap { card -> Keyed? in
            guard let found = seat(for: card, tagKey: WheelhouseCardMatcher.seatTagKey, in: wheelhouses) else {
                return nil
            }
            let wheelhouseOrder = wheelhouses.firstIndex { $0.root == found.wheelhouse.root } ?? 0
            let order = found.wheelhouse.seats.firstIndex { $0.command == found.seat.command } ?? 0
            return Keyed(card: card, wheelhouseOrder: wheelhouseOrder, group: found.seat.group.sortOrder, order: order)
        }
        .sorted { ($0.wheelhouseOrder, $0.group, $0.order) < ($1.wheelhouseOrder, $1.group, $1.order) }
        .map(\.card)
    }

    /// Seat cards among `cards`, limited to `root` when given.
    func seatCards(in cards: [TerminalCard], root: String? = nil) -> [TerminalCard] {
        cards.filter { card in
            guard card.deletedAt == nil, let found = seat(for: card) else { return false }
            return root == nil || found.wheelhouse.root == root
        }
    }
}
