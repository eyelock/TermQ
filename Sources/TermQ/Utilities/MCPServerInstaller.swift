import Foundation

/// Common installation locations for the MCP Server
enum MCPInstallLocation: String, CaseIterable, Identifiable {
    case usrLocalBin = "/usr/local/bin"
    case homeLocalBin = "~/.local/bin"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usrLocalBin:
            return "/usr/local/bin (Recommended)"
        case .homeLocalBin:
            return "~/.local/bin (No admin required)"
        }
    }

    var path: String {
        switch self {
        case .usrLocalBin:
            return "/usr/local/bin"
        case .homeLocalBin:
            return NSString(string: "~/.local/bin").expandingTildeInPath
        }
    }

    var fullPath: String {
        "\(path)/termqmcp"
    }

    var requiresAdmin: Bool {
        switch self {
        case .usrLocalBin:
            return true
        case .homeLocalBin:
            return false
        }
    }

    var pathNote: String {
        switch self {
        case .usrLocalBin:
            return "Requires administrator privileges"
        case .homeLocalBin:
            return "Add ~/.local/bin to your PATH if not already"
        }
    }
}

/// Handles installation of the termqmcp MCP Server
enum MCPServerInstaller {
    static let bundledMCPServerName = "termqmcp"

    /// Get the path to the bundled MCP server within the app bundle
    static var bundledMCPServerPath: URL? {
        Bundle.main.url(forResource: bundledMCPServerName, withExtension: nil)
    }

    /// Check if the MCP server is installed at a specific location
    static func isInstalled(at location: MCPInstallLocation) -> Bool {
        FileManager.default.fileExists(atPath: location.fullPath)
    }

    /// Check if the MCP server is installed at a custom path
    static func isInstalled(atPath path: String) -> Bool {
        let fullPath = path.hasSuffix("/termqmcp") ? path : "\(path)/termqmcp"
        let expanded = NSString(string: fullPath).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    /// Find where the MCP server is currently installed (if anywhere)
    static var currentInstallLocation: MCPInstallLocation? {
        MCPInstallLocation.allCases.first { isInstalled(at: $0) }
    }

    /// Install the MCP server to a standard location
    static func install(to location: MCPInstallLocation) async -> Result<String, MCPServerInstallerError> {
        return await install(toPath: location.path, requiresAdmin: location.requiresAdmin)
    }

    /// Install the MCP server to a custom path
    static func install(
        toPath path: String, requiresAdmin: Bool? = nil
    ) async -> Result<String, MCPServerInstallerError> {
        guard let sourcePath = bundledMCPServerPath else {
            return .failure(.bundledMCPServerNotFound)
        }

        let expandedPath = NSString(string: path).expandingTildeInPath
        let fullPath = "\(expandedPath)/termqmcp"

        // Determine if admin is needed (if not explicitly specified, check if path is writable)
        let needsAdmin = requiresAdmin ?? !FileManager.default.isWritableFile(atPath: expandedPath)

        if needsAdmin {
            return await installWithAdmin(source: sourcePath.path, destination: fullPath, directory: expandedPath)
        } else {
            return await installWithoutAdmin(source: sourcePath.path, destination: fullPath, directory: expandedPath)
        }
    }

    /// Install using AppleScript for admin privileges
    private static func installWithAdmin(
        source: String, destination: String, directory: String
    ) async -> Result<String, MCPServerInstallerError> {
        // Ensure directory exists
        let ensureDirScript = """
            do shell script "mkdir -p '\(directory)'" with administrator privileges
            """

        // Copy the MCP server
        let copyScript = """
            do shell script "cp '\(source)' '\(destination)' && chmod +x '\(destination)'" with administrator privileges
            """

        // First ensure directory exists
        var error: NSDictionary?
        NSAppleScript(source: ensureDirScript)?.executeAndReturnError(&error)
        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            if message.contains("canceled") || message.contains("cancelled") {
                return .failure(.userCancelled)
            }
            return .failure(.installFailed(message))
        }

        // Then copy the file
        error = nil
        NSAppleScript(source: copyScript)?.executeAndReturnError(&error)
        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            if message.contains("canceled") || message.contains("cancelled") {
                return .failure(.userCancelled)
            }
            return .failure(.installFailed(message))
        }

        return .success("MCP Server installed successfully to \(destination)")
    }

    /// Install without admin (user-writable location)
    private static func installWithoutAdmin(
        source: String, destination: String, directory: String
    ) async -> Result<String, MCPServerInstallerError> {
        let fileManager = FileManager.default

        do {
            // Create directory if needed
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

            // Remove existing file if present
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }

            // Copy the MCP server
            try fileManager.copyItem(atPath: source, toPath: destination)

            // Make executable
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)

            return .success("MCP Server installed successfully to \(destination)")
        } catch {
            return .failure(.installFailed(error.localizedDescription))
        }
    }

    /// Uninstall the MCP server from a specific location
    static func uninstall(from location: MCPInstallLocation) async -> Result<String, MCPServerInstallerError> {
        return await uninstall(fromPath: location.fullPath, requiresAdmin: location.requiresAdmin)
    }

    /// Uninstall the MCP server from a custom path
    static func uninstall(
        fromPath path: String, requiresAdmin: Bool? = nil
    ) async -> Result<String, MCPServerInstallerError> {
        let expandedPath = NSString(string: path).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .failure(.notInstalled)
        }

        let needsAdmin = requiresAdmin ?? !FileManager.default.isWritableFile(atPath: expandedPath)

        if needsAdmin {
            let script = """
                do shell script "rm '\(expandedPath)'" with administrator privileges
                """

            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error = error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                if message.contains("canceled") || message.contains("cancelled") {
                    return .failure(.userCancelled)
                }
                return .failure(.uninstallFailed(message))
            }
        } else {
            do {
                try FileManager.default.removeItem(atPath: expandedPath)
            } catch {
                return .failure(.uninstallFailed(error.localizedDescription))
            }
        }

        return .success("MCP Server uninstalled successfully")
    }

    /// Generate Claude Code configuration JSON for MCP server
    static func generateClaudeCodeConfig() -> String {
        return """
            {
              "mcpServers": {
                "termq": {
                  "command": "termqmcp"
                }
              }
            }
            """
    }
}

enum MCPServerInstallerError: LocalizedError {
    case bundledMCPServerNotFound
    case installFailed(String)
    case uninstallFailed(String)
    case notInstalled
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .bundledMCPServerNotFound:
            return "The MCP server was not found in the app bundle."
        case .installFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallFailed(let message):
            return "Uninstallation failed: \(message)"
        case .notInstalled:
            return "The MCP server is not installed."
        case .userCancelled:
            return "Operation cancelled by user."
        }
    }
}
