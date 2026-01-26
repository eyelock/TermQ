import Foundation
import os.log
import TermQShared

/// Common installation locations for the MCP Server
enum MCPInstallLocation: String, CaseIterable, Identifiable, InstallLocationProtocol {
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
        "\(path)/\(AppProfile.Current.mcpBinaryName)"
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
    private static let log = OSLog(subsystem: "net.eyelock.termq", category: "MCPServerInstaller")

    private static let config: ComponentInstaller<MCPInstallLocation>.Config = {
        let cfg = ComponentInstaller<MCPInstallLocation>.Config(
            bundledResourceName: AppProfile.Current.mcpBinaryName,
            componentDisplayName: "MCP Server"
        )
        os_log("🔧 Config created:", log: log, type: .info)
        os_log("   - bundledResourceName: %{public}@", log: log, type: .info, cfg.bundledResourceName)
        os_log("   - componentDisplayName: %{public}@", log: log, type: .info, cfg.componentDisplayName)
        os_log("   - AppProfile.Current.mcpBinaryName: %{public}@", log: log, type: .info, AppProfile.Current.mcpBinaryName)
        return cfg
    }()

    static let bundledMCPServerName = AppProfile.Current.mcpBinaryName

    /// Get the path to the bundled MCP server within the app bundle
    static var bundledMCPServerPath: URL? {
        ComponentInstaller<MCPInstallLocation>.bundledPath(config: config)
    }

    /// Check if the MCP server is installed at a specific location
    static func isInstalled(at location: MCPInstallLocation) -> Bool {
        ComponentInstaller<MCPInstallLocation>.isInstalled(at: location, config: config)
    }

    /// Check if the MCP server is installed at a custom path
    static func isInstalled(atPath path: String) -> Bool {
        ComponentInstaller<MCPInstallLocation>.isInstalled(atPath: path, config: config)
    }

    /// Find where the MCP server is currently installed (if anywhere)
    static var currentInstallLocation: MCPInstallLocation? {
        ComponentInstaller<MCPInstallLocation>.currentInstallLocation(config: config)
    }

    /// Install the MCP server to a standard location
    static func install(to location: MCPInstallLocation) async -> Result<String, MCPServerInstallerError> {
        await ComponentInstaller<MCPInstallLocation>.install(to: location, config: config)
            .mapError { MCPServerInstallerError(from: $0) }
    }

    /// Install the MCP server to a custom path
    static func install(
        toPath path: String, requiresAdmin: Bool? = nil
    ) async -> Result<String, MCPServerInstallerError> {
        await ComponentInstaller<MCPInstallLocation>.install(
            toPath: path, requiresAdmin: requiresAdmin, config: config
        ).mapError { MCPServerInstallerError(from: $0) }
    }

    /// Uninstall the MCP server from a specific location
    static func uninstall(from location: MCPInstallLocation) async -> Result<String, MCPServerInstallerError> {
        await ComponentInstaller<MCPInstallLocation>.uninstall(from: location, config: config)
            .mapError { MCPServerInstallerError(from: $0) }
    }

    /// Uninstall the MCP server from a custom path
    static func uninstall(
        fromPath path: String, requiresAdmin: Bool? = nil
    ) async -> Result<String, MCPServerInstallerError> {
        await ComponentInstaller<MCPInstallLocation>.uninstall(
            fromPath: path, requiresAdmin: requiresAdmin, config: config
        ).mapError { MCPServerInstallerError(from: $0) }
    }

    /// Generate Claude Code configuration JSON for MCP server
    static func generateClaudeCodeConfig() -> String {
        return """
            {
              "mcpServers": {
                "termq": {
                  "command": "\(AppProfile.Current.mcpBinaryName)"
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

    init(from error: ComponentInstallerError) {
        switch error {
        case .bundledComponentNotFound:
            self = .bundledMCPServerNotFound
        case .installFailed(let message):
            self = .installFailed(message)
        case .uninstallFailed(let message):
            self = .uninstallFailed(message)
        case .notInstalled:
            self = .notInstalled
        case .userCancelled:
            self = .userCancelled
        }
    }

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
