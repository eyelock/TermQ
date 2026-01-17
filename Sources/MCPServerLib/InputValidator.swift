import Foundation
import MCP

/// Centralized input validation for MCP tool handlers
/// Provides consistent error messages and type-safe parameter extraction
enum InputValidator {
    // MARK: - Security Limits

    /// Maximum allowed length for general string fields (name, description, badge)
    static let maxGeneralStringLength = 1000

    /// Maximum allowed length for LLM context fields (llmPrompt, llmNextAction)
    static let maxLLMContextLength = 50000

    /// Maximum allowed length for path strings
    static let maxPathLength = 4096

    // MARK: - Validation Errors

    enum ValidationError: LocalizedError, Sendable {
        case missingRequired(parameter: String, tool: String)
        case invalidUUID(parameter: String, value: String)
        case invalidPath(parameter: String, value: String, reason: String)
        case invalidType(parameter: String, expected: String, got: String)
        case emptyValue(parameter: String)
        case valueTooLong(parameter: String, maxLength: Int, actualLength: Int)
        case pathTraversal(parameter: String, value: String)

        var errorDescription: String? {
            switch self {
            case .missingRequired(let param, let tool):
                return "Missing required parameter '\(param)' for \(tool)"
            case .invalidUUID(let param, let value):
                return "Invalid UUID format for '\(param)': \(value)"
            case .invalidPath(let param, let value, let reason):
                return "Invalid path for '\(param)': \(value) (\(reason))"
            case .invalidType(let param, let expected, let got):
                return "Invalid type for '\(param)': expected \(expected), got \(got)"
            case .emptyValue(let param):
                return "Parameter '\(param)' cannot be empty"
            case .valueTooLong(let param, let maxLength, let actualLength):
                return "Parameter '\(param)' exceeds maximum length (\(actualLength) > \(maxLength))"
            case .pathTraversal(let param, let value):
                return "Path traversal detected in '\(param)': \(value)"
            }
        }
    }

    // MARK: - Parameter Extraction

    /// Extract a required string parameter
    static func requireString(
        _ name: String,
        from arguments: [String: Value]?,
        tool: String
    ) throws -> String {
        guard let value = arguments?[name] else {
            throw ValidationError.missingRequired(parameter: name, tool: tool)
        }
        guard let stringValue = value.stringValue else {
            throw ValidationError.invalidType(parameter: name, expected: "string", got: describeType(value))
        }
        return stringValue
    }

    /// Extract a required non-empty string parameter
    static func requireNonEmptyString(
        _ name: String,
        from arguments: [String: Value]?,
        tool: String
    ) throws -> String {
        let value = try requireString(name, from: arguments, tool: tool)
        guard !value.isEmpty else {
            throw ValidationError.emptyValue(parameter: name)
        }
        return value
    }

    /// Extract an optional string parameter
    static func optionalString(_ name: String, from arguments: [String: Value]?) -> String? {
        arguments?[name]?.stringValue
    }

    /// Extract an optional boolean parameter with default
    static func optionalBool(_ name: String, from arguments: [String: Value]?, default: Bool = false) -> Bool {
        arguments?[name]?.boolValue ?? `default`
    }

    // MARK: - Length Validation

    /// Validate string length against a maximum limit
    static func validateLength(
        _ name: String,
        value: String,
        maxLength: Int
    ) throws -> String {
        guard value.count <= maxLength else {
            throw ValidationError.valueTooLong(parameter: name, maxLength: maxLength, actualLength: value.count)
        }
        return value
    }

    /// Extract an optional string with length validation (for general fields)
    static func optionalBoundedString(
        _ name: String,
        from arguments: [String: Value]?,
        maxLength: Int = maxGeneralStringLength
    ) throws -> String? {
        guard let value = arguments?[name]?.stringValue else {
            return nil
        }
        return try validateLength(name, value: value, maxLength: maxLength)
    }

    /// Extract an optional string for LLM context fields (llmPrompt, llmNextAction)
    static func optionalLLMContext(
        _ name: String,
        from arguments: [String: Value]?
    ) throws -> String? {
        guard let value = arguments?[name]?.stringValue else {
            return nil
        }
        return try validateLength(name, value: value, maxLength: maxLLMContextLength)
    }

    // MARK: - UUID Validation

    /// Extract and validate a required UUID parameter
    static func requireUUID(
        _ name: String,
        from arguments: [String: Value]?,
        tool: String
    ) throws -> UUID {
        let value = try requireNonEmptyString(name, from: arguments, tool: tool)
        guard let uuid = UUID(uuidString: value) else {
            throw ValidationError.invalidUUID(parameter: name, value: value)
        }
        return uuid
    }

    /// Extract and validate an optional UUID parameter
    static func optionalUUID(_ name: String, from arguments: [String: Value]?) throws -> UUID? {
        guard let value = arguments?[name]?.stringValue else {
            return nil
        }
        guard let uuid = UUID(uuidString: value) else {
            throw ValidationError.invalidUUID(parameter: name, value: value)
        }
        return uuid
    }

    // MARK: - Path Validation

    /// Validate and normalize a path parameter with security checks
    /// - Prevents path traversal attacks (../ sequences)
    /// - Enforces maximum path length
    /// - Optionally validates path existence
    static func validatePath(_ name: String, value: String, mustExist: Bool = false) throws -> String {
        // Check length first
        guard value.count <= maxPathLength else {
            throw ValidationError.valueTooLong(parameter: name, maxLength: maxPathLength, actualLength: value.count)
        }

        // Expand tilde
        let expanded = NSString(string: value).expandingTildeInPath

        // Validate it's not empty
        guard !expanded.isEmpty else {
            throw ValidationError.invalidPath(parameter: name, value: value, reason: "path is empty")
        }

        // Normalize the path to resolve any .. or . components
        let normalized = (expanded as NSString).standardizingPath

        // Security check: detect path traversal attempts
        // Check if the original path contained ".." as a path component
        // This catches attempts like "/Users/foo/../../../etc/passwd"
        // Note: We check components, not the raw string, to allow filenames like "file..txt"
        let originalComponents = expanded.components(separatedBy: "/")
        if originalComponents.contains("..") {
            throw ValidationError.pathTraversal(parameter: name, value: value)
        }

        // Also check normalized path components in case normalization didn't fully resolve
        let normalizedComponents = normalized.components(separatedBy: "/")
        if normalizedComponents.contains("..") {
            throw ValidationError.pathTraversal(parameter: name, value: value)
        }

        // Optionally check existence
        if mustExist {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory)
            if !exists {
                throw ValidationError.invalidPath(parameter: name, value: value, reason: "path does not exist")
            }
            if !isDirectory.boolValue {
                throw ValidationError.invalidPath(parameter: name, value: value, reason: "path is not a directory")
            }
        }

        return normalized
    }

    /// Extract an optional path parameter with validation
    static func optionalPath(
        _ name: String,
        from arguments: [String: Value]?,
        mustExist: Bool = false
    ) throws -> String? {
        guard let value = arguments?[name]?.stringValue else {
            return nil
        }
        return try validatePath(name, value: value, mustExist: mustExist)
    }

    // MARK: - Helpers

    /// Describe the type of a Value for error messages
    private static func describeType(_ value: Value) -> String {
        switch value {
        case .null:
            return "null"
        case .bool:
            return "boolean"
        case .int, .double:
            return "number"
        case .string:
            return "string"
        case .data:
            return "data"
        case .array:
            return "array"
        case .object:
            return "object"
        }
    }
}
