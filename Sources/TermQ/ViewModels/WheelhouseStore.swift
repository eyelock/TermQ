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
    @Published private(set) var failures: [WheelhouseLoader.Discovery.Failure] = []
    @Published private(set) var isLoading = false
    /// In-progress beads per Wheelhouse root, keyed by assignee.
    @Published private(set) var work: [String: [String: [WheelhouseBead]]] = [:]
    /// Wheelhouse roots whose work graph could not be read (no `bd`, or it failed).
    @Published private(set) var workUnavailable: Set<String> = []
    /// Seat commands per Wheelhouse root known to have had no first session yet.
    @Published private(set) var unborn: [String: Set<String>] = [:]

    private var refreshTask: Task<Void, Never>?
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
        }
    }

    /// Re-reads every Wheelhouse's in-progress beads.
    func refreshWork() {
        workTask?.cancel()
        let roots = wheelhouses.map(\.root)
        workTask = Task { [weak self] in
            var results: [String: [String: [WheelhouseBead]]] = [:]
            var unavailable: Set<String> = []
            for root in roots {
                if Task.isCancelled { return }
                if let beads = await WheelhouseWork.fetchInProgress(root: root) {
                    results[root] = beads
                } else {
                    unavailable.insert(root)
                }
            }
            guard !Task.isCancelled, let self else { return }
            let beads = results.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
            TermQLogger.ui.debug(
                "wheelhouse work: roots=\(roots.count) read=\(results.count)"
                    + " unavailable=\(unavailable.count) beads=\(beads)")
            self.work = results
            self.workUnavailable = unavailable
        }
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

    func beadCount(for seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> Int {
        work[wheelhouse.root]?[seat.command]?.count ?? 0
    }

    /// The Wheelhouse and seat a card was launched for, from its tags.
    func seat(for card: TerminalCard) -> (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        guard
            let root = card.tags.first(where: { $0.key == WheelhouseCardMatcher.wheelhouseTagKey })?.value,
            let command = card.tags.first(where: { $0.key == WheelhouseCardMatcher.seatTagKey })?.value,
            let wheelhouse = wheelhouses.first(where: { $0.root == root }),
            let seat = wheelhouse.seats.first(where: { $0.command == command })
        else { return nil }
        return (wheelhouse, seat)
    }

    /// Seat cards among `cards`, limited to `root` when given.
    func seatCards(in cards: [TerminalCard], root: String? = nil) -> [TerminalCard] {
        cards.filter { card in
            guard card.deletedAt == nil, let found = seat(for: card) else { return false }
            return root == nil || found.wheelhouse.root == root
        }
    }
}
