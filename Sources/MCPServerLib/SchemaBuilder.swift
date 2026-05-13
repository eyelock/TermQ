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

    /// Create an array property (of strings)
    static func stringArray(_ name: String, _ description: String, required: Bool = false) -> Property {
        Property(name, .array, description: description, required: required)
    }

    // MARK: - Output Schemas (Tier 1b — structured tool output)
    //
    // These describe the shape of `structuredContent` returned by read-shaped tools.
    // Per the MCP spec, the structuredContent must validate against the tool's
    // outputSchema — clients can codegen types or runtime-validate against these.

    /// Schema for a single TerminalOutput row.
    static var terminalOutputItemSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "id": stringField("Terminal UUID"),
                "name": stringField("Display name"),
                "description": stringField("Free-form description"),
                "column": stringField("Column display name"),
                "columnId": stringField("Column UUID"),
                "tags": .object(["type": .string("object")]),
                "path": stringField("Working directory"),
                "badges": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                ]),
                "isFavourite": boolField("Pinned to favourites bar"),
                "llmPrompt": stringField("Persistent LLM context"),
                "llmNextAction": stringField("Queued one-time action"),
                "allowAutorun": boolField("Whether queued actions auto-execute"),
            ]),
        ])
    }

    /// Schema for an array of TerminalOutput rows (used by `list`, `find`).
    static var terminalListSchema: Value {
        .object([
            "type": .string("array"),
            "items": terminalOutputItemSchema,
        ])
    }

    /// Schema for ColumnOutput.
    static var columnOutputItemSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "id": stringField("Column UUID"),
                "name": stringField("Column name"),
                "description": stringField("Free-form description"),
                "color": stringField("Hex colour"),
                "terminalCount": intField("Number of active cards in this column"),
            ]),
        ])
    }

    /// Schema for a PendingOutput envelope.
    static var pendingOutputSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "terminals": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "id": stringField("Terminal UUID"),
                            "name": stringField("Display name"),
                            "column": stringField("Column display name"),
                            "path": stringField("Working directory"),
                            "llmNextAction": stringField("Queued one-time action"),
                            "llmPrompt": stringField("Persistent LLM context"),
                            "allowAutorun": boolField("Whether queued actions auto-execute"),
                            "staleness": stringField("Staleness tag value"),
                            "tags": .object(["type": .string("object")]),
                        ]),
                    ]),
                ]),
                "summary": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "total": intField("Total cards considered"),
                        "withNextAction": intField("Cards with llmNextAction set"),
                        "stale": intField("Cards tagged stale or old"),
                        "fresh": intField("Cards tagged fresh"),
                    ]),
                ]),
            ]),
        ])
    }

    private static func stringField(_ description: String) -> Value {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func boolField(_ description: String) -> Value {
        .object(["type": .string("boolean"), "description": .string(description)])
    }

    private static func intField(_ description: String) -> Value {
        .object(["type": .string("integer"), "description": .string(description)])
    }
}
