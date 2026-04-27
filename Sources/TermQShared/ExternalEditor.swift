import Foundation

public struct ExternalEditor: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case xcode
        case vscode
        case cursor
        case intellij
        case intellijCE
    }

    public let kind: Kind
    public let displayName: String
    public let appURL: URL

    public var id: Kind { kind }

    public init(kind: Kind, displayName: String, appURL: URL) {
        self.kind = kind
        self.displayName = displayName
        self.appURL = appURL
    }
}
