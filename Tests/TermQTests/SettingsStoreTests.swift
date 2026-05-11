import TermQCore
import XCTest

@testable import TermQ

@MainActor
final class SettingsStoreTests: XCTestCase {

    // MARK: - Defaults

    func testInit_emptyStore_returnsBuiltInDefaults() {
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)

        XCTAssertEqual(store.safePaste, SettingsStore.Defaults.safePaste)
        XCTAssertEqual(store.fontSize, SettingsStore.Defaults.fontSize)
        XCTAssertEqual(store.themeId, SettingsStore.Defaults.themeId)
        XCTAssertEqual(store.backend, SettingsStore.Defaults.backend)
    }

    // MARK: - User-layer reads

    func testInit_storedSafePasteFalse_isReturned() {
        let kvs = InMemoryKeyValueStore()
        kvs.set(false, forKey: "defaultSafePaste")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.safePaste, false)
    }

    func testInit_storedThemeId_isReturned() {
        let kvs = InMemoryKeyValueStore()
        kvs.set("dracula", forKey: "terminalTheme")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.themeId, "dracula")
    }

    func testInit_storedBackend_isReturned() {
        let kvs = InMemoryKeyValueStore()
        kvs.set("tmuxAttach", forKey: "defaultBackend")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.backend, .tmuxAttach)
    }

    func testInit_storedBackendInvalid_fallsBackToDefault() {
        let kvs = InMemoryKeyValueStore()
        kvs.set("nonsense", forKey: "defaultBackend")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.backend, SettingsStore.Defaults.backend)
    }

    // MARK: - Write-through

    func testSetSafePaste_persistsToStore() {
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)
        store.safePaste = false
        XCTAssertEqual(kvs.object(forKey: "defaultSafePaste") as? Bool, false)
    }

    func testSetBackend_persistsRawValue() {
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)
        store.backend = .tmuxControl
        XCTAssertEqual(kvs.string(forKey: "defaultBackend"), "tmuxControl")
    }

    // MARK: - Override resolution (the four drift fields)

    func testEffectiveSafePaste_nilOverride_inheritsUser() {
        let kvs = InMemoryKeyValueStore()
        kvs.set(false, forKey: "defaultSafePaste")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.effectiveSafePaste(card: nil), false)
    }

    func testEffectiveSafePaste_concreteOverride_winsOverUser() {
        let kvs = InMemoryKeyValueStore()
        kvs.set(false, forKey: "defaultSafePaste")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.effectiveSafePaste(card: true), true)
    }

    func testEffectiveFontSize_nilOverride_inheritsUserDefault() {
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.effectiveFontSize(card: nil), SettingsStore.Defaults.fontSize)
    }

    func testEffectiveThemeId_nilOverride_inheritsUser() {
        let kvs = InMemoryKeyValueStore()
        kvs.set("nord", forKey: "terminalTheme")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.effectiveThemeId(card: nil), "nord")
    }

    func testEffectiveThemeId_emptyStringOverride_inherits() {
        // Backward-compat: pre-Optional cards may have stored "" as the
        // override; treat it as "inherit" rather than as an empty theme.
        let kvs = InMemoryKeyValueStore()
        kvs.set("nord", forKey: "terminalTheme")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.effectiveThemeId(card: ""), "nord")
    }

    func testEffectiveBackend_nilOverride_inheritsUser() {
        let kvs = InMemoryKeyValueStore()
        kvs.set("tmuxAttach", forKey: "defaultBackend")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.effectiveBackend(card: nil), .tmuxAttach)
    }

    func testEffectiveBackend_concreteOverride_winsOverUser() {
        let kvs = InMemoryKeyValueStore()
        kvs.set("tmuxAttach", forKey: "defaultBackend")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.effectiveBackend(card: .direct), .direct)
    }

    // MARK: - Drift contract

    func testGlobalChange_propagatesToInheritingCards() {
        // The audit's complaint: when a card carries a `nil` override,
        // changing the global pref must propagate. With SettingsStore this
        // is the normal case — `effectiveSafePaste(card: nil)` reads the
        // current store value every time.
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.effectiveSafePaste(card: nil), true)

        store.safePaste = false
        XCTAssertEqual(store.effectiveSafePaste(card: nil), false)
    }

    // MARK: - Tier C quick wins

    func testInit_emptyStore_returnsBuiltInDefaults_tierC() {
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)

        XCTAssertEqual(store.copyOnSelect, SettingsStore.Defaults.copyOnSelect)
        XCTAssertEqual(store.diagnosticsVerboseMode, SettingsStore.Defaults.diagnosticsVerboseMode)
        XCTAssertEqual(
            store.defaultWorkingDirectory, SettingsStore.Defaults.defaultWorkingDirectory)
    }

    func testInit_storedCopyOnSelectTrue_isReturned() {
        let kvs = InMemoryKeyValueStore()
        kvs.set(true, forKey: "copyOnSelect")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.copyOnSelect, true)
    }

    func testSetCopyOnSelect_persistsToStore() {
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)
        store.copyOnSelect = true
        XCTAssertEqual(kvs.object(forKey: "copyOnSelect") as? Bool, true)
    }

    func testInit_storedDefaultWorkingDirectory_isReturned() {
        let kvs = InMemoryKeyValueStore()
        kvs.set("/Users/test/projects", forKey: "defaultWorkingDirectory")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.defaultWorkingDirectory, "/Users/test/projects")
    }

    func testInit_emptyStringWorkingDirectory_fallsBackToHomeDir() {
        let kvs = InMemoryKeyValueStore()
        kvs.set("", forKey: "defaultWorkingDirectory")
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.defaultWorkingDirectory, NSHomeDirectory())
    }

    func testSetDiagnosticsVerboseMode_persistsToStore() {
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)
        store.diagnosticsVerboseMode = true
        XCTAssertEqual(kvs.object(forKey: "diagnosticsVerboseMode") as? Bool, true)
    }

    // MARK: - External write reconciliation

    func testExternalWriteToStore_syncsIntoStoreProperty() {
        // Simulates the existing `@AppStorage` Settings UI: an external
        // writer hits the underlying KeyValueStore directly. After the
        // notification path triggers `syncFromStore`, the SettingsStore's
        // in-memory value reflects the new write.
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)
        XCTAssertEqual(store.backend, .direct)

        kvs.set("tmuxAttach", forKey: "defaultBackend")
        store.syncFromStore()

        XCTAssertEqual(store.backend, .tmuxAttach)
    }

    func testExternalWriteToStore_propagatesToInheritingCardResolution() {
        // The end-to-end behavior the audit cares about: when a global
        // pref changes externally, a new card created with `nil` override
        // sees the new value at session-create time.
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)

        kvs.set(false, forKey: "defaultSafePaste")
        store.syncFromStore()
        XCTAssertEqual(store.effectiveSafePaste(card: nil), false)

        kvs.set(true, forKey: "defaultSafePaste")
        store.syncFromStore()
        XCTAssertEqual(store.effectiveSafePaste(card: nil), true)
    }

    func testSyncFromStore_idempotent() {
        // Re-syncing without external changes shouldn't perturb anything.
        // This guards the loop-break: the didSet guard means a sync pass
        // doesn't itself trigger another store write.
        let kvs = InMemoryKeyValueStore()
        kvs.set("dracula", forKey: "terminalTheme")
        let store = SettingsStore(store: kvs)

        store.syncFromStore()
        store.syncFromStore()
        store.syncFromStore()

        XCTAssertEqual(store.themeId, "dracula")
    }

    func testGlobalChange_doesNotPropagateToOverridingCards() {
        // Cards with an explicit override stay put across global changes.
        // This is the upgrade-day footgun documented in CHANGELOG.
        let kvs = InMemoryKeyValueStore()
        let store = SettingsStore(store: kvs)
        store.safePaste = true
        XCTAssertEqual(store.effectiveSafePaste(card: false), false)

        store.safePaste = false
        XCTAssertEqual(store.effectiveSafePaste(card: false), false)
    }
}
