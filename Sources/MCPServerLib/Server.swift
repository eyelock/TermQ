import Foundation
import MCP

/// TermQ MCP Server implementation
///
/// Provides Model Context Protocol interface for LLM assistants to interact
/// with TermQ's terminal management functionality.
///
/// - Warning: This server is designed for LOCAL USE ONLY. Do not deploy
///   as a networked service or expose to the internet.
public final class TermQMCPServer: @unchecked Sendable {
    private let server: Server
    let dataDirectory: URL?

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
            return try await self.dispatchToolCall(params)
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
            return try await self.dispatchResourceRead(params)
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
            return try await self.dispatchPromptGet(params)
        }
    }

    // MARK: - Helpers

    /// Load the board from the data directory
    func loadBoard() throws -> MCPBoard {
        try BoardLoader.loadBoard(dataDirectory: dataDirectory)
    }
}
