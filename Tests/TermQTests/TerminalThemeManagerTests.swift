import XCTest

@testable import TermQ

@MainActor
final class TerminalThemeManagerTests: XCTestCase {

    func testInit_noStoredValue_usesDefaultDark() {
        let store = InMemoryKeyValueStore()
        let manager = TerminalThemeManager(store: store)
        XCTAssertEqual(manager.themeId, "default-dark")
    }

    func testInit_storedValue_usesStored() {
        let store = InMemoryKeyValueStore()
        store.set("solarized-light", forKey: "terminalTheme")
        let manager = TerminalThemeManager(store: store)
        XCTAssertEqual(manager.themeId, "solarized-light")
    }

    func testSetThemeId_persistsToStore() {
        let store = InMemoryKeyValueStore()
        let manager = TerminalThemeManager(store: store)
        manager.themeId = "dracula"
        XCTAssertEqual(store.string(forKey: "terminalTheme"), "dracula")
    }

    func testSetThemeId_invokesOnThemeChanged() {
        let store = InMemoryKeyValueStore()
        let manager = TerminalThemeManager(store: store)
        var callCount = 0
        manager.onThemeChanged = { callCount += 1 }
        manager.themeId = "dracula"
        XCTAssertEqual(callCount, 1)
    }
}

// MARK: - In-memory KeyValueStore for tests

/// Single-threaded test double for `KeyValueStore`. Tests drive it from the test
/// runner's main thread, so no synchronisation is required; the `@unchecked`
/// opt-out keeps it usable from `@MainActor`-isolated code under test.
final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private var storage: [String: Any] = [:]

    func string(forKey key: String) -> String? {
        storage[key] as? String
    }

    func bool(forKey key: String) -> Bool {
        storage[key] as? Bool ?? false
    }

    func integer(forKey key: String) -> Int {
        if let i = storage[key] as? Int { return i }
        if let d = storage[key] as? Double { return Int(d) }
        return 0
    }

    func double(forKey key: String) -> Double {
        if let d = storage[key] as? Double { return d }
        if let i = storage[key] as? Int { return Double(i) }
        return 0
    }

    func object(forKey key: String) -> Any? {
        storage[key]
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func set(_ value: Bool, forKey key: String) {
        storage[key] = value
    }

    func set(_ value: Int, forKey key: String) {
        storage[key] = value
    }

    func set(_ value: Double, forKey key: String) {
        storage[key] = value
    }
}
