import Dispatch
import Foundation
import MCP
import TermQShared

// MARK: - Subscription Manager
//
// Tracks `resources/subscribe` registrations and emits `notifications/resources/updated`
// when the board.json file underneath them changes.
//
// Design notes:
// - One `DispatchSourceFileSystemObject` watches the board.json inode for `.write`,
//   `.extend`, `.delete`, `.rename`. macOS coalesces these aggressively; the debouncer
//   below adds a second layer because atomic writes (which `BoardWriter` does) replace
//   the inode entirely, briefly firing `.delete` followed by a new file appearing.
// - Notifications are coalesced via a 150ms debounce window. Two writes inside the
//   window produce one notification per subscribed URI, not two.
// - Re-arming after `.rename` / `.delete` is handled by re-opening the file descriptor
//   on a slight delay (the file briefly doesn't exist between unlink and link).
// - Self-write detection is deliberately NOT implemented in this initial version. The
//   audit (§3.2, Tier 1b) flagged it as a refinement; the practical impact is that an
//   MCP client that just wrote a card will also see a `resources/updated` for that
//   write. Acceptable as a starting point — subscribers can no-op on stale ETags / their
//   own causal write tracking. A future revision can add a per-write "skip notification"
//   token threaded through `BoardWriter`.

/// Actor-isolated subscription tracker and file-watcher. Holds the live
/// `DispatchSourceFileSystemObject` and emits `notifications/resources/updated` for
/// any matching subscriber when board.json changes.
actor ResourceSubscriptionManager {
    /// URIs that any client has subscribed to.
    private var subscribedURIs: Set<String> = []

    /// Active file-system watcher.
    private var source: DispatchSourceFileSystemObject?
    private var watchedURL: URL?
    private var fileDescriptor: Int32 = -1

    /// Pending debounce timer.
    private var debounceTask: Task<Void, Never>?
    private static let debounceWindow: Duration = .milliseconds(150)

    /// Callback to actually deliver the notification. Held weakly so the server owns
    /// the lifecycle; if the server is deallocated the deliver closure becomes a no-op.
    private let deliver: @Sendable (String) async -> Void

    init(deliver: @escaping @Sendable (String) async -> Void) {
        self.deliver = deliver
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }

    // MARK: - Subscription state

    func subscribe(uri: String) {
        subscribedURIs.insert(uri)
    }

    func unsubscribe(uri: String) {
        subscribedURIs.remove(uri)
    }

    func subscriberCount() -> Int { subscribedURIs.count }

    // MARK: - File watching

    /// Begin watching `boardURL`. Idempotent — calling again with the same URL is a no-op;
    /// with a different URL it tears down the previous watch and arms a new one.
    func startWatching(boardURL: URL) {
        if watchedURL == boardURL && source != nil {
            return
        }
        stopWatching()
        watchedURL = boardURL
        arm(boardURL: boardURL)
    }

    private func arm(boardURL: URL) {
        // The file may not yet exist at first-launch — schedule a retry rather than
        // failing silently. A subscriber arriving before the file is created is the
        // expected path for `termqmcp` startup ordering against the GUI.
        let fd = open(boardURL.path, O_EVTONLY)
        guard fd >= 0 else {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                await self?.armIfNeeded(boardURL: boardURL)
            }
            return
        }
        fileDescriptor = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleChangeEvent()
            }
        }
        src.setCancelHandler { [fd] in
            close(fd)
        }
        source = src
        src.resume()
    }

    private func armIfNeeded(boardURL: URL) {
        guard source == nil else { return }
        arm(boardURL: boardURL)
    }

    func stopWatching() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            // Cancel handler closes the fd; nil out our copy.
            fileDescriptor = -1
        }
    }

    private func handleChangeEvent() async {
        // If the file was renamed/deleted by an atomic-write, re-arm after a brief delay.
        if let url = watchedURL,
            let src = source,
            src.data.contains(.delete) || src.data.contains(.rename)
        {
            stopWatching()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                await self?.armIfNeeded(boardURL: url)
            }
        }

        // Debounce the emit. Cancel any pending task and schedule a fresh one.
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceWindow)
            if Task.isCancelled { return }
            await self?.fireEmissions()
        }
    }

    private func fireEmissions() async {
        let uris = subscribedURIs
        for uri in uris {
            await deliver(uri)
        }
    }
}
