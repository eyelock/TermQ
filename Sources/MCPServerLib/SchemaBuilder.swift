import Foundation
import MCP

/// Type-safe JSON Schema builder for MCP tool definitions
/// Provides a cleaner alternative to nested dictionary literals
enum SchemaBuilder {
    // MARK: - Property Types

    /// JSON Schema property types
    enum PropertyType: String {
        case string
        case boolean
        case integer
        case number
        case array
        case object
    }

    /// A single schema property definition
    struct Property {
        let name: String
        let type: PropertyType
        let description: String
        let isRequired: Bool

        init(_ name: String, _ type: PropertyType, description: String, required: Bool = false) {
            self.name = name
            self.type = type
            self.description = description
            self.isRequired = required
        }
    }

    // MARK: - Builder Methods

    /// Build an object schema with properties
    static func objectSchema(_ properties: [Property]) -> Value {
        var propertiesDict: [String: Value] = [:]
        var requiredFields: [Value] = []

        for prop in properties {
            propertiesDict[prop.name] = .object([
                "type": .string(prop.type.rawValue),
                "description": .string(prop.description),
            ])

            if prop.isRequired {
                requiredFields.append(.string(prop.name))
            }
        }

        return .object([
            "type": .string("object"),
            "properties": .object(propertiesDict),
            "required": .array(requiredFields),
        ])
    }

    /// Build an empty object schema (no parameters)
    static func emptySchema() -> Value {
        .object([
            "type": .string("object"),
            "properties": .object([:]),
            "required": .array([]),
        ])
    }

    // MARK: - Convenience Methods

    /// Create a string property
    static func string(_ name: String, _ description: String, required: Bool = false) -> Property {
        Property(name, .string, description: description, required: required)
    }

    /// Create a boolean property
    static func bool(_ name: String, _ description: String, required: Bool = false) -> Property {
        Property(name, .boolean, description: description, required: required)
    }

    /// Create an integer property
    static func int(_ name: String, _ description: String, required: Bool = false) -> Property {
        Property(name, .integer, description: description, required: required)
    }
}
