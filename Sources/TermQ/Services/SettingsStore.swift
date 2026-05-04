import Foundation
import Observation
import SwiftUI
import TermQCore

/// Single owner for TermQ's user-layer preferences.
///
/// Models the three-tier layering the codebase has been implementing
/// informally:
///   - tier 0: built-in defaults (`Defaults`)
///   - tier 1: user prefs (this store, backed by `KeyValueStore`)
///   - tier 2: per-card overrides (carried on `TerminalCard`)
///
/// Per-card override resolution lives on this type so callers don't reach
/// past the store to recompute fallbacks. The first wave of consumers is
/// the four audit-named drift settings (safePaste, fontSize, themeId,
/// backend); other globals are exposed here too so future migrations can
/// retire scattered `@AppStorage` / `UserDefaults` reads incrementally.
@MainActor
@Observable
public final class SettingsStore {

    /// Process-wide singleton backed by `UserDefaults.standard`. Tests and
    /// previews may construct independent instances against an in-memory
    /// `KeyValueStore`.
    public static let shared = SettingsStore()

    public enum Defaults {
        public static let safePaste = true
        public static let fontSize: CGFloat = 13
        public static let themeId = "default-dark"
        public static let backend: TerminalBackend = .direct

        public static let enableTerminalAutorun = false
        public static let allowOscClipboard = false
        public static let confirmExternalLLMModifications = true
        public static let tmuxEnabled = true
        public static let tmuxAutoReattach = true
        public static let binRetentionDays = 14
        public static let terminalScrollbackLines = 5000
    }

    private enum Keys {
        static let safePaste = "defaultSafePaste"
        static let fontSize = "defaultFontSize"
        static let themeId = "terminalTheme"
        static let backend = "defaultBackend"

        static let enableTerminalAutorun = "enableTerminalAutorun"
        static let allowOscClipboard = "allowOscClipboard"
        static let confirmExternalLLMModifications = "confirmExternalLLMModifications"
        static let tmuxEnabled = "tmuxEnabled"
        static let tmuxAutoReattach = "tmuxAutoReattach"
        static let binRetentionDays = "binRetentionDays"
        static let terminalScrollbackLines = "terminalScrollbackLines"
    }

    @ObservationIgnored
    private let store: any KeyValueStore

    /// External-write reconciliation flag. While `true`, didSet handlers
    /// skip the write-back to `store` so a sync from the underlying
    /// `UserDefaults` doesn't loop back into another notification.
    @ObservationIgnored
    private var isSyncingFromStore = false

    @ObservationIgnored
    private var notificationObserver: NSObjectProtocol?

    // MARK: - Per-card overridable settings (the four audit-named drift fields)

    public var safePaste: Bool {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(safePaste, forKey: Keys.safePaste)
        }
    }

    public var fontSize: CGFloat {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(Double(fontSize), forKey: Keys.fontSize)
        }
    }

    public var themeId: String {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(themeId, forKey: Keys.themeId)
        }
    }

    public var backend: TerminalBackend {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(backend.rawValue, forKey: Keys.backend)
        }
    }

    // MARK: - Other globals (no per-card override today; surfaced here so
    // future migrations can replace ad-hoc UserDefaults reads).

    public var enableTerminalAutorun: Bool {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(enableTerminalAutorun, forKey: Keys.enableTerminalAutorun)
        }
    }

    public var allowOscClipboard: Bool {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(allowOscClipboard, forKey: Keys.allowOscClipboard)
        }
    }

    public var confirmExternalLLMModifications: Bool {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(confirmExternalLLMModifications, forKey: Keys.confirmExternalLLMModifications)
        }
    }

    public var tmuxEnabled: Bool {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(tmuxEnabled, forKey: Keys.tmuxEnabled)
        }
    }

    public var tmuxAutoReattach: Bool {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(tmuxAutoReattach, forKey: Keys.tmuxAutoReattach)
        }
    }

    public var binRetentionDays: Int {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(binRetentionDays, forKey: Keys.binRetentionDays)
        }
    }

    public var terminalScrollbackLines: Int {
        didSet {
            guard !isSyncingFromStore else { return }
            store.set(terminalScrollbackLines, forKey: Keys.terminalScrollbackLines)
        }
    }

    public init(store: any KeyValueStore = UserDefaults.standard) {
        self.store = store

        self.safePaste =
            (store.object(forKey: Keys.safePaste) as? Bool) ?? Defaults.safePaste

        let storedFontSize = store.double(forKey: Keys.fontSize)
        self.fontSize = storedFontSize > 0 ? CGFloat(storedFontSize) : Defaults.fontSize

        let storedThemeId = store.string(forKey: Keys.themeId)
        self.themeId = (storedThemeId?.isEmpty == false ? storedThemeId : nil) ?? Defaults.themeId

        let storedBackendRaw = store.string(forKey: Keys.backend)
        self.backend = storedBackendRaw.flatMap(TerminalBackend.init(rawValue:)) ?? Defaults.backend

        self.enableTerminalAutorun =
            (store.object(forKey: Keys.enableTerminalAutorun) as? Bool)
            ?? Defaults.enableTerminalAutorun
        self.allowOscClipboard =
            (store.object(forKey: Keys.allowOscClipboard) as? Bool) ?? Defaults.allowOscClipboard
        self.confirmExternalLLMModifications =
            (store.object(forKey: Keys.confirmExternalLLMModifications) as? Bool)
            ?? Defaults.confirmExternalLLMModifications
        self.tmuxEnabled =
            (store.object(forKey: Keys.tmuxEnabled) as? Bool) ?? Defaults.tmuxEnabled
        self.tmuxAutoReattach =
            (store.object(forKey: Keys.tmuxAutoReattach) as? Bool) ?? Defaults.tmuxAutoReattach

        let storedBinRetentionDays = store.integer(forKey: Keys.binRetentionDays)
        self.binRetentionDays =
            storedBinRetentionDays > 0 ? storedBinRetentionDays : Defaults.binRetentionDays

        let storedScrollback = store.integer(forKey: Keys.terminalScrollbackLines)
        self.terminalScrollbackLines =
            storedScrollback > 0 ? storedScrollback : Defaults.terminalScrollbackLines

        // Bridge external writes (e.g. existing `@AppStorage` Settings UI,
        // CLI/MCP, Sparkle) into the store's @Observable graph. Without
        // this, an `@AppStorage("defaultBackend")` write from SettingsView
        // updates UserDefaults but leaves the in-memory snapshot stale,
        // and new cards see the old value until app restart.
        if let userDefaults = store as? UserDefaults {
            // Don't pass `queue: .main` — `OperationQueue.main` callbacks
            // aren't recognised as `MainActor`-isolated by Swift's
            // concurrency runtime, so `MainActor.assumeIsolated` would
            // be a hidden trap. Hop explicitly via a Task instead, which
            // is the pattern used elsewhere (e.g. `BoardPersistence`'s
            // file-monitor callbacks).
            notificationObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: userDefaults,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncFromStore()
                }
            }
        }
    }

    // No `deinit` cleanup: the singleton lives for the life of the
    // process, and the observer's `[weak self]` closure no-ops once the
    // instance deallocates. Adding an actor-isolated cleanup would
    // require either Sendable hoops on the observer token or a Task
    // re-dispatch from a nonisolated deinit — not worth the friction
    // for a leak that only matters in test instances backed by real
    // UserDefaults (currently zero such instances).

    /// Re-read each property from the underlying store and update if
    /// changed. Triggers @Observable propagation downstream; the
    /// `isSyncingFromStore` flag suppresses the didSet write-back so
    /// idempotent UserDefaults notifications don't loop.
    ///
    /// Internal so tests can drive sync against an in-memory store
    /// without depending on `UserDefaults.didChangeNotification` plumbing.
    func syncFromStore() {
        isSyncingFromStore = true
        defer { isSyncingFromStore = false }

        let newSafePaste =
            (store.object(forKey: Keys.safePaste) as? Bool) ?? Defaults.safePaste
        if safePaste != newSafePaste { safePaste = newSafePaste }

        let storedFontSize = store.double(forKey: Keys.fontSize)
        let newFontSize: CGFloat = storedFontSize > 0 ? CGFloat(storedFontSize) : Defaults.fontSize
        if fontSize != newFontSize { fontSize = newFontSize }

        let storedThemeId = store.string(forKey: Keys.themeId)
        let newThemeId =
            (storedThemeId?.isEmpty == false ? storedThemeId : nil) ?? Defaults.themeId
        if themeId != newThemeId { themeId = newThemeId }

        let storedBackendRaw = store.string(forKey: Keys.backend)
        let newBackend =
            storedBackendRaw.flatMap(TerminalBackend.init(rawValue:)) ?? Defaults.backend
        if backend != newBackend { backend = newBackend }

        let newEnableTerminalAutorun =
            (store.object(forKey: Keys.enableTerminalAutorun) as? Bool)
            ?? Defaults.enableTerminalAutorun
        if enableTerminalAutorun != newEnableTerminalAutorun {
            enableTerminalAutorun = newEnableTerminalAutorun
        }

        let newAllowOscClipboard =
            (store.object(forKey: Keys.allowOscClipboard) as? Bool) ?? Defaults.allowOscClipboard
        if allowOscClipboard != newAllowOscClipboard { allowOscClipboard = newAllowOscClipboard }

        let newConfirmExternal =
            (store.object(forKey: Keys.confirmExternalLLMModifications) as? Bool)
            ?? Defaults.confirmExternalLLMModifications
        if confirmExternalLLMModifications != newConfirmExternal {
            confirmExternalLLMModifications = newConfirmExternal
        }

        let newTmuxEnabled =
            (store.object(forKey: Keys.tmuxEnabled) as? Bool) ?? Defaults.tmuxEnabled
        if tmuxEnabled != newTmuxEnabled { tmuxEnabled = newTmuxEnabled }

        let newTmuxAutoReattach =
            (store.object(forKey: Keys.tmuxAutoReattach) as? Bool) ?? Defaults.tmuxAutoReattach
        if tmuxAutoReattach != newTmuxAutoReattach { tmuxAutoReattach = newTmuxAutoReattach }

        let storedBinRetentionDays = store.integer(forKey: Keys.binRetentionDays)
        let newBinRetentionDays =
            storedBinRetentionDays > 0 ? storedBinRetentionDays : Defaults.binRetentionDays
        if binRetentionDays != newBinRetentionDays { binRetentionDays = newBinRetentionDays }

        let storedScrollback = store.integer(forKey: Keys.terminalScrollbackLines)
        let newScrollback =
            storedScrollback > 0 ? storedScrollback : Defaults.terminalScrollbackLines
        if terminalScrollbackLines != newScrollback { terminalScrollbackLines = newScrollback }
    }

    // MARK: - Override resolution

    /// Resolve a per-card override against the user-layer value.
    /// `override == nil` means "inherit"; the caller should pass the
    /// matching user-layer value as `user`.
    public func resolve<T>(override: T?, user: T) -> T {
        override ?? user
    }

    public func effectiveSafePaste(card: Bool?) -> Bool {
        card ?? safePaste
    }

    public func effectiveFontSize(card: CGFloat?) -> CGFloat {
        card ?? fontSize
    }

    public func effectiveThemeId(card: String?) -> String {
        // Empty-string card override is treated as "inherit" for backward
        // compatibility with cards persisted before themeId became Optional.
        if let card, !card.isEmpty { return card }
        return themeId
    }

    public func effectiveBackend(card: TerminalBackend?) -> TerminalBackend {
        card ?? backend
    }
}

// MARK: - SwiftUI environment
//
// `SettingsStore` is published via the `@Observable`-native environment
// pattern: inject with `.environment(store)` at the scene root and read
// with `@Environment(SettingsStore.self) private var settings` in views
// that need it. No EnvironmentKey is required — SwiftUI handles the
// lookup by type.
