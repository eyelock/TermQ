import Combine
import Foundation
import TermQCore

// @unchecked Sendable: entries is mutated only on MainActor (via Task hop);
// verboseMode is mutated only on MainActor (via SwiftUI binding).
final class TermQLogBuffer: ObservableObject, @unchecked Sendable {
    static let shared = TermQLogBuffer()
    static let capacity = 2_000

    @Published private(set) var entries: [LogEntry] = []

    @Published var verboseMode: Bool {
        didSet {
            // Write through SettingsStore on the main actor — its setter
            // persists to UserDefaults and propagates to other observers.
            let newValue = verboseMode
            Task { @MainActor in SettingsStore.shared.diagnosticsVerboseMode = newValue }
        }
    }

    private init() {
        // Initial value sourced directly from UserDefaults: this init may
        // run on any thread, and `SettingsStore.shared` is `@MainActor`.
        // The store and UserDefaults share the same key, so the value is
        // identical regardless of which one we read from at startup.
        verboseMode = UserDefaults.standard.bool(forKey: "diagnosticsVerboseMode")
    }

    func append(level: DiagnosticsLevel, category: String, message: String) {
        // Same reasoning: `append` is called from arbitrary actor contexts
        // (loggers fire from anywhere), so this gate uses the nonisolated
        // UserDefaults read instead of `SettingsStore.shared`. The value
        // stays consistent because writes route through the store, which
        // writes through to this same UserDefaults key.
        guard level >= .notice || UserDefaults.standard.bool(forKey: "diagnosticsVerboseMode")
        else { return }

        let entry = LogEntry(level: level, category: category, message: message)
        Task { @MainActor [weak self] in
            guard let self else { return }
            entries.append(entry)
            if entries.count > Self.capacity {
                entries.removeFirst(entries.count - Self.capacity)
            }
        }
    }

    @MainActor
    func clear() { entries.removeAll() }
}
