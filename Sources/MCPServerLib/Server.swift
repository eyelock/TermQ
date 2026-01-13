import Foundation
import MCP
import TermQCore

/// TermQ MCP Server implementation
///
/// Provides Model Context Protocol interface for LLM assistants to interact
/// with TermQ's terminal management functionality.
///
/// - Warning: This server is designed for LOCAL USE ONLY. Do not deploy
///   as a networked service or expose to the internet.
public final class TermQMCPServer: @unchecked Sendable {
    private let server: Server
    private let dataDirectory: URL?

    /// Server name identifier
    public static let serverName = "termq"

    /// Server version
    public static let serverVersion = "1.0.0"

    /// Initialize the MCP server
    /// - Parameter dataDirectory: Optional custom data directory (nil uses default)
    public init(dataDirectory: URL? = nil) {
        self.dataDirectory = dataDirectory
        self.server = Server(
            name: Self.serverName,
            version: Self.serverVersion,
            capabilities: Server.Capabilities(
                logging: .init(),
                prompts: .init(listChanged: true),
                resources: .init(subscribe: true, listChanged: true),
                tools: .init(listChanged: true)
            )
        )
    }

    // MARK: - Running

    /// Run the server with the specified transport
    /// - Parameter transport: The transport to use (stdio or HTTP)
    public func run(transport: any Transport) async throws {
        // Register handlers before starting
        await registerHandlers()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }


    // MARK: - Handler Registration

    private func registerHandlers() async {
        // Register tool handlers
        _ = await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard self != nil else {
                return ListTools.Result(tools: [])
            }
            return ListTools.Result(tools: Self.availableTools)
        }

        _ = await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self = self else {
                throw MCPError.internalError("Server deallocated")
            }
            return try await self.handleToolCall(params)
        }

        // Register resource handlers
        _ = await server.withMethodHandler(ListResources.self) { [weak self] _ in
            guard self != nil else {
                return ListResources.Result(resources: [])
            }
            return ListResources.Result(resources: Self.availableResources)
        }

        _ = await server.withMethodHandler(ReadResource.self) { [weak self] params in
            guard let self = self else {
                throw MCPError.internalError("Server deallocated")
            }
            return try await self.handleResourceRead(params)
        }

        // Register prompt handlers
        _ = await server.withMethodHandler(ListPrompts.self) { [weak self] _ in
            guard self != nil else {
                return ListPrompts.Result(prompts: [])
            }
            return ListPrompts.Result(prompts: Self.availablePrompts)
        }

        _ = await server.withMethodHandler(GetPrompt.self) { [weak self] params in
            guard let self = self else {
                throw MCPError.internalError("Server deallocated")
            }
            return try await self.handlePromptGet(params)
        }
    }

    // MARK: - Tool Definitions

    private static var availableTools: [Tool] {
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
                            "description": "Only show terminals with llmNextAction set"
                        ])
                    ]),
                    "required": .array([])
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
                    "required": .array([])
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
                            "description": "Filter by column name"
                        ]),
                        "columnsOnly": .object([
                            "type": "boolean",
                            "description": "Return only column names"
                        ])
                    ]),
                    "required": .array([])
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
                        "favourites": .object(["type": "boolean", "description": "Only show favourites"])
                    ]),
                    "required": .array([])
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
                            "description": "Terminal name, UUID, or path (partial match supported)"
                        ])
                    ]),
                    "required": .array([.string("identifier")])
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
                        "llmNextAction": .object(["type": "string", "description": "One-time action for next session"])
                    ]),
                    "required": .array([])
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
                        "favourite": .object(["type": "boolean", "description": "Set favourite status"])
                    ]),
                    "required": .array([.string("identifier")])
                ])
            ),
            Tool(
                name: "termq_move",
                description: "Move a terminal to a different column (workflow stage).",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "identifier": .object(["type": "string", "description": "Terminal name or UUID"]),
                        "column": .object(["type": "string", "description": "Target column name"])
                    ]),
                    "required": .array([.string("identifier"), .string("column")])
                ])
            )
        ]
    }

    // MARK: - Resource Definitions

    private static var availableResources: [Resource] {
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
            )
        ]
    }

    // MARK: - Prompt Definitions

    private static var availablePrompts: [Prompt] {
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
            )
        ]
    }

    // MARK: - Tool Handlers

    private func handleToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "termq_pending":
            return try await handlePending(params.arguments)
        case "termq_context":
            return try await handleContext()
        case "termq_list":
            return try await handleList(params.arguments)
        case "termq_find":
            return try await handleFind(params.arguments)
        case "termq_open":
            return try await handleOpen(params.arguments)
        case "termq_create":
            return try await handleCreate(params.arguments)
        case "termq_set":
            return try await handleSet(params.arguments)
        case "termq_move":
            return try await handleMove(params.arguments)
        default:
            throw MCPError.invalidRequest("Unknown tool: \(params.name)")
        }
    }

    private func handlePending(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        // TODO: Implement using PendingOperation
        let actionsOnly = arguments?["actionsOnly"]?.boolValue ?? false
        let message = actionsOnly
            ? "Pending terminals (actions only) - implementation pending"
            : "Pending terminals - implementation pending"
        return CallTool.Result(content: [.text(message)])
    }

    private func handleContext() async throws -> CallTool.Result {
        // TODO: Implement using ContextOperation
        return CallTool.Result(content: [.text("Context documentation - implementation pending")])
    }

    private func handleList(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        // TODO: Implement using ListOperation
        return CallTool.Result(content: [.text("Terminal list - implementation pending")])
    }

    private func handleFind(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        // TODO: Implement using FindOperation
        return CallTool.Result(content: [.text("Find results - implementation pending")])
    }

    private func handleOpen(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let identifier = arguments?["identifier"]?.stringValue else {
            throw MCPError.invalidParams("identifier is required")
        }
        // TODO: Implement using OpenOperation
        return CallTool.Result(content: [.text("Opening terminal: \(identifier) - implementation pending")])
    }

    private func handleCreate(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        // TODO: Implement using CreateOperation
        return CallTool.Result(content: [.text("Create terminal - implementation pending")])
    }

    private func handleSet(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let identifier = arguments?["identifier"]?.stringValue else {
            throw MCPError.invalidParams("identifier is required")
        }
        // TODO: Implement using SetOperation
        return CallTool.Result(content: [.text("Setting terminal: \(identifier) - implementation pending")])
    }

    private func handleMove(_ arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let identifier = arguments?["identifier"]?.stringValue,
              let column = arguments?["column"]?.stringValue else {
            throw MCPError.invalidParams("identifier and column are required")
        }
        // TODO: Implement using MoveOperation
        return CallTool.Result(content: [.text("Moving \(identifier) to \(column) - implementation pending")])
    }

    // MARK: - Resource Handlers

    private func handleResourceRead(_ params: ReadResource.Parameters) async throws -> ReadResource.Result {
        let uri = params.uri
        switch uri {
        case "termq://terminals":
            return ReadResource.Result(contents: [.text("[]", uri: uri)])
        case "termq://columns":
            return ReadResource.Result(contents: [.text("[]", uri: uri)])
        case "termq://pending":
            return ReadResource.Result(contents: [.text("{}", uri: uri)])
        case "termq://context":
            return ReadResource.Result(contents: [.text("# TermQ Workflow Guide\n\nImplementation pending.", uri: uri)])
        default:
            throw MCPError.invalidRequest("Unknown resource: \(uri)")
        }
    }

    // MARK: - Prompt Handlers

    private func handlePromptGet(_ params: GetPrompt.Parameters) async throws -> GetPrompt.Result {
        switch params.name {
        case "session_start":
            return GetPrompt.Result(
                description: "TermQ Session Start",
                messages: [
                    .user(.text(text: "# TermQ Session Start\n\nImplementation pending."))
                ]
            )
        case "workflow_guide":
            return GetPrompt.Result(
                description: "TermQ Workflow Guide",
                messages: [
                    .user(.text(text: "# TermQ Workflow Guide\n\nImplementation pending."))
                ]
            )
        case "terminal_summary":
            let terminal = params.arguments?["terminal"] ?? "unknown"
            return GetPrompt.Result(
                description: "Terminal Summary: \(terminal)",
                messages: [
                    .user(.text(text: "# Terminal Summary: \(terminal)\n\nImplementation pending."))
                ]
            )
        default:
            throw MCPError.invalidRequest("Unknown prompt: \(params.name)")
        }
    }
}
