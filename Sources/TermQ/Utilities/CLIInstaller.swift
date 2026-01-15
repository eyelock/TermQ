import Foundation

/// Common installation locations for the CLI tool
enum InstallLocation: String, CaseIterable, Identifiable, InstallLocationProtocol {
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
        "\(path)/termqcli"
    }

    /// Legacy path for backwards compatibility (older versions installed as "termq")
    var legacyFullPath: String {
        "\(path)/termq"
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

/// Handles installation of the termqcli CLI tool
enum CLIInstaller {
    private static let config = ComponentInstaller<InstallLocation>.Config(
        bundledResourceName: "termqcli",
        componentDisplayName: "CLI tool"
    )

    static let bundledCLIName = "termqcli"

    /// Get the path to the bundled CLI tool within the app bundle
    static var bundledCLIPath: URL? {
        ComponentInstaller<InstallLocation>.bundledPath(config: config)
    }

    /// Check if the CLI tool is installed at a specific location
    /// Also checks for legacy name "termq" for backwards compatibility
    static func isInstalled(at location: InstallLocation) -> Bool {
        ComponentInstaller<InstallLocation>.isInstalled(at: location, config: config)
            || FileManager.default.fileExists(atPath: location.legacyFullPath)
    }

    /// Check if the CLI tool is installed at a custom path
    static func isInstalled(atPath path: String) -> Bool {
        ComponentInstaller<InstallLocation>.isInstalled(atPath: path, config: config)
    }

    /// Find where the CLI is currently installed (if anywhere)
    /// Checks for both current name "termqcli" and legacy name "termq"
    static var currentInstallLocation: InstallLocation? {
        InstallLocation.allCases.first { isInstalled(at: $0) }
    }

    /// Install the CLI tool to a standard location
    static func install(to location: InstallLocation) async -> Result<String, CLIInstallerError> {
        await ComponentInstaller<InstallLocation>.install(to: location, config: config)
            .mapError { CLIInstallerError(from: $0) }
    }

    /// Install the CLI tool to a custom path
    static func install(toPath path: String, requiresAdmin: Bool? = nil) async -> Result<String, CLIInstallerError> {
        await ComponentInstaller<InstallLocation>.install(toPath: path, requiresAdmin: requiresAdmin, config: config)
            .mapError { CLIInstallerError(from: $0) }
    }

    /// Uninstall the CLI tool from a specific location
    static func uninstall(from location: InstallLocation) async -> Result<String, CLIInstallerError> {
        await ComponentInstaller<InstallLocation>.uninstall(from: location, config: config)
            .mapError { CLIInstallerError(from: $0) }
    }

    /// Uninstall the CLI tool from a custom path
    static func uninstall(fromPath path: String, requiresAdmin: Bool? = nil) async -> Result<String, CLIInstallerError>
    {
        await ComponentInstaller<InstallLocation>.uninstall(
            fromPath: path, requiresAdmin: requiresAdmin, config: config
        )
        .mapError { CLIInstallerError(from: $0) }
    }
}

enum CLIInstallerError: LocalizedError {
    case bundledCLINotFound
    case installFailed(String)
    case uninstallFailed(String)
    case notInstalled
    case userCancelled

    init(from error: ComponentInstallerError) {
        switch error {
        case .bundledComponentNotFound:
            self = .bundledCLINotFound
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
        case .bundledCLINotFound:
            return "The CLI tool was not found in the app bundle."
        case .installFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallFailed(let message):
            return "Uninstallation failed: \(message)"
        case .notInstalled:
            return "The CLI tool is not installed."
        case .userCancelled:
            return "Operation cancelled by user."
        }
    }
}
