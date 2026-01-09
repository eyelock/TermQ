import Foundation

/// Common installation locations for the CLI tool
enum InstallLocation: String, CaseIterable, Identifiable {
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

/// Handles installation of the termq CLI tool
enum CLIInstaller {
    static let bundledCLIName = "termq"

    /// Get the path to the bundled CLI tool within the app bundle
    static var bundledCLIPath: URL? {
        Bundle.main.url(forResource: bundledCLIName, withExtension: nil)
    }

    /// Check if the CLI tool is installed at a specific location
    static func isInstalled(at location: InstallLocation) -> Bool {
        FileManager.default.fileExists(atPath: location.fullPath)
    }

    /// Check if the CLI tool is installed at a custom path
    static func isInstalled(atPath path: String) -> Bool {
        let fullPath = path.hasSuffix("/termq") ? path : "\(path)/termq"
        let expanded = NSString(string: fullPath).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    /// Find where the CLI is currently installed (if anywhere)
    static var currentInstallLocation: InstallLocation? {
        InstallLocation.allCases.first { isInstalled(at: $0) }
    }

    /// Install the CLI tool to a standard location
    static func install(to location: InstallLocation) async -> Result<String, CLIInstallerError> {
        return await install(toPath: location.path, requiresAdmin: location.requiresAdmin)
    }

    /// Install the CLI tool to a custom path
    static func install(toPath path: String, requiresAdmin: Bool? = nil) async -> Result<String, CLIInstallerError> {
        guard let sourcePath = bundledCLIPath else {
            return .failure(.bundledCLINotFound)
        }

        let expandedPath = NSString(string: path).expandingTildeInPath
        let fullPath = "\(expandedPath)/termq"

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
    ) async -> Result<String, CLIInstallerError> {
        // Ensure directory exists
        let ensureDirScript = """
            do shell script "mkdir -p '\(directory)'" with administrator privileges
            """

        // Copy the CLI tool
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

        return .success("CLI tool installed successfully to \(destination)")
    }

    /// Install without admin (user-writable location)
    private static func installWithoutAdmin(
        source: String, destination: String, directory: String
    ) async -> Result<String, CLIInstallerError> {
        let fileManager = FileManager.default

        do {
            // Create directory if needed
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

            // Remove existing file if present
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }

            // Copy the CLI tool
            try fileManager.copyItem(atPath: source, toPath: destination)

            // Make executable
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)

            return .success("CLI tool installed successfully to \(destination)")
        } catch {
            return .failure(.installFailed(error.localizedDescription))
        }
    }

    /// Uninstall the CLI tool from a specific location
    static func uninstall(from location: InstallLocation) async -> Result<String, CLIInstallerError> {
        return await uninstall(fromPath: location.fullPath, requiresAdmin: location.requiresAdmin)
    }

    /// Uninstall the CLI tool from a custom path
    static func uninstall(fromPath path: String, requiresAdmin: Bool? = nil) async -> Result<String, CLIInstallerError>
    {
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

        return .success("CLI tool uninstalled successfully")
    }
}

enum CLIInstallerError: LocalizedError {
    case bundledCLINotFound
    case installFailed(String)
    case uninstallFailed(String)
    case notInstalled
    case userCancelled

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
