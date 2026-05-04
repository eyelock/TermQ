import Combine
import Foundation
import Sparkle

/// Injectable seam around Sparkle's `SPUUpdater` for `UpdaterViewModel`.
///
/// Production code uses `LiveUpdaterProvider`, which wraps the real
/// `SPUUpdater` (and optionally `SPUStandardUpdaterController`). Tests
/// inject a stub that records `checkForUpdates()` calls and emits
/// `canCheckForUpdates` changes via a `PassthroughSubject` — letting
/// `UpdaterViewModel`'s state plumbing be exercised without Sparkle
/// reaching the network.
@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    /// Stream of `canCheckForUpdates` changes. Live impl bridges Sparkle's
    /// KVO publisher; tests drive it directly.
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { get }
    func checkForUpdates()
}

/// Production provider: wraps `SPUUpdater` with optional controller-driven
/// `checkForUpdates` (used so the menu-bar action and the manual button
/// share a code path in production).
@MainActor
final class LiveUpdaterProvider: UpdaterProviding {
    private let updater: SPUUpdater
    private let controller: SPUStandardUpdaterController?

    init(updater: SPUUpdater, controller: SPUStandardUpdaterController? = nil) {
        self.updater = updater
        self.controller = controller
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func checkForUpdates() {
        if let controller {
            controller.checkForUpdates(nil)
        } else {
            updater.checkForUpdates()
        }
    }
}
