import Foundation
import MCP
import TermQShared

// `SetLoggingLevel` is provided by the MCP Swift SDK as of the 2025-11-25 spec;
// no local re-declaration is needed. The SDK's version uses the proper `LogLevel`
// enum rather than a free-form String.

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

    /// Lazily-created subscription manager. Watches board.json and fires
    /// `notifications/resources/updated` for subscribed URIs when the file changes.
    private var subscriptionManager: ResourceSubscriptionManager?

    /// Server name identifier
    public static let serverName = "termq"

    /// Server version
    public static let serverVersion = "1.0.0"

    // MARK: - Log Level State
    //
    // `logging/setLevel` is a client request to filter `notifications/message`
    // notifications by minimum severity. The MCP spec lets clients dial verbosity up
    // and down at runtime. We store the configured threshold and gate emissions on it.

    /// `NSLock`-guarded minimum log level — defaults to `.info` (matches most clients'
    /// expectations). Mutable: clients raise/lower it via `logging/setLevel`.
    private let logLevelLock = NSLock()
    private var _minLogLevel: LogLevel = .info

    var minLogLevel: LogLevel {
        logLevelLock.lock()
        defer { logLevelLock.unlock() }
        return _minLogLevel
    }

    func setMinLogLevel(_ level: LogLevel) {
        logLevelLock.lock()
        _minLogLevel = level
        logLevelLock.unlock()
    }

    /// Initialize the MCP server
    /// - Parameter dataDirectory: Optional custom data directory (nil uses default)
    public init(dataDirectory: URL? = nil) {
        self.dataDirectory = dataDirectory
        self.server = Server(
            name: Self.serverName,
            version: Self.serverVersion,
            capabilities: Server.Capabilities(
                completions: .init(),
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
        await startSubscriptionWatcher()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    /// Initialise the subscription manager and arm the file watcher pointed at the
    /// resolved board.json. Called from `run(transport:)` once at startup. No-op when
    /// subscriptions aren't useful (e.g. tests that pass in a manual `dataDirectory`
    /// pointing nowhere) — the watcher silently retries until the file appears.
    private func startSubscriptionWatcher() async {
        let dataDir = dataDirectory ?? BoardLoader.getDataDirectoryPath()
        let boardURL = dataDir.appendingPathComponent("board.json")
        let manager = ResourceSubscriptionManager { [weak self] uri in
            await self?.emitResourceUpdated(uri: uri)
        }
        self.subscriptionManager = manager
        await manager.startWatching(boardURL: boardURL)
    }

    /// Emit `notifications/resources/updated` for a single URI. Best-effort —
    /// transport hiccups don't propagate (subscribers will catch up on next change).
    private func emitResourceUpdated(uri: String) async {
        let params = ResourceUpdatedNotification.Parameters(uri: uri)
        try? await server.notify(ResourceUpdatedNotification.message(params))
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

        _ = await server.withMethodHandler(ListResourceTemplates.self) { [weak self] _ in
            guard self != nil else {
                return ListResourceTemplates.Result(templates: [])
            }
            return ListResourceTemplates.Result(templates: Self.availableResourceTemplates)
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

        // Register logging handler — apply the client's requested minimum severity
        // threshold so subsequent `notifications/message` emissions are filtered.
        _ = await server.withMethodHandler(SetLoggingLevel.self) { [weak self] params in
            self?.setMinLogLevel(params.level)
            return Empty()
        }

        // Register completion handler (required when declaring completions capability).
        // Surfaces autocomplete suggestions for prompt arguments — currently the `terminal`
        // argument of `terminal_summary`.
        _ = await server.withMethodHandler(Complete.self) { [weak self] params in
            guard let self = self else {
                throw MCPError.internalError("Server deallocated")
            }
            return try await self.dispatchCompletion(params)
        }

        // Register subscription handlers. The actual emission lives in
        // ResourceSubscriptionManager; these just track which URIs are live.
        _ = await server.withMethodHandler(ResourceSubscribe.self) { [weak self] params in
            await self?.subscriptionManager?.subscribe(uri: params.uri)
            return Empty()
        }
        _ = await server.withMethodHandler(ResourceUnsubscribe.self) { [weak self] params in
            await self?.subscriptionManager?.unsubscribe(uri: params.uri)
            return Empty()
        }
    }

    // MARK: - Helpers

    /// Load the board from the data directory.
    ///
    /// On failure, mirrors the error as a `notifications/message` (error level) so a
    /// remote operator sees the failure even without local `--verbose` stderr. Then
    /// re-throws — surfacing the failure to the calling tool is still mandatory.
    func loadBoard() throws -> Board {
        do {
            return try BoardLoader.loadBoard(dataDirectory: dataDirectory)
        } catch {
            // Best-effort fire-and-forget mirror; never let logging affect the error path.
            Task { [weak self] in
                await self?.emitLog(
                    .error,
                    "Board load failed: \(error.localizedDescription)",
                    logger: "termq.board"
                )
            }
            throw error
        }
    }

    // MARK: - Logging Mirror

    /// Severity ordering used by `notifications/message` filtering. Higher index = more
    /// severe. Matches the MCP spec ordering (debug → emergency).
    private static let severityOrder: [LogLevel] = [
        .debug, .info, .notice, .warning, .error, .critical, .alert, .emergency,
    ]

    /// Emit a `notifications/message` to the client — best-effort, gated by the
    /// client-configured minimum log level. Silent failure is intentional: a transport
    /// hiccup must never break the calling tool. The internal `os.Logger` (TermQLogger)
    /// stays the source of truth for local debugging; this just mirrors selected events
    /// over the wire so a remote operator can see them without `--verbose` stderr.
    func emitLog(_ level: LogLevel, _ message: String, logger: String = "termq") async {
        guard let minIdx = Self.severityOrder.firstIndex(of: minLogLevel),
            let curIdx = Self.severityOrder.firstIndex(of: level),
            curIdx >= minIdx
        else {
            return
        }
        let params = LogMessageNotification.Parameters(
            level: level,
            logger: logger,
            data: .string(message)
        )
        try? await server.notify(LogMessageNotification.message(params))
    }
}
