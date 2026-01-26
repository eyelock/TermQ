import Foundation

/// Single source of truth for all TermQ app identifiers across production and debug variants
///
/// **IMPORTANT:** This is the ONLY place these values should be defined.
/// Do NOT hardcode bundle IDs, binary names, or data directories anywhere else.
///
/// Usage:
/// ```swift
/// #if TERMQ_DEBUG_BUILD
///     let bundleId = AppProfile.Debug.bundleIdentifier
/// #else
///     let bundleId = AppProfile.Production.bundleIdentifier
/// #endif
/// ```
///
/// Or use the convenience properties:
/// ```swift
/// let bundleId = AppProfile.Current.bundleIdentifier
/// ```
public enum AppProfile {
    /// Production app identifiers
    public enum Production {
        /// Bundle identifier for production app
        /// Source: TermQ.app/Contents/Info.plist (when built for release)
        public static let bundleIdentifier = "net.eyelock.termq.app"

        /// CLI binary name
        public static let cliBinaryName = "termqcli"

        /// MCP server binary name
        public static let mcpBinaryName = "termqmcp"

        /// App bundle name
        public static let appBundleName = "TermQ.app"

        /// Data directory name (in ~/Library/Application Support/)
        public static let dataDirectoryName = "TermQ"

        /// URL scheme
        public static let urlScheme = "termq"

        /// Display name
        public static let displayName = "TermQ"
    }

    /// Debug app identifiers
    public enum Debug {
        /// Bundle identifier for debug app
        /// Source: TermQDebug.app/Contents/Info.plist
        public static let bundleIdentifier = "net.eyelock.termq.app.debug"

        /// CLI binary name (debug variant)
        public static let cliBinaryName = "termqclid"

        /// MCP server binary name (debug variant)
        public static let mcpBinaryName = "termqmcpd"

        /// App bundle name
        public static let appBundleName = "TermQDebug.app"

        /// Data directory name (in ~/Library/Application Support/)
        public static let dataDirectoryName = "TermQ-Debug"

        /// URL scheme
        public static let urlScheme = "termqd"

        /// Display name
        public static let displayName = "TermQ Debug"
    }

    /// Other identifiers not tied to production/debug
    public enum Services {
        /// Keychain service identifier
        public static let keychainService = "net.eyelock.termq.secrets"
    }

    /// Convenience accessor for current build configuration
    /// Uses typealias to avoid repetitive #if blocks for each property
    public enum Current {
        #if TERMQ_DEBUG_BUILD
            private typealias Profile = Debug
        #else
            private typealias Profile = Production
        #endif

        public static var bundleIdentifier: String { Profile.bundleIdentifier }
        public static var cliBinaryName: String { Profile.cliBinaryName }
        public static var mcpBinaryName: String { Profile.mcpBinaryName }
        public static var appBundleName: String { Profile.appBundleName }
        public static var dataDirectoryName: String { Profile.dataDirectoryName }
        public static var urlScheme: String { Profile.urlScheme }
        public static var displayName: String { Profile.displayName }
    }

    /// All possible bundle identifiers for detection purposes
    public static let allBundleIdentifiers: [String] = [
        Production.bundleIdentifier,
        Debug.bundleIdentifier,
    ]
}
