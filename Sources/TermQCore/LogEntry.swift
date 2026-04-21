import Foundation

public struct LogEntry: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let level: DiagnosticsLevel
    public let category: String
    public let message: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: DiagnosticsLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }
}
