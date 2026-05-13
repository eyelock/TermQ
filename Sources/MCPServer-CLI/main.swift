import ArgumentParser
import Foundation
import MCP
import MCPServerLib
import TermQShared

// MARK: - Build Configuration

/// Resolves the AppProfile.Variant for this invocation. In a debug build, `.debug` is the
/// only valid option (overriding any user input). In a production build, the user's
/// `--debug` flag selects between `.production` and `.debug`.
private func resolveProfile(explicitDebug: Bool) -> AppProfile.Variant {
    #if TERMQ_DEBUG_BUILD
        return .debug
    #else
        return explicitDebug ? .debug : .production
    #endif
}

@main
struct TermQMCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "termqmcp",
        abstract: "MCP Server for TermQ - Terminal Queue Manager",
        discussion: """
            Model Context Protocol server enabling LLM assistants like Claude Code
            to interact with TermQ's terminal management functionality.

            \u{26A0}\u{FE0F}  LOCAL USE ONLY: This server is designed for local development workflows.
                Do NOT deploy as a networked service or expose to the internet.

            EXAMPLES:
              # Stdio mode (for Claude Code)
              termqmcp

              # HTTP mode with authentication
              termqmcp --http --port 8742 --secret "your-uuid-token"

              # Debug mode (uses separate data directory)
              termqmcp --debug
            """,
        version: TermQMCPServer.serverVersion
    )

    @Flag(help: "Run HTTP server instead of stdio (default: stdio)")
    var http = false

    @Option(help: "HTTP port (default: 8742, requires --http)")
    var port: Int = 8742

    @Option(help: "Bearer token for HTTP authentication (required if --http)")
    var secret: String?

    @Flag(help: "Use debug data directory")
    var debug = false

    @Flag(help: "Enable verbose logging")
    var verbose = false

    mutating func validate() throws {
        if http && secret == nil {
            throw ValidationError("--secret is required when using --http mode")
        }
        if port < 1024 || port > 65535 {
            throw ValidationError("Port must be between 1024 and 65535")
        }
    }

    func run() async throws {
        // Resolve the app profile and derive the data directory from it.
        // The resolved values are logged below so debug/production mismatches are visible
        // — that was the root cause of the "MCP returns empty results" bug.
        let profile = resolveProfile(explicitDebug: debug)
        let dataDirectory = BoardLoader.getDataDirectoryPath(profile: profile)

        if verbose {
            fputs(
                """
                termqmcp starting
                  profile:       \(profile)
                  data directory: \(dataDirectory.path)
                  bundle id:     \(profile.bundleIdentifier)
                  transport:     \(http ? "http" : "stdio")

                """,
                stderr
            )
        }

        // Create server with the explicit data directory derived from profile.
        let server = TermQMCPServer(dataDirectory: dataDirectory)

        if http {
            // HTTP mode with bearer token authentication
            if verbose {
                fputs("Starting HTTP server on port \(port)...\n", stderr)
            }
            // HTTP transport implementation pending
            fputs("HTTP transport not yet implemented. Use stdio mode.\n", stderr)
            throw ExitCode.failure
        } else {
            // Stdio mode (default)
            if verbose {
                fputs("Starting stdio server...\n", stderr)
            }
            let transport = StdioTransport()
            try await server.run(transport: transport)
        }
    }
}
