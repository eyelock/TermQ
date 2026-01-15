import Foundation
import TermQCore

/// Manages tmux session lifecycle for TermQ terminals
///
/// Provides detection, session creation, listing, and attachment functionality.
/// When tmux is not available, callers should fall back to direct shell mode.
@MainActor
public class TmuxManager: ObservableObject {
    public static let shared = TmuxManager()

    /// Prefix for all TermQ-managed tmux sessions
    public static let sessionPrefix = "termq-"

    /// Whether tmux is available on the system
    @Published public private(set) var isAvailable: Bool = false

    /// Detected tmux version (nil if not available)
    @Published public private(set) var version: String?

    /// Path to tmux executable
    @Published public private(set) var tmuxPath: String?

    /// Cached list of recoverable sessions (populated on app launch)
    @Published public private(set) var recoverableSessions: [TmuxSessionInfo] = []

    private init() {
        Task {
            await detectTmux()
        }
    }

    // MARK: - Detection

    /// Detect if tmux is installed and get its version
    public func detectTmux() async {
        // Check common locations
        let paths = [
            "/opt/homebrew/bin/tmux",  // Apple Silicon Homebrew
            "/usr/local/bin/tmux",  // Intel Homebrew
            "/usr/bin/tmux",  // System
            "/opt/local/bin/tmux",  // MacPorts
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                tmuxPath = path
                break
            }
        }

        // Also check PATH via `which`
        if tmuxPath == nil {
            if let whichResult = try? await runCommand("/usr/bin/which", args: ["tmux"]),
                !whichResult.isEmpty
            {
                let path = whichResult.trimmingCharacters(in: .whitespacesAndNewlines)
                if FileManager.default.isExecutableFile(atPath: path) {
                    tmuxPath = path
                }
            }
        }

        guard let path = tmuxPath else {
            isAvailable = false
            version = nil
            return
        }

        // Get version
        if let versionOutput = try? await runCommand(path, args: ["-V"]) {
            // Output is like "tmux 3.3a" or "tmux 3.4"
            let parts = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            if parts.count >= 2 {
                version = String(parts[1])
            }
            isAvailable = true
        } else {
            isAvailable = false
            version = nil
        }
    }

    // MARK: - Session Management

    /// Generate a tmux session name for a terminal card
    public func sessionName(for cardId: UUID) -> String {
        "\(Self.sessionPrefix)\(cardId.uuidString.prefix(8).lowercased())"
    }

    /// Parse a card ID from a tmux session name (if it's a TermQ session)
    public func cardIdPrefix(from sessionName: String) -> String? {
        guard sessionName.hasPrefix(Self.sessionPrefix) else { return nil }
        return String(sessionName.dropFirst(Self.sessionPrefix.count))
    }

    /// Check if a specific tmux session exists
    public func sessionExists(name: String) async -> Bool {
        guard let path = tmuxPath else { return false }
        let result = try? await runCommand(path, args: ["has-session", "-t", name])
        // has-session returns exit code 0 if exists, non-zero otherwise
        // runCommand throws on non-zero, so if we get here it exists
        return result != nil
    }

    /// List all TermQ-managed tmux sessions
    public func listSessions() async -> [TmuxSessionInfo] {
        guard let path = tmuxPath else { return [] }

        // Get session list with format: name|created|attached|path
        guard
            let output = try? await runCommand(
                path,
                args: [
                    "list-sessions",
                    "-F",
                    "#{session_name}|#{session_created}|#{session_attached}|#{pane_current_path}",
                ]
            )
        else {
            return []
        }

        var sessions: [TmuxSessionInfo] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { continue }

            let name = String(parts[0])
            guard name.hasPrefix(Self.sessionPrefix) else { continue }

            let createdTimestamp = TimeInterval(parts[1]) ?? 0
            let isAttached = parts[2] == "1"
            let currentPath = String(parts[3])

            sessions.append(
                TmuxSessionInfo(
                    name: name,
                    cardIdPrefix: String(name.dropFirst(Self.sessionPrefix.count)),
                    createdAt: Date(timeIntervalSince1970: createdTimestamp),
                    isAttached: isAttached,
                    currentPath: currentPath.isEmpty ? nil : currentPath
                ))
        }

        recoverableSessions = sessions.filter { !$0.isAttached }
        return sessions
    }

    /// Create a new tmux session (detached)
    public func createSession(
        name: String,
        workingDirectory: String,
        shell: String,
        environment: [String: String] = [:]
    ) async throws {
        guard let path = tmuxPath else {
            throw TmuxError.notAvailable
        }

        // Build environment string for tmux
        var envArgs: [String] = []
        for (key, value) in environment {
            envArgs.append(contentsOf: ["-e", "\(key)=\(value)"])
        }

        // Create detached session with specified shell
        var args = [
            "new-session",
            "-d",  // Detached
            "-s", name,  // Session name
            "-c", workingDirectory,  // Working directory
        ]
        args.append(contentsOf: envArgs)

        // Specify shell as the command to run
        args.append(shell)
        args.append("-l")  // Login shell

        _ = try await runCommand(path, args: args)
    }

    /// Kill a tmux session
    public func killSession(name: String) async throws {
        guard let path = tmuxPath else {
            throw TmuxError.notAvailable
        }
        _ = try await runCommand(path, args: ["kill-session", "-t", name])
    }

    /// Get the command to attach to a tmux session (for use with terminal.startProcess)
    public func attachCommand(sessionName: String) -> (executable: String, args: [String]) {
        guard let path = tmuxPath else {
            // Fallback - shouldn't happen if isAvailable is checked first
            return ("/bin/sh", ["-c", "echo 'tmux not available'; exit 1"])
        }

        return (path, ["attach-session", "-t", sessionName])
    }

    /// Configure tmux for TermQ-friendly defaults (no status bar, etc.)
    public func configureSession(name: String) async throws {
        guard let path = tmuxPath else {
            throw TmuxError.notAvailable
        }

        // Disable status bar for cleaner TermQ integration
        _ = try? await runCommand(path, args: ["set-option", "-t", name, "status", "off"])

        // Set terminal type
        _ = try? await runCommand(path, args: ["set-option", "-t", name, "default-terminal", "xterm-256color"])

        // Enable mouse support
        _ = try? await runCommand(path, args: ["set-option", "-t", name, "mouse", "on"])

        // Faster escape time (better for vim users)
        _ = try? await runCommand(path, args: ["set-option", "-t", name, "escape-time", "10"])
    }

    /// Store metadata in tmux session environment (for recovery)
    public func setSessionMetadata(name: String, key: String, value: String) async throws {
        guard let path = tmuxPath else {
            throw TmuxError.notAvailable
        }
        // Use tmux environment variables for metadata storage
        _ = try await runCommand(path, args: ["set-environment", "-t", name, "TERMQ_\(key)", value])
    }

    /// Get metadata from tmux session environment
    public func getSessionMetadata(name: String, key: String) async -> String? {
        guard let path = tmuxPath else { return nil }
        let result = try? await runCommand(path, args: ["show-environment", "-t", name, "TERMQ_\(key)"])
        // Output is "TERMQ_KEY=value" or nothing
        guard let output = result, output.contains("=") else { return nil }
        return String(output.split(separator: "=", maxSplits: 1).last ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Full Metadata Sync

    /// Metadata keys stored in tmux session environment
    private enum MetadataKey: String, CaseIterable {
        case title = "TITLE"
        case description = "DESC"
        case tags = "TAGS"
        case llmPrompt = "LLM_PROMPT"
        case llmNextAction = "LLM_NEXT_ACTION"
        case badge = "BADGE"
        case columnId = "COLUMN_ID"
        case isFavourite = "IS_FAVOURITE"
        case cardId = "CARD_ID"
    }

    /// Save all terminal card metadata to tmux session environment
    /// This allows metadata recovery when reattaching orphaned sessions
    public func syncMetadataToSession(sessionName: String, card: TerminalCardMetadata) async {
        guard tmuxPath != nil else { return }

        do {
            try await setSessionMetadata(name: sessionName, key: MetadataKey.cardId.rawValue, value: card.id.uuidString)
            try await setSessionMetadata(name: sessionName, key: MetadataKey.title.rawValue, value: card.title)
            try await setSessionMetadata(
                name: sessionName, key: MetadataKey.description.rawValue, value: card.description)
            try await setSessionMetadata(
                name: sessionName, key: MetadataKey.tags.rawValue, value: encodeTagsToString(card.tags))
            try await setSessionMetadata(name: sessionName, key: MetadataKey.llmPrompt.rawValue, value: card.llmPrompt)
            try await setSessionMetadata(
                name: sessionName, key: MetadataKey.llmNextAction.rawValue, value: card.llmNextAction)
            try await setSessionMetadata(name: sessionName, key: MetadataKey.badge.rawValue, value: card.badge)
            if let columnId = card.columnId {
                try await setSessionMetadata(
                    name: sessionName, key: MetadataKey.columnId.rawValue, value: columnId.uuidString)
            }
            try await setSessionMetadata(
                name: sessionName, key: MetadataKey.isFavourite.rawValue, value: card.isFavourite ? "1" : "0")
        } catch {
            print("TmuxManager: Failed to sync metadata for \(sessionName): \(error)")
        }
    }

    /// Retrieve all terminal card metadata from tmux session environment
    /// Returns nil if no metadata is found (session was created without metadata)
    public func getMetadataFromSession(sessionName: String) async -> TerminalCardMetadata? {
        guard tmuxPath != nil else { return nil }

        // Card ID is required - if missing, no metadata was stored
        guard let cardIdString = await getSessionMetadata(name: sessionName, key: MetadataKey.cardId.rawValue),
            let cardId = UUID(uuidString: cardIdString)
        else {
            return nil
        }

        let title = await getSessionMetadata(name: sessionName, key: MetadataKey.title.rawValue) ?? "Recovered Terminal"
        let description = await getSessionMetadata(name: sessionName, key: MetadataKey.description.rawValue) ?? ""
        let tagsString = await getSessionMetadata(name: sessionName, key: MetadataKey.tags.rawValue) ?? ""
        let llmPrompt = await getSessionMetadata(name: sessionName, key: MetadataKey.llmPrompt.rawValue) ?? ""
        let llmNextAction = await getSessionMetadata(name: sessionName, key: MetadataKey.llmNextAction.rawValue) ?? ""
        let badge = await getSessionMetadata(name: sessionName, key: MetadataKey.badge.rawValue) ?? ""
        let columnIdString = await getSessionMetadata(name: sessionName, key: MetadataKey.columnId.rawValue) ?? ""
        let isFavouriteString =
            await getSessionMetadata(name: sessionName, key: MetadataKey.isFavourite.rawValue) ?? "0"

        let columnId = UUID(uuidString: columnIdString)
        let tags = decodeTagsFromString(tagsString)
        let isFavourite = isFavouriteString == "1"

        return TerminalCardMetadata(
            id: cardId,
            title: title,
            description: description,
            tags: tags,
            llmPrompt: llmPrompt,
            llmNextAction: llmNextAction,
            badge: badge,
            columnId: columnId,
            isFavourite: isFavourite
        )
    }

    /// Update a single metadata field in the tmux session
    public func updateSessionMetadata(
        sessionName: String, title: String? = nil, description: String? = nil,
        tags: [Tag]? = nil, llmPrompt: String? = nil, llmNextAction: String? = nil,
        badge: String? = nil, columnId: UUID? = nil, isFavourite: Bool? = nil
    ) async {
        guard tmuxPath != nil else { return }

        do {
            if let title = title {
                try await setSessionMetadata(name: sessionName, key: MetadataKey.title.rawValue, value: title)
            }
            if let description = description {
                try await setSessionMetadata(
                    name: sessionName, key: MetadataKey.description.rawValue, value: description)
            }
            if let tags = tags {
                try await setSessionMetadata(
                    name: sessionName, key: MetadataKey.tags.rawValue, value: encodeTagsToString(tags))
            }
            if let llmPrompt = llmPrompt {
                try await setSessionMetadata(name: sessionName, key: MetadataKey.llmPrompt.rawValue, value: llmPrompt)
            }
            if let llmNextAction = llmNextAction {
                try await setSessionMetadata(
                    name: sessionName, key: MetadataKey.llmNextAction.rawValue, value: llmNextAction)
            }
            if let badge = badge {
                try await setSessionMetadata(name: sessionName, key: MetadataKey.badge.rawValue, value: badge)
            }
            if let columnId = columnId {
                try await setSessionMetadata(
                    name: sessionName, key: MetadataKey.columnId.rawValue, value: columnId.uuidString)
            }
            if let isFavourite = isFavourite {
                try await setSessionMetadata(
                    name: sessionName, key: MetadataKey.isFavourite.rawValue, value: isFavourite ? "1" : "0")
            }
        } catch {
            print("TmuxManager: Failed to update metadata for \(sessionName): \(error)")
        }
    }

    // MARK: - Tag Encoding

    /// Encode tags to a string for storage (format: "key1:value1,key2:value2")
    private func encodeTagsToString(_ tags: [Tag]) -> String {
        tags.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }

    /// Decode tags from storage string
    private func decodeTagsFromString(_ string: String) -> [Tag] {
        guard !string.isEmpty else { return [] }
        return string.split(separator: ",").compactMap { pair in
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Tag(key: String(parts[0]), value: String(parts[1]))
        }
    }

    // MARK: - Recovery

    /// Refresh the list of recoverable sessions
    public func refreshRecoverableSessions() async {
        _ = await listSessions()
    }

    /// Mark a session as recovered (remove from recoverable list)
    public func markSessionRecovered(name: String) {
        recoverableSessions.removeAll { $0.name == name }
    }

    // MARK: - Private Helpers

    private func runCommand(_ executable: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(
                        throwing: TmuxError.commandFailed(
                            command: "\(executable) \(args.joined(separator: " "))",
                            exitCode: process.terminationStatus,
                            output: output
                        ))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Supporting Types

/// Information about a tmux session
public struct TmuxSessionInfo: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let cardIdPrefix: String
    public let createdAt: Date
    public let isAttached: Bool
    public let currentPath: String?
}

/// Errors from tmux operations
public enum TmuxError: Error, LocalizedError {
    case notAvailable
    case sessionNotFound(name: String)
    case commandFailed(command: String, exitCode: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "tmux is not installed. Install with: brew install tmux"
        case .sessionNotFound(let name):
            return "tmux session '\(name)' not found"
        case .commandFailed(let command, let exitCode, let output):
            return "tmux command failed (\(exitCode)): \(command)\n\(output)"
        }
    }
}

/// Lightweight metadata structure for tmux session storage/recovery
/// Contains the essential fields that can be recovered from an orphaned session
public struct TerminalCardMetadata: Sendable {
    public let id: UUID
    public let title: String
    public let description: String
    public let tags: [Tag]
    public let llmPrompt: String
    public let llmNextAction: String
    public let badge: String
    public let columnId: UUID?
    public let isFavourite: Bool

    public init(
        id: UUID,
        title: String,
        description: String = "",
        tags: [Tag] = [],
        llmPrompt: String = "",
        llmNextAction: String = "",
        badge: String = "",
        columnId: UUID? = nil,
        isFavourite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.tags = tags
        self.llmPrompt = llmPrompt
        self.llmNextAction = llmNextAction
        self.badge = badge
        self.columnId = columnId
        self.isFavourite = isFavourite
    }

    /// Create metadata from a TerminalCard
    public static func from(_ card: TerminalCard) -> TerminalCardMetadata {
        TerminalCardMetadata(
            id: card.id,
            title: card.title,
            description: card.description,
            tags: card.tags,
            llmPrompt: card.llmPrompt,
            llmNextAction: card.llmNextAction,
            badge: card.badge,
            columnId: card.columnId,
            isFavourite: card.isFavourite
        )
    }
}
