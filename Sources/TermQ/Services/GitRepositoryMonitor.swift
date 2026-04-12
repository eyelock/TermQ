import Foundation

/// Watches a git repository's state files for changes from any process and fires a refresh
/// callback when something interesting changes.
///
/// Monitored files:
/// - `.git/HEAD` — branch switch in the main worktree
/// - `.git/index` — staging/unstaging changes in the main worktree
/// - `.git/worktrees/{name}/HEAD` — branch switch in each linked worktree (enumerated at setup)
/// - `.git/worktrees/{name}/index` — staging changes in each linked worktree
///
/// Uses `DispatchSource` file-descriptor events so changes made by any process (git CLI,
/// other editors, etc.) are detected without polling.
///
/// `@unchecked Sendable`: follows the same pattern as `FileMonitor` in `BoardPersistence.swift` —
/// all mutable state is accessed on a single serial dispatch queue.
final class GitRepositoryMonitor: @unchecked Sendable {
    private let repoPath: String
    private let onRefresh: @Sendable () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "io.termq.git-monitor", qos: .utility)

    init(repoPath: String, onRefresh: @escaping @Sendable () -> Void) {
        self.repoPath = repoPath
        self.onRefresh = onRefresh
        // Run setup on the queue so all mutable state is queue-confined from the start,
        // satisfying the @unchecked Sendable contract.
        queue.sync { self.setup() }
    }

    deinit {
        cancelAll()
    }

    /// Re-enumerate worktree HEADs and restart all watches.
    /// Call after a worktree is added or removed.
    func resetWatches() {
        queue.async { [weak self] in
            self?.cancelAll()
            self?.setup()
        }
    }

    // MARK: - Private

    private func setup() {
        let gitDir = repoPath + "/.git"

        // Main worktree HEAD and index
        watchFile(gitDir + "/HEAD")
        watchFile(gitDir + "/index")

        // Linked worktrees
        let worktreesDir = gitDir + "/worktrees"
        if let names = try? FileManager.default.contentsOfDirectory(atPath: worktreesDir) {
            for name in names {
                let base = worktreesDir + "/" + name
                watchFile(base + "/HEAD")
                watchFile(base + "/index")
            }
        }
    }

    private func watchFile(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        let callback: @Sendable () -> Void = { [weak self] in self?.scheduleRefresh() }
        source.setEventHandler(handler: callback)
        source.setCancelHandler { close(fd) }
        source.resume()
        sources.append(source)
    }

    private func scheduleRefresh() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onRefresh() }
        debounceItem = item
        queue.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func cancelAll() {
        debounceItem?.cancel()
        debounceItem = nil
        for source in sources { source.cancel() }
        sources.removeAll()
    }
}
