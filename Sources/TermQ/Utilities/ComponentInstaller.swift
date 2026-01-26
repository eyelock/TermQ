import Foundation
import os.log

// MARK: - Protocols

/// Protocol for install location enums
public protocol InstallLocationProtocol: RawRepresentable, CaseIterable, Identifiable
where RawValue == String {
    var displayName: String { get }
    var path: String { get }
    var fullPath: String { get }
    var requiresAdmin: Bool { get }
    var pathNote: String { get }
}

// MARK: - Common Error Type

/// Common error type for component installation
public enum ComponentInstallerError: LocalizedError, Equatable {
    case bundledComponentNotFound(componentName: String)
    case installFailed(String)
    case uninstallFailed(String)
    case notInstalled
    case userCancelled

    public var errorDescription: String? {
        switch self {
        case .bundledComponentNotFound(let name):
            return "The \(name) was not found in the app bundle."
        case .installFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallFailed(let message):
            return "Uninstallation failed: \(message)"
        case .notInstalled:
            return "The component is not installed."
        case .userCancelled:
            return "Operation cancelled by user."
        }
    }

    public static func == (lhs: ComponentInstallerError, rhs: ComponentInstallerError) -> Bool {
        switch (lhs, rhs) {
        case (.bundledComponentNotFound(let a), .bundledComponentNotFound(let b)):
            return a == b
        case (.installFailed(let a), .installFailed(let b)):
            return a == b
        case (.uninstallFailed(let a), .uninstallFailed(let b)):
            return a == b
        case (.notInstalled, .notInstalled):
            return true
        case (.userCancelled, .userCancelled):
            return true
        default:
            return false
        }
    }
}

// MARK: - Generic Component Installer

/// Generic installer for bundled components (CLI tools, MCP servers, etc.)
public enum ComponentInstaller<Location: InstallLocationProtocol> {
    /// Configuration for a component installer
    public struct Config: Sendable {
        /// Name of the bundled resource (e.g., "termqcli", "termqmcp")
        public let bundledResourceName: String

        /// Human-readable component name for messages (e.g., "CLI tool", "MCP Server")
        public let componentDisplayName: String

        public init(bundledResourceName: String, componentDisplayName: String) {
            self.bundledResourceName = bundledResourceName
            self.componentDisplayName = componentDisplayName
        }
    }

    // MARK: - Bundle Access

    /// Get the path to the bundled component within the app bundle
    public static func bundledPath(config: Config) -> URL? {
        let log = OSLog(subsystem: "net.eyelock.termq", category: "ComponentInstaller")
        os_log("🔍 Looking for bundled resource: %{public}@", log: log, type: .debug, config.bundledResourceName)
        os_log("🔍 Component display name: %{public}@", log: log, type: .debug, config.componentDisplayName)

        // Try standard resource lookup first
        if let url = Bundle.main.url(forResource: config.bundledResourceName, withExtension: nil) {
            os_log("✅ Found via Bundle.main.url: %{public}@", log: log, type: .info, url.path)
            return url
        }
        os_log("⚠️ Standard Bundle.main.url lookup failed", log: log, type: .info)

        // For executable binaries not registered in Info.plist, check Resources directory directly
        guard let resourceURL = Bundle.main.resourceURL else {
            os_log("❌ Bundle.main.resourceURL is nil", log: log, type: .error)
            return nil
        }
        os_log("🔍 resourceURL: %{public}@", log: log, type: .debug, resourceURL.path)

        let binaryURL = resourceURL.appendingPathComponent(config.bundledResourceName)
        os_log("🔍 Checking direct path: %{public}@", log: log, type: .debug, binaryURL.path)

        // Verify the file exists
        if FileManager.default.fileExists(atPath: binaryURL.path) {
            os_log("✅ Found via direct path: %{public}@", log: log, type: .info, binaryURL.path)
            return binaryURL
        }

        os_log("❌ File does not exist at: %{public}@", log: log, type: .error, binaryURL.path)

        // List what's actually in the Resources directory
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: resourceURL.path)
            os_log("📁 Resources directory contents:", log: log, type: .info)
            for item in contents.sorted() {
                os_log("   - %{public}@", log: log, type: .info, item)
            }
        } catch {
            os_log("❌ Error listing directory: %{public}@", log: log, type: .error, error.localizedDescription)
        }

        return nil
    }

    // MARK: - Installation Checks

    /// Check if the component is installed at a specific location
    public static func isInstalled(at location: Location, config: Config) -> Bool {
        FileManager.default.fileExists(atPath: location.fullPath)
    }

    /// Check if the component is installed at a custom path
    public static func isInstalled(atPath path: String, config: Config) -> Bool {
        let fullPath =
            path.hasSuffix("/\(config.bundledResourceName)")
            ? path : "\(path)/\(config.bundledResourceName)"
        let expanded = NSString(string: fullPath).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    /// Find where the component is currently installed (if anywhere)
    public static func currentInstallLocation(config: Config) -> Location? {
        Location.allCases.first { isInstalled(at: $0, config: config) }
    }

    // MARK: - Installation

    /// Install the component to a standard location
    public static func install(
        to location: Location, config: Config
    ) async -> Result<String, ComponentInstallerError> {
        return await install(toPath: location.path, requiresAdmin: location.requiresAdmin, config: config)
    }

    /// Install the component to a custom path
    public static func install(
        toPath path: String, requiresAdmin: Bool? = nil, config: Config
    ) async -> Result<String, ComponentInstallerError> {
        let log = OSLog(subsystem: "net.eyelock.termq", category: "ComponentInstaller")
        os_log("🚀 Starting installation", log: log, type: .info)
        os_log("🚀 Target path: %{public}@", log: log, type: .info, path)
        os_log("🚀 Component: %{public}@", log: log, type: .info, config.bundledResourceName)

        guard let sourcePath = bundledPath(config: config) else {
            os_log("❌ bundledPath returned nil - component not found", log: log, type: .error)
            return .failure(.bundledComponentNotFound(componentName: config.componentDisplayName))
        }

        os_log("✅ Source path: %{public}@", log: log, type: .info, sourcePath.path)

        let expandedPath = NSString(string: path).expandingTildeInPath
        let fullPath = "\(expandedPath)/\(config.bundledResourceName)"

        os_log("🔍 Expanded path: %{public}@", log: log, type: .debug, expandedPath)
        os_log("🔍 Full destination: %{public}@", log: log, type: .debug, fullPath)

        // Determine if admin is needed (if not explicitly specified, check if path is writable)
        let needsAdmin = requiresAdmin ?? !FileManager.default.isWritableFile(atPath: expandedPath)
        os_log("🔍 Needs admin: %{public}d", log: log, type: .debug, needsAdmin)

        if needsAdmin {
            return await installWithAdmin(
                source: sourcePath.path,
                destination: fullPath,
                directory: expandedPath,
                config: config
            )
        } else {
            return await installWithoutAdmin(
                source: sourcePath.path,
                destination: fullPath,
                directory: expandedPath,
                config: config
            )
        }
    }

    /// Install using AppleScript for admin privileges
    private static func installWithAdmin(
        source: String, destination: String, directory: String, config: Config
    ) async -> Result<String, ComponentInstallerError> {
        // Ensure directory exists
        let ensureDirScript = """
            do shell script "mkdir -p '\(directory)'" with administrator privileges
            """

        // Copy the component
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

        return .success("\(config.componentDisplayName) installed successfully to \(destination)")
    }

    /// Install without admin (user-writable location)
    private static func installWithoutAdmin(
        source: String, destination: String, directory: String, config: Config
    ) async -> Result<String, ComponentInstallerError> {
        let fileManager = FileManager.default

        do {
            // Create directory if needed
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

            // Remove existing file if present
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }

            // Copy the component
            try fileManager.copyItem(atPath: source, toPath: destination)

            // Make executable
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)

            return .success("\(config.componentDisplayName) installed successfully to \(destination)")
        } catch {
            return .failure(.installFailed(error.localizedDescription))
        }
    }

    // MARK: - Uninstallation

    /// Uninstall the component from a specific location
    public static func uninstall(
        from location: Location, config: Config
    ) async -> Result<String, ComponentInstallerError> {
        return await uninstall(fromPath: location.fullPath, requiresAdmin: location.requiresAdmin, config: config)
    }

    /// Uninstall the component from a custom path
    public static func uninstall(
        fromPath path: String, requiresAdmin: Bool? = nil, config: Config
    ) async -> Result<String, ComponentInstallerError> {
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

        return .success("\(config.componentDisplayName) uninstalled successfully")
    }
}
