import Foundation
import MCP

// MARK: - Tool Definitions

extension TermQMCPServer {
    static var availableTools: [Tool] {
        [
            Tool(
                name: "termq_pending",
                description: """
                    Check terminals needing attention. Run this at the START of every LLM session.
                    Returns terminals with pending actions (llmNextAction) and staleness indicators.
                    Terminals are sorted: pending actions first, then by staleness (stale → ageing → fresh).
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "actionsOnly": .object([
                            "type": "boolean",
                            "description": "Only show terminals with llmNextAction set",
                        ])
                    ]),
                    "required": .array([]),
                ])
            ),
            Tool(
                name: "termq_context",
                description: """
                    Output comprehensive documentation for LLM/AI assistants.
                    Includes session start/end checklists, tag schema, command reference,
                    and workflow examples for cross-session continuity.
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([:]),
                    "required": .array([]),
                ])
            ),
            Tool(
                name: "termq_list",
                description: "List all terminals or filter by column. Supports listing columns only.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "column": .object([
                            "type": "string",
                            "description": "Filter by column name",
                        ]),
                        "columnsOnly": .object([
                            "type": "boolean",
                            "description": "Return only column names",
                        ]),
                    ]),
                    "required": .array([]),
                ])
            ),
            Tool(
                name: "termq_find",
                description: """
                    Search for terminals by various criteria. All filters are AND-combined.
                    Returns matching terminals as JSON array.
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "name": .object(["type": "string", "description": "Partial name match (case-insensitive)"]),
                        "column": .object(["type": "string", "description": "Filter by column name"]),
                        "tag": .object(["type": "string", "description": "Filter by tag (format: key=value)"]),
                        "id": .object(["type": "string", "description": "Filter by UUID"]),
                        "badge": .object(["type": "string", "description": "Filter by badge"]),
                        "favourites": .object(["type": "boolean", "description": "Only show favourites"]),
                    ]),
                    "required": .array([]),
                ])
            ),
            Tool(
                name: "termq_open",
                description: """
                    Open an existing terminal by name, UUID, or path. Returns terminal details
                    including llmPrompt (persistent context) and llmNextAction (one-time task).
                    Use partial name matching for convenience.
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "identifier": .object([
                            "type": "string",
                            "description": "Terminal name, UUID, or path (partial match supported)",
                        ])
                    ]),
                    "required": .array([.string("identifier")]),
                ])
            ),
            Tool(
                name: "termq_create",
                description: """
                    Create a new terminal in TermQ. Optionally specify name, description, column,
                    path, tags, and LLM context. Returns the created terminal's details.
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "name": .object(["type": "string", "description": "Terminal name"]),
                        "description": .object(["type": "string", "description": "Terminal description"]),
                        "column": .object(["type": "string", "description": "Column name (e.g., 'In Progress')"]),
                        "path": .object(["type": "string", "description": "Working directory path"]),
                        "llmPrompt": .object(["type": "string", "description": "Persistent LLM context"]),
                        "llmNextAction": .object(["type": "string", "description": "One-time action for next session"]),
                    ]),
                    "required": .array([]),
                ])
            ),
            Tool(
                name: "termq_set",
                description: """
                    Update terminal properties. Identify terminal by name or UUID.
                    Can set name, description, column, badges, LLM fields, tags, and favourite status.
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "identifier": .object(["type": "string", "description": "Terminal name or UUID"]),
                        "name": .object(["type": "string", "description": "New name"]),
                        "description": .object(["type": "string", "description": "New description"]),
                        "column": .object(["type": "string", "description": "Move to column"]),
                        "badge": .object(["type": "string", "description": "Comma-separated badges"]),
                        "llmPrompt": .object(["type": "string", "description": "Set persistent LLM context"]),
                        "llmNextAction": .object(["type": "string", "description": "Set one-time action"]),
                        "favourite": .object(["type": "boolean", "description": "Set favourite status"]),
                    ]),
                    "required": .array([.string("identifier")]),
                ])
            ),
            Tool(
                name: "termq_move",
                description: "Move a terminal to a different column (workflow stage).",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "identifier": .object(["type": "string", "description": "Terminal name or UUID"]),
                        "column": .object(["type": "string", "description": "Target column name"]),
                    ]),
                    "required": .array([.string("identifier"), .string("column")]),
                ])
            ),
        ]
    }
}

// MARK: - Resource Definitions

extension TermQMCPServer {
    static var availableResources: [Resource] {
        [
            Resource(
                name: "All Terminals",
                uri: "termq://terminals",
                description: "Complete list of all terminals in the board",
                mimeType: "application/json"
            ),
            Resource(
                name: "Board Columns",
                uri: "termq://columns",
                description: "List of all columns in the Kanban board",
                mimeType: "application/json"
            ),
            Resource(
                name: "Pending Work",
                uri: "termq://pending",
                description: "Terminals with pending actions and staleness indicators",
                mimeType: "application/json"
            ),
            Resource(
                name: "LLM Workflow Guide",
                uri: "termq://context",
                description: "Comprehensive documentation for cross-session workflows",
                mimeType: "text/markdown"
            ),
        ]
    }
}

// MARK: - Prompt Definitions

extension TermQMCPServer {
    static var availablePrompts: [Prompt] {
        [
            Prompt(
                name: "session_start",
                description: """
                    Initialize an LLM session with TermQ. Returns pending work,
                    board overview, and recommended first actions.
                    """,
                arguments: []
            ),
            Prompt(
                name: "workflow_guide",
                description: "Comprehensive guide for maintaining continuity across LLM sessions",
                arguments: []
            ),
            Prompt(
                name: "terminal_summary",
                description: "Get context and status for a specific terminal",
                arguments: [
                    Prompt.Argument(
                        name: "terminal",
                        description: "Terminal name or UUID",
                        required: true
                    )
                ]
            ),
        ]
    }
}
