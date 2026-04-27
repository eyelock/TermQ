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
        didSet { UserDefaults.standard.set(verboseMode, forKey: "diagnosticsVerboseMode") }
    }

    private init() {
        verboseMode = UserDefaults.standard.bool(forKey: "diagnosticsVerboseMode")
    }

    func append(level: DiagnosticsLevel, category: String, message: String) {
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
