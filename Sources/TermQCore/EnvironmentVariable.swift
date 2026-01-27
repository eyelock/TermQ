import Foundation

/// Environment variable for terminal injection
public struct EnvironmentVariable: Identifiable, Codable, Sendable {
    public let id: UUID
    public var key: String
    public var value: String
    public var isSecret: Bool

    public init(id: UUID = UUID(), key: String, value: String, isSecret: Bool = false) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }

    /// Validates that the key is a valid POSIX environment variable name.
    /// Rules:
    /// - Must not be empty
    /// - Must start with a letter or underscore
    /// - Can only contain letters, digits, and underscores
    public var isValidKey: Bool {
        guard let first = key.first else { return false }
        guard first.isLetter || first == "_" else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Sanitizes a string to be a valid environment variable name.
    /// - Converts to uppercase
    /// - Replaces invalid characters with underscores
    /// - Prepends underscore if starts with digit
    /// - Returns empty string if input is empty
    public static func sanitizeKey(_ key: String) -> String {
        guard !key.isEmpty else { return "" }

        var sanitized = key.uppercased()

        // Replace invalid characters with underscores
        sanitized = String(
            sanitized.map { char in
                if char.isLetter || char.isNumber || char == "_" {
                    return char
                }
                return "_" as Character
            })

        // If starts with digit, prepend underscore
        if let first = sanitized.first, first.isNumber {
            sanitized = "_" + sanitized
        }

        return sanitized
    }

    /// Common reserved environment variable names that users should avoid
    public static let reservedNames: Set<String> = [
        "PATH", "HOME", "USER", "SHELL", "TERM", "LANG", "PWD", "OLDPWD",
        "EDITOR", "VISUAL", "PAGER", "MAIL", "HOSTNAME", "LOGNAME", "TZ",
        "LC_ALL", "LC_CTYPE", "LC_MESSAGES", "LC_COLLATE",
    ]

    /// Whether this key is a reserved/system environment variable
    public var isReservedKey: Bool {
        Self.reservedNames.contains(key.uppercased())
    }
}

// MARK: - Equatable & Hashable (based on id only)

extension EnvironmentVariable: Equatable {
    public static func == (lhs: EnvironmentVariable, rhs: EnvironmentVariable) -> Bool {
        lhs.id == rhs.id
    }
}

extension EnvironmentVariable: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
