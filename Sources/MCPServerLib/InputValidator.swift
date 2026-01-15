import Foundation
import MCP

/// Centralized input validation for MCP tool handlers
/// Provides consistent error messages and type-safe parameter extraction
enum InputValidator {
    // MARK: - Validation Errors

    enum ValidationError: LocalizedError, Sendable {
        case missingRequired(parameter: String, tool: String)
        case invalidUUID(parameter: String, value: String)
        case invalidPath(parameter: String, value: String, reason: String)
        case invalidType(parameter: String, expected: String, got: String)
        case emptyValue(parameter: String)

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

    /// Validate and normalize a path parameter
    static func validatePath(_ name: String, value: String, mustExist: Bool = false) throws -> String {
        // Expand tilde
        let expanded = NSString(string: value).expandingTildeInPath

        // Validate it's not empty
        guard !expanded.isEmpty else {
            throw ValidationError.invalidPath(parameter: name, value: value, reason: "path is empty")
        }

        // Optionally check existence
        if mustExist {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory)
            if !exists {
                throw ValidationError.invalidPath(parameter: name, value: value, reason: "path does not exist")
            }
            if !isDirectory.boolValue {
                throw ValidationError.invalidPath(parameter: name, value: value, reason: "path is not a directory")
            }
        }

        return expanded
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
